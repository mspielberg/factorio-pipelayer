local Graph = require "Graph"

local surface_name = "plumbing"

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
    vias = {
      [unit_number] = via_aboveground_entity,
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
    vias = {},
  }
  setmetatable(self, {__index = Network})
  all_networks[network_id] = self
  return self
end

function Network:destroy()
  all_networks[self.id] = nil
end

function Network.for_entity(entity)
  return network_for_entity[entity.unit_number]
end

function Network:can_absorb(other_network)
  return other_network.fluid_name == self.fluid_name or other_network.fluid_name == nil or self.fluid_name == nil
end

function Network:absorb(other_network)
  if not self.fluid_name then
    self.fluid_name = other_network.fluid_name
  end
  for _, entity in pairs(other_network.pipes) do
    self:add_underground_pipe(entity)
  end
  for _, via in pairs(other_network.vias) do
    self.vias[#self.vias+1] = via
  end
  other_network:destroy()
end

function Network:add_via(entity)
  assert(entity.name == "plumbing-via")
  assert(entity.surface.name == "nauvis")
  self.vias[entity.unit_number] = entity
end

function Network:remove_via(entity)
  assert(entity.name == "plumbing-via")
  assert(entity.surface.name == "nauvis")
  self.vias[entity.unit_number] = nil
end

function Network:add_underground_pipe(entity)
  assert(entity.surface.name == surface_name)
  local unit_number = entity.unit_number
  network_for_entity[unit_number] = self
  self.pipes[unit_number] = entity
  self.graph:add(unit_number)
  for _, neighbor in ipairs(entity.neighbours[1]) do
    self.graph:add(unit_number, neighbor.unit_number)
  end
  fill_pipe(entity, self.fluid_name)
  game.print("added pipe "..entity.unit_number.." to network "..self.id)
end

local function set_to_list(set)
  local out = {}
  for k in pairs(set) do
    out[#out+1] = k
  end
  return out
end

function Network:remove_underground_pipe(entity)
  game.print("before = "..self.graph:tostring())
  assert(entity.surface.name == surface_name)
  local unit_number = entity.unit_number
  self.pipes[unit_number] = nil
  network_for_entity[unit_number] = nil

  local fragments = self.graph:removal_fragments(unit_number)
  for i=2,#fragments do
    local fragment = fragments[i]
    local split_network = Network.new()
    game.print(serpent.block{
      msg="created network "..split_network.id.." as split from "..self.id,
      pipes=set_to_list(self.pipes),
      fragment= fragment})
    for fragment_pipe_unit_number in pairs(fragment) do
      split_network:add_underground_pipe(self.pipes[fragment_pipe_unit_number])
      network_for_entity[fragment_pipe_unit_number] = split_network
      self.pipes[fragment_pipe_unit_number] = nil
      game.print("removing "..fragment_pipe_unit_number.." from graph")
      self.graph:remove(fragment_pipe_unit_number)
    end
    split_network.graph:remove(unit_number)
  end
  self.graph:remove(unit_number)
  game.print("after = "..self.graph:tostring())
  if not next(self.pipes) then
    self:destroy()
  end
end

function Network:balance()
  if not self.fluid_name then return end

  local total_amount = 0
  local total_temperature = 0
  local num_vias = 0
  for unit_number, via in pairs(self.vias) do
    if via.valid then
      local fluidbox = via.fluidbox[1]
      if fluidbox then
        local amount = fluidbox.amount
        total_amount = total_amount + amount
        total_temperature = total_temperature + amount * fluidbox.temperature
      end
      num_vias = num_vias + 1
    else
      self.vias[unit_number] = nil
    end
  end

  local new_fluid = {
    name = self.fluid_name,
    amount = total_amount / num_vias,
    temperature = total_temperature / total_amount,
  }
  for _, via in pairs(self.vias) do
    via.fluidbox[1] = new_fluid
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
  game.print("setting fluid for network "..self.id.." to "..(fluid_name or "(nil)"))
  self.fluid_name = fluid_name
  self:foreach_underground_entity(function(entity)
    fill_pipe(entity, self.fluid_name)
  end)
  local surface = game.surfaces[surface_name]
  for _, via in pairs(self.vias) do
    local counterpart = surface.find_entity("plumbing-via", via.position)
    local fluidbox = via.fluidbox[1]
    if fluidbox and fluidbox.amount > 0 then
      fill_pipe(counterpart, via.fluidbox[1].name)
    end
  end
end

function Network:infer_fluid_from_vias()
  local inferred_fluid
  for _, via in pairs(self.vias) do
    local via_fluidbox = via.fluidbox[1]
    if via_fluidbox then
      if inferred_fluid then
        if via_fluidbox.name ~= inferred_fluid then
          return nil
        end
      else
        inferred_fluid = via_fluidbox.name
      end
    end
  end
  return inferred_fluid
end

function Network:update()
  local inferred = self:infer_fluid_from_vias()
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