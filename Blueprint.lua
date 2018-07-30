local Constants = require "Constants"
local Editor = require "Editor"
require "util"

local SURFACE_NAME = Constants.SURFACE_NAME
local debug = function() end
if Constants.DEBUG_ENABLED then
  debug = log
end

local M = {}

local editor_surface

function M.on_init()
  M.on_load()
end

function M.on_load()
  editor_surface = global.editor_surface
end

function M.is_setup_bp(stack)
  return stack and
    stack.valid and
    stack.valid_for_read and
    stack.is_blueprint and
    stack.is_blueprint_setup()
end

-- returns BoundingBox of blueprint entities (not tiles!) in blueprint coordinates
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

local function find_in_area(surface, area, args)
  local find_args = util.table.deepcopy(args)
  if area.left_top.x >= area.right_bottom.x or area.left_top.y >= area.right_bottom.y then
    find_args.position = area.left_top
  else
    find_args.area = area
  end
  return surface.find_entities_filtered(find_args)
end

local function nonproxy_name(name)
  return name:match("^pipefitter%-bpproxy%-(.*)$")
end

local function counterpart_surface(surface)
  if surface.name == SURFACE_NAME then
    return game.surfaces.nauvis
  end
  return editor_surface
end

local function surface_counterpart(entity)
  local name = entity.name
  if name == "pipefitter-connector" then
    return game.surfaces.nauvis.find_entity(name, entity.position)
  end
  return game.surfaces.nauvis.find_entity("pipefitter-bpproxy-"..name, entity.position)
end

local function underground_counterpart(entity)
  local pipe_name = nonproxy_name(entity.name)
  if pipe_name then
    return editor_surface.find_entity(pipe_name, entity.position)
  end
  return editor_surface.find_entity(entity.name, entity.position)
end

-- converts overworld bpproxy ghost to regular ghost underground
local function on_player_built_bpproxy_ghost(ghost, pipe_name)
  local position = ghost.position
  local create_entity_args = {
    name = "entity-ghost",
    inner_name = pipe_name,
    position = position,
    force = ghost.force,
    direction = ghost.direction,
  }

  if editor_surface.can_place_entity(create_entity_args) then
    local editor_ghost = editor_surface.create_entity(create_entity_args)
    editor_ghost.last_user = ghost.last_user
    if pipe_name == "pipefitter-connector" then
      ghost.destroy()
    end
  else
    ghost.destroy()
  end
end

local function on_player_built_underground_ghost(ghost)
  game.surfaces.nauvis.create_entity{
    name = "entity-ghost",
    inner_name = "pipefitter-bpproxy-"..ghost.ghost_name,
    position = ghost.position,
    force = ghost.force,
    direction = ghost.direction
  }
end

local function on_player_built_ghost(ghost)
  local pipe_name = nonproxy_name(ghost.ghost_name)
  if pipe_name then
    if editor_surface.find_entity("entity-ghost", ghost.position) then
      ghost.destroy()
      return
    end
    return on_player_built_bpproxy_ghost(ghost, pipe_name)
  end
  if ghost.surface == editor_surface then
    local surface_ghost = game.surfaces.nauvis.find_entity("entity-ghost", ghost.position)
    if surface_ghost and
      (surface_ghost.ghost_name == "pipefitter-connector" or nonproxy_name(surface_ghost.ghost_name)) then
      ghost.destroy()
      return
    end
    return on_player_built_underground_ghost(ghost)
  end
end

local function create_underground_pipe(name, position, force, direction)
  local underground_pipe = editor_surface.create_entity{
    name = name,
    position = position,
    force = force,
    direction = direction,
  }
  game.surfaces.nauvis.create_entity{
    name="flying-text",
    position=position,
    text={"pipefitter-message.created-underground", underground_pipe.localised_name},
  }
  Editor.connect_underground_pipe(underground_pipe)
end

local ghost_mined
function M.on_player_built_entity(event)
  local entity = event.created_entity
  if entity.name == "entity-ghost" then
    return on_player_built_ghost(entity)
  end

  if entity.surface ~= game.surfaces.nauvis then return end
  if not ghost_mined then return end

  local name = entity.name
  local direction = entity.direction
  local position = entity.position
  local force = entity.force
  if ghost_mined.tick == event.tick and
    ghost_mined.name == name and
    ghost_mined.position.x == position.x and
    ghost_mined.position.y == position.y and
    ghost_mined.direction == direction and
    ghost_mined.force == force.name or force.get_friend(ghost_mined.force) then
      create_underground_pipe(name, position, force, entity.direction)
      entity.destroy()
  end
end

function M.on_robot_built_entity(_, entity, _)
  local surface = entity.surface
  if surface ~= game.surfaces.nauvis then return end
  local pipe_name = nonproxy_name(entity.name)
  if not pipe_name then return end
  create_underground_pipe(pipe_name, entity.position, entity.force, entity.direction)
  entity.destroy()
end

local function player_mined_connector_ghost(connector_ghost)
  local counterpart = counterpart_surface(connector_ghost.surface).find_entity("entity-ghost", connector_ghost.position)
  if counterpart and counterpart.ghost_name == "pipefitter-connector" then
    counterpart.destroy()
  end
end

function M.on_pre_player_mined_item(event)
  local entity = event.entity
  if entity.name == "entity-ghost" then
    local ghost_name = entity.ghost_name
    local pipe_name = nonproxy_name(ghost_name)
    if pipe_name then
      ghost_mined = {
        tick = event.tick,
        name = pipe_name,
        direction = entity.direction,
        force = entity.force.name,
        position = entity.position,
      }
    elseif ghost_name == "pipefitter-connector" then
      return player_mined_connector_ghost(entity)
    end
  end
