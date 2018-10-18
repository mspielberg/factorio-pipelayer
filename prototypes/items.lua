require "util"

local ug = data.raw.item["pipe-to-ground"]
local connector = util.table.deepcopy(ug)
connector.name = "pipelayer-connector"
connector.place_result = "pipelayer-connector"
data:extend{connector}