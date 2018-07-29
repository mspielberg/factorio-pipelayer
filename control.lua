local Blueprint = require "Blueprint"
local Editor = require "Editor"
local Network = require "Network"

local function on_init()
  Blueprint.on_init()
  Editor.on_init()
  Network.on_init()
end

local function on_load()
  Blueprint.on_load()
  Editor.on_load()
  Network.on_load()
end

local event_handlers = {
  on_built_entity = function(event)
    if event.mod_name then
      Editor.on_robot_built_entity(event)
    else
      Blueprint.on_player_built_entity(event)
      Editor.on_player_built_entity(event)
    end
  end,

  on_robot_built_entity = function(event)
    local robot = event.robot
    local entity = event.created_entity
    local stack = event.stack
    Blueprint.on_robot_built_entity(robot, entity, stack)
    Editor.on_robot_built_entity(robot, entity, stack)
  end,

  on_pre_player_mined_item = function(event)
    Blueprint.on_pre_player_mined_item(event.player_index, event.entity)
  end,

  on_player_mined_entity = function(event)
    Blueprint.on_player_mined_entity(event.player_index, event.entity, event.buffer)
    Editor.on_player_mined_entity(event)
  end,

  on_pre_ghost_deconstructed = function(event)
    Blueprint.on_pre_player_mined_item(event.player_index, event.ghost)
  end,

  on_player_setup_blueprint = function(event)
    Blueprint.on_player_setup_blueprint(event)
  end,

  on_put_item = function(event)
    Blueprint.on_put_item(event)
  end,

  on_player_rotated_entity = function(event)
     Editor.on_player_rotated_entity(event)
  end,

  on_entity_died = function(event)
    Editor.on_entity_died(event)
  end,
}

local function on_toggle_editor(event)
  Editor.toggle_editor_status_for_player(event.player_index)
end

local function on_tick()
  Blueprint.build_underground_ghosts()
  Network.update_all()
end

script.on_init(on_init)
script.on_load(on_load)
script.on_nth_tick(60, on_tick)
script.on_event("pipefitter-toggle-editor-view", on_toggle_editor)
for event_name, handler in pairs(event_handlers) do
  script.on_event(defines.events[event_name], handler)
end