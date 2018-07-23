local M = {}

local Graph = {}

function M.new()
  local self = {}
  return setmetatable(self, { __index = Graph })
end

-- add node with neighbors ...
function Graph:add(node, ...)
  local neighbors = {...}
  if not self[node] then self[node] = {} end
  for _, neighbor in ipairs(neighbors) do
    if not self[neighbor] then self[neighbor] = {} end
    self[node][neighbor] = true
    self[neighbor][node] = true
  end
end

function Graph:remove(node)
  if not self[node] then return end
  for neighbor in pairs(self[node]) do
    self[neighbor][node] = nil
  end
  self[node] = nil
end

local function dfs(self, node, visited)
  visited[node] = true
  for neighbor in pairs(self[node]) do
    if not visited[neighbor] then
      dfs(self, neighbor, visited)
    end
  end
  return visited
end

--[[
  Computes the disjoint graphs that would result from removing the specified node.
  Returns an array (possibly of length 1) of sets of nodes:
  {
    {
      [node1] = true,
      [node3] = true,
      ...
    },
    {
      [node5] = true,
      [node4] = true,
    },
  }
]]
function Graph:removal_fragments(node)
  local original_neighbors = {}
  for neighbor in pairs(self[node]) do
    original_neighbors[neighbor] = true
  end

  local fragments = {}
  for start_point in pairs(self[node]) do
    local fragment = dfs(self, start_point, {[node] = true})
    for neighbor in pairs(self[node]) do
      if fragment[neighbor] then
        self[node][neighbor] = nil
      end
    end
    fragment[node] = nil
    fragments[#fragments+1] = fragment
  end
  self[node] = original_neighbors
  return fragments
end

-- Renders the Graph as a comma-separated list of directed edges
function Graph:tostring()
  local out = ""
  for node in pairs(self) do
    for neighbor in pairs(self[node]) do
      out = out..node.."->"..neighbor..","
    end
  end
  return out
end

return M