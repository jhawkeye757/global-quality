-- Only run if the startup setting is enabled
local setting = settings.startup["gq_no_negative_quality_modules"]
if setting and setting.value then
  local modules = data.raw["module"]
  if modules then
    for _, module in pairs(modules) do
      if module.effect then
        local q = module.effect.quality

        -- If there's no quality effect at all, add neutral (0) so it never penalizes
        if q == nil then
          module.effect.quality = 0

        else
          local t = type(q)

          if t == "number" then
            -- Old-style or simple definition: clamp negative -> 0
            if q < 0 then
              module.effect.quality = 0
            end

          elseif t == "table" then
            -- EffectValue table form: { bonus = ... }
            if q.bonus and q.bonus < 0 then
              q.bonus = 0
            end
          end
        end
      end
    end
  end
end
