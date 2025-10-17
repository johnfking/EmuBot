-- emubot/modules/db.lua
-- SQLite persistence for EmuBot bot data (unique DB per server)

local mq = require('mq')

-- Lightweight logger for early bootstrap (before module debug is set)
local function _pm_log(fmt, ...)
    -- Disabled by default; flip to true for troubleshooting
    local PM_LOG_ENABLED = false
    if not PM_LOG_ENABLED then return end
    local msg = string.format(fmt, ...)
    if mq and mq.printf then mq.printf('%s', msg) else print(msg) end
end

-- Ensure Lua can find packages installed into <luaDir>/modules
local function _append_unique(list, suffix)
    if not list or not suffix or suffix == '' then return list end
    if not string.find(list, suffix, 1, true) then
        if list == '' then return suffix end
        return list .. ';' .. suffix
    end
    return list
end

local function _ensure_package_paths()
    local lua_dir = nil
    local ok, res = pcall(function()
        if type(mq.luaDir) == 'function' then return mq.luaDir() end
        return mq.luaDir
    end)
    if ok and res and res ~= '' then lua_dir = tostring(res) end
    if not lua_dir then return end
    package.path  = _append_unique(package.path  or '', lua_dir .. '/?.lua')
    package.path  = _append_unique(package.path  or '', lua_dir .. '/?/init.lua')
    package.path  = _append_unique(package.path  or '', lua_dir .. '/modules/?.lua')
    package.cpath = _append_unique(package.cpath or '', lua_dir .. '/modules/?.dll')
end

_ensure_package_paths()
local ok_sqlite, sqlite3 = pcall(require, 'lsqlite3')

local M = {}
M._db = nil
M._db_path = nil
M._debug = false

-- Resolve current character (owner) name for scoping
local function get_owner_name()
    if mq and mq.TLO and mq.TLO.Me then
        local ok, name = pcall(function()
            if mq.TLO.Me.CleanName and mq.TLO.Me.CleanName() then return mq.TLO.Me.CleanName() end
            if mq.TLO.Me.Name and mq.TLO.Me.Name() then return mq.TLO.Me.Name() end
            return nil
        end)
        if ok and name and name ~= '' then return tostring(name) end
    end
    return 'unknown'
end

function M.set_debug(enabled)
    M._debug = not not enabled
    printf('[EmuBot][DB] Debug logging %s', M._debug and 'ENABLED' or 'DISABLED')
    if M._debug and M._db then
        -- Dump items schema for quick verification
        printf('[EmuBot][DB] DB Path: %s', tostring(M._db_path))
        printf('[EmuBot][DB] item_stats schema:')
        for row in M._db:nrows("PRAGMA table_info('item_stats');") do
            printf('  - %s (%s)', tostring(row.name), tostring(row.type))
        end
        printf('[EmuBot][DB] bot_items schema:')
        for row in M._db:nrows("PRAGMA table_info('bot_items');") do
            printf('  - %s (%s)', tostring(row.name), tostring(row.type))
        end
        printf('[EmuBot][DB] bots schema:')
        for row in M._db:nrows("PRAGMA table_info('bots');") do
            printf('  - %s (%s)', tostring(row.name), tostring(row.type))
        end
    end
end

local function dump_schema_if_debug()
    if not M._debug or not M._db then return end
    printf('[EmuBot][DB] DB Path: %s', tostring(M._db_path))
    printf('[EmuBot][DB] item_stats schema:')
    for row in M._db:nrows("PRAGMA table_info('item_stats');") do
        printf('  - %s (%s)', tostring(row.name), tostring(row.type))
    end
    printf('[EmuBot][DB] bot_items schema:')
    for row in M._db:nrows("PRAGMA table_info('bot_items');") do
        printf('  - %s (%s)', tostring(row.name), tostring(row.type))
    end
    printf('[EmuBot][DB] bots schema:')
    for row in M._db:nrows("PRAGMA table_info('bots');") do
        printf('  - %s (%s)', tostring(row.name), tostring(row.type))
    end
