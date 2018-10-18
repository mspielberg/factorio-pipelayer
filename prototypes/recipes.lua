require "util"

local connector = util.table.deepcopy(data.raw.recipe["pipe-to-ground"])
connector.name = "pipelayer-connector"
connector.result_count = 1
connector.result = "pipelayer-connector"
data:extend{connector}