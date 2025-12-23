local EVENT = defines.events

----------------------------------------------------------------
-- Global machine quality (ue_global_chance)
-- Interprets X% as "extra first-step chance" using vanilla next_probability.
----------------------------------------------------------------

local function apply_global_effect_to_all_surfaces()
  local setting = settings.global["ue_global_chance"]
  local v = (setting and setting.value) or 0

  -- Vanilla-assuming shorthand: effect = v * normal.next_probability
  local np = prototypes.quality["normal"].next_probability or 0.1
  local effect = v * np

  -- modifies but does not replace global_effect table
  for _, surface in pairs(game.surfaces) do
    local eff = surface.global_effect or {}
    eff.quality = effect
    surface.global_effect = eff
  end
end


----------------------------------------------------------------
-- Unlock Uncommon quality from start
----------------------------------------------------------------

local function unlock_uncommon_for_all_forces()
  for _, force in pairs(game.forces) do
    if force.valid and force.unlock_quality then
      force.unlock_quality("uncommon")
    end
  end
end

----------------------------------------------------------------
-- Shared quality roll (vanilla-style default, capped by unlocks)
----------------------------------------------------------------

-- effect here is in "quality effect" units:
-- chance(step) = effect * current_quality.next_probability
local function roll_quality(initial_quality, probability, force, use_exponential_probability)
  if use_exponential_probability == nil then
    local setting = settings.startup["gq_exponential_probability"]
    use_exponential_probability = setting and setting.value or false
  end
  if probability <= 0 then
    return initial_quality
  end

  local q = prototypes.quality[initial_quality] or prototypes.quality["normal"]
  if not q then
    return initial_quality
  end

  while q.next and ((force == nil) or force.is_quality_unlocked(q.next)) do
    local next_prob = q.next_probability or 0.1
    if next_prob <= 0 then break end
    if use_exponential_probability then next_prob = probability end
    local step_chance = probability * next_prob
    if step_chance <= 0 or math.random() >= step_chance then
      break
    end

    q = q.next
  end

  return q.name
end

----------------------------------------------------------------
-- Crash site piece quality on new game
----------------------------------------------------------------

local export_stack
local insert_stack

local CRASH_SITE_QUALITY_CHANCE = 80

