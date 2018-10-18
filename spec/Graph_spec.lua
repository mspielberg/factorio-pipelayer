local Graph = require "lualib.Graph"

local function to_set(...)
  local out = {}
  for i,v in ipairs{...} do
    out[v] = true
  end
  return out
end

describe("Graph framework", function()
  describe("should detect articulation points", function()
    it("for graph 1", function()
      local g = Graph.new()
      g:add(0, 1, 2, 3)
      g:add(1, 2)
      g:add(3, 4)

      assert.are_same({to_set(1,2), to_set(3,4)}, g:removal_fragments(0))
      assert.are_same({to_set(0,2,3,4)}, g:removal_fragments(1))
      assert.are_same({to_set(0,1,3,4)}, g:removal_fragments(2))
      assert.are_same({to_set(0,1,2), to_set(4)}, g:removal_fragments(3))
      assert.are_same({to_set(0,1,2,3)}, g:removal_fragments(4))
    end)

    it("for graph 2", function()
      local g = Graph.new()
      g:add(0, 1)
      g:add(1, 2)
      g:add(2, 3)

      assert.are_same({to_set(1,2,3)}, g:removal_fragments(0))
      assert.are_same({to_set(0), to_set(2,3)}, g:removal_fragments(1))
      assert.are_same({to_set(0,1), to_set(3)}, g:removal_fragments(2))
      assert.are_same({to_set(0,1,2)}, g:removal_fragments(3))
    end)

    it("for graph 3", function()
      local g = Graph.new()
      g:add(0, 1, 2)
      g:add(1, 2, 3, 4, 6)
      g:add(3, 5)
      g:add(4, 5)

      assert.are_same({to_set(1,2,3,4,5,6)}, g:removal_fragments(0))
      assert.are_same({to_set(0,2), to_set(3,4,5), to_set(6)}, g:removal_fragments(1))
      assert.are_same({to_set(0,1,3,4,5,6)}, g:removal_fragments(2))
      assert.are_same({to_set(0,1,2,4,5,6)}, g:removal_fragments(3))
      assert.are_same({to_set(0,1,2,3,5,6)}, g:removal_fragments(4))
      assert.are_same({to_set(0,1,2,3,4,6)}, g:removal_fragments(5))
      assert.are_same({to_set(0,1,2,3,4,5)}, g:removal_fragments(6))
    end)
  end)
end)