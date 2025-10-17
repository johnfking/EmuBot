package.loaded['mq'] = nil
package.preload['mq'] = function()
    error('mq module should not load during unit tests')
end

local db = require('modules.db')

local TEST_DB_DIR = 'spec/tmp'
local TEST_DB_PATH = TEST_DB_DIR .. '/test_emubot.sqlite'

local function cleanup_db()
    os.remove(TEST_DB_PATH)
end

local function ensure_dir()
    os.execute(string.format('mkdir -p %q', TEST_DB_DIR))
end

describe('modules.db persistence', function()
    before_each(function()
        ensure_dir()
        cleanup_db()
        db.close()
        db.set_database_path(TEST_DB_PATH)
        db.set_owner_name('TestOwner')
        local ok, err = db.init()
        assert.is_true(ok, err)
    end)

    after_each(function()
        db.close()
        cleanup_db()
    end)

    it('persists equipped items without MacroQuest', function()
        local bot_data = {
            equipped = {
                {
                    name = 'Sword of Testing',
                    slotid = 13,
                    slotname = 'Primary',
                    itemID = 1234,
                    icon = 42,
                    ac = 10,
                    hp = 20,
                    mana = 30,
                    damage = 15,
                    delay = 25,
                    qty = 1,
                    nodrop = 1,
                },
            },
        }

        local meta = {
            Name = 'TestBot',
            Level = 60,
            Class = 'Warrior',
            Race = 'Human',
            Gender = 'Male',
        }

        local ok, err = db.save_bot_inventory('TestBot', bot_data, meta)
        assert.is_true(ok, err)

        local loaded = db.load_all()
        assert.is_table(loaded['TestBot'])
        local equipped = loaded['TestBot'].equipped
        assert.is_table(equipped)
        assert.are.equal(1, #equipped)
        assert.are.equal('Sword of Testing', equipped[1].name)
        assert.are.equal(1234, equipped[1].itemID)
        assert.are.equal(15, equipped[1].damage)
        assert.are.equal(25, equipped[1].delay)
    end)
end)
