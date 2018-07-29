local Constants = require "Constants"
local Graph = require "Graph"
local PipeConnections = require "PipeConnections"

local function debug(...)
  game.print(...)
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
    Graph = Graph(),
    pipes = {
      [unit_number] = pipe_entity,
      ...
    },
    connectors = {
      [underground_unit_number] = connector_aboveground_entity,
      ...
    }
  }
]]
function Network.new()
  global.network_id = (global.network_id or 0) + 1
  local network_id = global.network_id
  local self = {
    id = network_id,
    fluid_name = nil,
    graph = Graph.new(),
    pipes = {},
    connectors = {},
  }
  setmetatable(self, {__index = Network})
  all_networks[network_id] = self
  return self
end

function Network.for_entity(entity)
  return network_for_entity[entity.unit_number]
end

function Network:destroy()
  debug("destroying network "..self.id)
  all_networks[self.id] = nil
end

function Network:is_singleton()
  local n = next(self.pipes)
  local n2 = next(self.pipes, n)
  return n and not n2
end

function Network:absorb(other_network)
  if not self.fluid_name then
    self.fluid_name = other_network.fluid_name
  end
  for _, entity in pairs(other_network.pipes) do
    self:add_underground_pipe(entity)
  end
  for underground_unit_number, connector in pairs(other_network.connectors) do
    self:add_connector(connector, underground_unit_number)
  end
  other_network:destroy()
  self:update()
end

function Network:add_connector(above, below_unit_number)
  self.connectors[below_unit_number] = above
  self:update()
end

function Network:remove_connector(below_unit_number)
  self.connectors[below_unit_number] = nil
  self:update()
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
  self:update()
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
      split_network:update()
    end
  end

  self.graph:remove(unit_number)
  if next(self.pipes) then
    self:update()
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

function Network:balance()
  local fluid_name = self.fluid_name
  if not fluid_name then return end

  local total_amount = 0
  local total_temperature = 0
  local num_connectors = 0
  local output_connectors = {}
  local input_connectors = {}
  local other_connectors = {}

  foreach_connector(self, function(connector)
      local fluidbox = connector.fluidbox[1]
      if fluidbox then
        local amount = fluidbox.amount
        total_amount = total_amount + amount
        total_temperature = total_temperature + amount * fluidbox.temperature
      end
      num_connectors = num_connectors + 1

      local type = PipeConnections.get_connected_connection_type(connector, 1)
      if type == "input" then
        input_connectors[#input_connectors+1] = connector
      elseif type == "output" then
        output_connectors[#output_connectors+1] = connector
      else
        other_connectors[#other_connectors+1] = connector
      end
  end)
  local average_temp = (total_amount > 0 and total_temperature / total_amount or 15)

  -- distribute fluid by priority
  total_amount = distribute(input_connectors, fluid_name, total_amount, average_temp)
  total_amount = distribute(other_connectors, fluid_name, total_amount, average_temp)
  total_amount = distribute(output_connectors, fluid_name, total_amount, average_temp)
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
      local counterpart = surface.find_entity("plumbing-connector", connector.position)
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

function Network:update()
  local inferred = self:infer_fluid_from_connectors()
  if inferred == self.fluid_name then
    self:balance()
  else
    self:set_fluid(inferred)
  end
end

function Network.update_all()
  for _, network in pairs(all_networks) do
    network:update()
  end
end

return Network