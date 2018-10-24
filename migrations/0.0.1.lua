for _, f in pairs(game.forces) do
  if f.technologies["fluid-handling"] and f.technologies["fluid-handling"].researched == true then
    if f.recipes["pipelayer-connector"] then
      f.recipes["pipelayer-connector"].enabled = true
    end
  end
end