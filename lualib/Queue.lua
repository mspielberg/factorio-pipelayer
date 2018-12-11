local inspect = require "inspect"

local M = {}

local Queue = {}

function Queue:append(x)
  local write_cursor = self.write_cursor
  self.write[write_cursor] = x
  self.write_cursor = write_cursor + 1
end

function Queue:dequeue(x)
  local read_cursor = self.read_cursor
  local head = self.read[read_cursor]

  if head then
    self.read_cursor = read_cursor + 1
  elseif next(self.write) then
    -- exhausted read queue
    -- clean out excess old references
    local write = self.write
    local write_cursor = self.write_cursor
    for k in pairs(write) do
      if k >= write_cursor then
        write[k] = nil
      end
    end
    -- swap roles
    self.read, self.write = self.write, self.read
    head = self.read[1]
    self.read_cursor = 2
    self.write_cursor = 1
  end

  return head
end

function M.new()
  local self = {
    read = {},
    write = {},
    read_cursor = 1,
    write_cursor = 1,
  }
  return M.restore(self)
end

function M.restore(self)
  return setmetatable(self, { __index = Queue })
end

return M
