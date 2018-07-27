local Blueprint = require "Blueprint"
local Editor = require "Editor"
local Network = require "Network"

local function on_init()
  Blueprint.on_init()
  Editor.on_init()
  Network.on_init()
end

local function on_load()
  Editor.on_load()
  Network.on_load()
end

local function on_built_entity(event)
  if event.mod_name or event.robot then
    Editor.on_robot_built_entity(event)
  else
    Blueprint.on_player_built_entity(event)
    Editor.on_player_built_entity(event)
  end
end

local function on_pre_player_mined_item(event)
  Blueprint.on_pre_player_mined_item(event.player_index, event.entity)
end

local function on_pre_ghost_deconstructed(event)
  Blueprint.on_pre_player_mined_item(event.player_index, event.ghost)
end

local function on_player_setup_blueprint(event)
  Blueprint.on_player_setup_blueprint(event)
end

local function on_toggle_editor(event)
  Editor.toggle_editor_status_for_player(event.player_index)
end

local function on_tick()
  Blueprint.build_underground_ghosts()
  Network.update_all()
end

script.on_init(on_init)
script.on_load(on_load)

script.on_event({defines.events.on_built_entity, defines.events.on_robot_built_entity}, on_built_entity)
script.on_event(defines.events.on_pre_player_mined_item, on_pre_player_mined_item)
script.on_event(defines.events.on_pre_ghost_deconstructed, on_pre_ghost_deconstructed)
script.on_event(defines.events.on_player_mined_entity, Editor.on_player_mined_entity)
script.on_event(defines.events.on_player_rotated_entity, Editor.on_player_rotated_entity)
script.on_event(defines.events.on_entity_died, Editor.on_entity_died)
script.on_event("plumbing-toggle-editor-view", on_toggle_editor)
script.on_event(defines.events.on_player_setup_blueprint, on_player_setup_blueprint)
script.on_event(defines.events.on_put_item, Blueprint.on_put_item)

script.on_nth_tick(60, on_tick)