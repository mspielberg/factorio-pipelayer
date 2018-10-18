serpent = require "serpent"
local M = {}

-- connection_type[entity_name] = { [x] = { [y] = "input", ...}, ... }
-- derived from prototypes pipe_connections
local connection_type = {
  -- base
  ["assembling-machine-2"] = {
    [0] = { [-2] = "input", [2] = "output" },
  },
  ["assembling-machine-3"] = {
    [0] = { [-2] = "input", [2] = "output" },
  },
  ["boiler"] = {
    [-2] = { [0.5] = "input" },
    [0] = { [-1.5] = "output" },
    [2] = { [0.5] = "input" },
  },
  ["chemical-plant"] = {
    [-1] = { [-2] = "input", [2] = "output" },
    [1] = { [-2] = "input", [2] = "output" },
  },
  ["heat-exchanger"] = {
    [-2] = { [0.5] = "input" },
    [0] = { [-1.5] = "output" },
    [2] = { [0.5] = "input" },
  },
  ["offshore-pump"] = {
    [0] = { [1] = "output" },
  },
  ["oil-refinery"] = {
    [-1] = { [3] = "input" },
    [1] = { [3] = "input" },
    [-2] = { [-3] = "output" },
    [0] = { [-3] = "output" },
    [2] = { [-3] = "output" },
  },
  ["pump"] = {
    [0] = { [-1.5] = "output", [1.5] = "input" },
  },
  ["steam-engine"] = {
    [0] = { [-3] = "input", [3] = "input" },
  },
  ["steam-turbine"] = {
    [0] = { [-3] = "input", [3] = "input" },
  },
}

-- Calculates p2's position in relation to entity at p1 with direction
-- as if p1 were the origin with direction north.
local function get_offset(p1, direction, p2)
  local dx = p2.x - p1.x
  local dy = p2.y - p1.y
  if direction == defines.direction.north then return dx, dy
  elseif direction == defines.direction.east then return dy, -dx
  elseif direction == defines.direction.south then return -dx, -dy
  elseif direction == defines.direction.west then return -dy, dx
  end
end

local function get_connection_type(entity, world_position)
  local dx, dy = get_offset(entity.position, entity.direction, world_position)
  local xs = connection_type[entity.name]
  if not xs then return "input-output" end
  local ys = xs[dx]
  if not ys then return "input-output" end
  local type = ys[dy]
  return type or "input-output"
end

function M.get_connected_connection_type(entity, fluidbox_index)
  local other_fluidbox = entity.fluidbox.get_connections(fluidbox_index)[1]
  if other_fluidbox then
    local other_entity = other_fluidbox.owner
    return get_connection_type(other_entity, entity.position)
  else
    return "input-output"
  end
end

return M