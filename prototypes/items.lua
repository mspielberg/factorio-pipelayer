require "util"

local overlay_icon = {
  icon = "__core__/graphics/icons/mip/collapse.png",
  icon_size = 32,
  scale = 0.5,
  shift = {-8, -8},
  icon_mipmaps = 2,
  tint = {r=1,g=1,b=0,a=1},
}


local ug = data.raw.item["pipe-to-ground"]
local connector = util.table.deepcopy(ug)
connector.icons = {
    {
      icon = ug.icon,
      icon_size = ug.icon_size,
    },
    overlay_icon,
  }
connector.icon = nil
connector.icon_size = nil
connector.name = "pipelayer-connector"
connector.place_result = "pipelayer-connector"
data:extend{connector}