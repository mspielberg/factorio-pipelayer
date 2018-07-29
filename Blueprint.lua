local Constants = require "Constants"
local Editor = require "Editor"
require "util"

local SURFACE_NAME = Constants.SURFACE_NAME

local M = {}

--[[
  -- before surface connector & chest are built
  ghost_info_for_position[x] = {
    [y] = {
      ghosts = {
        [ghost_unit_number] = underground_pipe_ghost_entity,
      },
      pipe_counts = {
        [pipe_name] = 42, -- number of ghosts still existing associated with this chest
      },
    }
  }
]]
local ghost_info_for_position

--[[
  -- once chest is built
  ghost_info_for_chest[pipe_request_chest_unit_number] = {
    chest = pipe_request_chest_entity,
    ghosts = ghost_info_for_position[chest.position.x][chest.position.y].ghosts,
    pipe_counts = ghost_info_for_position[chest.position.x][chest.position.y].pipe_counts,
  }
]]
local ghost_info_for_chest

--[[
  -- On update on or after this tick_to_deconstruct, destroy all pipes and
  -- place them in a new surface chest at x,y, marked for deconstruction.
  deconstruction_info[x] = {
    [y] = {
      tick_to_deconstruct = 12345,
      pipes = { underground_pipe_entity, ... },
    }
  }
]]
local deconstruction_info

local function debug(...)
  log(...)
end

function M.on_init()
  global.ghost_info = {
    for_position = {},
    for_chest = {},
  }
  global.deconstruction_info = {}
  M.on_load()
end

function M.on_load()
  ghost_info_for_position = global.ghost_info.for_position
  ghost_info_for_chest = global.ghost_info.for_chest
  deconstruction_info = global.deconstruction_info
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

local function get_ghost_info(position)
  local ys = ghost_info_for_position[position.x]
  if ys then
    return ys[position.y]
  end
  return nil
end

local function on_built_surface_connector(surface_connector)
  local position = surface_connector.position
  local ghost_info = get_ghost_info(position)
  if not ghost_info then return end

  ghost_info_for_position[position.x][position.y] = nil
  local surface = surface_connector.surface
  local force = surface_connector.force
  local last_user = surface_connector.last_user

  local pipe_request_chest = surface.create_entity{
    name = "pipefitter-pipe-request-chest",
    position = position,
    force = force,
  }
  pipe_request_chest.operable = false
  pipe_request_chest.last_user = last_user

  local pipe_request_proxy = surface.create_entity{
    name = "item-request-proxy",
    position = position,
    force = force,
    target = pipe_request_chest,
    modules = ghost_info.pipe_counts,
  }

  pipe_request_proxy.last_user = last_user

  ghost_info_for_chest[pipe_request_chest.unit_number] = {
    chest = pipe_request_chest,
    ghosts = ghost_info.ghosts,
    pipe_counts = ghost_info.pipe_counts,
  }
end

do
  -- encapsulates all inter-event state between on_built_entity events that happen
  -- as a result of placing a blueprint
  local built_first_connector_ghost
  local pipe_ghosts
  local pipe_counts

  local function add_item_request(ghost, name)
    pipe_counts[name] = (pipe_counts[name] or 0) + 1
    pipe_ghosts[ghost.unit_number] = ghost
  end

  local function player_built_surface_connector_ghost(ghost)
    if built_first_connector_ghost then return end
    built_first_connector_ghost = true
    local position = ghost.position
    ghost_info_for_position[position.x] = ghost_info_for_position[position.x] or {}
    ghost_info_for_position[position.x][position.y] = {
      ghosts = pipe_ghosts,
      pipe_counts = pipe_counts,
    }
  end

  -- converts overworld bpproxy ghost to regular ghost underground
  local function player_built_pipefitter_bpproxy_ghost(ghost, nonproxy_name)
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
      if nonproxy_name ~= "pipefitter-connector" then
        add_item_request(editor_ghost, nonproxy_name)
      end
    end

    ghost.destroy()
  end

  function M.on_player_built_entity(event)
    local entity = event.created_entity
    if entity.surface ~= game.surfaces.nauvis then return end

    if entity.name == "pipefitter-connector" then
      return on_built_surface_connector(entity)
    elseif entity.name == "entity-ghost" then
      if entity.ghost_name == "pipefitter-connector" then
        return player_built_surface_connector_ghost(entity)
      end

      local nonproxy_name = entity.ghost_name:match("^pipefitter%-bpproxy%-(.*)$")
      if nonproxy_name then
        return player_built_pipefitter_bpproxy_ghost(entity, nonproxy_name)
      end
    end
  end

  function M.on_robot_built_entity(_, entity, _)
    if entity.name == "pipefitter-connector" and entity.surface == game.surfaces.nauvis then
      return on_built_surface_connector(entity)
    end
  end

  function M.on_put_item(_)
    built_first_connector_ghost = false
    pipe_ghosts = {}
    pipe_counts = {}
  end
end

local function insert_or_spill(insertable, player, stack)
  local inserted = insertable.insert(stack)
  if inserted < stack.count then
    player.surface.spill_item_stack{position = player.position, name = stack.name, count = stack.count - inserted}
  end
end

local function cleanup_surface_connector(surface_connector, player, insertable)
  local surface = surface_connector.surface
  local position = surface_connector.position
  local chest = surface.find_entity("pipefitter-pipe-request-chest", position)
  if chest then
    local inv = chest.get_inventory(defines.inventory.chest)
    for i=1,#inv do
      local stack = inv[i]
      if stack.valid_for_read then
        insert_or_spill(insertable, player, stack)
      end
    end
    ghost_info_for_chest[chest.unit_number] = nil
    chest.destroy()
  end
