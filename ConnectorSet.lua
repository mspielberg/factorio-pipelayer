local Connector = require "Connector"

local M = {}

local ConnectorSet = {}

function M.new()
  local self = {
    connector_for = {},
    input_connectors = {},
    output_connectors = {},
    input_iter = 1,
    output_iter = 1,
  }
  return M.restore(self)
end

function M.restore(self)
  setmetatable(self, { __index = ConnectorSet })
  for connector in self:all_connectors() do
    Connector.restore(connector)
  end
  return self
end

function ConnectorSet:remove(connector)
  self.connector_for[connector.unit_number] = nil
  for _, list in ipairs{self.input_connectors, self.output_connectors} do
    for i, existing in ipairs(list) do
      if existing == connector then
        local len = #list
        list[i] = list[len]
        list[len] = nil
        return
      end
    end
  end
end

-- Returns #other_list if connector is found as the last element in other_list,
-- otherwise returns nil.
local function add(self, connector, to_list, other_list)
  for _, existing in ipairs(to_list) do
    if existing == connector then return end
  end

  self.connector_for[connector.unit_number] = connector

  to_list[#to_list+1] = connector
  for i, existing in ipairs(other_list) do
    if existing == connector then
      local l = #other_list
      other_list[i] = other_list[l]
      other_list[l] = nil

      if i == l then
        return i
      else
        return nil
      end
    end
  end
  return nil
end

function ConnectorSet:add_input(connector)
  local was_last_output = add(self, connector, self.input_connectors, self.output_connectors)
  if self.output_iter == was_last_output then
    self.output_iter = 1
  end
end

function ConnectorSet:add_output(connector)
  local was_last_input = add(self, connector, self.output_connectors, self.input_connectors)
  if self.input_iter == was_last_input then
    self.input_iter = 1
  end
end

function ConnectorSet:add(connector)
  if connector.mode == "input" then
    self:add_input(connector)
  else
    self:add_output(connector)
  end
end

function ConnectorSet:next_input()
  local l = self.input_connectors
  local i = self.input_iter
  if i > #l then
    i = 1
  end
  local starting_index = i
  repeat
    local connector = l[i]
    if connector then
      if connector:ready_as_input() then
        self.input_iter = i
        return connector
      else
        i = i + 1
      end
    else
      i = 1
    end
  until i == starting_index
  return nil
end

function ConnectorSet:next_output()
  local l = self.output_connectors
  local i = self.output_iter
  if i > #l then
    i = 1
  end
  local starting_index = i
  repeat
    local connector = l[i]
    if connector then
      if connector:ready_as_output() then
        self.output_iter = i
        return connector
      else
        i = i + 1
      end
    else
      i = 1
    end
  until i == starting_index
  return nil
end

function ConnectorSet:all_connectors()
  local is = self.input_connectors
  local i_iter = 1
  local os = self.output_connectors
  local o_iter = 1

  return function()
    local connector = is[i_iter]
    if connector then
      i_iter = i_iter + 1
      return connector
    end
    connector = os[o_iter]
    if connector then
      o_iter = o_iter + 1
      return connector
    end
    return nil
  end
end

return M