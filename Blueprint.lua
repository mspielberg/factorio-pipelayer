local Constants = require "Constants"
local Editor = require "Editor"

local SURFACE_NAME = Constants.SURFACE_NAME

local M = {}

local function debug(...)
  log(...)
end

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

do
  local pipe_request_chest
  local pipe_request_proxy
  local pending_pipe_ghosts
  local pending_pipe_counts

  local function create_pipe_request_proxy()
    debug("creating pipe_request_proxy")
    pipe_request_proxy = pipe_request_chest.surface.create_entity{
      name = "item-request-proxy",
      position = pipe_request_chest.position,
      force = pipe_request_chest.force,
      target = pipe_request_chest,
      modules = pending_pipe_counts,
    }
    pipe_request_proxy.last_user = pipe_request_chest.last_user
  end

  local function add_item_request(ghost, name)
    pending_pipe_counts[name] = (pending_pipe_counts[name] or 0) + 1
    pending_pipe_ghosts[ghost.unit_number] = ghost
  end

  local function defer(func)
    script.on_event(defines.events.on_tick, function(event)
      func(event)
      script.on_event(defines.events.on_tick, nil)
    end)
  end

  local function player_built_surface_via_ghost(entity)
    defer(function(_)
      local position = entity.position
      local surface = entity.surface
      if not pipe_request_chest then
        debug("creating pipe_request_chest")
        pipe_request_chest = surface.create_entity{
          name = "plumbing-pipe-request-chest",
          position = position,
          force = entity.force,
        }
        pipe_request_chest.operable = false
        pipe_request_chest.last_user = entity.last_user
        global.editor_ghosts[pipe_request_chest.unit_number] = {
          chest = pipe_request_chest,
          ghosts = pending_pipe_ghosts,
          pipe_counts = pending_pipe_counts,
        }
      end
      if not pipe_request_proxy and next(pending_pipe_counts) then
        create_pipe_request_proxy()
      end
    end)
  end

  local function player_built_plumbing_bpproxy_ghost(ghost, nonproxy_name)
    debug("placing ghost for "..nonproxy_name)
    local position = ghost.position
    local editor_surface = game.surfaces[SURFACE_NAME]
    local create_entity_args = {
      name = "entity-ghost",
      inner_name = nonproxy_name,
      position = position,
      force = ghost.force,
      direction = ghost.direction,
    }

    if editor_surface.can_place_entity(create_entity_args) then
      local editor_ghost = editor_surface.create_entity(create_entity_args)
      editor_ghost.last_user = ghost.last_user
      if nonproxy_name ~= "plumbing-via" then
        add_item_request(editor_ghost, nonproxy_name)
      end
    end

    ghost.destroy()
  end

  function M.on_player_built_entity(event)
    local entity = event.created_entity
    if entity.surface ~= game.surfaces.nauvis then return end
    if entity.name ~= "entity-ghost" then return end
    if entity.ghost_name == "plumbing-via" then return player_built_surface_via_ghost(entity) end

    local nonproxy_name = entity.ghost_name:match("^plumbing%-bpproxy%-(.*)$")
    if nonproxy_name then return player_built_plumbing_bpproxy_ghost(entity, nonproxy_name) end
  end

  function M.on_put_item(_)
    pipe_request_chest = nil
    pipe_request_proxy = nil
    pending_pipe_ghosts = {}
    pending_pipe_counts = {}
  end
end

local function insert_or_spill(insertable, player, stack)
  local inserted = insertable.insert(stack)
  if inserted < stack.count then
    player.surface.spill_item_stack{position = player.position, name = stack.name, count = stack.count - inserted}
  end
end

local function cleanup_surface_via(surface_via, player, insertable)
  local surface = surface_via.surface
  local position = surface_via.position
  local chest = surface.find_entity("plumbing-pipe-request-chest", position)
  if chest then
    local inv = chest.get_inventory(defines.inventory.chest)
    for i=1,#inv do
      local stack = inv[i]
      if stack.valid_for_read then
        insert_or_spill(insertable, player, stack)
      end
    end
    editor_ghosts[chest.unit_number] = nil
    chest.destroy()
  end
end

local function player_mined_surface_via_ghost(player, ghost)
  local counterpart = game.surfaces[SURFACE_NAME].find_entity("entity-ghost", ghost.position)
  if counterpart and counterpart.ghost_name == "plumbing-via" then
    counterpart.destroy()
  end
  cleanup_surface_via(ghost, player, player)
end

local function player_mined_underground_via_ghost(player, ghost)
  local counterpart = game.surfaces.nauvis.find_entity("entity-ghost", ghost.position)
  if counterpart and counterpart.ghost_name == "plumbing-via" then
    cleanup_surface_via(counterpart, player, player)
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

function M.on_player_mined_entity(player_index, entity, buffer)
  if entity.name == "plumbing-via" and entity.surface == game.surfaces.nauvis then
    local player = game.players[player_index]
    cleanup_surface_via(entity, player, buffer)
  end
end

------------------------------------------------------------------------------------------------------------------------
-- capture underground pipes as bpproxy ghosts

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
    if ug_pipe.name ~= "entity-ghost" then
      bp_entities[#bp_entities + 1] = {
        entity_number = #bp_entities + 1,
        name = "plumbing-bpproxy-"..ug_pipe.name,
        position = world_to_bp(ug_pipe.position),
        direction = ug_pipe.direction,
      }
    end
  end
  bp.set_blueprint_entities(bp_entities)
end

local function count_can_build(chest_inventory, pipe_counts)
  local out = {}
  local actual_available = chest_inventory.get_contents()
  for pipe_name, requested in pairs(pipe_counts) do
    local can_build =  math.min(requested, actual_available[pipe_name] or 0)
    pipe_counts[pipe_name] = pipe_counts[pipe_name] - can_build
    out[pipe_name] = can_build
  end
  return out
end

local function cleanup_pipe_request_chest(chest, chest_inventory)
  local request_proxy = chest.surface.find_entity("item-request-proxy", chest.position)
  if request_proxy then
    request_proxy.destroy()
  end

  if chest_inventory.is_empty() then
    chest.destroy()
  else
    chest.order_deconstruction(chest.force)
  end
end

function M.build_underground_ghosts()
  for chest_unit_number, chest_info in pairs(global.editor_ghosts) do
    local chest = chest_info.chest
    local ghosts = chest_info.ghosts
    local pipe_counts = chest_info.pipe_counts
    if chest.valid then
      local chest_inventory = chest.get_inventory(defines.inventory.chest)
      local can_build = count_can_build(chest_inventory, pipe_counts)
      for ghost_unit_number, ghost in pairs(ghosts) do
        if ghost.valid then
          local entity_name = ghost.ghost_name
          local count = can_build[entity_name] or 0
          if count > 0 then
            chest_inventory.remove{name=entity_name, count=1}
            local _, revived = ghost.revive()
            Editor.connect_underground_pipe(revived)
            can_build[entity_name] = can_build[entity_name] - 1
            ghosts[ghost_unit_number] = nil
          end
        else
          ghosts[ghost_unit_number] = nil
        end
      end

      if not next(ghosts) then
        cleanup_pipe_request_chest(chest, chest_inventory)
        global.editor_ghosts[chest_unit_number] = nil
      end
    else
      global.editor_ghosts[chest_unit_number] = nil
    end
  end
end

return M