data:extend{
  {
    type = "int-setting",
    name = "pipefitter-deconstruction-delay",
    setting_type = "runtime-global",
    minimum_value = 0,
    maximum_value = 300,
    default_value = 10,
  },

  {
    type = "int-setting",
    name = "pipefitter-connector-capacity",
    setting_type = "startup",
    minimum_value = 10,
    maximum_value = 1000000,
    default_value = 5000,
  },
}