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
    default_value = 10000,
  },

  {
    type = "int-setting",
    name = "pipelayer-update-period",
    setting_type = "runtime-global",
    minimum_value = 1,
    maximum_value = 216000, -- 1 hour
    default_value = 60,
  },

  {
    type = "int-setting",
    name = "pipelayer-transfer-threshold",
    setting_type = "runtime-global",
    minimum_value = 1,
    default_value = 2500,
  },

  {
    type = 'int-setting',
    name = 'pipelayer-max-distance-checked',
    setting_type = 'runtime-global',
    minimum_value = 50,
    maximum_value = 500,
    default_value = 80,
    order = 'a'
},
}
