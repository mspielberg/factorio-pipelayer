local Constants = require "Constants"

local SURFACE_NAME = Constants.SURFACE_NAME

local M = {}

function M.on_init()
  global.editor_ghosts = {}
end

function M.is_setup_bp(stack)
  return stack and
    stack.valid and
    stack.valid_for_read and
    stack.is_blueprint and
    stack.is_blueprint_setup()
end

function M.bounding_box(bp)
  local left = -0.1
  local top = -0.1
  local right = 0.1
  local bottom = 0.1

  local entities = bp.get_blueprint_entities()
  if entities then
    for _, e in pairs(entities) do
      local pos = e.position
      if pos.x < left then left = pos.x - 0.5 end
      if pos.y < top then top = pos.y - 0.5 end
      if pos.x > right then right = pos.x + 0.5 end
      if pos.y > bottom then bottom = pos.y + 0.5 end
    end
  end

  return {
    left_top = {x=left, y=top},
    right_bottom = {x=right, y=bottom},
  }
end

local pipe_request_chest
local pipe_request_proxy
local pending_pipe_ghosts
local pending_pipe_counts

local function add_item_request(name)
  if pipe_request_proxy then
    local requests = pipe_request_proxy.item_requests
    requests[name] = (requests[name] or 0) + 1
    pipe_request_proxy.item_requests = requests
  elseif pipe_request_chest then
    pending_pipe_counts[name] = (pending_pipe_counts[name] or 0) + 1
    pipe_request_proxy = pipe_request_chest.surface.create_entity{
      name = "item-request-proxy",
      position = pipe_request_chest.position,
      force = pipe_request_chest.force,
      target = pipe_request_chest,
      modules = pending_pipe_counts,
    }
    pipe_request_proxy.last_user = pipe_request_chest.last_user
    pending_pipe_counts = nil
  end
end

function M.on_player_built_entity(event)
  local entity = event.created_entity
  if entity.name ~= "entity-ghost" then return end
  local nonproxy_name = entity.ghost_name:match("^plumbing%-bpproxy%-(.*)$")
  if not nonproxy_name then return end

  local surface = entity.surface
  local position = entity.position
  local editor_surface = game.surfaces[SURFACE_NAME]
  local create_entity_args = {
    name = "entity-ghost",
    inner_name = nonproxy_name,
    position = position,
    force = entity.force,
    direction = entity.direction,
  }
  if editor_surface.can_place_entity(create_entity_args) then
    local editor_ghost = editor_surface.create_entity(create_entity_args)
    editor_ghost.last_user = entity.last_user

    if nonproxy_name == "plumbing-via" and not pipe_request_chest then
      pipe_request_chest = surface.create_entity{
        name = "plumbing-pipe-request-chest",
        position = position,
        force = entity.force,
      }
      pipe_request_chest.operable = false
      pipe_request_chest.last_user = entity.last_user
      global.editor_ghosts[pipe_request_chest.unit_number] = pending_pipe_ghosts
      pending_pipe_ghosts = nil
    elseif pipe_request_chest then
      add_item_request(nonproxy_name)
    else
      pending_pipe_ghosts[#pending_pipe_ghosts + 1] = editor_ghost
      pending_pipe_counts[nonproxy_name] = (pending_pipe_counts[nonproxy_name] or 0) + 1
    end
  end

  entity.destroy()
end

function M.on_put_item(_)
  pipe_request_chest = nil
  pipe_request_proxy = nil
  pending_pipe_ghosts = {}
  pending_pipe_counts = {}
end

local function insert_or_spill(player, stack)
  local inserted = player.insert(stack)
  if inserted < stack.count then
    player.surface.spill_item_stack{name = stack.name, count = stack.count - inserted}
  end
end

local function cleanup_surface_via(player, surface_via)
  local surface = surface_via.surface
  local position = surface_via.position
  local chest = surface.find_entity("plumbing-pipe-request-chest", position)
  if chest then
    local inv = pipe_request_chest.get_inventory(defines.inventory.chest)
    for i=1,#inv do
      local stack = inv[i]
      if stack.valid_for_read then
        insert_or_spill(player, stack)
      end
    end
    global.editor_ghosts[chest.unit_number] = nil
    chest.destroy()
  end
end

local function player_mined_surface_via_ghost(player, ghost)
  local counterpart = game.surfaces[SURFACE_NAME].find_entity("entity-ghost", ghost.position)
  if counterpart and counterpart.ghost_name == "plumbing-via" then
    counterpart.destroy()
  end
  cleanup_surface_via(player, ghost)
end

local function player_mined_underground_via_ghost(player, ghost)
  local counterpart = game.surfaces.nauvis.find_entity("entity-ghost", ghost.position)
  if counterpart and counterpart.ghost_name == "plumbing-via" then
    cleanup_surface_via(player, counterpart)
    counterpart.destroy()
  end
end

function M.on_pre_player_mined_item(player_index, entity)
  if entity.name == "entity-ghost" and entity.ghost_name == "plumbing-via" then
    local player = game.players[player_index]
    if entity.surface.name == SURFACE_NAME then
      return player_mined_underground_via_ghost(player, entity)
    else
      return player_mined_surface_via_ghost(player, entity)
    end
  end
end

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