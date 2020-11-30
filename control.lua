local configchange = require "configchange"
local console = require "console"
local Editor = require "Editor"
local Network = require "Network"

require "PipeMarker"
local editor

local function on_init()
  global.players = {}
  global.editor = Editor.new()
  editor = global.editor
  Network.on_init()
end

local function on_load()
  if global.editor then
    editor = Editor.restore(global.editor)
  end
  Network.on_load()
end

local function on_configuration_changed(data)
  if data.mod_changes.pipelayer then
    configchange.on_mod_version_changed(data.mod_changes.pipelayer.old_version or "0.0.0")
    editor = global.editor
  end
  editor:on_configuration_changed(data)
end

local event_handlers = {
  on_built_entity                = function(event) editor:on_built_entity(event)                 end,
  on_cancelled_deconstruction    = function(event) editor:on_cancelled_deconstruction(event)     end,
  on_entity_died                 = function(event) editor:on_entity_died(event)                  end,
  on_marked_for_deconstruction   = function(event) editor:on_marked_for_deconstruction(event)    end,
  on_picked_up_item              = function(event) editor:on_picked_up_item(event)               end,
  on_player_changed_position     = function(event) editor:on_player_changed_position(event)      end,
  on_player_cursor_stack_changed = function(event) editor:on_player_cursor_stack_changed(event)  end,
  on_player_deconstructed_area   = function(event) editor:on_player_deconstructed_area(event)    end,
  on_player_mined_entity         = function(event) editor:on_player_mined_entity(event)          end,
  on_player_mined_item           = function(event) editor:on_player_mined_item(event)            end,
  on_player_rotated_entity       = function(event) editor:on_player_rotated_entity(event)        end,
  on_player_setup_blueprint      = function(event) editor:on_player_setup_blueprint(event)       end,
  on_pre_build                   = function(event) editor:on_pre_build(event)                    end,
  on_pre_ghost_deconstructed     = function(event) editor:on_pre_ghost_deconstructed(event)      end,
  on_pre_player_mined_item       = function(event) editor:on_pre_player_mined_item(event)        end,
  on_robot_built_entity          = function(event) editor:on_robot_built_entity(event)           end,
  on_robot_mined_entity          = function(event) editor:on_robot_mined_entity(event)           end,
  on_runtime_mod_setting_changed = function(event) Network.on_runtime_mod_setting_changed(event) end,
  on_tick                        = function(event) editor:on_tick(event)                         end,
  script_raised_built            = function(event) editor:on_script_raised_built(event)          end,
  script_raised_destroy          = function(event) editor:on_script_raised_destroy(event)        end,
  script_raised_revive           = function(event) editor:on_script_raised_revive(event)         end,
}

local function on_toggle_editor(event)
  editor:toggle_editor_status_for_player(event.player_index)
end

local function on_toggle_connector_mode(event)
  editor:toggle_connector_mode(event.player_index)
end

script.on_init(on_init)
script.on_load(on_load)
script.on_configuration_changed(on_configuration_changed)
script.on_event("pipelayer-toggle-editor-view", on_toggle_editor)
script.on_event("pipelayer-toggle-connector-mode", on_toggle_connector_mode)
for event_name, handler in pairs(event_handlers) do
  script.on_event(defines.events[event_name], handler)
end

script.on_event(defines.events.on_gui_click, console.on_gui_click)
remote.add_interface("pipelayer", {console = console.create_gui})
