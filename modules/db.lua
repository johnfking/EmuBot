-- emubot/modules/db.lua
-- SQLite persistence for EmuBot bot data (unique DB per server)

local mq = require('mq')
local ok_sqlite, sqlite3 = pcall(require, 'lsqlite3')

local M = {}
M._db = nil
M._db_path = nil

local function printf(fmt, ...)
    if mq.printf then mq.printf(fmt, ...) else print(string.format(fmt, ...)) end
end

local function normalizePathSeparators(path)
    return path and path:gsub('\\\\', '/') or nil
end

local function trimTrailingSlash(path)
    if not path then return nil end
    return path:gsub('/+$', '')
end

local function detectResourcesDir()
    -- Try MacroQuest.Resources path first
    if mq and mq.TLO and mq.TLO.MacroQuest and mq.TLO.MacroQuest.Path then
        local ok, result = pcall(function()
            local tlo = mq.TLO.MacroQuest.Path('Resources')
            if tlo and tlo() and tlo() ~= '' then return tlo() end
            return nil
        end)
        if ok and result and result ~= '' then
            local normalized = trimTrailingSlash(normalizePathSeparators(tostring(result)))
            if normalized and normalized ~= '' then return normalized end
        end
    end
    -- Fallback: derive from luaDir
    if mq and mq.luaDir then
        local ok, result = pcall(function()
            if type(mq.luaDir) == 'function' then return mq.luaDir() end
            return mq.luaDir
        end)
        if ok and result and result ~= '' then
            local normalized = trimTrailingSlash(normalizePathSeparators(tostring(result)))
            if normalized then
                local root = normalized:match('^(.*)/lua$')
                if root and root ~= '' then
                    return root .. '/Resources'
                end
            end
        end
    end
    return nil
end

local function get_server_name()
    if mq and mq.TLO and mq.TLO.EverQuest and mq.TLO.EverQuest.Server then
        local ok, server = pcall(function() return mq.TLO.EverQuest.Server() end)
        if ok and server and server ~= '' then return tostring(server) end
    end
    return 'default'
end

local function ensure_parent_dir_exists(path)
    -- Best effort: Lua standard libs don’t have mkdir; MacroQuest usually ensures Resources exists.
    -- We’ll no-op here assuming Resources exists.
    return true
end

local function open_db()
    if not ok_sqlite then
        printf('[EmuBot][DB] ERROR: lsqlite3 module not found. Please install lsqlite3 for Lua.')
        return false, 'lsqlite3 not available'
    end
    local resources = detectResourcesDir() or '.'
    local server = get_server_name()
    local filename = string.format('emubot_%s.sqlite', server:gsub('[^%w%-_%.]', '_'))
    local db_path = resources .. '/' .. filename
    ensure_parent_dir_exists(db_path)

    local db = sqlite3.open(db_path)
    if not db then
        return false, 'failed to open sqlite database'
    end

    -- Pragmas for better durability/performance
    db:exec('PRAGMA journal_mode=WAL;')
    db:exec('PRAGMA synchronous=NORMAL;')

    M._db = db
    M._db_path = db_path
    return true
end

local function exec_ddl()
    local ddl = [[
    CREATE TABLE IF NOT EXISTS bots (
        name TEXT PRIMARY KEY,
        level INTEGER,
        class TEXT,
        race TEXT,
        gender TEXT,
        last_updated INTEGER
    );

    CREATE TABLE IF NOT EXISTS items (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        bot_name TEXT NOT NULL,
        location TEXT NOT NULL,
        slotid INTEGER,
        slotname TEXT,
        name TEXT,
        itemID INTEGER,
        icon INTEGER,
        ac INTEGER,
        hp INTEGER,
        mana INTEGER,
        itemlink TEXT,
        rawline TEXT,
        qty INTEGER,
        nodrop INTEGER,
        stackSize INTEGER,
        charges INTEGER,
        aug1Name TEXT, aug1link TEXT, aug1Icon INTEGER,
        aug2Name TEXT, aug2link TEXT, aug2Icon INTEGER,
        aug3Name TEXT, aug3link TEXT, aug3Icon INTEGER,
        aug4Name TEXT, aug4link TEXT, aug4Icon INTEGER,
        aug5Name TEXT, aug5link TEXT, aug5Icon INTEGER,
        aug6Name TEXT, aug6link TEXT, aug6Icon INTEGER
    );

    CREATE INDEX IF NOT EXISTS idx_items_bot ON items(bot_name);
    CREATE INDEX IF NOT EXISTS idx_items_bot_loc ON items(bot_name, location);
    CREATE INDEX IF NOT EXISTS idx_items_slot ON items(slotid);
    ]]
    return M._db:exec(ddl) == sqlite3.OK
end

function M.init()
    local ok, err = open_db()
    if not ok then return false, err end
    local okddl = exec_ddl()
    if not okddl then return false, 'failed to create schema' end
    printf('[EmuBot][DB] Using %s', tostring(M._db_path))
    return true
end

local function upsert_bot(botName, meta)
    local stmt = M._db:prepare([[INSERT INTO bots(name, level, class, race, gender, last_updated)
        VALUES(?,?,?,?,?, strftime('%s','now'))
        ON CONFLICT(name) DO UPDATE SET
            level=excluded.level,
            class=excluded.class,
            race=excluded.race,
            gender=excluded.gender,
            last_updated=strftime('%s','now')
    ]])
    if not stmt then return false end
    stmt:bind_values(
        botName,
        meta and meta.Level or nil,
        meta and meta.Class or nil,
        meta and meta.Race or nil,
        meta and meta.Gender or nil
    )
    local rc = stmt:step()
    stmt:finalize()
    return rc == sqlite3.DONE
