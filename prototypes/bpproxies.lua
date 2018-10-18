require "util"

local function add_tint(proto, tint)
  local pictures
  if proto.type == "pipe" or proto.type == "pipe-to-ground" then
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
  proxy_proto.name = "pipefitter-bpproxy-"..proto.name
  proxy_proto.localised_name = {"entity-name.pipefitter-bpproxy", proto.localised_name or {"entity-name."..proto.name}}
  proxy_proto.collision_mask = {}
  proxy_proto.flags = {"player-creation"}
  proxy_proto.placeable_by = proxy_proto.placeable_by or {{item=proto.minable.result, count=1}}
  add_tint(proxy_proto, {r = 0.5, g = 0.5, b = 0.8, a = 0.25})
  return proxy_proto
end

local connector_proxy = make_proxy(data.raw["storage-tank"]["pipefitter-connector"])
connector_proxy.placeable_by[1].count = 0
local output_connector_proxy = make_proxy(data.raw["storage-tank"]["pipefitter-output-connector"])
output_connector_proxy.placeable_by[1].count = 0
data:extend{connector_proxy, output_connector_proxy}

for _, type in ipairs{"pipe", "pipe-to-ground"} do
  for _, proto in pairs(data.raw[type]) do
    if not proto.name:find("^pipefitter%-bpproxy%-") then
      data:extend{make_proxy(proto)}
    end
  end
end