end

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

local function last_error()
    if M._db and M._db.errmsg then
        return M._db:errmsg()
    end
    return 'unknown sqlite error'
end

local function exec_ddl()
    local ddl = [[
    CREATE TABLE IF NOT EXISTS bots (
        name TEXT PRIMARY KEY,
        level INTEGER,
        class TEXT,
        race TEXT,
        gender TEXT,
        owner TEXT,
        last_updated INTEGER
    );

    CREATE TABLE IF NOT EXISTS item_stats (
        name TEXT PRIMARY KEY,
        itemID INTEGER,
        icon INTEGER,
        ac INTEGER,
        hp INTEGER,
        mana INTEGER,
        itemlink TEXT,
        rawline TEXT,
        qty INTEGER,
        stackSize INTEGER,
        charges INTEGER,
        nodrop INTEGER,
        aug1Name TEXT, aug1link TEXT, aug1Icon INTEGER,
        aug2Name TEXT, aug2link TEXT, aug2Icon INTEGER,
        aug3Name TEXT, aug3link TEXT, aug3Icon INTEGER,
        aug4Name TEXT, aug4link TEXT, aug4Icon INTEGER,
        aug5Name TEXT, aug5link TEXT, aug5Icon INTEGER,
        aug6Name TEXT, aug6link TEXT, aug6Icon INTEGER,
        damage INTEGER,
        delay INTEGER
    );

    CREATE TABLE IF NOT EXISTS bot_items (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        owner TEXT,
        bot_name TEXT NOT NULL,
        location TEXT NOT NULL,
        slotid INTEGER,
        slotname TEXT,
        item_name TEXT NOT NULL,
        FOREIGN KEY(item_name) REFERENCES item_stats(name)
    );

    CREATE INDEX IF NOT EXISTS idx_bot_items_bot ON bot_items(owner, bot_name, location);
    CREATE INDEX IF NOT EXISTS idx_bot_items_slot ON bot_items(slotid);
    CREATE INDEX IF NOT EXISTS idx_bot_items_item ON bot_items(item_name);
    CREATE INDEX IF NOT EXISTS idx_item_stats_itemid ON item_stats(itemID);

    CREATE TABLE IF NOT EXISTS bot_groups (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL UNIQUE,
        description TEXT,
        created_at INTEGER DEFAULT (strftime('%s','now')),
        updated_at INTEGER DEFAULT (strftime('%s','now'))
    );

    CREATE TABLE IF NOT EXISTS bot_group_members (
        group_id INTEGER NOT NULL,
        bot_name TEXT NOT NULL,
        added_at INTEGER DEFAULT (strftime('%s','now')),
        PRIMARY KEY (group_id, bot_name),
        FOREIGN KEY (group_id) REFERENCES bot_groups(id) ON DELETE CASCADE
    );

    CREATE INDEX IF NOT EXISTS idx_group_members_group ON bot_group_members(group_id);
    CREATE INDEX IF NOT EXISTS idx_group_members_bot ON bot_group_members(bot_name);
    ]]
    return M._db:exec(ddl) == sqlite3.OK
end

-- Lightweight migrations: ensure new columns exist on existing databases
local function column_exists(table_name, column_name)
    local exists = false
    for row in M._db:nrows(string.format("PRAGMA table_info('%s');", table_name)) do
        if tostring(row.name) == tostring(column_name) then
            exists = true
            break
        end
    end
    return exists
end

local function table_exists(table_name)
    local stmt = M._db:prepare("SELECT name FROM sqlite_master WHERE type='table' AND name=?")
    if not stmt then return false end
    stmt:bind_values(table_name)
    local rc = stmt:step()
    local exists = (rc == sqlite3.ROW)
    stmt:finalize()
    return exists
end

local function sanitize_item_name(name)
    if not name then return nil end
    local str = tostring(name)
    str = str:gsub('^%s+', ''):gsub('%s+$', '')
    if str == '' then return nil end
    return str
