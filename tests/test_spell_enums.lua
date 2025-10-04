package.path = table.concat({
    './?.lua',
    './?/init.lua',
    './?/?.lua',
}, ';') .. ';' .. package.path

-- The production code expects to be required as `EmuBot.modules.spell_enums`
-- from the MacroQuest Lua runtime. When running tests inside the repository
-- we shim that module name to the local filesystem layout.
package.preload['EmuBot.modules.spell_enums'] = function()
    return require('modules.spell_enums')
end

local SpellEnums = require('EmuBot.modules.spell_enums')

local function assert_equal(actual, expected, message)
    if actual ~= expected then
        error(string.format('%s\nExpected: %s\nActual: %s', message or 'Values are not equal', tostring(expected), tostring(actual)), 2)
    end
end

local function assert_truthy(value, message)
    if not value then
        error(message or 'Assertion failed: value was not truthy', 2)
    end
end

local function assert_error(fn, expected_message)
    local ok, err = pcall(fn)
    if ok then
        error('Expected function to error, but it succeeded', 2)
    end
    if expected_message and not tostring(err):find(expected_message, 1, true) then
        error(string.format('Expected error message to contain %q but got %s', expected_message, tostring(err)), 2)
    end
end

print('[tests] spell_enums: verifying exported enum metadata')
assert_truthy(SpellEnums.SpellTypes, 'SpellEnums.SpellTypes not defined')
assert_truthy(SpellEnums.SpellTypes.Nuke, 'SpellEnums.SpellTypes.Nuke not defined')
assert_equal(SpellEnums.SpellTypes.Nuke.canonical, 'Nuke', 'Canonical name mismatch for Nuke')
assert_equal(SpellEnums.SpellTypes.Nuke.short, 'nuke', 'Short name mismatch for Nuke')

print('[tests] spell_enums: resolving identifiers to short names')
assert_equal(SpellEnums.get_short_name('Nuke'), 'nuke', 'Failed to resolve canonical name')
assert_equal(SpellEnums.get_short_name('nuke'), 'nuke', 'Failed to resolve lower-case short name')
assert_equal(SpellEnums.get_short_name('NUKE'), 'nuke', 'Failed to resolve mixed case short name')
assert_equal(SpellEnums.get_short_name(SpellEnums.SpellTypes.Nuke), 'nuke', 'Failed to resolve enum table value')
assert_equal(SpellEnums.get_short_name({short = 'nuke'}), 'nuke', 'Failed to resolve table with short field')
assert_equal(SpellEnums.get_short_name(42), 42, 'Numeric identifiers should pass through')

local nil_short, nil_err = SpellEnums.get_short_name(nil)
assert_equal(nil_short, nil, 'Nil value should return nil short name')
assert_truthy(nil_err:find('nil', 1, true), 'Expected nil error message to mention nil')

local bad_short, bad_err = SpellEnums.get_short_name({})
assert_equal(bad_short, nil, 'Unexpected short name for invalid table input')
assert_truthy(bad_err:find('unrecognized spell type', 1, true), 'Expected error to mention unrecognized spell type')

print('[tests] spell_enums: normalizing spell max thresholds')
local normalized = SpellEnums.normalize_spell_max_thresholds({
    [SpellEnums.SpellTypes.Nuke] = '5',
    HoTHeals = 12,
})
assert_equal(normalized.nuke, 5, 'Failed to normalize numeric string value')
assert_equal(normalized.hotheals, 12, 'Failed to normalize canonical key')

local empty_normalized = SpellEnums.normalize_spell_max_thresholds(nil)
assert_truthy(type(empty_normalized) == 'table', 'Expected empty table result for nil input')
assert_equal(next(empty_normalized), nil, 'Expected empty table for nil input')

assert_error(function()
    SpellEnums.normalize_spell_max_thresholds({ InvalidKey = 1 })
end, 'Invalid spell type key')

assert_error(function()
    SpellEnums.normalize_spell_max_thresholds({ [SpellEnums.SpellTypes.Nuke] = 'not-a-number' })
end, 'Threshold value for nuke')

print('[tests] spell_enums: all tests passed')
