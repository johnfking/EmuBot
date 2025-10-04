-- Example: configuring Elba spell thresholds using EmuBot's spell enum helpers
local SpellEnums = require('EmuBot.modules.spell_enums')

-- Use the strongly-typed spell enum instead of a raw short-name string.
-- SpellEnums.set_spell_max_threshold resolves the canonical identifier
-- for us before delegating to the bot's spellmaxthresholds method.
SpellEnums.set_spell_max_threshold(
    Elba,
    SpellEnums.SpellTypes.FastHeals,
    40,
    Actionable.spawned()
)

-- You can still provide numeric IDs or canonical names directly if you need to
-- mix different sources in a single table. SpellEnums.normalize_spell_max_thresholds
-- accepts enum values, canonical names, short names, or numeric IDs and produces
-- a normalized map ready for consumption by bot commands.
local normalized_thresholds = SpellEnums.normalize_spell_max_thresholds({
    [SpellEnums.SpellTypes.FastHeals] = 40,
    [SpellEnums.SpellTypes.HoTHeals] = '25',
})

-- Iterate over the normalized map if you need to issue multiple commands.
for spell_type, max_threshold in pairs(normalized_thresholds) do
    Elba:spellmaxthresholds(spell_type, max_threshold, Actionable.spawned())
end