end

local upsert_item_stats_record
local insert_bot_item_record

local function run_migrations()
    -- Owner scoping support (bots)
    if not column_exists('bots', 'owner') then
        M._db:exec('ALTER TABLE bots ADD COLUMN owner TEXT;')
    end

    -- Legacy migration: move denormalized items into normalized tables
    local legacy_items_table = table_exists('items') and column_exists('items', 'bot_name')
    local already_normalized = table_exists('bot_items') and table_exists('item_stats')
    if legacy_items_table and already_normalized then
        -- Determine if migration already occurred (no bot_items rows yet)
        local has_bot_items = false
        for _ in M._db:nrows('SELECT 1 FROM bot_items LIMIT 1') do
            has_bot_items = true
            break
        end

        if not has_bot_items then
            for row in M._db:nrows('SELECT * FROM items') do
                local sanitized = sanitize_item_name(row.name)
                if sanitized and sanitized ~= '' then
                    local item_record = {
                        name = sanitized,
                        itemID = tonumber(row.itemID),
                        icon = tonumber(row.icon),
                        ac = tonumber(row.ac),
                        hp = tonumber(row.hp),
                        mana = tonumber(row.mana),
                        itemlink = row.itemlink,
                        rawline = row.rawline,
                        qty = tonumber(row.qty),
                        stackSize = tonumber(row.stackSize),
                        charges = tonumber(row.charges),
                        nodrop = tonumber(row.nodrop),
                        damage = tonumber(row.damage),
                        delay = tonumber(row.delay),
                        aug1Name = row.aug1Name, aug1link = row.aug1link, aug1Icon = tonumber(row.aug1Icon),
                        aug2Name = row.aug2Name, aug2link = row.aug2link, aug2Icon = tonumber(row.aug2Icon),
                        aug3Name = row.aug3Name, aug3link = row.aug3link, aug3Icon = tonumber(row.aug3Icon),
                        aug4Name = row.aug4Name, aug4link = row.aug4link, aug4Icon = tonumber(row.aug4Icon),
                        aug5Name = row.aug5Name, aug5link = row.aug5link, aug5Icon = tonumber(row.aug5Icon),
                        aug6Name = row.aug6Name, aug6link = row.aug6link, aug6Icon = tonumber(row.aug6Icon),
                    }
                    upsert_item_stats_record(item_record)

                    insert_bot_item_record({
                        owner = row.owner,
                        bot_name = row.bot_name,
                        location = row.location,
                        slotid = tonumber(row.slotid),
                        slotname = row.slotname,
                        item_name = sanitized,
                    })
                end
            end

            -- Preserve legacy data but mark table as unused
            local renamed, err = pcall(function()
                M._db:exec('ALTER TABLE items RENAME TO items_legacy;')
            end)
            if not renamed and M._debug then
                printf('[EmuBot][DB][migrate] Failed to rename legacy items table: %s', tostring(err))
            end
        end
    end

    -- Ensure indexes exist for normalized schema
    M._db:exec('CREATE INDEX IF NOT EXISTS idx_bot_items_bot ON bot_items(owner, bot_name, location);')
    M._db:exec('CREATE INDEX IF NOT EXISTS idx_bot_items_slot ON bot_items(slotid);')
    M._db:exec('CREATE INDEX IF NOT EXISTS idx_bot_items_item ON bot_items(item_name);')
    M._db:exec('CREATE INDEX IF NOT EXISTS idx_item_stats_itemid ON item_stats(itemID);')
end

