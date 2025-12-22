data:extend({
  {
    type = "double-setting",
    name = "ue_global_chance",
    setting_type = "runtime-global",
    default_value = 2,
    minimum_value = 0,
    maximum_value = 50,
    order = "aa"
  },
  {
    type = "double-setting",
    name = "ue_hand_mining_chance",
    setting_type = "runtime-global",
    default_value = 2,
    minimum_value = 0,
    maximum_value = 50,
    order = "ab"
  },
  {
    type = "double-setting",
    name = "ue_hand_craft_chance",
    setting_type = "runtime-global",
    default_value = 2,
    minimum_value = 0,
    maximum_value = 50,
    order = "ac"
  },
  {
    type = "double-setting",
    name = "gq_enemy_quality_minimum",
    setting_type = "runtime-global",
    default_value = 10,
    minimum_value = 0,
    maximum_value = 100,
    order = "ad"
  },
  {
    type = "double-setting",
    name = "gq_enemy_quality_evolution_factor_percentage",
    setting_type = "runtime-global",
    default_value = 40,
    minimum_value = 0,
    maximum_value = 100,
    order = "ae"
  },
  {
    type = "bool-setting",
    name = "gq_no_negative_quality_modules",
    setting_type = "startup",
    default_value = true,
    order = "za"
  }
})
