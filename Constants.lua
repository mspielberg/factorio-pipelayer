local M = {
  DEBUG_ENABLED = true,

  SURFACE_NAME = "pipelayer",
  CONNECTOR_CAPACITY = settings.startup["pipelayer-connector-capacity"].value,

  MAX_CONNECTOR_UPDATE_INTERVAL = 7200,
}

return M