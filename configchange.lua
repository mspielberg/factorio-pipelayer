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

return M