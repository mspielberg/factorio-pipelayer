local M = {
  DEBUG_ENABLED = true,

  SURFACE_NAME = "pipelayer",
  CONNECTOR_CAPACITY = settings.startup["pipelayer-connector-capacity"].value,

  ACTIVE_UPDATE_INTERVAL = settings.startup["pipelayer-update-period"].value,
  INACTIVE_UPDATE_INTERVAL = settings.startup["pipelayer-update-period"].value * 10,
  NO_FLUID_UPDATE_INTERVAL = settings.startup["pipelayer-update-period"].value * 30,
}

return M