require "util"

local ug = util.table.deepcopy(data.raw.recipe["pipe-to-ground"])
ug.name = "plumbing-via"
ug.result_count = 1
ug.result = "plumbing-via"
data:extend{ug}