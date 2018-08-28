local Connector = require "Connector"
local Constants = require "Constants"
local dheap = require "dheap"
local Graph = require "Graph"

local debug = function() end
if Constants.DEBUG_ENABLED then
  -- debug = log
end

local SURFACE_NAME = Constants.SURFACE_NAME

local pipe_capacity_cache = {}
local function pipe_capacity(name)
  if not pipe_capacity_cache[name] then
    pipe_capacity_cache[name] = game.entity_prototypes[name].fluid_capacity
  end
  return pipe_capacity_cache[name]
end

local function fill_pipe(entity, fluid_name)
  if fluid_name then
    local new_fluid = {name = fluid_name, amount = pipe_capacity(entity.name)}
    entity.fluidbox[1] = new_fluid
  else
    entity.fluidbox[1] = nil
  end
end

local Network = {}

local all_networks
local network_for_entity = {}

function Network.on_init()
  global.all_networks = {}
  global.network_iter = nil
  Network:on_load()
end

function Network.on_load()
  all_networks = global.all_networks
  for _, network in pairs(all_networks) do
    setmetatable(network, {__index = Network})
    Graph.restore(network.graph)
    for unit_number, pipe in pairs(network.pipes) do
      if pipe.valid then
        network_for_entity[pipe.unit_number] = network
      else
        network.pipes[unit_number] = nil
      end
    end
    for _, connector in pairs(network.connectors) do
      Connector.restore(connector)
    end
  end
end

--[[
  {
    fluid_name = "water",
    fluid_amount = 0,
    fluid_temperature = 15,
    Graph = Graph(),
    pipes = {
      [unit_number] = pipe_entity,
      ...
    },
    connectors = {
      [underground_unit_number] = connector_aboveground_entity,
      ...
    },
    connector_iter = nil,
  }
]]
function Network.new()
  global.network_id = (global.network_id or 0) + 1
  local network_id = global.network_id
  local self = {
    id = network_id,
    fluid_name = nil,
    fluid_amount = 0,
    fluid_temperature = 15,
    graph = Graph.new(),
    pipes = {},
    connectors = {},
    input_connectors = dheap.new(),
    output_connectors = dheap.new(),
  }
  setmetatable(self, {__index = Network})
  all_networks[network_id] = self
  debug("created new network "..network_id)
  return self
end

function Network.for_entity(entity)
  return network_for_entity[entity.unit_number]
end

function Network:destroy()
  if Constants.DEBUG_ENABLED then
    for pipe, id in pairs(network_for_entity) do
      if id == self.id then
        error("Network destroyed while pipe reference exists for pipe "..pipe.unit_number)
      end
    end
  end

  debug("destroyed network "..self.id)
  all_networks[self.id] = nil
end

function Network:is_singleton()
  local n = next(self.pipes)
  local n2 = next(self.pipes, n)
  return n and not n2
end

function Network:absorb(other_network)
  for _, entity in pairs(other_network.pipes) do
    self:add_underground_pipe(entity)
  end
  for underground_unit_number, connector in pairs(other_network.connectors) do
    self:add_connector(connector, underground_unit_number)
  end
  if self.fluid_name ~= other_network.fluid_name then
    self:set_fluid(nil)
  end
  other_network:destroy()
  -- self:update()
end

function Network:add_connector(above, below_unit_number)
  local connector = Connector.new(above)
  self.connectors[below_unit_number] = connector
  self:enqueue_connector(connector)
  -- self:update()
end

function Network:remove_connector(below_unit_number)
  self.connectors[below_unit_number] = nil
  -- self:update()
end

function Network:add_underground_pipe(entity)
  assert(entity.surface.name == SURFACE_NAME)
  local unit_number = entity.unit_number
  network_for_entity[unit_number] = self
  self.pipes[unit_number] = entity
  self.graph:add(unit_number)
  for _, neighbor in ipairs(entity.neighbours[1]) do
    self.graph:add(unit_number, neighbor.unit_number)
  end
  fill_pipe(entity, self.fluid_name)
  -- self:update()
end