local function apply_quality_to_crash_site_pieces()
  if CRASH_SITE_QUALITY_CHANCE <= 0 then
    return 0
  end

  local crash_names = {}
  local entity_protos = prototypes.entity or (game and game.entity_prototypes)
  if not entity_protos then
    return 0
  end
  for name, _ in pairs(entity_protos) do
    if name:sub(1, 11) == "crash-site-" then
      crash_names[#crash_names + 1] = name
    end
  end
  if #crash_names == 0 then
    return 0
  end

  local seen = 0
  for _, surface in pairs(game.surfaces) do
    for _, name in ipairs(crash_names) do
      local entities = surface.find_entities_filtered{name = name}
      for _, entity in ipairs(entities) do
        if entity.valid then
          seen = seen + 1
          local base_quality = entity.quality or "normal"
          if type(base_quality) ~= "string" then
            base_quality = base_quality.name or "normal"
          end

          local effect = CRASH_SITE_QUALITY_CHANCE / 100
          local target_quality = roll_quality(base_quality, effect, nil, true)
          if target_quality ~= base_quality then
            local inv_data
            local inv = entity.get_inventory(defines.inventory.chest)
            if inv and inv.valid then
              inv_data = {}
              for i = 1, #inv do
                local stack = inv[i]
                if stack.valid_for_read then
                  inv_data[#inv_data + 1] = export_stack(stack)
                end
              end
            end

            local position = entity.position
            local direction = entity.direction
            local force = entity.force
            local entity_surface = entity.surface
            local entity_name = entity.name

            entity.destroy()
            local created = entity_surface.create_entity{
              name = entity_name,
              position = position,
              force = force,
              direction = direction,
              quality = target_quality
            }

            if created and created.valid and inv_data then
              local new_inv = created.get_inventory(defines.inventory.chest)
              if new_inv and new_inv.valid then
                for _, data in ipairs(inv_data) do
                  insert_stack(new_inv, data, nil)
                end
              end
            end
          end
        end
      end
    end
  end

  return seen
end


----------------------------------------------------------------
-- Enemy spawn quality (evolution-based)
----------------------------------------------------------------

local function on_enemy_entity_spawned(event)
  local entity = event.entity
  local spawner = event.spawner
  local surface = entity.surface
  local base_quality = spawner.quality.name or entity.quality.name or "normal"
  
  local evolution_factor = game.forces["enemy"].get_evolution_factor(surface)
  
  local min_percent = settings.global["gq_enemy_quality_minimum"].value
  local evo_percent = settings.global["gq_enemy_quality_evolution_factor_percentage"].value

  local base_probability = math.min(1, (evolution_factor * (evo_percent / 100)) + (min_percent / 100))

  local probability = base_probability * 10
    
  local target_quality = roll_quality(base_quality, probability)
  if target_quality == base_quality then
    return
  else
    local position = entity.position
    local force = entity.force
    local name = entity.name
    entity.destroy()
    surface.create_entity{
      name = name,
      position = position,
      force = force,
      quality = target_quality
  }
  end
end

----------------------------------------------------------------
-- Player spawn/respawn quality (time-based)
----------------------------------------------------------------

local function compute_player_spawn_quality_chance(player)
  local hours_played = player.online_time / (60 * 60 * 60) -- Convert ticks to hours
  return (math.min(hours_played * 0.01, 0.4) + 0.1) -- Cap the probability at 50%
end

local character_inventory_ids = {
  defines.inventory.character_main,
  defines.inventory.character_armor,
  defines.inventory.character_guns,
  defines.inventory.character_ammo
}

export_stack = function(stack)
  local ok, data = pcall(stack.export_stack, stack)
  if ok and data then
    return data
  end
  return {name = stack.name, count = stack.count}
end

insert_stack = function(inv, data, quality)
  local payload = {}
  for k, v in pairs(data) do
    payload[k] = v
  end
  if quality then
    payload.quality = quality
  end

  local count = payload.count or 1
  local inserted = inv.insert(payload)
  if inserted < count then
    payload.quality = nil
    payload.count = count - inserted
    inv.insert(payload)
  end
end

local function apply_player_items_quality(player, quality)
  local saw_items = false
  for _, inv_id in ipairs(character_inventory_ids) do
    local inv = player.get_inventory(inv_id)
    if inv and inv.valid then
      local items = {}
      for i = 1, #inv do
        local stack = inv[i]
        if stack.valid_for_read then
          items[#items + 1] = export_stack(stack)
        end
      end
      if #items > 0 then
        saw_items = true
        inv.clear()
        for _, data in ipairs(items) do
          insert_stack(inv, data, quality)
        end
      end
    end
  end
  return saw_items
end

local function replace_character_with_quality(player, quality)
  local character = player and player.valid and player.character
  if not (character and character.valid) then
    return false
  end

  local position = character.position
  local surface = character.surface
  local force = character.force
  local direction = character.direction
  local name = character.name

  local snapshot = {}
  for _, inv_id in ipairs(character_inventory_ids) do
    local inv = player.get_inventory(inv_id)
    if inv and inv.valid then
      local items = {}
      for i = 1, #inv do
        local stack = inv[i]
        if stack.valid_for_read then
          items[#items + 1] = export_stack(stack)
        end
      end
      snapshot[inv_id] = items
      inv.clear()
    end
  end

  local function restore_items()
    for inv_id, items in pairs(snapshot) do
      local inv = player.get_inventory(inv_id)
      if inv and inv.valid then
        for _, data in ipairs(items) do
          insert_stack(inv, data, nil)
        end
      end
    end
  end

  if not pcall(player.set_controller, player, {type = defines.controllers.god}) then
    restore_items()
    return false
  end

  if character.valid then
    character.destroy()
  end

  local new_character
  pcall(function()
    new_character = surface.create_entity{
      name = name,
      position = position,
      force = force,
      direction = direction,
      quality = quality
    }
  end)
  if not (new_character and new_character.valid) then
    pcall(function()
      new_character = surface.create_entity{
        name = name,
        position = position,
        force = force,
        direction = direction
      }
    end)
  end
  if not (new_character and new_character.valid) then
    pcall(player.create_character, player)
    new_character = player.character
  end
  if not (new_character and new_character.valid) then
    restore_items()
    return false
  end

  pcall(player.set_controller, player, {type = defines.controllers.character, character = new_character})
  restore_items()
  return true
end

local function apply_spawn_quality_to_player(player)
  if not (player and player.valid) then
    return nil
  end

  local character = player.character
  if not (character and character.valid) then
    return nil
  end

  local base_quality = character.quality or "normal"
  if type(base_quality) ~= "string" then
    base_quality = base_quality.name or "normal"
  end

  local q_proto = prototypes.quality[base_quality] or prototypes.quality["normal"]
  local next_prob = (q_proto and q_proto.next_probability) or 0.1
  if next_prob <= 0 then
    next_prob = 0.1
  end

  local final_quality = base_quality
  local chance = compute_player_spawn_quality_chance(player)
  if chance > 0 then
    final_quality = roll_quality(base_quality, chance / next_prob, player.force)
  end

  if final_quality ~= base_quality then
    replace_character_with_quality(player, final_quality)
  end

  local final_proto = prototypes.quality[final_quality]
  if final_proto and final_proto.color then
    player.color = final_proto.color
  end

  return final_quality
end

local function on_player_spawn_or_respawn(event)
  local player = game.get_player(event.player_index)
  if not player or not player.valid then
    return
  end

  if not global.gq_crash_site_quality_applied then
    local seen = apply_quality_to_crash_site_pieces()
    if seen > 0 then
      global.gq_crash_site_quality_applied = true
    end
  end

  local quality = apply_spawn_quality_to_player(player)
  if quality then
    apply_player_items_quality(player, quality)
  end
end

----------------------------------------------------------------
-- Handcrafting quality (ue_hand_craft_chance)
----------------------------------------------------------------

local function compute_handcraft_effect()
  local setting = settings.global["ue_hand_craft_chance"]
  if not setting then
    return 0
  end

  local bonus_percent = setting.value or 0
  if bonus_percent <= 0 then
    return 0
  end

  local normal = prototypes.quality["normal"]
  local next_prob = normal.next_probability or 0.1
  if next_prob <= 0 then
    next_prob = 0.1
  end

  local effect = (bonus_percent / 100) / next_prob
  if effect < 0 then effect = 0 end
  return effect
end

local function on_player_crafted_item(event)
  local player = game.get_player(event.player_index)
  if not player or not player.valid then
    return
  end

  local stack = event.item_stack
  if not (stack and stack.valid_for_read and stack.prototype) then
    return
  end

  local effect = compute_handcraft_effect()
  if effect <= 0 then
    return
  end

  local force = player.force
  local name = stack.name
  local base_quality = stack.quality or "normal"
  if type(base_quality) ~= "string" then
    base_quality = base_quality.name or "normal"
  end
  local count = stack.count
  local health = stack.health

  if count <= 0 then
    return
  end

  local target_q = roll_quality(base_quality, effect, force)
  if target_q == base_quality then
    return
  end

  -- Update the crafted stack in place so queued crafts consume it correctly.
  stack.set_stack({
    name = name,
    count = count,
    health = health,
    quality = target_q
  })
  
end

----------------------------------------------------------------
-- Hand mining quality (ue_hand_mining_chance)
-- Applies to natural map entities only: ores, rocks, trees, fish, etc.
----------------------------------------------------------------

local function compute_hand_mining_effect()
  local setting = settings.global["ue_hand_mining_chance"]
  if not setting then
    return 0
  end

  local bonus_percent = setting.value or 0
  if bonus_percent <= 0 then
    return 0
  end

  local normal = prototypes.quality["normal"]
  local next_prob = normal.next_probability or 0.1
  if next_prob <= 0 then
    next_prob = 0.1
  end

  local effect = (bonus_percent / 100) / next_prob
  if effect < 0 then effect = 0 end
  return effect
end

-- Only treat these entity types as "natural hand-mined" targets.
local natural_mined_types = {
  ["resource"] = true,
  ["tree"] = true,
  ["simple-entity"] = true,
  ["simple-entity-with-owner"] = true,
  ["simple-entity-with-force"] = true,
  ["fish"] = true
}

local function on_player_mined_entity(event)
  local player = game.get_player(event.player_index)
  if not player or not player.valid then
    return
  end

  local entity = event.entity
  if not (entity and entity.valid) then
    return
  end

  -- Only apply to natural map stuff, not buildings.
  if not natural_mined_types[entity.type] then
    return
  end

  local effect = compute_hand_mining_effect()
  if effect <= 0 then
    return
  end

  local force = player.force
  local buffer = event.buffer
  if not (buffer and buffer.valid) then
    return
  end

  -- Snapshot original drops so we don't double-process.
  local originals = {}
  for i = 1, #buffer do
    local stack = buffer[i]
    if stack.valid_for_read then
      local base_quality = stack.quality or "normal"
      if type(base_quality) ~= "string" then
        base_quality = base_quality.name or "normal"
      end

      originals[#originals+1] = {
        index = i,
        name = stack.name,
        base_quality = base_quality,
        count = stack.count
      }
    end
  end

  -- Clear and reinsert with rolled qualities.
  for _, s in ipairs(originals) do
    buffer[s.index].clear()

    local result_counts = {}

    for _ = 1, s.count do
      local target_q = roll_quality(s.base_quality, effect, force)
      result_counts[target_q] = (result_counts[target_q] or 0) + 1
    end

    for quality, c in pairs(result_counts) do
      if c > 0 then
        buffer.insert{
          name = s.name,
          count = c,
          quality = quality
        }
      end
    end
  end
end

----------------------------------------------------------------
-- Init / configuration
----------------------------------------------------------------

local function full_init()
  unlock_uncommon_for_all_forces()
  apply_global_effect_to_all_surfaces()
end

script.on_init(function()
  if not global then
    global = {}
  end
  full_init()
  global.gq_crash_site_quality_applied = false
  local seen = apply_quality_to_crash_site_pieces()
  if seen > 0 then
    global.gq_crash_site_quality_applied = true
  end
end)

script.on_configuration_changed(function(_)
  full_init()
end)

script.on_event(EVENT.on_runtime_mod_setting_changed, function(event)
  if event.setting == "ue_global_chance" then
    apply_global_effect_to_all_surfaces()
  end
  -- handcraft/mining effects are read dynamically in their handlers
end)

script.on_event(EVENT.on_player_created, on_player_spawn_or_respawn)
script.on_event(EVENT.on_player_respawned, on_player_spawn_or_respawn)
script.on_event(EVENT.on_entity_spawned, on_enemy_entity_spawned)
script.on_event(EVENT.on_player_crafted_item, on_player_crafted_item)
script.on_event(EVENT.on_player_mined_entity, on_player_mined_entity)


