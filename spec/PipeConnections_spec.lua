local PipeConnections = require "PipeConnections"

local function check_connect(name, position, direction, expected_type)
  local fake_entity = {
    name = name,
    position = position,
    direction = direction,
    fluidbox = {},
  }
  fake_entity.fluidbox.owner = fake_entity
  local pipe = {
    position = {x=0, y=0},
    fluidbox = {
      get_connections = function(index)
        if index == 1 then
          return {fake_entity.fluidbox}
        else
          error("bad connection index")
        end
      end,
    },
  }
  local actual_type = PipeConnections.get_connected_connection_type(pipe, 1)
  assert.are.same(expected_type, actual_type)
end

expose("PipeConnections", function()
  _G.defines = {
    direction = {
      north = 0,
      east = 2,
      south = 4,
      west = 6,
    }
  }

  describe("should identify pump connections", function()
    it("for north facing pump", function()
      check_connect("pump", {x=0, y=-1.5}, 0, "input")
      check_connect("pump", {x=0, y=1.5}, 0, "output")
    end)
    it("for east facing pump", function()
      check_connect("pump", {x=1.5, y=0}, 2, "input")
      check_connect("pump", {x=-1.5, y=0}, 2, "output")
    end)
    it("for south facing pump", function()
      check_connect("pump", {x=0, y=-1.5}, 4, "output")
      check_connect("pump", {x=0, y=1.5}, 4, "input")
    end)
    it("for west facing pump", function()
      check_connect("pump", {x=-1.5, y=0}, 6, "input")
      check_connect("pump", {x=1.5, y=0}, 6, "output")
    end)
  end)

  describe("should identify oil refinery connections", function()
    local ent = "oil-refinery"
    it("for north facing", function()
      local dir = 0
      check_connect(ent, {x=-1, y=-3}, dir, "input")
      check_connect(ent, {x=1, y=-3}, dir, "input")
      check_connect(ent, {x=-2, y=3}, dir, "output")
      check_connect(ent, {x=0, y=3}, dir, "output")
      check_connect(ent, {x=2, y=3}, dir, "output")
    end)
    it("for east facing", function()
      local dir = 2
      check_connect(ent, {x=3, y=-1}, dir, "input")
      check_connect(ent, {x=3, y=1}, dir, "input")
      check_connect(ent, {x=-3, y=-2}, dir, "output")
      check_connect(ent, {x=-3, y=0}, dir, "output")
      check_connect(ent, {x=-3, y=2}, dir, "output")
    end)
    it("for south facing", function()
      local dir = 4
      check_connect(ent, {x=-1, y=3}, dir, "input")
      check_connect(ent, {x=1, y=3}, dir, "input")
      check_connect(ent, {x=-2, y=-3}, dir, "output")
      check_connect(ent, {x=0, y=-3}, dir, "output")
      check_connect(ent, {x=2, y=-3}, dir, "output")
    end)
    it("for west facing", function()
      local dir = 6
      check_connect(ent, {x=-3, y=-1}, dir, "input")
      check_connect(ent, {x=-3, y=1}, dir, "input")
      check_connect(ent, {x=3, y=-2}, dir, "output")
      check_connect(ent, {x=3, y=0}, dir, "output")
      check_connect(ent, {x=3, y=2}, dir, "output")
    end)
  end)
end)