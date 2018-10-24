require "util"

local connector = util.table.deepcopy(data.raw.recipe["pipe-to-ground"])
connector.name = "pipelayer-connector"
connector.enabled = false
connector.ingredients = {{"storage-tank", 1}, {"pipe-to-ground", 2}}
connector.result_count = 1
connector.result = "pipelayer-connector"
data:extend{connector}

local tech = data.raw.technology["fluid-handling"]
if tech then
  table.insert(tech.effects, { type = "unlock-recipe", recipe = "pipelayer-connector" })
end