upsert_item_stats_record = function(item)
    if not item or not item.name or item.name == '' then return false, 'item name required' end
    local stmt = M._db:prepare([[INSERT INTO item_stats(
        name, itemID, icon, ac, hp, mana, itemlink, rawline, qty, stackSize, charges, nodrop,
        aug1Name, aug1link, aug1Icon,
        aug2Name, aug2link, aug2Icon,
        aug3Name, aug3link, aug3Icon,
        aug4Name, aug4link, aug4Icon,
        aug5Name, aug5link, aug5Icon,
        aug6Name, aug6link, aug6Icon,
        damage, delay
    ) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
    ON CONFLICT(name) DO UPDATE SET
        itemID = COALESCE(excluded.itemID, item_stats.itemID),
        icon = COALESCE(excluded.icon, item_stats.icon),
        ac = COALESCE(excluded.ac, item_stats.ac),
        hp = COALESCE(excluded.hp, item_stats.hp),
        mana = COALESCE(excluded.mana, item_stats.mana),
        itemlink = COALESCE(excluded.itemlink, item_stats.itemlink),
        rawline = COALESCE(excluded.rawline, item_stats.rawline),
        qty = COALESCE(excluded.qty, item_stats.qty),
        stackSize = COALESCE(excluded.stackSize, item_stats.stackSize),
        charges = COALESCE(excluded.charges, item_stats.charges),
        nodrop = COALESCE(excluded.nodrop, item_stats.nodrop),
        aug1Name = COALESCE(excluded.aug1Name, item_stats.aug1Name),
        aug1link = COALESCE(excluded.aug1link, item_stats.aug1link),
        aug1Icon = COALESCE(excluded.aug1Icon, item_stats.aug1Icon),
        aug2Name = COALESCE(excluded.aug2Name, item_stats.aug2Name),
        aug2link = COALESCE(excluded.aug2link, item_stats.aug2link),
        aug2Icon = COALESCE(excluded.aug2Icon, item_stats.aug2Icon),
        aug3Name = COALESCE(excluded.aug3Name, item_stats.aug3Name),
        aug3link = COALESCE(excluded.aug3link, item_stats.aug3link),
        aug3Icon = COALESCE(excluded.aug3Icon, item_stats.aug3Icon),
        aug4Name = COALESCE(excluded.aug4Name, item_stats.aug4Name),
        aug4link = COALESCE(excluded.aug4link, item_stats.aug4link),
        aug4Icon = COALESCE(excluded.aug4Icon, item_stats.aug4Icon),
        aug5Name = COALESCE(excluded.aug5Name, item_stats.aug5Name),
        aug5link = COALESCE(excluded.aug5link, item_stats.aug5link),
        aug5Icon = COALESCE(excluded.aug5Icon, item_stats.aug5Icon),
        aug6Name = COALESCE(excluded.aug6Name, item_stats.aug6Name),
        aug6link = COALESCE(excluded.aug6link, item_stats.aug6link),
        aug6Icon = COALESCE(excluded.aug6Icon, item_stats.aug6Icon),
        damage = COALESCE(excluded.damage, item_stats.damage),
        delay = COALESCE(excluded.delay, item_stats.delay)
    )]])
    if not stmt then return false, last_error() end
    stmt:bind_values(
        item.name,
        tonumber(item.itemID), tonumber(item.icon), tonumber(item.ac), tonumber(item.hp), tonumber(item.mana),
        item.itemlink, item.rawline, tonumber(item.qty), tonumber(item.stackSize), tonumber(item.charges), tonumber(item.nodrop),
        item.aug1Name, item.aug1link, tonumber(item.aug1Icon),
        item.aug2Name, item.aug2link, tonumber(item.aug2Icon),
        item.aug3Name, item.aug3link, tonumber(item.aug3Icon),
        item.aug4Name, item.aug4link, tonumber(item.aug4Icon),
        item.aug5Name, item.aug5link, tonumber(item.aug5Icon),
        item.aug6Name, item.aug6link, tonumber(item.aug6Icon),
        tonumber(item.damage), tonumber(item.delay)
    )
    local rc = stmt:step()
    local ok = (rc == sqlite3.DONE)
    local err = not ok and last_error() or nil
    stmt:finalize()
    if not ok then return false, err end
    return true
end

