require "util"

local ug = util.table.deepcopy(data.raw.recipe["pipe-to-ground"])
ug.name = "plumbing-connector"
ug.result_count = 1
ug.result = "plumbing-connector"
data:extend{ug}