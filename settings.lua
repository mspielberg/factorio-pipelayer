data:extend{
  {
    type = "bool-setting",
    name = "pipelayer-deconstruction-warning",
    setting_type = "runtime-per-user",
    default_value = true,
  },

  {
    type = "int-setting",
    name = "pipelayer-connector-capacity",
    setting_type = "startup",
    minimum_value = 10,
    maximum_value = 1000000,
    default_value = 5000,
  },
}