end

local function player_mined_surface_connector_ghost(player, ghost)
  local counterpart = game.surfaces[SURFACE_NAME].find_entity("entity-ghost", ghost.position)
  if counterpart and counterpart.ghost_name == "pipefitter-connector" then
    counterpart.destroy()
  end
  cleanup_surface_connector(ghost, player, player)
end

local function player_mined_underground_connector_ghost(player, ghost)
  local counterpart = game.surfaces.nauvis.find_entity("entity-ghost", ghost.position)
  if counterpart and counterpart.ghost_name == "pipefitter-connector" then
    cleanup_surface_connector(counterpart, player, player)
    counterpart.destroy()
  end
end

function M.on_pre_player_mined_item(player_index, entity)
  if entity.name == "entity-ghost" and entity.ghost_name == "pipefitter-connector" then
    local player = game.players[player_index]
    if entity.surface.name == SURFACE_NAME then
      return player_mined_underground_connector_ghost(player, entity)
    else
      return player_mined_surface_connector_ghost(player, entity)
    end
  end
end

function M.on_player_mined_entity(player_index, entity, buffer)
  if entity.name == "pipefitter-connector" and entity.surface == game.surfaces.nauvis then
    local player = game.players[player_index]
    cleanup_surface_connector(entity, player, buffer)
  end
end

function M.on_robot_mined_entity(_, entity, buffer)
  if entity.name == "pipefitter-connector" and entity.surface == game.surfaces.nauvis then
    cleanup_surface_connector(entity, nil, buffer)
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

------------------------------------------------------------------------------------------------------------------------
-- construction of underground ghosts from pipes in pipe request chests

local function count_can_build(chest_inventory, pipe_counts)
  local out = {}
  local actual_available = chest_inventory.get_contents()
  for pipe_name, requested in pairs(pipe_counts) do
    local can_build = math.min(requested, actual_available[pipe_name] or 0)
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

local function build_underground_ghosts()
  for chest_unit_number, ghost_info in pairs(ghost_info_for_chest) do
    local chest = ghost_info.chest
    local ghosts = ghost_info.ghosts
    local pipe_counts = ghost_info.pipe_counts
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
        ghost_info_for_chest[chest_unit_number] = nil
      end
    else
      ghost_info_for_chest[chest_unit_number] = nil
    end
  end
end

------------------------------------------------------------------------------------------------------------------------
-- Deconstruction of surface connectors

function M.on_player_deconstructed_area(player_index, area, _, alt)
  if alt then return end
  local player = game.players[player_index]
  local nauvis = game.surfaces.nauvis
  if player.surface ~= nauvis then return end
  local selected_connectors = find_in_area(nauvis, area, {name = "pipefitter-connector"})
  if not next(selected_connectors) then return end

  local main_connector = selected_connectors[1]
  local connector_position = main_connector.position
  local editor_surface = game.surfaces[SURFACE_NAME]
  local pipes_to_deconstruct = {}
  for _, pipe in ipairs(find_in_area(editor_surface, area, {})) do
    if pipe.name ~= "pipefitter-connector" then
      pipes_to_deconstruct[#pipes_to_deconstruct + 1] = pipe
      pipe.order_deconstruction(pipe.force)
    end
  end

  if not deconstruction_info[connector_position.x] then deconstruction_info[connector_position.x] = {} end
  local delay = settings.global["pipefitter-deconstruction-delay"].value
  deconstruction_info[connector_position.x][connector_position.y] = {
    tick_to_deconstruct = game.tick + delay * 60,
    pipes = pipes_to_deconstruct,
  }

  player.print({"pipefitter-message.marked-for-deconstruction", #pipes_to_deconstruct, delay})
end

function M.on_canceled_deconstruction(entity, _)
  if entity.surface ~= game.surfaces.nauvis then return end
  local position = entity.position
  local info = deconstruction_info[position.x] and deconstruction_info[position.x][position.y]
  if info then
    for _, pipe in ipairs(info.pipes) do
      if pipe.valid then
        pipe.cancel_deconstruction(pipe.force)
      end
    end
    deconstruction_info[position.x][position.y] = nil
  end
end

local function dump_to_chest(position, pipes)
  local pipes_to_insert = {}
  local force
  for _, pipe in ipairs(pipes) do
    if pipe.valid and pipe.to_be_deconstructed(pipe.force) then
      if not force then force = pipe.force end
      local pipe_name = pipe.name
      pipes_to_insert[pipe_name] = (pipes_to_insert[pipe_name] or 0) + 1
      Editor.disconnect_underground_pipe(pipe)
      pipe.destroy()
    end
  end

  if not next(pipes_to_insert) then return end

  local dump_chest = game.surfaces.nauvis.create_entity{
    name = "pipefitter-pipe-dump-chest",
    position = position,
    force = force,
  }
  dump_chest.operable = false
  local chest_inventory = dump_chest
  for name, count in pairs(pipes_to_insert) do
    chest_inventory.insert{name = name, count = count}
  end
  dump_chest.order_deconstruction(force)
end

local function check_for_deconstruction_ready()
  local tick = game.tick
  for x, ys in pairs(deconstruction_info) do
    for y, info in pairs(ys) do
      if info.tick_to_deconstruct <= tick then
        dump_to_chest({x=x, y=y}, info.pipes)
        ys[y] = nil
      end
    end
  end
end

function M.on_tick(tick)
  build_underground_ghosts()
  check_for_deconstruction_ready()
end

return M