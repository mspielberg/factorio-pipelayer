-------------------------------------------------------------------------------
--[[Pipelayer ground penetrating highligther]] --
-------------------------------------------------------------------------------
-- Concept designed and code written by TheStaplergun (staplergun on mod portal)
-- Code revision and adaptation by Zeibach/Therax

local M = {}

--? Bit styled table. 2 ^ defines.direction is used for entry to the table. Only compatible with 4 way directions.
local directional_table = {
  [0x00] = '',
  [0x01] = '-n',
  [0x04] = '-e',
  [0x05] = '-ne',
  [0x10] = '-s',
  [0x11] = '-ns',
  [0x14] = '-se',
  [0x15] = '-nse',
  [0x40] = '-w',
  [0x41] = '-nw',
  [0x44] = '-ew',
  [0x45] = '-new',
  [0x50] = '-sw',
  [0x51] = '-nsw',
  [0x54] = '-sew',
  [0x55] = '-nsew'
}

--? Tables for read-limits
local allowed_types = {
  ['pipe'] = true,
  ['pipe-to-ground'] = true,
  ['storage-tank'] = true,
}

local not_allowed_names = {
  ['factory-fluid-dummy-connector'] = true,
  ['factory-fluid-dummy-connector-south'] = true,
  ['offshore-pump-output'] = true
}

--? Table for types and names to draw dashes between
local draw_dashes_types = {
  ['pipe-to-ground'] = true
}
local draw_dashes_names = {
  ['4-to-4-pipe'] = true
}

-- Returns a list of bounding boxes within radius of position that are not in radius of old_position.
-- Diagonal movement may result in two rects, one on the x axis and one on the y axis.
local function delta_rects(position, old_position, radius)
  local px = position.x
  local py = position.y
  local ox = px - old_position.x
  local oy = py - old_position.y

  local rects = {}

  if ox > 0 then
    rects[#rects+1] = {
      left_top     = { x = px + radius - ox, y = py - radius },
      right_bottom = { x = px + radius     , y = py + radius },
    }
  elseif ox < 0 then
    rects[#rects+1] = {
      left_top     = { x = px - radius     , y = py - radius },
      right_bottom = { x = px - radius - ox, y = py + radius },
    }
  end

  if oy > 0 then
    rects[#rects+1] = {
      left_top     = { x = px - radius, y = py + radius - oy },
      right_bottom = { x = px + radius, y = py + radius      },
    }
  elseif oy < 0 then
    rects[#rects+1] = {
      left_top     = { x = px - radius, y = py - radius      },
      right_bottom = { x = px + radius, y = py - radius - oy },
    }
  end

  return rects
end

local function get_ew(delta_x)
  return delta_x > 0 and defines.direction.west or defines.direction.east
end

local function get_ns(delta_y)
  return delta_y > 0 and defines.direction.north or defines.direction.south
end

--? Gets fourway direction relation based on positions
local abs = math.abs
local function get_direction(entity_position, neighbour_position)
  local delta_x = entity_position.x - neighbour_position.x
  local delta_y = entity_position.y - neighbour_position.y
  if delta_x == 0 then
    return get_ns(delta_y)
  elseif delta_y == 0 then
    return get_ew(delta_x)
  else
    local adx, ady = abs(delta_x), abs(delta_y)
    if adx > ady then
      return get_ew(delta_x)
    else --? Exact diagonal relations get returned as a north/south relation.
      return get_ns(delta_y)
    end
  end
end

--? Destroy markers from player's global data table
local function destroy_markers(markers)
  for _, entity in pairs(markers) do
    entity.destroy()
  end
end

