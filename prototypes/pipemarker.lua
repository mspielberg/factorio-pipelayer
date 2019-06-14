local merge = _G.util.merge
local base_entity = {
    type = 'corpse',
    name = 'fillerstuff',
    flags = {'placeable-neutral', 'not-on-map'},
    subgroup = 'remnants',
    order = 'd[remnants]-c[wall]',
    icon = '__core__/graphics/empty.png',
    icon_size = 1,
    time_before_removed = 2000000000,
    collision_box = {{0, 0}, {0, 0}},
    selection_box = {{-0.5, -0.5}, {0.5, 0.5}},
    selectable_in_game = false,
    final_render_layer = 'selection-box',
    animation = {
        width = 64,
        height = 64,
        frame_count = 1,
        direction_count = 1,
        shift = {-0.5, -0.5},
        filename = '__pipelayer__/graphics/entity/markers/pipe-marker-dot.png'
    }
}

local directional_table = {
    ['0'] = '',
    [1] = '-n',
    [4] = '-e',
    [5] = '-ne',
    [16] = '-s',
    [17] = '-ns',
    [20] = '-se',
    [21] = '-nse',
    [64] = '-w',
    [65] = '-nw',
    [68] = '-ew',
    [69] = '-new',
    [80] = '-sw',
    [81] = '-nsw',
    [84] = '-sew',
    [85] = '-nsew'
}
local new_dots = {}
for direction_index, directions in pairs(directional_table) do
    local current_entity = util.table.deepcopy(base_entity)
    --current_entity.type = 'corpse'
    current_entity.name = 'pipelayer-pipe-dot' .. directions
    if direction_index == '0' then
        current_entity.final_render_layer = 'light-effect'
        --? The single pipe dot is twice as large so must be scaled
        current_entity.animation.scale = 0.5
    else
      current_entity.animation.width = 32
      current_entity.animation.height = 32
    end
    current_entity.animation.filename = '__pipelayer__/graphics/entity/markers/pipe-marker-dot' .. directions .. '.png'
    new_dots[#new_dots + 1] = current_entity
end

for _, stuff in pairs(new_dots) do
  data:extend{
    merge{
      base_entity,
      stuff
    }
  }
end

local underground_marker_beams = {}
local marker_beams = util.table.deepcopy(data.raw['beam']['electric-beam-no-sound'])
marker_beams.name = 'pipelayer-pipe-marker-beam'
marker_beams.width = 1.0

--? Ensure beam doesn't fade when in use
marker_beams.damage_interval = 2000000000
--? Don't need the beam to conduct an action
marker_beams.action = nil

--? Start and ending properties must be present but have to match framecount of body and other properties
local empty_animation = {
    filename = '__core__/graphics/empty.png',
    line_length = 1,
    width = 1,
    height = 1,
    frame_count = 1,
    axially_symmetrical = false,
    direction_count = 1
}
marker_beams.start = empty_animation
marker_beams.start_light = empty_animation
marker_beams.ending = empty_animation
marker_beams.ending_light = empty_animation
marker_beams.head_light = empty_animation
marker_beams.tail_light = empty_animation
marker_beams.body_light = empty_animation

--? Head tail and body must all have same frame count
marker_beams.head = {
    filename = '__pipelayer__/graphics/entity/markers/pipe-marker-horizontal.png',
    line_length = 1,
    width = 64,
    height = 64,
    frame_count = 1,
    animation_speed = 1,
    scale = 0.5
}
marker_beams.tail = {
    filename = '__pipelayer__/graphics/entity/markers/pipe-marker-horizontal.png',
    line_length = 1,
    width = 64,
    height = 64,
    frame_count = 1,
    animation_speed = 1,
    scale = 0.5
}
--? Body is an array of sprite definitions instead of a single sprite definition
marker_beams.body = {
    {
        filename = '__pipelayer__/graphics/entity/markers/pipe-marker-horizontal.png',
        line_length = 1,
        width = 64,
        height = 64,
        frame_count = 1,
        scale = 0.5
    }
}
underground_marker_beams[#underground_marker_beams + 1] = marker_beams

data:extend(underground_marker_beams)
