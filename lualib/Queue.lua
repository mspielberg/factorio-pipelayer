local M = {}

--- An implementation of a FIFO queue based on dual tables.
-- One table holds new entries, one table holds entries that are ready to read.
-- The tables swap roles when the tables for reads is exhausted.
-- Runtime is guaranteed amortized O(1), with actual O(1) in most scenarios.
-- The internal tables are reused, and no allocation is performed in steady state.
local Queue = {}

function Queue:append(x)
  local write_cursor = self.write_cursor
  self.write[write_cursor] = x
  self.write_cursor = write_cursor + 1
end

function Queue:dequeue(x)
  local read = self.read
  local read_cursor = self.read_cursor
  local head = read[read_cursor]

  if head then
    self.read_cursor = read_cursor + 1
    return head
  end

  -- exhausted read queue
  local write_cursor = self.write_cursor
  if write_cursor == 1 then
    -- entire queues empty
    return nil
  end

  -- ...but at least one entry is available in write queue
  local write = self.write
  -- clean out old entries that have not been overwritten
  for i=write_cursor,#write do
    write[i] = nil
  end

  -- swap roles for upcoming calls
  self.read, self.write = write, read
  self.read_cursor = 2
  -- lazily overwrite old entries during append()
  self.write_cursor = 1

  -- return entry from (what used to be) the write queue
  return write[1]
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
