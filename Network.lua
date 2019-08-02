local Connector = require "Connector"
local ConnectorSet = require "ConnectorSet"
local dheap = require "lualib.dheap"
local Scheduler = require "lualib.Scheduler"

local debugp = function() end
local function _debugp(...)
  local info = debug.getinfo(2, "nl")
  local out = serpent.block(...)
  if info then
    log(info.name..":"..info.currentline..":"..out)
  else
    log("?:?:"..out)
  end
end
-- debugp = _debugp

local active_update_period = 1
local inactive_update_period
local no_fluid_update_period

local pipe_filler = {name = "water", amount = 0.1}
local function fill_pipe(entity, fluid_name)
  if fluid_name then
    pipe_filler.name = fluid_name
    entity.fluidbox[1] = pipe_filler
  else
    entity.fluidbox[1] = nil
  end
end

local function set_update_periods()
  local base_update_period = settings.global["pipelayer-update-period"].value
  inactive_update_period = base_update_period
  no_fluid_update_period = base_update_period * 5
  debugp("setting update period to "..base_update_period.." ticks.")
end

local Network = {}

local all_networks
local absorb_queue
local network_for_entity = {}

function Network.refresh_locals()
  all_networks = global.all_networks
  if global.absorb_queue then
    absorb_queue = dheap.restore(global.absorb_queue)
  end
end

function Network.on_init()
  global.all_networks = {}
  global.network_iter = nil
  global.absorb_queue = dheap.new()
  Network.on_load()
end

function Network.on_load()
  log("running Network.on_load")
  set_update_periods()
  Network.refresh_locals()
  Scheduler.schedule(0, Network.process_absorb_queue)
  for _, network in pairs(all_networks) do
    setmetatable(network, {__index = Network})
    for unit_number, pipe in pairs(network.pipes) do
      if pipe.valid then
        network_for_entity[unit_number] = network
      end
    end
    ConnectorSet.restore(network.connectors)
    Scheduler.schedule(network.next_tick or 0, function(tick) network:update(tick) end)
  end
end

--[[
  {
    fluid_name = "water",
    pipes = {
      [unit_number] = pipe_entity,
      ...
    },
    connectors = ConnectorSet(),
  }
]]
function Network.new()
  global.network_id = (global.network_id or 0) + 1
  local network_id = global.network_id
  local self = {
    id = network_id,
    fluid_name = nil,
    pipes = {},
    connectors = ConnectorSet.new(),
    next_tick = 0,
  }
  setmetatable(self, {__index = Network})
  Scheduler.schedule(self.next_tick, function(tick) self:update(tick) end)
  all_networks[network_id] = self
  debugp("created new network "..network_id)
  return self
end

function Network.for_unit_number(unit_number)
  return network_for_entity[unit_number]
end

function Network.for_entity(entity)
  return Network.for_unit_number(entity.unit_number)
end

function Network:destroy()
  debugp("destroyed network "..self.id)
  all_networks[self.id] = nil
  if global.network_iter == self.id then
    global.network_iter = nil
  end
end

local function create_marker(surface, position, id)
  local marker = surface.create_entity{
    name = "flying-text",
    position = position,
    text = tostring(id),
  }
  marker.active = false
end

function Network:create_or_destroy_network_markers()
  local _, pipe = next(self.pipes)
  if not pipe or not pipe.valid then return end
  local surface = pipe.surface
  local network_id = self.id

  if settings.global["pipelayer-show-network-ids"].value then
    for _, pipe in pairs(self.pipes) do
      create_marker(surface, pipe.position, network_id)
    end
  else
    for _, entity in ipairs(surface.find_entities_filtered{name = "flying-text"}) do
      entity.destroy()
    end
  end
end

function Network:is_singleton()
  local n = next(self.pipes)
  local n2 = next(self.pipes, n)
  return n and not n2
end

function Network:add_connector(connector)
  self.connectors:add(connector)
end

function Network:remove_connector_by_below_unit_number(below_unit_number)
  local connector = Connector.for_below_unit_number(below_unit_number)
  if connector then
    self.connectors:remove(connector)
  end
end

