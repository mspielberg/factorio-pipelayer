local Constants = require "Constants"

local M = {}

local Connector = {}

local CAPACITY = Constants.CONNECTOR_CAPACITY
local MAX_UPDATE_INTERVAL = Constants.MAX_CONNECTOR_UPDATE_INTERVAL

local all_connectors = {}

function M.new(entity)
  if getmetatable(entity) == Connector then
    return entity
  end
  local self = {
    entity = entity,
    prev_amount = entity.fluidbox[1].amount,
    prev_tick = 0,
    flow_est = 0,
    next_tick = 0,
  }
  return M.restore(self)
end

function M.restore(self)
  all_connectors[self.entity.unit_number] = self
  return setmetatable(self, { __index = Connector })
end

function M.for_entity(entity)
  return all_connectors[entity.unit_number]
end

function Connector:estimate_flow(tick, current_amount)
  if not current_amount then
    current_amount = self.entity.fluidbox[1].amount
  end

  local interval = tick - self.prev_tick
  local amount_delta = current_amount - self.prev_amount
  local current_flow = amount_delta / interval
  local flow_est = (self.flow_est + current_flow) / 2
  self.flow_est = flow_est
  self.prev_tick = tick
end

function Connector:estimate_next_tick(new_amount)
  if not new_amount then
    local fluidbox = self.entity.fluidbox[1]
    if fluidbox then
      new_amount = fluidbox.amount
    else
      new_amount = 0
    end
  end

  local flow_est = self.flow_est
  local amount_to_saturate
  if flow_est > 0 then
    amount_to_saturate = CAPACITY - new_amount
  else
    amount_to_saturate = new_amount
  end

  self.prev_amount = new_amount
  if flow_est < 1 and flow_est > 0.1 then
    self.next_tick = self.prev_tick + MAX_UPDATE_INTERVAL
  else
    local time_to_saturate = amount_to_saturate / flow_est
    self.next_tick = self.prev_tick + math.min(MAX_UPDATE_INTERVAL, time_to_saturate / 2)
  end
end

function Connector:is_conflicting(expected_fluid)
  local fluid = self.entity.fluidbox[1]
  return expected_fluid and fluid and fluid.fluid ~= expected_fluid
end

function Connector:transfer_to(tick, expected_fluid, to_connector)
  local from_fluid = self.entity.fluidbox[1]
  local to_fluid = to_connector.entity.fluidbox[1]

  local from_amount = from_fluid and from_fluid.amount or 0
  local to_amount = to_fluid and to_fluid.amount or 0
  local space_available = CAPACITY - to_amount
  local amount_to_move = math.min(from_amount, space_available)
  self:estimate_flow(tick, from_amount)
  to_connector:estimate_flow(tick, to_amount)

  if not from_fluid then
    -- no fluid available to transfer
    return 0
  end

  local from_temperature = from_fluid and from_fluid.temperature or 0
  local to_temperature = to_fluid and to_fluid.temperature or 0
  local from_weighted_temperature = from_amount * from_temperature
  local to_weighted_temperature = to_amount * to_temperature
  local new_to_temperature = (from_weighted_temperature + to_weighted_temperature) / (from_amount + to_amount)

  local new_from_amount = from_amount - amount_to_move
  self.entity.fluidbox[1] = {amount = new_from_amount, fluid = expected_fluid, temperature = from_temperature}
  self:estimate_next_tick(new_from_amount)

  local new_to_amount = to_amount + amount_to_move
  to_connector.entity.fluidbox[1] = {amount = new_to_amount, fluid = expected_fluid, temperature = new_to_temperature}
  to_connector:estimate_next_tick(new_to_amount)

  return amount_to_move
end

return M