end

local function on_player_mined_surface_entity(entity)
  local pipe_name = nonproxy_name(entity.name)
  if not pipe_name then return end
  local counterpart = underground_counterpart(entity)
  if counterpart then
    Editor.disconnect_underground_pipe(counterpart)
    counterpart.destroy()
  end
end

local function on_player_mined_underground_entity(entity)
  local counterpart = surface_counterpart(entity)
  if counterpart then
    counterpart.destroy()
  end
end

function M.on_player_mined_entity(_, entity, _)
  if not entity.valid then return end
  game.print(entity.surface.name)
  if entity.surface == editor_surface then
    return on_player_mined_underground_entity(entity)
  elseif entity.surface == game.surfaces.nauvis then
    return on_player_mined_surface_entity(entity)
  end
end

function M.on_robot_mined_entity(_, entity, _)
  if not entity.valid or entity.surface ~= game.surfaces.nauvis then return end
  local pipe_name = nonproxy_name(entity.name)
  if not pipe_name then return end
  local counterpart = underground_counterpart(entity)
  if counterpart then
    Editor.disconnect_underground_pipe(counterpart)
    counterpart.destroy()
  end
end

------------------------------------------------------------------------------------------------------------------------
-- deconstruction

local function order_underground_deconstruction(player, area)
  local nauvis = game.surfaces.nauvis
  local num_to_deconstruct = 0
  local underground_pipes = find_in_area(editor_surface, area, {})
  for _, pipe in ipairs(underground_pipes) do
    if pipe.name == "pipefitter-connector" then
      pipe.minable = true
      pipe.order_deconstruction(pipe.force)
      pipe.minable = false
    else
      local proxy = nauvis.create_entity{
        name = "pipefitter-bpproxy-"..pipe.name,
        position = pipe.position,
        force = pipe.force,
        direction = pipe.direction,
      }
      proxy.destructible = false
      proxy.order_deconstruction(proxy.force, player)
      pipe.order_deconstruction(pipe.force)
      num_to_deconstruct = num_to_deconstruct + 1
    end
  end
  return underground_pipes
end

local function area_contains_connectors(area)
  local nauvis = game.surfaces.nauvis
  return find_in_area(nauvis, area, {name = "pipefitter-connector", limit = 1})[1] or
    find_in_area(nauvis, area, {name = "entity-ghost", ghost_name = "pipefitter-connector", limit = 1})[1]
end

local function on_player_deconstructed_surface_area(player, area)
  local selected_connectors = find_in_area(game.surfaces.nauvis, area, {name = "pipefitter-connector", limit = 1})
  if not next(selected_connectors) then return end
  local underground_pipes = order_underground_deconstruction(player, area)
  if settings.get_player_settings(player)["pipefitter-deconstruction-warning"].value then
    player.print({"pipefitter-message.marked-for-deconstruction", #underground_pipes})
  end
end

local function on_player_deconstructed_underground_area(player, area)
  local underground_pipes = order_underground_deconstruction(player, area)
  for _, pipe in ipairs(underground_pipes) do
    if pipe.name == "pipefitter-connector" then
      local counterpart = surface_counterpart(pipe)
      if counterpart then
        counterpart.order_deconstruction(counterpart.force)
      end
    end
  end
end

function M.on_player_deconstructed_area(player_index, area, _, alt)
  if alt then return end
  local player = game.players[player_index]
  if player.surface == game.surfaces.nauvis then
    return on_player_deconstructed_surface_area(player, area)
  elseif player.surface == editor_surface then
    return on_player_deconstructed_underground_area(player, area)
  end
end

function M.on_canceled_deconstruction(entity, _)
  if entity.surface == game.surfaces.nauvis then
    local counterpart = underground_counterpart(entity)
    if counterpart and counterpart.to_be_deconstructed(counterpart.force) then
      counterpart.cancel_deconstruction(counterpart.force)
    end
  elseif entity.surface == editor_surface then
    local counterpart = surface_counterpart(entity)
    if counterpart then
      if counterpart.name == "pipefitter-connector" then
        counterpart.cancel_deconstruction(counterpart.force)
      else
        counterpart.destroy()
      end
    end
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

  local anchor_connector = find_in_area(surface, area, { name = "pipefitter-connector"})[1]
  if not anchor_connector then return end

  local pipefitter_surface = game.surfaces[SURFACE_NAME]

  -- find counterpart in blueprint
  local world_to_bp
  for _, bp_entity in ipairs(bp_entities) do
    if bp_entity.name == "pipefitter-connector" then
      local x_offset = bp_entity.position.x - anchor_connector.position.x
      local y_offset = bp_entity.position.y - anchor_connector.position.y
      world_to_bp = function(position)
        return { x = position.x + x_offset, y = position.y + y_offset }
      end
      break
    end
  end

  for _, ug_pipe in ipairs(find_in_area(pipefitter_surface, area, {})) do
    if ug_pipe.name ~= "entity-ghost" then
      bp_entities[#bp_entities + 1] = {
        entity_number = #bp_entities + 1,
        name = "pipefitter-bpproxy-"..ug_pipe.name,
        position = world_to_bp(ug_pipe.position),
        direction = ug_pipe.direction,
      }
    end
  end
  bp.set_blueprint_entities(bp_entities)
end

return M