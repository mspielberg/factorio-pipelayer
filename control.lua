local Editor = require "Editor"
local Network = require "Network"

local function on_init()
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
    Editor.on_player_built_entity(event)
  end
end

local function on_toggle_editor(event)
  Editor.toggle_editor_status_for_player(event.player_index)
end

local function on_chunk_generated(event)
  if event.surface.name == "plumbing" then
    Editor.on_chunk_generated(event)
  end
end

local function on_tick()
  Network.update_all()
end

script.on_init(on_init)
script.on_load(on_load)

script.on_event({defines.events.on_built_entity, defines.events.on_robot_built_entity}, on_built_entity)
script.on_event(defines.events.on_player_mined_entity, Editor.on_player_mined_entity)
script.on_event(defines.events.on_entity_died, Editor.on_entity_died)
script.on_event("plumbing-toggle-editor-view", on_toggle_editor)
script.on_event(defines.events.on_chunk_generated, on_chunk_generated)

script.on_nth_tick(60, on_tick)