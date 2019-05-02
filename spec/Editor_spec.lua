local inspect = require "inspect"

local function setup_mocks()
  _G.defines = {
    build_check_type = {
      ghost_place = {},
    }
  }

  _G.settings = {
    startup = {
      ["pipelayer-connector-capacity"] = { value = 10000 },
    },
    global = {
      ["pipelayer-transfer-threshold"] = { value = 2500 },
    }
  }

  _G.global = {}

  local nauvis = {
    name = "nauvis",
    can_place_entity = spy.new(function() return true end),
    is_chunk_generated = function() return true end,
  }
  local editor_surface = {
    name = "pipelayer",
    can_place_entity = spy.new(function() return true end),
    is_chunk_generated = function() return true end,
  }

  local player = {}

  local position = {x=1, y=2}
  local function ghost_mock(surface, ghost_name, direction)
    return {
      name = "entity-ghost",
      ghost_name = ghost_name,
      surface = surface,
      position = position,
      direction = direction,
      force = "player",
      last_user = "user",
      destroy = stub(),
    }
  end

  local nauvis_connector_ghost = ghost_mock(nauvis, "pipelayer-connector", 2)
  local nauvis_reverse_ghost = ghost_mock(nauvis, "pipelayer-connector", 6)
  local nauvis_bpproxy_ghost = ghost_mock(nauvis, "pipelayer-bpproxy-pipelayer-connector", 4)
  local editor_connector_ghost = ghost_mock(editor_surface, "pipelayer-connector", 2)
  local editor_reverse_ghost = ghost_mock(editor_surface, "pipelayer-connector", 6)
  local editor_bpproxy_ghost = ghost_mock(editor_surface, "pipelayer-bpproxy-pipelayer-connector", 4)
  local editor_bpproxy_converted_ghost = ghost_mock(editor_surface, "pipelayer-connector", 4)

  local nauvis_final_ghost = ghost_mock(editor_surface, "pipelayer-connector", 2)
  local editor_final_ghost = ghost_mock(editor_surface, "pipelayer-connector", 4)

  _G.game = {
    delete_surface = function() end,
    players = { player },
    surfaces = {
      nauvis = nauvis,
      pipelayer = editor_surface,
    }
  }

  return {
    player = player,

    nauvis = nauvis,

    nauvis_connector_ghost = nauvis_connector_ghost,
    nauvis_reverse_ghost = nauvis_reverse_ghost,
    nauvis_bpproxy_ghost = nauvis_bpproxy_ghost,
    editor_surface = editor_surface,
    editor_reverse_ghost = editor_reverse_ghost,
    editor_connector_ghost = editor_connector_ghost,
    editor_bpproxy_ghost = editor_bpproxy_ghost,
    editor_bpproxy_converted_ghost = editor_bpproxy_converted_ghost,

    nauvis_final_ghost = nauvis_final_ghost,
    editor_final_ghost = editor_final_ghost,
  }
end

