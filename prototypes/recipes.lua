require "util"

local connector = util.table.deepcopy(data.raw.recipe["pipe-to-ground"])
connector.name = "pipefitter-connector"
connector.result_count = 1
connector.result = "pipefitter-connector"
data:extend{connector}