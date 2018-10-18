local M = {}

local name_for_id = {}
for name, id in pairs(defines.events) do
  name_for_id[id] = name
end

local function dump_event(event)
  event.name_str = name_for_id[event.name]
  game.print(serpent.line(event))
end

local registration_blacklist = {
  on_tick = true,
  on_chunk_generated = true,
  on_player_changed_position = true,
  on_selected_entity_changed = true,
}

local function register()
  for name, id in pairs(defines.events) do
    if not registration_blacklist[name] then
      script.on_event(id, dump_event)
    end
  end
end

function M.insert_or_spill(insertable, player, stack)
  local inserted = insertable.insert(stack)
  if inserted < stack.count then
    player.surface.spill_item_stack{position = player.position, name = stack.name, count = stack.count - inserted}
  end
end

function M.on_load()
  remote.add_interface("pipelayer", {register=register})
end

return M