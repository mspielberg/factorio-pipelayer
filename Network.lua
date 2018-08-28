local Constants = require "Constants"
local Graph = require "Graph"
local PipeConnections = require "PipeConnections"

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
    connector_iter = nil,
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
  self.connectors[below_unit_number] = above
  self.connector_iter = nil
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

-- returns amount of fluid left undistributed
local function distribute(connectors, fluid_name, fluid_amount, fluid_temperature)
  local num_connectors = #connectors
  local total_connector_capacity = Constants.CONNECTOR_CAPACITY * num_connectors
  local total_to_distribute = fluid_amount
  if total_to_distribute > total_connector_capacity then
    total_to_distribute = total_connector_capacity
  end

  local amount_per_connector = total_to_distribute / num_connectors
  for _, connector in ipairs(connectors) do
    connector.fluidbox[1] = {
      name = fluid_name,
      temperature = fluid_temperature,
      amount = amount_per_connector,
    }
  end

  return fluid_amount - total_to_distribute
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
      local fluidbox = connector.fluidbox[1]
      if fluidbox and fluidbox.amount > 0 then
        fill_pipe(counterpart, connector.fluidbox[1].name)
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

local function adjust_connector_to_target(self, connector, fluidbox, target_amount)
  local fluidboxes = connector.fluidbox
  local connector_amount = fluidbox and fluidbox.amount or 0
  local delta = target_amount - connector_amount
  local network_amount = self.fluid_amount or 0
  local network_temperature = self.fluid_temperature or 15
  debug(function() return "before: "..serpent.block{
    network_id = self.id,
    network_amount = self.fluid_amount,
    network_fluid = self.fluid_name,
    connector_position = connector.position,
    connector_amount = fluidbox and fluidbox.amount or 0,
    connector_fluid = fluidbox and fluidbox.name,
    target_amount = target_amount,
    delta = delta,
  } end)
  if delta > 0 then
    if delta > network_amount then
      if network_amount > 0 then
        fluidboxes[1] = {name = self.fluid_name, temperature = network_temperature, amount = connector_amount + network_amount}
        self.fluid_amount = 0
      end
    else
      fluidboxes[1] = {name = self.fluid_name, temperature = network_temperature, amount = target_amount}
      self.fluid_amount = network_amount - delta
    end
  elseif delta < 0 then
    local network_space = network_amount - Constants.NETWORK_CAPACITY
    if network_space > delta then
      delta = network_space
    end
    local new_temp = (network_amount * network_temperature + connector_amount * fluidbox.temperature) / (network_amount + connector_amount)
    self.fluid_amount = network_amount - delta - 1
    self.fluid_temperature = new_temp
    fluidboxes[1] = {name = self.fluid_name, temperature = fluidbox.temperature, amount = connector_amount + delta + 1}
  end
  debug(function() return "after: "..serpent.block{
    network_amount = self.fluid_amount,
    connector_amount = fluidboxes[1] and fluidboxes[1].amount or 0,
  } end)
end

function Network:update_connector(connector, fluidbox)
  local type = PipeConnections.get_connected_connection_type(connector, 1)
  if type == "input" then
    adjust_connector_to_target(self, connector, fluidbox, Constants.CONNECTOR_CAPACITY)
  elseif type == "output" then
    adjust_connector_to_target(self, connector, fluidbox, 0)
  else
    adjust_connector_to_target(self, connector, fluidbox, Constants.CONNECTOR_CAPACITY / 2)
  end
end

function Network:update()
  local connector
  self.connector_iter, connector = next(self.connectors, self.connector_iter)
  if connector then
    local fluidbox = connector.fluidbox[1]
    if fluidbox and fluidbox.name ~= self.fluid_name then
      -- local inferred = self:infer_fluid_from_connectors()
      -- self:set_fluid(inferred)
    end
    self:update_connector(connector, fluidbox)
  end
end

function Network.update_all()
  local network
  for i=1,50 do
    global.network_iter, network = next(all_networks, global.network_iter)
    if network then
      network:update()
    end
  end
end

return Network