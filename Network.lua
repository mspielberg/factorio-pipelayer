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
    force = game.forces["player"],
    pipes = {
      pipe_entity,
      ...
    },
    vias = {
      [unit_number] = via_aboveground_entity,
      ...
    }
  }
]]
function Network.new(via)
  global.network_id = (global.network_id or 0) + 1
  local network_id = global.network_id
  local self = {
    id = network_id,
    fluid_name = via.fluidbox[1] and via.fluidbox[1].name,
    force = via.force,
    pipes = {},
    vias = {
      [via.unit_number] = via,
    },
  }
  setmetatable(self, {__index = Network})
  all_networks[network_id] = self
  return self
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
  for unit_number, entity in pairs(other_network.pipes) do
    self.pipes[unit_number] = entity
  end
  for _, via in pairs(other_network.vias) do
    self.vias[#self.vias+1] = via
  end
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
  network_for_entity[entity.unit_number] = self
  self.pipes[entity.unit_number] = entity
  fill_pipe(entity, self.fluid_name)
end

function Network:remove_underground_pipe(entity)
  assert(entity.surface.name == surface_name)
  self.pipes[entity.unit_number] = nil
  network_for_entity[entity.unit_number] = nil
end

function Network:balance()
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
    temperature = total_temperature / num_vias,
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
  self.fluid_name = fluid_name
  self.foreach_underground_entity(function(entity)
    fill_pipe(entity, self.fluid_name)
  end)
  local surface = game.surfaces[surface_name]
  for _, via in pairs(self.vias) do
    local counterpart = surface.find_entity("plumbing-via", via.position)
    local fluidbox = via.fluidbox
    if fluidbox and fluidbox.amount > 0 then
      fill_pipe(counterpart, via.fluid)
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
  if inferred == self.fluid_type then
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