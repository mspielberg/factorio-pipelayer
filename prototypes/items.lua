require "util"

local overlay_icon = {
  icon = "__core__/graphics/arrows/indication-arrow-up-to-down.png",
  icon_size = 64,
  scale = 0.25,
  shift = {8, -8},
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