local Constants = require "Constants"

local SURFACE_NAME = Constants.SURFACE_NAME

local M = {}

function M.on_player_setup_blueprint(event)
  local player_index = event.player_index
  local player = game.players[player_index]
  local surface = player.surface
  if surface.name ~= "nauvis" then return end

  local bp = player.blueprint_to_setup
  if not bp or not bp.valid_for_read then bp = player.cursor_stack end
  local bp_entities = bp.get_blueprint_entities()
  local area = event.area

  local anchor_via = surface.find_entities_filtered{
    area = area,
    name = "plumbing-via",
  }[1]
  if not anchor_via then return end

  local plumbing_surface = game.surfaces[SURFACE_NAME]

  -- find counterpart in blueprint
  local world_to_bp
  for _, bp_entity in ipairs(bp_entities) do
    if bp_entity.name == "plumbing-via" then
      game.print(serpent.line{bp=bp_entity.direction,anchor=anchor_via.direction})
      local x_offset = bp_entity.position.x - anchor_via.position.x
      local y_offset = bp_entity.position.y - anchor_via.position.y
      world_to_bp = function(position)
        return { x = position.x + x_offset, y = position.y + y_offset }
      end
      break
    end
  end

  for _, ug_pipe in ipairs(plumbing_surface.find_entities(area)) do
    bp_entities[#bp_entities + 1] = {
      entity_number = #bp_entities + 1,
      name = "plumbing-bpproxy-"..ug_pipe.name,
      position = world_to_bp(ug_pipe.position),
      direction = ug_pipe.direction,
    }
  end
  bp.set_blueprint_entities(bp_entities)
end

return M