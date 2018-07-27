local Constants = require "Constants"
local Network = require "Network"

local M = {}
local SURFACE_NAME = Constants.SURFACE_NAME
local UNDERGROUND_TILE_NAME = Constants.UNDERGROUND_TILE_NAME

local editor_surface
local player_state

local function debug(...)
  log(...)
end

function M.on_init()
    local surface = game.create_surface(
      SURFACE_NAME,
      {
        starting_area = "none",
        water = "none",
        cliff_settings = { cliff_elevation_0 = 1024 },
        default_enable_all_autoplace_controls = false,
        autoplace_controls = {
          dirt = {
            frequency = "very-low",
            size = "very-high",
          },
        },
        autoplace_settings = {
          decorative = { treat_missing_as_default = false },
          entity = { treat_missing_as_default = false },
        },
      }
    )
    surface.daytime = 0.35
    surface.freeze_daytime = true
    global.editor_surface = surface
    global.player_state = {}
    M.on_load()
end

function M.on_load()
  editor_surface = global.editor_surface
  player_state = global.player_state
end

local function get_player_pipe_stacks(player)
  local stacks = {}
  for _, inventory_index in ipairs{defines.inventory.player_quickbar, defines.inventory.player_main} do
    local inventory = player.get_inventory(inventory_index)
    if inventory then
      for i=1,#inventory do
        local stack = inventory[i]
        if stack.valid_for_read then
          local place_result = stack.prototype.place_result
          if place_result and (place_result.type == "pipe" or place_result.type == "pipe-to-ground") then
            stacks[#stacks+1] = {name = stack.name, count = stack.count}
          end
        end
      end
    end
  end
  return stacks
end

local function move_player_to_editor(player)
  local pipe_stacks = get_player_pipe_stacks(player)
  local player_index = player.index
  player_state[player_index] = {
    position = player.position,
    surface = player.surface,
    character = player.character,
  }
  player.character = nil
  player.teleport(player.position, editor_surface)
  for _, stack in ipairs(pipe_stacks) do
    player.insert(stack)
  end
end

local function return_player_from_editor(player)
  local player_index = player.index
  player.clean_cursor()
  player.get_main_inventory().clear()
  player.get_quickbar().clear()
  player.teleport(player_state[player_index].position, player_state[player_index].surface)
  player.character = player_state[player_index].character
  player_state[player_index] = nil
end

function M.toggle_editor_status_for_player(player_index)
  local player = game.players[player_index]
  if player.surface == editor_surface then
    return_player_from_editor(player)
  elseif player.surface == game.surfaces.nauvis then
    move_player_to_editor(player)
  else
    player.print({"plumbing-error.bad-surface"})
  end
end

local function set_to_list(set)
  local out = {}
  for k in pairs(set) do
    out[#out+1] = k
  end
  return out
end

local function connected_networks(entity)
  local out = {}
  for _, neighbor in ipairs(entity.neighbours[1]) do
    local neighbor_network = Network.for_entity(neighbor)
    out[neighbor_network] = true
  end
  return set_to_list(out)
end

 function M.connect_underground_pipe(entity)
  debug(serpent.line{entity=entity,neighbours=entity.neighbours})
  local networks = connected_networks(entity)
  if not next(networks) then
    local network = Network:new()
    debug("created new network "..network.id)
    network:add_underground_pipe(entity)
    return network
  end

  local main_network = networks[1]
  main_network:add_underground_pipe(entity)
  for i=2,#networks do
    local to_absorb = networks[i]
    debug("absorbing network "..to_absorb.id.." into network "..main_network.id)
    main_network:absorb(to_absorb)
  end
  return main_network
end

local function abort_player_build(player, entity)
  player.insert({name = entity.name, count = 1})
  entity.surface.create_entity{
    name = "flying-text",
    position = entity.position,
    text = {"plumbing-error.underground-obstructed"},
  }
  entity.destroy()
end

local function opposite_direction(direction)
  return (direction + 4) % 8
end

local function built_surface_via(player, entity)
  local position = entity.position
  if not editor_surface.is_chunk_generated(position) then
    editor_surface.request_to_generate_chunks(position, 1)
    editor_surface.force_generate_chunk_requests()
  end
  local create_args = {
    name = "plumbing-via",
    position = position,
    direction = opposite_direction(entity.direction),
    force = entity.force,
  }
  if not editor_surface.can_place_entity(create_args) then
    if player then
      abort_player_build(player, entity)
    else
      entity.order_deconstruction(entity.force)
    end
  else
    local underground_via = editor_surface.create_entity(create_args)
    underground_via.active = false
    underground_via.minable = false
    local network = M.connect_underground_pipe(underground_via)
    network:add_via(entity, underground_via.unit_number)
  end
end

local function player_built_underground_pipe(player_index, entity, stack)
    local character = player_state[player_index].character
    if character then
      character.remove_item(stack)
    end
    entity.active = false
    M.connect_underground_pipe(entity)
end

function M.on_player_built_entity(event)
  local player_index = event.player_index
  local player = game.players[player_index]
  local entity = event.created_entity
  if not entity.valid or entity.name == "entity-ghost" then return end
  local surface = entity.surface

  if entity.name == "plumbing-via" then
    if surface.name == "nauvis" then
      built_surface_via(player, entity)
    else
      abort_player_build(player, entity, {"plumbing-error.bad-surface"})
    end
  elseif surface == editor_surface then
    player_built_underground_pipe(player_index, entity, event.stack)
  end
end

function M.on_robot_built_entity(event)
end

local function mined_surface_via(entity)
  local underground_via = editor_surface.find_entity("plumbing-via", entity.position)
  local network = Network.for_entity(underground_via)
  if network then
    network:remove_underground_pipe(underground_via)
  end
  underground_via.destroy()
end

local function return_to_character_inventory(player_index, character, buffer)
  local player = game.players[player_index]
  for i=1,#buffer do
    local stack = buffer[i]
    if stack.valid_for_read then
      local inserted = character.insert(stack)
      if inserted < stack.count then
        player.print({"inventory-restriction.player-inventory-full", stack.prototype.localised_name})
        character.surface.spill_item_stack(
          character.position,
          {name = stack.name, count = stack.count - inserted})
        stack.count = inserted
      end
    end
  end
end

local function player_mined_from_editor(event)
  local entity = event.entity
  local network = Network.for_entity(entity)
  if network then
    network:remove_underground_pipe(entity)
  end
  local character = player_state[event.player_index].character
  if character then
    return_to_character_inventory(event.player_index, character, event.buffer)
  end
end

function M.on_player_mined_entity(event)
  local entity = event.entity
  local surface = entity.surface
  if surface == editor_surface then
    player_mined_from_editor(event)
  elseif surface.name == "nauvis" and entity.name == "plumbing-via" then
    mined_surface_via(entity)
  end
end

function M.on_player_rotated_entity(event)
  local entity = event.entity
  if entity.surface ~= editor_surface then return end
  local surface_via = game.surfaces.nauvis.find_entity("plumbing-via", entity.position)
  local old_network = Network.for_entity(entity)
  local new_networks = connected_networks(entity)
  if old_network:is_singleton() and not next(new_networks) then
    return
  end
  if surface_via then
    old_network:remove_via(entity.unit_number)
  end
  old_network:remove_underground_pipe(entity)
  local new_network = M.connect_underground_pipe(entity)
  if surface_via then
    new_network:add_via(surface_via, entity.unit_number)
  end
end

return M