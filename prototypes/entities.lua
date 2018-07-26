local Constants = require 'Constants'

local empty_sprite = {
  filename = "__core__/graphics/empty.png",
  width = 0,
  height = 0,
  frame_count = 1,
}

local ug = data.raw["pipe-to-ground"]["pipe-to-ground"]

local via = {
  type = "storage-tank",
  name = "plumbing-via",
  icon = ug.icon,
  icon_size = ug.icon_size,
  flags = ug.flags,
  minable = {mining_time = 1.5, result = "plumbing-via"},
  max_health = ug.max_health,
  corpse = ug.corpse,
  resistances = ug.resistances,
  collision_box = ug.collision_box,
  selection_box = ug.selection_box,
  fluid_box = {
    base_area = Constants.VIA_CAPACITY / 100,
    pipe_covers = pipecoverspictures(),
    pipe_connections = {
      { position = {0, -1} },
    }
  },
  window_bounding_box = {{0, 0}, {0, 0}},
  pictures = {
    picture = {
      north = {
        filename = "__base__/graphics/entity/pipe-to-ground/pipe-to-ground-up.png",
        priority = "high",
        width = 64,
        height = 64, --, shift = {0.10, -0.04}
        hr_version =
        {
          filename = "__base__/graphics/entity/pipe-to-ground/hr-pipe-to-ground-up.png",
          priority = "extra-high",
          width = 128,
          height = 128,
          scale = 0.5
        }
      },
      east = {
        filename = "__base__/graphics/entity/pipe-to-ground/pipe-to-ground-right.png",
        priority = "high",
        width = 64,
        height = 64, --, shift = {0.1, 0.1}
        hr_version =
        {
          filename = "__base__/graphics/entity/pipe-to-ground/hr-pipe-to-ground-right.png",
          priority = "extra-high",
          width = 128,
          height = 128,
          scale = 0.5
        }
      },
      south = {
        filename = "__base__/graphics/entity/pipe-to-ground/pipe-to-ground-down.png",
        priority = "high",
        width = 64,
        height = 64, --, shift = {0.05, 0}
        hr_version =
        {
          filename = "__base__/graphics/entity/pipe-to-ground/hr-pipe-to-ground-down.png",
          priority = "extra-high",
          width = 128,
          height = 128,
          scale = 0.5
        }
      },
      west = {
        filename = "__base__/graphics/entity/pipe-to-ground/pipe-to-ground-left.png",
        priority = "high",
        width = 64,
        height = 64, --, shift = {-0.12, 0.1}
        hr_version =
        {
          filename = "__base__/graphics/entity/pipe-to-ground/hr-pipe-to-ground-left.png",
          priority = "extra-high",
          width = 128,
          height = 128,
          scale = 0.5
        }
      },
    },
    window_background = empty_sprite,
    fluid_background = empty_sprite,
    flow_sprite = empty_sprite,
    gas_flow = empty_sprite,
  },
  flow_length_in_ticks = 1,
}

local pipe_request_chest = {
  type = "container",
  name = "plumbing-pipe-request-chest",
  icon = "__core__/graphics/empty.png",
  icon_size = 1,
  flags = {},
  collision_box = {{-0.3, -0.3}, {0.3, 0.3}},
  selection_box = {{-0.5, -0.5}, {0.5, 0.5}},
  collision_mask = {},
  inventory_size = 100,
  picture = empty_sprite,
}

data:extend{
  via,
  pipe_request_chest,
}