end

local function last_error()
    if M._db and M._db.errmsg then
        return M._db:errmsg()
    end
    return 'unknown sqlite error'
end

local function insert_item(botName, location, it)
    local stmt = M._db:prepare([[INSERT INTO items(
        bot_name, location, slotid, slotname, name, itemID, icon, ac, hp, mana,
        itemlink, rawline, qty, nodrop, stackSize, charges,
        aug1Name, aug1link, aug1Icon,
        aug2Name, aug2link, aug2Icon,
        aug3Name, aug3link, aug3Icon,
        aug4Name, aug4link, aug4Icon,
        aug5Name, aug5link, aug5Icon,
        aug6Name, aug6link, aug6Icon
    ) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)]])
    if not stmt then return false, 'prepare failed' end
    stmt:bind_values(
        botName, location,
        tonumber(it.slotid), it.slotname, it.name, tonumber(it.itemID), tonumber(it.icon),
        tonumber(it.ac), tonumber(it.hp), tonumber(it.mana),
        it.itemlink, it.rawline, tonumber(it.qty), tonumber(it.nodrop), tonumber(it.stackSize), tonumber(it.charges),
        it.aug1Name, it.aug1link, tonumber(it.aug1Icon),
        it.aug2Name, it.aug2link, tonumber(it.aug2Icon),
        it.aug3Name, it.aug3link, tonumber(it.aug3Icon),
        it.aug4Name, it.aug4link, tonumber(it.aug4Icon),
        it.aug5Name, it.aug5link, tonumber(it.aug5Icon),
        it.aug6Name, it.aug6link, tonumber(it.aug6Icon)
    )
    local rc = stmt:step()
    local ok = (rc == sqlite3.DONE)
    if not ok then
        local err = last_error()
        stmt:finalize()
        return false, err
    end
    stmt:finalize()
    return true
end

function M.save_bot_inventory(botName, data, meta)
    if not M._db then return false, 'db not initialized' end
    if not botName or not data then return false, 'bad args' end
    M._db:exec('BEGIN;')
    local ok1 = upsert_bot(botName, meta or {})
    if not ok1 then M._db:exec('ROLLBACK;'); return false, 'upsert bot failed' end

    -- Replace Equipped items for this bot
    local del = M._db:prepare('DELETE FROM items WHERE bot_name=? AND location=?')
    del:bind_values(botName, 'Equipped')
    del:step()
    del:finalize()

for _, it in ipairs((data.equipped) or {}) do
        local ok, ierr = insert_item(botName, 'Equipped', it)
        if not ok then M._db:exec('ROLLBACK;'); return false, 'insert item failed: ' .. tostring(ierr) end
    end

    -- Future: bags/bank persistence can be added similarly

    M._db:exec('COMMIT;')
    return true
end

local function collect_rows(query, bind)
    local t = {}
    local stmt = M._db:prepare(query)
    if not stmt then return t end
    if bind then bind(stmt) end
    while true do
        local rc = stmt:step()
        if rc == sqlite3.ROW then
            local row = {}
            local n = stmt:columns()
            for i = 0, n - 1 do
                local name = stmt:get_name(i) or tostring(i)
                row[name] = stmt:get_value(i)
            end
            table.insert(t, row)
        elseif rc == sqlite3.DONE then
            break
        else
            break
        end
    end
    stmt:finalize()
    return t
end

function M.load_all()
    if not M._db then return {} end
    local bots = collect_rows('SELECT name, level, class, race, gender FROM bots', nil)
    local result = {}
    for _, b in ipairs(bots) do
        result[b.name] = { name = b.name, equipped = {}, bags = {}, bank = {} }
        local items = collect_rows('SELECT * FROM items WHERE bot_name=? AND location=? ORDER BY slotid', function(s)
            s:bind_values(b.name, 'Equipped')
        end)
        for _, r in ipairs(items) do
            table.insert(result[b.name].equipped, {
                name = r.name, slotid = tonumber(r.slotid), slotname = r.slotname,
                itemlink = r.itemlink, rawline = r.rawline, itemID = tonumber(r.itemID), icon = tonumber(r.icon),
                ac = tonumber(r.ac), hp = tonumber(r.hp), mana = tonumber(r.mana), qty = tonumber(r.qty), nodrop = tonumber(r.nodrop),
                stackSize = tonumber(r.stackSize), charges = tonumber(r.charges),
                aug1Name = r.aug1Name, aug1link = r.aug1link, aug1Icon = tonumber(r.aug1Icon),
                aug2Name = r.aug2Name, aug2link = r.aug2link, aug2Icon = tonumber(r.aug2Icon),
                aug3Name = r.aug3Name, aug3link = r.aug3link, aug3Icon = tonumber(r.aug3Icon),
                aug4Name = r.aug4Name, aug4link = r.aug4link, aug4Icon = tonumber(r.aug4Icon),
                aug5Name = r.aug5Name, aug5link = r.aug5link, aug5Icon = tonumber(r.aug5Icon),
                aug6Name = r.aug6Name, aug6link = r.aug6link, aug6Icon = tonumber(r.aug6Icon),
            })
        end
    end
    return result
end

return M
