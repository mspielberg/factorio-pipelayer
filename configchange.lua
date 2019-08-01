local Connector = require "Connector"
local Editor = require "Editor"
local Network = require "Network"
local Queue = require "lualib.Queue"
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

add_migration{
  name = "v0_2_1_add_network_absorb_work_queue",
  version = {0,2,1},
  task = function()
    global.absorb_queue = Queue.new()
    for _, network in pairs(global.all_networks) do
      network.graph = nil
    end
    Network.on_load()
  end,
}

local function resolve_duplicated_pipe(pipe, na, nb)
  local unit_number = pipe.unit_number
  log("pipe "..unit_number.." in network "..nb.id.." is already part of network "..na.id)
  local connector = Connector.for_below_unit_number(unit_number)
  na:remove_underground_pipe(pipe, true)
  nb:remove_underground_pipe(pipe, true)
  if na.id > nb.id then
    if not na.surface then na.surface = pipe.surface end
    na:add_underground_pipe(pipe, connector and connector.entity)
  else
    if not nb.surface then nb.surface = pipe.surface end
    nb:add_underground_pipe(pipe, connector and connector.entity)
  end
end

add_migration{
  name = "clean_corrupted_networks",
  task = function()
    for network_id, network in pairs(global.all_networks) do
      for unit_number, pipe in pairs(network.pipes) do
        if pipe.valid then
          local previous_network = Network.for_entity(pipe)
          if previous_network ~= network then
            resolve_duplicated_pipe(pipe, previous_network, network)
          end
        else
          log("pipe "..unit_number.." in network "..network_id.." no longer valid")
          network.pipes[unit_number] = nil
        end
      end

      if not next(network.pipes) then
        network:destroy()
      end
    end
  end,
}

add_migration{
  name = "v0_3_5_remove_duplicate_bpproxies",
  version = {0,3,5},
  task = function()
    for _, surface in pairs(game.surfaces) do
      local prev = nil
      for _, en in ipairs(surface.find_entities_filtered{type = {"pipe","pipe-to-ground"}}) do
        if en.name:find("^pipelayer%-bpproxy%-") then
          if prev and prev.position.x == en.position.x and prev.position.y == en.position.y then
            en.destroy()
          else
            prev = en
          end
        end
      end
    end
  end,
}

add_migration{
  name = "v0_3_5_remove_duplicate_bpproxy_ghosts",
  version = {0,3,5},
  task = function()
    for _, surface in pairs(game.surfaces) do
      local prev = nil
      for _, en in ipairs(surface.find_entities_filtered{name = "entity-ghost"}) do
        if en.ghost_name:find("^pipelayer%-bpproxy%-") then
          if prev and prev.position.x == en.position.x and prev.position.y == en.position.y then
            en.destroy()
          else
            prev = en
          end
        end
      end
    end
  end,
}

add_migration{
  name = "v0_3_5_cache_network_surface",
  version = {0,3,5},
  task = function()
    for _, n in pairs(global.all_networks) do
      local _, p = next(n.pipes)
      n.surface = p.surface
    end
  end,
}

return M