function Network:add_underground_pipe(underground_pipe, aboveground_connector_entity)
  local surface = underground_pipe.surface
  if surface ~= self.surface then error("tried to add pipe on different surface to Network") end

  local unit_number = underground_pipe.unit_number
  network_for_entity[unit_number] = self
  self.pipes[unit_number] = underground_pipe

  --fill_pipe(underground_pipe, self.fluid_name)

  local connector = Connector.for_below_unit_number(unit_number)
  if connector then
    self:add_connector(connector)
  elseif aboveground_connector_entity then
    local connector = Connector.for_entity(aboveground_connector_entity)
    if not connector then
      connector = Connector.new(aboveground_connector_entity, unit_number)
    end
    fill_pipe(underground_pipe, aboveground_connector_entity.fluidbox.get_locked_fluid(1))
    self:add_connector(connector)
  end

  if settings.global["pipelayer-show-network-ids"].value then
    local position = underground_pipe.position
    local old_marker = surface.find_entity("flying-text", position)
    if old_marker then old_marker.destroy() end
    create_marker(surface, position, self.id)
  end
end

local function start_new_network_from(pipe)
  local old_network = Network.for_entity(pipe)
  if old_network then
    old_network:remove_underground_pipe(pipe, true)
  end

  local new_network = Network.new()
  new_network:add_underground_pipe(pipe)
  local connector = Connector.for_below_unit_number(pipe.unit_number)
  if connector then
    new_network:add_connector(connector)
  end
  Network.absorb_from(pipe)
end

local function break_to_fragments(self, neighbours)
  for i=2,#neighbours do
    local neighbour = neighbours[i]
    start_new_network_from(neighbour)
  end
end

function Network:remove_underground_pipe(entity, by_absorption)
  local surface = entity.surface
  local unit_number = entity.unit_number
  local pipes = self.pipes

  pipes[unit_number] = nil
  self:remove_connector_by_below_unit_number(unit_number)
  if network_for_entity[unit_number] == self then
    network_for_entity[unit_number] = nil
  end

  local old_marker = surface.find_entity("flying-text", entity.position)
  if old_marker then old_marker.destroy() end

  local neighbours = entity.neighbours[1]
  if not by_absorption and #neighbours > 1 then
    break_to_fragments(self, neighbours)
  end

  if not next(pipes) then
    self:destroy()
  end
end

function Network:underground_pipe_replaced(old_unit_number, entity, new_neighbours, removed_neighbours)
  local new_unit_number = entity.unit_number
  network_for_entity[old_unit_number] = nil
  network_for_entity[new_unit_number] = self
  self.pipes[old_unit_number] = nil
  self.pipes[new_unit_number] = entity

  for neighbour in pairs(new_neighbours) do
    self:add_underground_pipe(neighbour)
  end

  for neighbour in pairs(removed_neighbours) do
    self:remove_underground_pipe(neighbour, true)
    start_new_network_from(neighbour)
  end
end

function Network:set_connector_mode(entity, mode)
  local connector = Connector.for_entity(entity)
  if mode == "input" then
    self.connectors:add_input(connector)
  elseif mode == "output" then
    self.connectors:add_output(connector)
  else
    error("invalid mode: "..mode)
  end
  connector.mode = mode
end

function Network:toggle_connector_mode(entity)
  local connector = Connector.for_entity(entity)
  local current_mode = connector.mode
  if current_mode == "input" then
    self:set_connector_mode(entity, "output")
  else
    self:set_connector_mode(entity, "input")
  end
  return connector.mode
end

