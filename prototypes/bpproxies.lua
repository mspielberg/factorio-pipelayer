require "util"

local function add_tint(proto, tint)
  local pictures
  if proto.type == "pipe" then
    pictures = proto.pictures
  elseif proto.type == "storage-tank" then
    pictures = proto.pictures.picture
  end

  for _, picture in pairs(pictures) do
    picture.tint = tint
    if picture.hr_version then
      picture.hr_version.tint = tint
    end
  end
end


local function make_proxy(proto)
  local proxy_proto = util.table.deepcopy(proto)
  proxy_proto.name = "plumbing-bpproxy-"..proto.name
  proxy_proto.collision_mask = {}
  proxy_proto.flags = {"player-creation", "placeable-off-grid"}
  proxy_proto.placeable_by = proxy_proto.placeable_by or {{item=proto.minable.result, count=1}}
  add_tint(proxy_proto, {r = 0.5, g = 0.5, b = 0.8, a = 0.25})
  return proxy_proto
end

local via_proxy = make_proxy(data.raw["storage-tank"]["plumbing-via"])
via_proxy.placeable_by[1].count = 0
data:extend{via_proxy}

for _, proto in pairs(data.raw["pipe"]) do
  if not proto.name:find("^plumbing%-bpproxy%-") then
    local proxy = make_proxy(proto)
    log("adding entity "..proxy.type..","..proxy.name)
    data:extend{proxy}
  end
end