local PipeConnections = require "lualib.PipeConnections"

local M = {}

local Connector = {}

local CAPACITY = settings.startup["pipelayer-connector-capacity"].value

local transfer_threshold = settings.global["pipelayer-transfer-threshold"].value

local connector_for_above = {}
local connector_for_below = {}

function M.new(entity, below_unit_number)
  local fluid = entity.fluidbox[1]
  local self = {
    entity = entity,
    fluidbox = entity.fluidbox,
    unit_number = entity.unit_number,
    below_unit_number = below_unit_number,
    mode = "input",
  }
  M.restore(self)
  self:infer_mode()
  return self
end

function M.restore(self)
  connector_for_above[self.unit_number] = self
  connector_for_below[self.below_unit_number] = self
  return setmetatable(self, { __index = Connector })
end

function M.on_runtime_mod_setting_changed(event)
  if event.setting == "pipelayer-transfer-threshold" then
    transfer_threshold = settings.global["pipelayer-transfer-threshold"].value
  end
end

function M.for_entity(entity)
  return connector_for_above[entity.unit_number]
end

function M.for_below_unit_number(id)
  return connector_for_below[id]
end

function M.infer_mode_for_connectors(entity)
  local fluidbox = entity.fluidbox
  for i=1,#fluidbox do
    for _, neighbor in ipairs(entity.neighbours()[i]) do
      if neighbor.name == "pipelayer-connector" then
        M.for_entity(neighbor):infer_mode()
      end
    end
  end
end

function Connector:ready_as_input()
  self.fluidbox = self.fluidbox or self.entity.fluidbox
  local fluid = self.fluidbox[1]
  return fluid and fluid.amount >= transfer_threshold
end

function Connector:ready_as_output()
  self.fluidbox = self.fluidbox or self.entity.fluidbox
  local fluid = self.fluidbox[1]
  return not fluid or ((CAPACITY - fluid.amount) >= transfer_threshold)
end

function Connector:is_conflicting(expected_fluid)
  self.fluidbox = self.fluidbox or self.entity.fluidbox
  local fluid = self.fluidbox[1]
  return expected_fluid and fluid and fluid.name ~= expected_fluid
end

function Connector:infer_mode()
  local connected_mode = PipeConnections.get_connected_connection_type(self.entity, 1)
  if connected_mode == "input" then
    self.mode = "output"
  elseif connected_mode == "output" then
    self.mode = "input"
  end
end

function Connector:transfer_to(expected_fluid, to_connector)
  self.fluidbox = self.fluidbox or self.entity.fluidbox
  local from_fluidbox = self.fluidbox
  local from_fluid = from_fluidbox[1]
  if not from_fluid then return end

  local to_fluidbox = to_connector.fluidbox
  local to_fluid = to_fluidbox[1]

  local from_amount = from_fluid and from_fluid.amount or 0
  local to_amount = to_fluid and to_fluid.amount or 0
  local space_available = CAPACITY - to_amount
  local amount_to_move = math.min(from_amount, space_available)


  local from_temperature = from_fluid and from_fluid.temperature or 0
  local to_temperature = to_fluid and to_fluid.temperature or 0
  local from_weighted_temperature = from_amount * from_temperature
  local to_weighted_temperature = to_amount * to_temperature
  local new_to_temperature = (from_weighted_temperature + to_weighted_temperature) / (from_amount + to_amount)

  local new_from_amount = from_amount - amount_to_move
  if new_from_amount > 0 then
    from_fluidbox[1] = {amount = new_from_amount, name = expected_fluid, temperature = from_temperature}
  else
    from_fluidbox[1] = nil
  end

  local new_to_amount = to_amount + amount_to_move
  if new_to_amount > 0 then
    to_fluidbox[1] = {amount = new_to_amount, name = expected_fluid, temperature = new_to_temperature}
  else
    to_fluidbox[1] = nil
  end

  return amount_to_move
end

return M