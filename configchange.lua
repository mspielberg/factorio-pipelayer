
local Editor = require "Editor"
local version = require "lualib.version"

local M = {}

local all_migrations = {}

local function add_migration(migration)
  all_migrations[#all_migrations+1] = migration
end

function M.on_mod_version_changed(old)
  old = version.parse(old)
  for _, migration in ipairs(all_migrations) do
    if version.lt(old, migration.version) then
      log("running world migration "..migration.name)
      migration.task()
    end
  end
end

add_migration{
  name = "v0_2_0_migrate_globals",
  version = {0,2,0},
  task = function()
    global.editor = Editor.instance()
    global.editor.player_state = global.player_state or {}
    global.player_state = nil
    global.editor_surface = nil
  end,
}

add_migration{
  name = "v0_2_1_add_pipemarker_global",
  version = {0,2,1},
  task = function()
    global.players = global.players or {}
  end,
}

return M