insert_bot_item_record = function(entry)
    if not entry or not entry.bot_name or not entry.location or not entry.item_name or entry.item_name == '' then
        return false, 'invalid bot item entry'
    end
    local stmt = M._db:prepare([[INSERT INTO bot_items(owner, bot_name, location, slotid, slotname, item_name)
        VALUES(?,?,?,?,?,?)]])
    if not stmt then return false, last_error() end
    stmt:bind_values(
        entry.owner,
        entry.bot_name,
        entry.location,
        tonumber(entry.slotid),
        entry.slotname,
        entry.item_name
    )
    local rc = stmt:step()
    local ok = (rc == sqlite3.DONE)
    local err = not ok and last_error() or nil
    stmt:finalize()
    if not ok then return false, err end
    return true
end

function M.init()
    -- Ensure sqlite dependency at runtime (not during module import)
    if not ok_sqlite then
        _pm_log('[EmuBot][DB] lsqlite3 not found. Attempting PackageMan install (runtime)...')
        local ok_pm, PackageMan = pcall(require, 'mq.PackageMan')
        if not ok_pm then
            ok_pm, PackageMan = pcall(require, 'mq/PackageMan')
        end
        if ok_pm and PackageMan and type(PackageMan.Require) == 'function' then
            local ok_install, perr = pcall(function()
                return PackageMan.Require('lsqlite3')
            end)
            if ok_install then
                _pm_log('[EmuBot][DB] PackageMan.Require("lsqlite3") completed.')
            else
                _pm_log('[EmuBot][DB] PackageMan.Require("lsqlite3") failed: %s', tostring(perr))
            end
            _ensure_package_paths()
            -- Diagnostics
            local lua_dir = nil
            local ok_ld, res_ld = pcall(function()
                if type(mq.luaDir) == 'function' then return mq.luaDir() end
                return mq.luaDir
            end)
            if ok_ld and res_ld and res_ld ~= '' then lua_dir = tostring(res_ld) end
            if lua_dir then
                _pm_log('[EmuBot][DB] luaDir: %s', lua_dir)
                local candidate = lua_dir .. '/modules/lsqlite3.dll'
                local f = io.open(candidate, 'rb')
                if f then f:close(); _pm_log('[EmuBot][DB] Found candidate: %s', candidate) else _pm_log('[EmuBot][DB] Candidate missing: %s', candidate) end
            end
            _pm_log('[EmuBot][DB] package.cpath: %s', tostring(package.cpath))
            _pm_log('[EmuBot][DB] package.path: %s', tostring(package.path))
            ok_sqlite, sqlite3 = pcall(require, 'lsqlite3')
            if ok_sqlite then
                _pm_log('[EmuBot][DB] Successfully loaded lsqlite3 after install.')
            else
                _pm_log('[EmuBot][DB] Still failed to load lsqlite3 after install.')
            end
        else
            _pm_log('[EmuBot][DB] PackageMan not available or missing Require().')
        end
    end

    if not ok_sqlite then
        return false, 'lsqlite3 not available'
    end

    local ok, err = open_db()
    if not ok then return false, err end
    local okddl = exec_ddl()
    if not okddl then return false, 'failed to create schema' end
    -- Ensure schema migrations for existing DBs
    run_migrations()
    dump_schema_if_debug()
    printf('[EmuBot][DB] Using %s', tostring(M._db_path))
    return true
end

-- Expose a manual migration trigger for troubleshooting
function M.migrate()
    if not M._db then
        local ok, err = open_db()
        if not ok then return false, err end
    end
    local okddl = exec_ddl()
    if not okddl then return false, 'failed to create schema' end
    run_migrations()
    dump_schema_if_debug()
    return true
end

