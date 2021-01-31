local Editor = require "Editor"
local Network = require "Network"
local version = require "lualib.version"

local M = {}

local all_migrations = {}

local function add_migration(migration)
  all_migrations[#all_migrations+1] = migration
end

function M.on_mod_version_changed(old)
  old = version.parse(old)
  for _, migration in ipairs(all_migrations) do
    if not migration.version or version.lt(old, migration.version) then
      log("running world migration "..migration.name)
      migration.task()
    end
  end
end

add_migration{
  name = "remove_orphan_underground_pipes",
  task = function()
    Editor.restore(global.editor)
    local editor = global.editor
    local entities_deleted = 0
    local surfaces_affected = 0
    for _, surface in pairs(game.surfaces) do
      local surface_affected = false
      if editor:is_editor_surface(surface) then
        for _, entity in pairs(surface.find_entities()) do
          if not Network.for_entity(entity) then
            entity.destroy()
            entities_deleted = entities_deleted + 1
            surface_affected = true
          end
        end
      end
      if surface_affected then
        surfaces_affected = surfaces_affected + 1
      end
    end
    if entities_deleted > 0 then
      log("Deleted "..entities_deleted.."orphaned entities on "..surfaces_affected.." surface(s).")
    end
  end,
}

return M