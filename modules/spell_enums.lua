-- emubot/modules/spell_enums.lua
-- Helper utilities for working with bot spell type enumerations.

local SpellEnums = {}

-- Raw mapping of canonical BotSpellTypes names to the short names used by EQEmu
-- bot commands. The short names are derived from the upstream source in
-- zone/bot.cpp (see spell_type_short_names).
local _raw_spell_types = {
    ['AEDebuff'] = 'aedebuff',
    ['AEDispel'] = 'aedispel',
    ['AEDoT'] = 'aedot',
    ['AEFear'] = 'aefear',
    ['AEHateLine'] = 'aehateline',
    ['AELifetap'] = 'aelifetap',
    ['AELull'] = 'aelull',
    ['AEMez'] = 'aemez',
    ['AENukes'] = 'aenukes',
    ['AERains'] = 'aerains',
    ['AERoot'] = 'aeroot',
    ['AESlow'] = 'aeslow',
    ['AESnare'] = 'aesnare',
    ['AEStun'] = 'aestun',
    ['BindAffinity'] = 'bindaffinity',
    ['Buff'] = 'buff',
    ['Charm'] = 'charm',
    ['CompleteHeal'] = 'completeheal',
    ['Cure'] = 'cure',
    ['DOT'] = 'dot',
    ['DamageShields'] = 'damageshields',
    ['Debuff'] = 'debuff',
    ['Dispel'] = 'dispel',
    ['Escape'] = 'escape',
    ['FastHeals'] = 'fastheals',
    ['Fear'] = 'fear',
    ['GroupCompleteHeals'] = 'groupcompleteheals',
    ['GroupCures'] = 'groupcures',
    ['GroupHeals'] = 'groupheals',
    ['GroupHoTHeals'] = 'grouphotheals',
    ['HateLine'] = 'hateline',
    ['HateRedux'] = 'hateredux',
    ['HoTHeals'] = 'hotheals',
    ['Identify'] = 'identify',
    ['InCombatBuff'] = 'incombatbuff',
    ['InCombatBuffSong'] = 'incombatbuffsong',
    ['Invisibility'] = 'invisibility',
    ['Levitate'] = 'levitate',
    ['Lifetap'] = 'lifetap',
    ['Lull'] = 'lull',
    ['Mez'] = 'mez',
    ['MovementSpeed'] = 'movementspeed',
    ['Nuke'] = 'nuke',
    ['OutOfCombatBuffSong'] = 'outofcombatbuffsong',
    ['PBAENuke'] = 'pbaenuke',
    ['Pet'] = 'pet',
    ['PetBuffs'] = 'petbuffs',
    ['PetCompleteHeals'] = 'petcompleteheals',
    ['PetCures'] = 'petcures',
    ['PetDamageShields'] = 'petdamageshields',
    ['PetFastHeals'] = 'petfastheals',
    ['PetHoTHeals'] = 'pethotheals',
    ['PetRegularHeals'] = 'petregularheals',
    ['PetResistBuffs'] = 'petresistbuffs',
    ['PetVeryFastHeals'] = 'petveryfastheals',
    ['PreCombatBuff'] = 'precombatbuff',
    ['PreCombatBuffSong'] = 'precombatbuffsong',
    ['RegularHeal'] = 'regularheal',
    ['ResistBuffs'] = 'resistbuffs',
    ['Resurrect'] = 'resurrect',
    ['Root'] = 'root',
    ['Rune'] = 'rune',
    ['SendHome'] = 'sendhome',
    ['Size'] = 'size',
    ['Slow'] = 'slow',
    ['Snare'] = 'snare',
    ['Stun'] = 'stun',
    ['Succor'] = 'succor',
    ['SummonCorpse'] = 'summoncorpse',
    ['Teleport'] = 'teleport',
    ['VeryFastHeals'] = 'veryfastheals',
    ['WaterBreathing'] = 'waterbreathing',
}

local _by_canonical = {}
local _by_short = {}

local function create_enum(canonical, short)
    local enum = {}
    enum.canonical = canonical
    enum.short = short
    return setmetatable(enum, {
        __index = enum,
        __tostring = function()
            return short
        end,
    })
end

SpellEnums.SpellTypes = {}

for canonical, short in pairs(_raw_spell_types) do
    local enum = create_enum(canonical, short)
    SpellEnums.SpellTypes[canonical] = enum
    _by_canonical[canonical:lower()] = enum
    _by_short[short] = enum
end

---Resolve a spell type identifier into its short name.
---@param value any
---@return string|nil shortName
---@return string|nil err
function SpellEnums.get_short_name(value)
    if value == nil then
        return nil, 'spell type value was nil'
    end

    if type(value) == 'table' and value.short and _by_short[value.short] then
        return value.short
    end

    if type(value) == 'string' then
        local lowered = value:lower()
        if _by_short[lowered] then
            return _by_short[lowered].short
        end
        if _by_canonical[lowered] then
            return _by_canonical[lowered].short
        end
    end

    if type(value) == 'number' then
        -- Passing numeric IDs directly is still supported by bot commands; allow them.
        return value
    end

    return nil, string.format('unrecognized spell type: %s', tostring(value))
end

---Normalize a table of spell max thresholds by converting keys into short names.
---@param threshold_map table
---@return table normalized
function SpellEnums.normalize_spell_max_thresholds(threshold_map)
    local normalized = {}
    if type(threshold_map) ~= 'table' then
        return normalized
    end

    for key, value in pairs(threshold_map) do
        local short, err = SpellEnums.get_short_name(key)
        if not short then
            error(string.format('Invalid spell type key (%s): %s', tostring(key), err or 'unknown error'))
        end

        local numeric_value = tonumber(value)
        if not numeric_value then
            error(string.format('Threshold value for %s must be numeric, received %s', tostring(short), tostring(value)))
        end

        normalized[short] = numeric_value
    end

    return normalized
end

---Helper to call a bot's spellmaxthresholds method using enum values.
---@param bot table|userdata
---@param spell_type any
---@param threshold any
---@param condition any
---@return any
function SpellEnums.set_spell_max_threshold(bot, spell_type, threshold, condition)
    if bot == nil then
        error('SpellEnums.set_spell_max_threshold: bot instance was nil')
    end

    local spellmaxthresholds = bot.spellmaxthresholds
    if type(spellmaxthresholds) ~= 'function' then
        error('SpellEnums.set_spell_max_threshold: provided bot does not implement spellmaxthresholds')
    end

    local short, err = SpellEnums.get_short_name(spell_type)
    if not short then
        error(string.format('Invalid spell type key (%s): %s', tostring(spell_type), err or 'unknown error'))
    end

    local numeric_value = tonumber(threshold)
    if not numeric_value then
        error(string.format('Threshold value for %s must be numeric, received %s', tostring(short), tostring(threshold)))
    end

    return bot:spellmaxthresholds(short, numeric_value, condition)
end

return SpellEnums

