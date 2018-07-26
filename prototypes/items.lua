require "util"

local ug = data.raw.item["pipe-to-ground"]
local via = util.table.deepcopy(ug)
via.name = "plumbing-via"
via.place_result = "plumbing-via"
data:extend{via}