local function upsert_bot(botName, meta)
    local owner = get_owner_name()
    local stmt = M._db:prepare([[INSERT INTO bots(name, level, class, race, gender, owner, last_updated)
        VALUES(?,?,?,?,?,?, strftime('%s','now'))
        ON CONFLICT(name) DO UPDATE SET
            level=excluded.level,
            class=excluded.class,
            race=excluded.race,
            gender=excluded.gender,
            owner=excluded.owner,
            last_updated=strftime('%s','now')
    ]])
    if not stmt then
        -- Retry after running migrations in case owner column is missing
        run_migrations()
        stmt = M._db:prepare([[INSERT INTO bots(name, level, class, race, gender, owner, last_updated)
        VALUES(?,?,?,?,?,?, strftime('%s','now'))
        ON CONFLICT(name) DO UPDATE SET
            level=excluded.level,
            class=excluded.class,
            race=excluded.race,
            gender=excluded.gender,
            owner=excluded.owner,
            last_updated=strftime('%s','now')
    ]])
    end
    if not stmt then return false, last_error() end
    stmt:bind_values(
        botName,
        meta and meta.Level or nil,
        meta and meta.Class or nil,
        meta and meta.Race or nil,
        meta and meta.Gender or nil,
        owner
    )
    local rc = stmt:step()
    local ok = (rc == sqlite3.DONE)
    local err = not ok and last_error() or nil
    stmt:finalize()
    if not ok then return false, err end
    return true
end