local function foreach_connector(self, callback)
  local to_remove = {}
  for connector in self.connectors:all_connectors() do
    if connector.entity.valid then
      callback(connector)
    else
      to_remove[#to_remove+1] = connector
    end
  end
  for _, connector in ipairs(to_remove) do
    self.connectors:remove(connector)
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
  self.fluid_name = fluid_name
  if fluid_name == "PIPELAYER-CONFLICT" then
    self:foreach_underground_entity(function(entity)
      fill_pipe(entity, nil)
    end)
  else
    -- make sure underground connector counterparts reflect content of overworld
    foreach_connector(self, function(connector)
      local counterpart = self.surface.find_entity("pipelayer-connector", connector.entity.position)
      fill_pipe(counterpart, fluid_name)
    end)
  end
end

function Network:infer_fluid_from_connectors()
  local inferred_fluid
  local conflict
  foreach_connector(self, function(connector)
    local locked_fluid = connector.entity.fluidbox.get_locked_fluid(1)
    if locked_fluid then
      if inferred_fluid then
        if locked_fluid ~= inferred_fluid then
          conflict = true
          return
        end
      else
        inferred_fluid = locked_fluid
      end
    end
  end)
  if conflict then
    return "PIPELAYER-CONFLICT"
  else
    return inferred_fluid
  end
end

function Network:can_transfer(from, to)
  if not from or not to then return false end
  local fluid_name = self.fluid_name
  return not from:is_conflicting(fluid_name) and not to:is_conflicting(fluid_name)
end

function Network:infer_fluid()
  local fluid_name = self:infer_fluid_from_connectors()
  if fluid_name ~= self.fluid_name then
    self:set_fluid(fluid_name)
    return true
  end
  return false
end

function Network:reschedule(next_tick)
  self.next_tick = next_tick
  Scheduler.schedule(next_tick, function(tick) self:update(tick) end)
end

local function try_to_transfer(self)
  if not all_networks[self.id] then return nil end

  if self.connectors:is_empty() then
    self:set_fluid(nil)
    return no_fluid_update_period
  end

  if not self.fluid_name or self.fluid_name == "PIPELAYER-CONFLICT" then
    local success = self:infer_fluid()
    if not success then
      return no_fluid_update_period
    end
  end

  local next_input_connector = self.connectors:next_input()
  local next_output_connector = self.connectors:next_output()
  if not next_input_connector or not next_output_connector then
    return inactive_update_period
  end

  if self:can_transfer(next_input_connector, next_output_connector) then
    next_input_connector:transfer_to(self.fluid_name, next_output_connector)
  else
    if next_input_connector:is_conflicting(self.fluid_name)
    or next_output_connector:is_conflicting(self.fluid_name) then
      self:set_fluid("PIPELAYER-CONFLICT")
    end
  end

  return active_update_period
end

function Network:update(tick)
  local next_transfer_interval = try_to_transfer(self)
  if next_transfer_interval then
    self:reschedule(tick + next_transfer_interval)
  end
end

--- absorbs a single entity in the specified network
function Network:absorb_one(entity)
  local current_network = Network.for_entity(entity)
  if current_network then
    current_network:remove_underground_pipe(entity, true)
    if current_network.fluid_name ~= self.fluid_name then
      self.fluid_name = nil
    end
  end

  self:add_underground_pipe(entity)
  if entity.name == "pipelayer-connector" then
    connector = Connector.for_below_unit_number(entity.unit_number)
    if connector then
      self:add_connector(connector)
    end
  end
end

--- absorbs all entities into the network with highest index
local function absorb_entities(entities)
  local network_ids = {}
  local highest_network
  local highest_network_id = 0
  for i=1,#entities do
    local entity = entities[i]
    local network = Network.for_entity(entity)
    if network then
      local network_id = network.id
      network_ids[i] = network_id
      if network_id > highest_network_id then
        highest_network = network
        highest_network_id = network_id
      end
    end
  end

  for i=1,#entities do
    local entity = entities[i]
    local old_network_id = network_ids[i]
    if not old_network_id or old_network_id < highest_network_id then
      highest_network:absorb_one(entity)
      absorb_queue:insert(-highest_network_id, entity)
    end
  end
end

local function schedule_absorb(tick)
  Scheduler.schedule(tick + 1, Network.process_absorb_queue)
end

local last_processed_tick
function Network.process_absorb_queue(tick)
  if tick == last_processed_tick then return end
  last_processed_tick = tick

  for i=1,10 do
    local _, next_entity = absorb_queue:pop()
    if not next_entity then
      return
    end
    if next_entity.valid then
      local neighbours = next_entity.neighbours[1]
      neighbours[#neighbours+1] = next_entity
      absorb_entities(neighbours)
    end
  end
  schedule_absorb(tick)
end

function Network.absorb_from(entity)
  log(serpent.line(Network.for_entity(entity)))
  absorb_queue:insert(-Network.for_entity(entity).id, entity)
  schedule_absorb(game.tick)
end

function Network.update_all(event)
  Scheduler.on_tick(event.tick)
end

function Network.on_runtime_mod_setting_changed(event)
  local name = event.setting
  if name == "pipelayer-transfer-threshold" then
    Connector.on_runtime_mod_setting_changed(event)
  elseif name == "pipelayer-update-period" then
    set_update_periods()
  elseif name == "pipelayer-show-network-ids" then
    for _, network in pairs(all_networks) do
      network:create_or_destroy_network_markers()
    end
  end
end

return Network