local bor = bit32.bor
local lshift = bit32.lshift
local function highlight_pipelayer_surface(player_index, editor_surface, area)
  --? Get player and build player's global data table for markers
  local player = game.players[player_index]
  local pdata = global.players[player_index]

  --? Declare working tables
  local read_entity_data = {}

  --? Assign working table references to global reference under player
  pdata.unit_numbers_marked = pdata.unit_numbers_marked or {}
  pdata.current_pipelayer_marker_table = pdata.current_pipelayer_marker_table or {}
  local unit_numbers_marked = pdata.unit_numbers_marked
  local all_markers = pdata.current_pipelayer_marker_table

  --? Setting and cache create entity function
  local create = player.surface.create_entity

  --? Variables
  local markers_made = #all_markers

  --? Draws marker at position based on connected directions
  local function draw_marker(position, directions)
    markers_made = markers_made + 1
    all_markers[markers_made] = create{
      name = 'pipelayer-pipe-dot' .. directional_table[directions],
      position = position
    }
  end

  --? Handles drawing dashes between two pipe to ground.
  local function draw_dashes(entity_position, neighbour_position)
    markers_made = markers_made + 1
    all_markers[markers_made] = create{
      name = 'pipelayer-pipe-marker-beam',
      position = entity_position,
      source_position = {entity_position.x, entity_position.y},
      target_position = {neighbour_position.x, neighbour_position.y},
      duration = 2000000000
    }
  end

  local function get_directions(entity_position, entity_neighbours)
    local table_entry = 0
    for _, neighbour_unit_number in pairs(entity_neighbours) do
      local current_neighbour = read_entity_data[neighbour_unit_number]
      if current_neighbour then
        local direction = get_direction(entity_position, current_neighbour[1])
        table_entry = bor(table_entry, lshift(1, direction))
      end
    end
    return table_entry
  end

  --? Construct filter table fed to function below
  local filter = {
    area = area,
    type = {'pipe-to-ground', 'pipe', 'storage-tank'},
    force = player.force
  }

  --? Get pipes within filter area and cache them
  for _, entity in pairs(editor_surface.find_entities_filtered(filter)) do
    local entity_type = entity.type
    local entity_name = entity.name

    --? Verify entity is allowed to be stored
    if allowed_types[entity_type] and not not_allowed_names[entity_name] then
      local entity_unit_number = entity.unit_number
      local entity_position = entity.position
      local entity_neighbours = entity.neighbours[1]
      read_entity_data[entity_unit_number] = {
        entity_position,
        entity_neighbours,
        entity_type,
        entity_name
      }

      --? Convert neighbour table to unit number references to gain access to already cached data above at later point
      for neighbour_index_number, neighbour in pairs(entity_neighbours) do
        local neighbour_unit_number = neighbour.unit_number
        entity_neighbours[neighbour_index_number] = neighbour_unit_number
      end
    end
  end

  --? Step through all cached pipes
  for unit_number, current_entity in pairs(read_entity_data) do
    --? Ensure no double marking
    if not unit_numbers_marked[unit_number] then
      --? Draw dashed beam entity if pipe_to_ground
      if draw_dashes_types[current_entity[3]] or draw_dashes_names[current_entity[4]] then
        for _, neighbour_unit_number in pairs(current_entity[2]) do
          --? Retrieve cached neighbour data
          local current_neighbour = read_entity_data[neighbour_unit_number]
          if current_neighbour then
            --? Ensure it's a valid name or type to draw dashes between. Don't draw dashes between "clamped" pipes (They are pipe to ground entities) and ensure we're not marking towards an already marked entity
            if (draw_dashes_types[current_neighbour[3]] or draw_dashes_names[current_neighbour[4]]) and not current_neighbour[4]:find('%-clamped%-') and not unit_numbers_marked[neighbour_unit_number] then
              draw_dashes(current_entity[1], current_neighbour[1])
            end
          end
        end
      end
      --? Draw a marker on the current entity with lines pointing towards each neighbour (Overlaps beam drawings without an issue)
      draw_marker(current_entity[1], get_directions(current_entity[1], current_entity[2]))
      --? Set current entity as marked
      unit_numbers_marked[unit_number] = true
    end
  end
end

function M.on_cursor_stack_changed(player_index, editor_surface)
  local player = game.players[player_index]
  global.players[player_index] = global.players[player_index] or {}
  local pdata = global.players[player_index]

  local cursor_item = player.cursor_stack.valid_for_read and player.cursor_stack.name
  if cursor_item == 'pipelayer-connector' then
    -- set up markers from scratch
    local radius = settings.global["pipelayer-max-distance-checked"].value
    local area = {
      {player.position.x - radius, player.position.y - radius},
      {player.position.x + radius, player.position.y + radius},
    }
    pdata.old_position = game.players[player_index].position
    highlight_pipelayer_surface(player_index, editor_surface, area)
  elseif pdata.current_pipelayer_marker_table then
    destroy_markers(pdata.current_pipelayer_marker_table)
    pdata.current_pipelayer_marker_table = nil
    pdata.unit_numbers_marked = nil
    pdata.old_position = nil
  end
end

local function chebyshev(p1, p2)
  local dx = abs(p1.x - p2.x)
  local dy = abs(p1.y - p2.y)
  if dx > dy then return dx end
  return dy
end

function M.on_player_changed_position(player_index, editor_surface)
  local player = game.players[player_index]
  global.players[player_index] = global.players[player_index] or {}
  local pdata = global.players[player_index]

  local old_position = pdata.old_position
  local position = player.position
  if old_position and chebyshev(position, old_position) > 5 then
    local radius = settings.global["pipelayer-max-distance-checked"].value

    -- draw markers in new areas
    local rects_to_mark = delta_rects(position, old_position, radius)
    for _, rect in ipairs(rects_to_mark) do
      highlight_pipelayer_surface(player_index, editor_surface, rect)
    end
    pdata.old_position = position
  end
end

return M