local function insert_item(botName, location, it)
    if not it then return true end
    local sanitizedName = sanitize_item_name(it.name)
    if not sanitizedName then return true end
    if M._debug then
        printf('[EmuBot][DB][insert] bot=%s loc=%s slot=%s name="%s" itemID=%s ac=%s hp=%s mana=%s dmg=%s dly=%s linkLen=%s rawLen=%s',
            tostring(botName), tostring(location), tostring(it.slotid), tostring(it.name or ''), tostring(it.itemID or 'nil'),
            tostring(it.ac or 'nil'), tostring(it.hp or 'nil'), tostring(it.mana or 'nil'), tostring(it.damage or 'nil'), tostring(it.delay or 'nil'),
            tostring(it.itemlink and #tostring(it.itemlink) or 0), tostring(it.rawline and #tostring(it.rawline) or 0))
    end

    local stats_item = {
        name = sanitizedName,
        itemID = it.itemID,
        icon = it.icon,
        ac = it.ac,
        hp = it.hp,
        mana = it.mana,
        itemlink = it.itemlink,
        rawline = it.rawline,
        qty = it.qty,
        stackSize = it.stackSize,
        charges = it.charges,
        nodrop = it.nodrop,
        damage = it.damage,
        delay = it.delay,
        aug1Name = it.aug1Name, aug1link = it.aug1link, aug1Icon = it.aug1Icon,
        aug2Name = it.aug2Name, aug2link = it.aug2link, aug2Icon = it.aug2Icon,
        aug3Name = it.aug3Name, aug3link = it.aug3link, aug3Icon = it.aug3Icon,
        aug4Name = it.aug4Name, aug4link = it.aug4link, aug4Icon = it.aug4Icon,
        aug5Name = it.aug5Name, aug5link = it.aug5link, aug5Icon = it.aug5Icon,
        aug6Name = it.aug6Name, aug6link = it.aug6link, aug6Icon = it.aug6Icon,
    }

    local ok_stats, err_stats = upsert_item_stats_record(stats_item)
    if not ok_stats then
        if M._debug then printf('[EmuBot][DB][insert] upsert stats failed: %s', tostring(err_stats)) end
        return false, err_stats
    end

    local owner = get_owner_name()
    local ok_link, err_link = insert_bot_item_record({
        owner = owner,
        bot_name = botName,
        location = location,
        slotid = tonumber(it.slotid),
        slotname = it.slotname,
        item_name = sanitizedName,
    })

    if not ok_link then
        if M._debug then printf('[EmuBot][DB][insert] link insert failed: %s', tostring(err_link)) end
        return false, err_link
    end

    if M._debug then printf('[EmuBot][DB][insert] OK for %s:%s slot %s', tostring(botName), tostring(location), tostring(it.slotid)) end
    return true
end

function M.save_bot_inventory(botName, data, meta)
    if not M._db then return false, 'db not initialized' end
    if not botName or not data then return false, 'bad args' end
    if M._debug then
        local eqc = (data.equipped and #data.equipped) or 0
        printf('[EmuBot][DB][save] bot=%s equipped=%d', tostring(botName), eqc)
    end
    M._db:exec('BEGIN;')
    local ok1, e1 = upsert_bot(botName, meta or {})
    if not ok1 then M._db:exec('ROLLBACK;'); return false, 'upsert bot failed: ' .. tostring(e1) end

    -- Replace Equipped items for this bot (scoped by owner)
    local owner = get_owner_name()
    local del = M._db:prepare('DELETE FROM bot_items WHERE owner=? AND bot_name=? AND location=?')
    del:bind_values(owner, botName, 'Equipped')
    del:step()
    del:finalize()

for _, it in ipairs((data.equipped) or {}) do
        local ok, ierr = insert_item(botName, 'Equipped', it)
        if not ok then M._db:exec('ROLLBACK;'); return false, 'insert item failed: ' .. tostring(ierr) end
    end

    -- Future: bags/bank persistence can be added similarly

    M._db:exec('COMMIT;')
    if M._debug then printf('[EmuBot][DB][save] COMMIT bot=%s', tostring(botName)) end
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
    local owner = get_owner_name()
    local bots = collect_rows('SELECT name, level, class, race, gender FROM bots WHERE owner = ?', function(s)
        s:bind_values(owner)
    end)
    local result = {}
    for _, b in ipairs(bots) do
        result[b.name] = { name = b.name, equipped = {}, bags = {}, bank = {} }
        local items = collect_rows([[SELECT
            bi.slotid,
            bi.slotname,
            bi.item_name,
            stats.name AS stats_name,
            stats.itemID,
            stats.icon,
            stats.ac,
            stats.hp,
            stats.mana,
            stats.itemlink,
            stats.rawline,
            stats.qty,
            stats.stackSize,
            stats.charges,
            stats.nodrop,
            stats.aug1Name, stats.aug1link, stats.aug1Icon,
            stats.aug2Name, stats.aug2link, stats.aug2Icon,
            stats.aug3Name, stats.aug3link, stats.aug3Icon,
            stats.aug4Name, stats.aug4link, stats.aug4Icon,
            stats.aug5Name, stats.aug5link, stats.aug5Icon,
            stats.aug6Name, stats.aug6link, stats.aug6Icon,
            stats.damage,
            stats.delay
        FROM bot_items AS bi
        LEFT JOIN item_stats AS stats ON stats.name = bi.item_name
        WHERE bi.owner=? AND bi.bot_name=? AND bi.location=?
        ORDER BY bi.slotid]], function(s)
            s:bind_values(owner, b.name, 'Equipped')
        end)
        for _, r in ipairs(items) do
            table.insert(result[b.name].equipped, {
                name = r.item_name or r.stats_name,
                slotid = tonumber(r.slotid),
                slotname = r.slotname,
                itemlink = r.itemlink,
                rawline = r.rawline,
                itemID = tonumber(r.itemID),
                icon = tonumber(r.icon),
                ac = tonumber(r.ac) or 0,
                hp = tonumber(r.hp) or 0,
                mana = tonumber(r.mana) or 0,
                qty = tonumber(r.qty) or 0,
                nodrop = tonumber(r.nodrop) or 0,
                stackSize = tonumber(r.stackSize), charges = tonumber(r.charges),
                aug1Name = r.aug1Name, aug1link = r.aug1link, aug1Icon = tonumber(r.aug1Icon),
                aug2Name = r.aug2Name, aug2link = r.aug2link, aug2Icon = tonumber(r.aug2Icon),
                aug3Name = r.aug3Name, aug3link = r.aug3link, aug3Icon = tonumber(r.aug3Icon),
                aug4Name = r.aug4Name, aug4link = r.aug4link, aug4Icon = tonumber(r.aug4Icon),
                aug5Name = r.aug5Name, aug5link = r.aug5link, aug5Icon = tonumber(r.aug5Icon),
                aug6Name = r.aug6Name, aug6link = r.aug6link, aug6Icon = tonumber(r.aug6Icon),
                damage = tonumber(r.damage) or 0, delay = tonumber(r.delay) or 0,
            })
        end
    end
    return result
end

-- Bot Group Management Functions

function M.create_group(name, description)
    if not M._db then return false, 'db not initialized' end
    if not name or name == '' then return false, 'group name required' end
    
    local stmt = M._db:prepare('INSERT INTO bot_groups (name, description) VALUES (?, ?)')
    if not stmt then return false, 'prepare failed' end
    
    stmt:bind_values(name, description or '')
    local rc = stmt:step()
    local ok = (rc == sqlite3.DONE)
    local groupId = nil
    
    if ok then
        groupId = M._db:last_insert_rowid()
    end
    
    local err = not ok and last_error() or nil
    stmt:finalize()
    
    if ok then
        return true, groupId
    else
        return false, err
    end
end

function M.delete_group(groupId)
    if not M._db then return false, 'db not initialized' end
    if not groupId then return false, 'group id required' end
    
    local stmt = M._db:prepare('DELETE FROM bot_groups WHERE id = ?')
    if not stmt then return false, 'prepare failed' end
    
    stmt:bind_values(groupId)
    local rc = stmt:step()
    local ok = (rc == sqlite3.DONE)
    
    stmt:finalize()
    return ok, not ok and last_error() or nil
end

function M.update_group(groupId, name, description)
    if not M._db then return false, 'db not initialized' end
    if not groupId or not name then return false, 'group id and name required' end
    
    local stmt = M._db:prepare('UPDATE bot_groups SET name = ?, description = ?, updated_at = strftime(\'%s\',\'now\') WHERE id = ?')
    if not stmt then return false, 'prepare failed' end
    
    stmt:bind_values(name, description or '', groupId)
    local rc = stmt:step()
    local ok = (rc == sqlite3.DONE)
    
    stmt:finalize()
    return ok, not ok and last_error() or nil
end

function M.get_all_groups()
    if not M._db then return {} end
    return collect_rows('SELECT id, name, description, created_at, updated_at FROM bot_groups ORDER BY name', nil)
end

function M.add_bot_to_group(groupId, botName)
    if not M._db then return false, 'db not initialized' end
    if not groupId or not botName then return false, 'group id and bot name required' end
    
    local stmt = M._db:prepare('INSERT OR IGNORE INTO bot_group_members (group_id, bot_name) VALUES (?, ?)')
    if not stmt then return false, 'prepare failed' end
    
    stmt:bind_values(groupId, botName)
    local rc = stmt:step()
    local ok = (rc == sqlite3.DONE)
    
    stmt:finalize()
    return ok, not ok and last_error() or nil
end

function M.remove_bot_from_group(groupId, botName)
    if not M._db then return false, 'db not initialized' end
    if not groupId or not botName then return false, 'group id and bot name required' end
    
    local stmt = M._db:prepare('DELETE FROM bot_group_members WHERE group_id = ? AND bot_name = ?')
    if not stmt then return false, 'prepare failed' end
    
    stmt:bind_values(groupId, botName)
    local rc = stmt:step()
    local ok = (rc == sqlite3.DONE)
    
    stmt:finalize()
    return ok, not ok and last_error() or nil
end

function M.get_group_members(groupId)
    if not M._db then return {} end
    if not groupId then return {} end
    
    return collect_rows('SELECT bot_name, added_at FROM bot_group_members WHERE group_id = ? ORDER BY bot_name', function(s)
        s:bind_values(groupId)
    end)
end

function M.get_groups_with_members()
    if not M._db then return {} end
    
    local groups = M.get_all_groups()
    for _, group in ipairs(groups) do
        group.members = M.get_group_members(group.id)
    end
    
    return groups
end

return M
