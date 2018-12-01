--- Debug console.
-- Creates a textfield allowing you to run commands directly in your mod's enviorment.
-- <p>This module requires the use of stdlib's @{Event} module for GUI interactions.
-- <p>This module was originally the ***Console*** code from a modder named ***adil***, which has been modified for use with stdlib.
-- @module Console
-- @usage
-- remote.add_interface("my_interface", {show = require("stdlib/utils/console")})
-- /c remote.call("my_interface", "show", game.player)
-- --In the window that appears you can run lua code directly on your mod, including globals.

local have_mod_name, mod_name = pcall(function() return script.mod_name end)
local prefix = (have_mod_name and mod_name) or (MOD and MOD.console_prefix) or "console"
local names = {
  frame = prefix..'_console',
  scroll = prefix..'_console_scroll',
  textbox = prefix..'_console_line',
  enter = prefix..'_console_enter',
  clear = prefix..'_console_clear',
  close = prefix..'_console_close',
}

local function create_gui_player(player)
  if player.gui.left[names.frame] then player.gui.left[names.frame].destroy() end

  local c = player.gui.left.add{type='frame', name = names.frame, direction = 'horizontal'}

  local scroll = c.add{type = 'scroll-pane', name = names.scroll}
  scroll.style.minimal_width=600
  scroll.style.maximal_width=600
  scroll.style.maximal_height=150
  scroll.style.minimal_height=150

  local t = scroll.add{type = 'text-box', name = names.textbox}
  t.style.minimal_width=600
  t.style.maximal_width=600
  t.style.minimal_height=150

  c.add{type = 'button', name = names.enter, caption = '<', tooltip = "Run Script"}
  c.add{type = 'button', name = names.clear, caption = 'C', tooltip = "Clear Input"}
  c.add{type = 'button', name = names.close, caption = "X", tooltip = "Close"}
end

local function create_gui(player)
  --if not sent with a player, then enable for all players?
  if not (player and player.valid) then
    for _, cur_player in pairs(game.players) do
      create_gui_player(cur_player)
    end
  else
    create_gui_player(player)
  end
end

local function get_gui(player_index)
  return game.players[player_index].gui.left[names.frame]
end

local function enter(player_index)
  local p = game.players[player_index]
  local s = get_gui(player_index)[names.scroll][names.textbox].text

  local ok, err = pcall(function() return loadstring(s)() end )
  --pcall(loadstring("return function(a, b, c) ".. chunkstring .. " end"))
  game.write_file(prefix..'/console.log', '$ '..s..'\n'..(err or "")..'\n', true, p.index)
  if not ok then p.print(err) end

end

local function close(event)
  get_gui(player_index).destroy()
end

local function clear(event)
  get_gui(player_index)[names.scroll][names.textbox].text = ""
end

local function on_gui_click(event)
  local name = event.element.name
  local player_index = event.player_index
  if name == names.enter then
    enter(player_index)
  elseif name == names.close then
    close(player_index)
  elseif name == names.clear then
    clear(player_index)
  end
end

return {
  create_gui = create_gui,
  on_gui_click = on_gui_click,
  on_enter = enter,
}
