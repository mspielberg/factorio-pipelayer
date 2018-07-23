local Network = require "Network"

local M = {}

local surface_name = "plumbing"
local tile_name = "dirt-6"

local player_state

function M.on_init()
  if not game.surfaces[surface_name] then
    game.create_surface(surface_name)
  end
  if not global.player_state then
    global.player_state = {}
  end
  M.on_load()
end

function M.on_load()
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
  player.teleport(player.position, surface_name)
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
  if player.surface.name == surface_name then
    return_player_from_editor(player)
  elseif player.surface == game.surfaces.nauvis then
    move_player_to_editor(player)
  else
    player.print({"plumbing-error.bad-surface"})
  end
end

function M.on_chunk_generated(event)
  if event.surface.name ~= surface_name then return end
  local surface = event.surface
  local area = event.area

  local tiles = {}
  for y=area.left_top.y,area.right_bottom.y do
    for x=area.left_top.x,area.right_bottom.x do
      tiles[#tiles+1] = {name = tile_name, position={x = x,y = y}}
    end
  end
  surface.set_tiles(tiles)
  surface.destroy_decoratives(area)

  for _, entity in ipairs(surface.find_entities(area)) do
    entity.destroy()
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

local function connect_underground_pipe(entity)
  local networks = connected_networks(entity)
  if not next(networks) then
    local network = Network:new()
    game.print("created new network "..network.id)
    network:add_underground_pipe(entity)
    return network
  end

  local main_network = networks[1]
  main_network:add_underground_pipe(entity)
  for i=2,#networks do
    local to_absorb = networks[i]
    game.print("absorbing network "..to_absorb.id.." into network "..main_network.id)
    main_network:absorb(to_absorb)
    main_network:update()
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

local function player_built_surface_via(player, entity)
  local surface = game.surfaces[surface_name]
  local create_args = {
    name = "plumbing-via",
    position = entity.position,
    direction = opposite_direction(entity.direction),
    force = entity.force,
  }
  if not surface.can_place_entity(create_args) then
    abort_player_build(player, entity)
  else
    local underground_via = surface.create_entity(create_args)
    underground_via.active = false
    underground_via.minable = false
    local network = connect_underground_pipe(underground_via)
    network:add_via(entity, underground_via.unit_number)
  end
end

local function player_built_underground_pipe(player_index, entity, stack)
    local character = player_state[player_index].character
    if character then
      character.remove_item(stack)
    end
    entity.active = false
    connect_underground_pipe(entity)
end

function M.on_player_built_entity(event)
  local player_index = event.player_index
  local player = game.players[player_index]
  local entity = event.created_entity
  local surface = entity.surface

  if entity.name == "plumbing-via" then
    if surface.name == "nauvis" then
      player_built_surface_via(player, entity)
    else
      abort_player_build(player, entity, {"plumbing-error.bad-surface"})
    end
  elseif surface.name == surface_name then
    player_built_underground_pipe(player_index, entity, event.stack)
  end
end

local function mined_surface_via(entity)
  local underground_via = game.surfaces[surface_name].find_entity("plumbing-via", entity.position)
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
  if surface.name == surface_name then
    player_mined_from_editor(event)
  elseif surface.name == "nauvis" and entity.name == "plumbing-via" then
    mined_surface_via(entity)
  end

end

return M