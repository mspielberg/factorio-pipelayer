local M = {
  DEBUG_ENABLED = true,

  SURFACE_NAME = "pipefitter",
  UNDERGROUND_TILE_NAME = "dirt-6",
  CONNECTOR_CAPACITY = settings.startup["pipefitter-connector-capacity"].value,
  NETWORK_CAPACITY = settings.startup["pipefitter-connector-capacity"].value * 10,
}

return M