function Network:remove_underground_pipe(entity)
  assert(entity.surface.name == SURFACE_NAME)
  local unit_number = entity.unit_number
  self.pipes[unit_number] = nil
  self:remove_connector(unit_number)
  network_for_entity[unit_number] = nil

  if #entity.neighbours[1] > 1 then
    -- multiple connections for this pipe, so this may split the network into multiple new networks
    local fragments = self.graph:removal_fragments(unit_number)
    for i=2,#fragments do
      local fragment = fragments[i]
      local split_network = Network.new()
      for fragment_pipe_unit_number in pairs(fragment) do
        split_network:add_underground_pipe(self.pipes[fragment_pipe_unit_number])
        if self.connectors[fragment_pipe_unit_number] then
          split_network:add_connector(self.connectors[fragment_pipe_unit_number], fragment_pipe_unit_number)
          self:remove_connector(fragment_pipe_unit_number)
        end
        network_for_entity[fragment_pipe_unit_number] = split_network
        self.pipes[fragment_pipe_unit_number] = nil
        self.graph:remove(fragment_pipe_unit_number)
      end
      split_network.graph:remove(unit_number)
      -- split_network:update()
    end
  end

  self.graph:remove(unit_number)
  if next(self.pipes) then
    -- self:update()
  else
    self:destroy()
  end
end

local function foreach_connector(self, callback)
  for k, connector in pairs(self.connectors) do
    if connector.valid then
      callback(connector)
    else
      self.connectors[k] = nil
    end
  end
end

function Network:foreach_underground_entity(callback)
  for unit_number, pipe in pairs(self.pipes) do
    if pipe.valid then
      callback(pipe)
    else
      self.pipes[unit_number] = nil
    end
  end
end

function Network:set_fluid(fluid_name)
  debug("setting fluid for network "..self.id.." to "..(fluid_name or "(nil)"))
  self.fluid_name = fluid_name
  self:foreach_underground_entity(function(entity)
    fill_pipe(entity, self.fluid_name)
  end)
  local surface = game.surfaces[SURFACE_NAME]

  if not fluid_name then
    -- make sure underground connector counterparts reflect content of overworld
    foreach_connector(self, function(connector)
      local counterpart = surface.find_entity("pipefitter-connector", connector.position)
      local fluidbox = connector.entity.fluidbox[1]
      if fluidbox and fluidbox.amount > 0 then
        fill_pipe(counterpart, fluidbox.name)
      end
    end)
  end
end

function Network:infer_fluid_from_connectors()
  local inferred_fluid
  local conflict
  foreach_connector(self, function(connector)
    local connector_fluidbox = connector.fluidbox[1]
    if connector_fluidbox then
      if inferred_fluid then
        if connector_fluidbox.name ~= inferred_fluid then
          conflict = true
          return
        end
      else
        inferred_fluid = connector_fluidbox.name
      end
    end
  end)
  if conflict then
    return nil
  else
    return inferred_fluid
  end
end

function Network:is_time_for_update(tick)
  local next_input_tick = self.input_connectors:peek()
  local next_output_tick = self.output_connectors:peek()
  if next_input_tick and next_input_tick > tick
  or next_output_tick and next_output_tick > tick then
    return true
  end
  return false
end

function Network:can_transfer(from, to)
  local fluid_name = self.fluid_name
  return from and not from:is_conflicting(fluid_name) and to and not to:is_conflicting(fluid_name)
end

function Network:infer_fluid()
  local fluid_name = self:infer_fluid_from_connectors()
  if fluid_name ~= self.fluid_name then
    self:set_fluid(fluid_name)
  end
end

function Network:queue_connector(connector)
  if connector.flow_est < 0 then
    self.output_connectors:insert(connector.next_tick, connector)
  else
    self.input_connectors:insert(connector.next_tick, connector)
  end
end

function Network:update(tick)
  if not self.fluid_name then
    if tick % 1000 == 0 then
      self:infer_fluid()
    end
    return
  end

  if not self:is_time_for_update(tick) then return end

  local _, next_input_connector = self.input_connectors:pop()
  local _, next_output_connector = self.output_connectors:pop()
  if self:can_transfer(next_input_connector, next_output_connector) then
    next_input_connector:transfer_to(tick, self.fluid_name, next_output_connector)
    self.input_connectors:insert(next_input_connector.next_tick, next_input_connector)
    self.output_connectors:insert(next_output_connector.next_tick, next_output_connector)
  else
    if next_input_connector then
      next_input_connector:estimate_flow(tick)
      next_input_connector:estimate_next_tick()
      self:queue_connector(next_input_connector)
    end
    if next_output_connector then
      next_output_connector:estimate_flow(tick)
      next_output_connector:estimate_next_tick()
      self:queue_connector(next_output_connector)
    end
    if next_input_connector and next_input_connector:is_conflicting(self.fluid_name)
    or next_output_connector and next_output_connector:is_conflicting(self.fluid_name) then
      self:set_fluid(nil)
    end
  end
end

function Network.update_all(tick)
  local network
  for i=1,50 do
    global.network_iter, network = next(all_networks, global.network_iter)
    if network then
      network:update(tick)
    else
      return
    end
  end
end

return Network