describe("A pipelayer editor", function()
  local uut
  local m
  before_each(function()
    m = setup_mocks()
    package.loaded.Editor = nil
    local Editor = require "Editor"
    uut = Editor.instance()
  end)

  describe("handles blueprints", function()
    describe("containing connector bpproxies", function()
      local position
      local final_nauvis_direction = 2
      local final_editor_direction = 4
      local reverse_direction = 6
      before_each(function()
        position = m.nauvis_bpproxy_ghost.position
      end)

      describe("placed aboveground", function()
        it("when the connector ghost is placed first", function()
          -- place connector ghost
          m.editor_surface.find_entities_filtered = spy.new(function() return {} end)
          m.editor_surface.create_entity = spy.new(function() return m.editor_reverse_ghost end)
          uut:on_built_entity{ created_entity = m.nauvis_connector_ghost }
          assert.spy(m.editor_surface.can_place_entity).was.called_with{
            name = "pipelayer-connector",
            position = position,
            direction = reverse_direction,
            force = "player",
            build_check_type = defines.build_check_type.ghost_place,
          }
          assert.spy(m.editor_surface.create_entity).was.called_with{
            name = "entity-ghost",
            inner_name = "pipelayer-connector",
            position = position,
            direction = reverse_direction,
            force = "player"
          }

          -- place bpproxy ghost
          m.nauvis.find_entities_filtered = spy.new(function() return {m.nauvis_connector_ghost} end)
          m.editor_surface.find_entities_filtered = spy.new(function() return {m.editor_reverse_ghost} end)
          m.editor_surface.create_entity = spy.new(function() return m.editor_connector_ghost end)
          uut:on_built_entity{ created_entity = m.nauvis_bpproxy_ghost }
          assert.stub(m.editor_reverse_ghost.destroy).was.called()
          assert.spy(m.editor_surface.can_place_entity).was.called_with{
            name = "pipelayer-connector",
            position = position,
            direction = final_editor_direction,
            force = "player",
            build_check_type = defines.build_check_type.ghost_place,
          }
          assert.spy(m.editor_surface.create_entity).was.called_with{
            name = "entity-ghost",
            inner_name = "pipelayer-connector",
            position = position,
            direction = final_editor_direction,
            force = "player"
          }
          assert.stub(m.nauvis_bpproxy_ghost.destroy).was.called()
        end)

        it("when the connector bpproxy ghost is placed first", function()
          -- place bpproxy ghost
          m.nauvis.find_entities_filtered = spy.new(function() return {} end)
          m.editor_surface.find_entities_filtered = spy.new(function() return {} end)
          m.editor_surface.create_entity = spy.new(function() return m.editor_bpproxy_ghost end)
          uut:on_built_entity{ created_entity = m.nauvis_bpproxy_ghost }
          assert.spy(m.editor_surface.find_entities_filtered).was.called_with{
            ghost_name = {"pipelayer-connector", "pipelayer-output-connector"},
            position = position,
          }
          assert.spy(m.editor_surface.create_entity).was.called_with{
            name = "entity-ghost",
            inner_name = "pipelayer-connector",
            position = position,
            direction = final_editor_direction,
            force = "player"
          }
          assert.stub(m.editor_connector_ghost.destroy).was_not.called()
          assert.stub(m.nauvis_bpproxy_ghost.destroy).was.called()

          -- place connector ghost
          m.editor_surface.can_place_entity = spy.new(function() return false end)
          m.editor_surface.create_entity = stub()
          uut:on_built_entity{ created_entity = m.nauvis_connector_ghost }
          assert.stub(m.editor_surface.create_entity).was_not.called()
        end)
      end)

      describe("placed in an editor", function()
        it("when the connector ghost is placed first", function()
          -- place connector ghost
          m.editor_surface.find_entities_filtered = spy.new(function() return {} end)
          m.nauvis.create_entity = spy.new(function() return m.nauvis_reverse_ghost end)
          uut:on_built_entity{ created_entity = m.editor_connector_ghost }
          assert.spy(m.nauvis.can_place_entity).was.called_with{
            name = "pipelayer-connector",
            position = position,
            direction = reverse_direction,
            force = "player",
            build_check_type = defines.build_check_type.ghost_place,
          }
          assert.spy(m.nauvis.create_entity).was.called_with{
            name = "entity-ghost",
            inner_name = "pipelayer-connector",
            position = position,
            direction = reverse_direction,
            force = "player"
          }
          assert.stub(m.editor_connector_ghost.destroy).was_not.called()

          -- place bpproxy ghost
          m.editor_surface.find_entities_filtered = spy.new(function() return {m.editor_connector_ghost} end)
          m.nauvis.find_entities_filtered = spy.new(function() return {m.nauvis_reverse_ghost} end)
          m.editor_surface.create_entity = spy.new(function() return m.editor_connector_ghost end)
          uut:on_built_entity{ created_entity = m.editor_bpproxy_ghost }
          assert.stub(m.nauvis_reverse_ghost.destroy).was.called()
          assert.spy(m.nauvis.create_entity).was.called_with{
            name = "entity-ghost",
            inner_name = "pipelayer-connector",
            position = position,
            direction = final_nauvis_direction,
            force = "player"
          }
          assert.stub(m.editor_connector_ghost.destroy).was.called()
          assert.spy(m.editor_surface.create_entity).was.called_with{
            name = "entity-ghost",
            inner_name = "pipelayer-connector",
            position = position,
            direction = final_editor_direction,
            force = "player"
          }
          assert.stub(m.editor_bpproxy_ghost.destroy).was.called()
        end)

        it("when the connector bpproxy ghost is placed first", function()
          -- place bpproxy ghost
          m.editor_surface.find_entities_filtered = spy.new(function() return {} end)
          m.editor_surface.create_entity = spy.new(function() return m.editor_connector_ghost end)
          uut:on_built_entity{ created_entity = m.editor_bpproxy_ghost }
          assert.spy(m.editor_surface.find_entities_filtered).was.called_with{
            ghost_name = {"pipelayer-connector", "pipelayer-output-connector"},
            position = position,
          }
          assert.spy(m.editor_surface.create_entity).was.called_with{
            name = "entity-ghost",
            inner_name = "pipelayer-connector",
            position = position,
            direction = final_editor_direction,
            force = "player"
          }
          assert.stub(m.editor_bpproxy_ghost.destroy).was.called()

          -- place connector ghost
          m.editor_surface.create_entity = stub()
          m.editor_surface.find_entities_filtered = spy.new(function()
            return {m.editor_connector_ghost, m.editor_bpproxy_converted_ghost}
          end)
          m.nauvis.create_entity = spy.new(function() return m.nauvis_connector_ghost end)
          uut:on_built_entity{ created_entity = m.editor_connector_ghost }
          assert.spy(m.editor_surface.find_entities_filtered).was.called_with{
            ghost_name = {"pipelayer-connector", "pipelayer-output-connector"},
            position = position,
          }
          assert.spy(m.nauvis.can_place_entity).was.called_with{
            name = "pipelayer-connector",
            position = position,
            direction = final_nauvis_direction,
            force = "player",
            build_check_type = defines.build_check_type.ghost_place,
          }
          assert.spy(m.nauvis.create_entity).was.called_with{
            name = "entity-ghost",
            inner_name = "pipelayer-connector",
            position = position,
            direction = final_nauvis_direction,
            force = "player",
          }
          assert.stub(m.editor_surface.create_entity).was_not.called()
          assert.stub(m.editor_connector_ghost.destroy).was.called()
        end)
      end)
    end)
  end)

  describe("handles pipe markers", function()
    it("when player is a spectator", function()
      m.player.surface = m.editor_surface
      uut:on_player_changed_position{player_index = 1}
    end)
  end)
end)