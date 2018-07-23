local surface_name = "plumbing"

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

--[[
  {
    "surface_name" = {
      [x] = {
        [y] = network,
        ...
      },
      ...
    },
    ...
  }
]]
global.network_for_via = global.network_for_via or {}
local network_for_via = global.network_for_via

-- Network class
local Network = {}
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
  self.vias[entity.unit_number] = entity
end

function Network:add_underground_pipe(entity)
  self.pipes[entity.unit_number] = entity
end

function Network:balance()
  local total_amount = 0
  local total_temperature = 0
  local num_vias = 0
  for unit_number, via in pairs(self.vias) do
    if via.valid then
      local fluidbox = via.fluidbox[1]
      local amount = fluidbox.amount
      total_amount = total_amount + amount
      total_temperature = total_temperature + amount * fluidbox.temperature
      num_vias = num_vias + 1
    else
      self.vias[unit_number] = nil
    end
  end

  local new_fluid = {name = self.fluid_name, amount = total_amount / num_vias, temperature = total_temperature / num_vias }
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

local pipe_capacity_cache = {}
local function pipe_capacity(name)
  if not pipe_capacity_cache[name] then
    pipe_capacity_cache[name] = game.entity_prototypes[name].fluid_capacity
  end
  return pipe_capacity_cache[name]
end

function Network:set_fluid(fluid_name)
  self.fluid_name = fluid_name
  if fluid_name then
    self.foreach_underground_entity(function(entity)
      local new_fluid = {name = self.fluid_name, amount = pipe_capacity(entity.name)}
      entity.fluidbox[1] = new_fluid
    end)
  else
    self.foreach_underground_entity(function(entity)
      entity.fluidbox[1] = nil
    end)
  end
end

function Network:infer_fluid_from_vias()
  local inferred_fluid
  for _, via in pairs(self.vias) do
    if inferred_fluid then
      local via_fluid = via.fluidbox[1].name
      if via_fluid and via_fluid ~= inferred_fluid then
        return nil
      end
    else
      inferred_fluid = via.fluidbox[1].name
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

return Network