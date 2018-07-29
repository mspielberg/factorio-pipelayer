require "util"

local ug = data.raw.item["pipe-to-ground"]
local connector = util.table.deepcopy(ug)
connector.name = "plumbing-connector"
connector.place_result = "plumbing-connector"
data:extend{connector}