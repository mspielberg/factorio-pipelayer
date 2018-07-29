require "util"

local ug = data.raw.item["pipe-to-ground"]
local connector = util.table.deepcopy(ug)
connector.name = "pipefitter-connector"
connector.place_result = "pipefitter-connector"
data:extend{connector}