-- bot_inventory.lua
local mq = require("mq")
local json = require("dkjson")
local db = require('EmuBot.modules.db')

local function printf(fmt, ...)
    if mq and mq.printf then
        mq.printf(fmt, ...)
    else
        print(string.format(fmt, ...))
    end
end

local BotInventory = {}
BotInventory.bot_inventories = {}
BotInventory.pending_requests = {}
BotInventory.current_bot_request = nil
BotInventory.cached_bot_list = {}
BotInventory.refreshing_bot_list = false
BotInventory.bot_list_start_time = nil
BotInventory.bot_request_start_time = nil
BotInventory.refresh_all_pending = false
BotInventory.spawn_issued_time = nil
BotInventory.target_issued_time = nil
BotInventory.bot_request_phase = 0
BotInventory.bot_list_capture_set = {}
BotInventory.invlist_issued_time = nil
BotInventory._resources_dir = nil
BotInventory._capture_count = {}
BotInventory.item_cache_by_name = {}
BotInventory._debug = false

local function debugPrintf(fmt, ...)
    if not BotInventory._debug then return end
    printf('[BotInventory][Debug] ' .. fmt, ...)
end

function BotInventory.set_debug(enabled)
    BotInventory._debug = not not enabled
    printf('[BotInventory][Debug] Debug logging %s', BotInventory._debug and 'ENABLED' or 'DISABLED')
    return BotInventory._debug
end

function BotInventory.is_debug_enabled()
    return BotInventory._debug
end

local CACHEABLE_STAT_FIELDS = {'ac', 'hp', 'mana', 'damage', 'delay'}
local CACHEABLE_ICON_FIELDS = {'icon', 'iconID'}
local CACHEABLE_MISC_FIELDS = {'stackSize', 'charges'}
local CACHEABLE_AUGMENT_FIELDS = {}
for i = 1, 6 do
    CACHEABLE_AUGMENT_FIELDS[#CACHEABLE_AUGMENT_FIELDS + 1] = string.format('aug%dName', i)
    CACHEABLE_AUGMENT_FIELDS[#CACHEABLE_AUGMENT_FIELDS + 1] = string.format('aug%dlink', i)
    CACHEABLE_AUGMENT_FIELDS[#CACHEABLE_AUGMENT_FIELDS + 1] = string.format('aug%dIcon', i)
end

local CACHEABLE_FIELDS = {}
for _, field in ipairs(CACHEABLE_STAT_FIELDS) do CACHEABLE_FIELDS[#CACHEABLE_FIELDS + 1] = field end
for _, field in ipairs(CACHEABLE_ICON_FIELDS) do CACHEABLE_FIELDS[#CACHEABLE_FIELDS + 1] = field end
for _, field in ipairs(CACHEABLE_MISC_FIELDS) do CACHEABLE_FIELDS[#CACHEABLE_FIELDS + 1] = field end
for _, field in ipairs(CACHEABLE_AUGMENT_FIELDS) do CACHEABLE_FIELDS[#CACHEABLE_FIELDS + 1] = field end

local function normalizeItemName(name)
    if not name then return nil end
    local str = tostring(name)
    str = str:gsub('^%s+', ''):gsub('%s+$', '')
    if str == '' then return nil end
    return string.lower(str)
end

local function isStringEmpty(value)
    return value == nil or (type(value) == 'string' and value == '')
end

local function shouldReplaceFromCache(currentValue)
    if currentValue == nil then return true end
    if type(currentValue) == 'number' then return currentValue == 0 end
    if type(currentValue) == 'string' then return currentValue == '' end
    return false
end

local function itemHasPrimaryStats(item)
    if not item then return false end
    for _, field in ipairs(CACHEABLE_STAT_FIELDS) do
        local numeric = tonumber(item[field] or 0)
        if numeric and numeric > 0 then
            return true
        end
    end
    return false
end

local function itemHasCacheableData(item)
    if not item then return false end
    if itemHasPrimaryStats(item) then return true end
    for _, field in ipairs(CACHEABLE_ICON_FIELDS) do
        local numeric = tonumber(item[field] or 0)
        if numeric and numeric > 0 then return true end
    end
    for _, field in ipairs(CACHEABLE_AUGMENT_FIELDS) do
        if not isStringEmpty(item[field]) then return true end
    end
    for _, field in ipairs(CACHEABLE_MISC_FIELDS) do
        if item[field] ~= nil then return true end
    end
    return false
end

function BotInventory.apply_cached_item_stats(item)
    local cacheKey = normalizeItemName(item and item.name)
    if not cacheKey then return false end
    local cached = BotInventory.item_cache_by_name[cacheKey]
    if not cached then return false end

    local applied = false
    for _, field in ipairs(CACHEABLE_FIELDS) do
        local cachedValue = cached[field]
        if cachedValue ~= nil and shouldReplaceFromCache(item[field]) then
            item[field] = cachedValue
            applied = true
        end
    end

    if applied then
        item._cacheMiss = false
    end

    return applied
end

function BotInventory.update_item_cache(item)
    local cacheKey = normalizeItemName(item and item.name)
    if not cacheKey or not itemHasCacheableData(item) then return false end

    local entry = BotInventory.item_cache_by_name[cacheKey] or {}
    for _, field in ipairs(CACHEABLE_FIELDS) do
        local value = item[field]
        if value ~= nil then
            if type(value) == 'string' then
                if value ~= '' then entry[field] = value end
            else
                entry[field] = value
            end
        end
    end
    BotInventory.item_cache_by_name[cacheKey] = entry
    item._cacheMiss = false
    return true
end

function BotInventory.ensure_item_cached(item)
    if not item then return false end

    local needsScan = false
    local hadStatsInitially = itemHasPrimaryStats(item)
    local hadCacheableInitially = itemHasCacheableData(item)
    local appliedFromCache = false
    local cacheUpdated = false

    if hadStatsInitially then
        cacheUpdated = BotInventory.update_item_cache(item) or cacheUpdated
    else
        local applied = BotInventory.apply_cached_item_stats(item)
        appliedFromCache = applied
        local hasStatsAfterCache = itemHasPrimaryStats(item)
        if not applied or not hasStatsAfterCache then
            needsScan = true
            item._cacheMiss = true
            if applied and itemHasCacheableData(item) then
                cacheUpdated = BotInventory.update_item_cache(item) or cacheUpdated
            end
        else
            cacheUpdated = BotInventory.update_item_cache(item) or cacheUpdated
        end
    end

    if not needsScan then
        item._cacheMiss = false
    end
    item.needsScan = needsScan
    local linkPresent = not isStringEmpty(item.itemlink) or not isStringEmpty(item.rawline)
    local hasStatsFinal = itemHasPrimaryStats(item)
    local hasCacheableFinal = itemHasCacheableData(item)

    debugPrintf(
        'Cache check for %s (ID=%s, link=%s): stats %s→%s, cacheable %s→%s, cache hit=%s, cache updated=%s, needsScan=%s, cacheMiss=%s',
        tostring(item.name or 'unknown'),
        tostring(item.itemID or 'nil'),
        linkPresent and 'yes' or 'no',
        hadStatsInitially and 'yes' or 'no',
        hasStatsFinal and 'yes' or 'no',
        hadCacheableInitially and 'yes' or 'no',
        hasCacheableFinal and 'yes' or 'no',
        appliedFromCache and 'yes' or 'no',
        cacheUpdated and 'yes' or 'no',
        needsScan and 'yes' or 'no',
        (item._cacheMiss and 'yes' or 'no')
    )
    return needsScan
end

function BotInventory.invalidate_item_cache(itemName)
    local cacheKey = normalizeItemName(itemName)
    if not cacheKey then return false end
    if BotInventory.item_cache_by_name[cacheKey] then
        BotInventory.item_cache_by_name[cacheKey] = nil
        return true
    end
    return false
end

function BotInventory.invalidate_item_cache_if_unused(itemName)
    local cacheKey = normalizeItemName(itemName)
    if not cacheKey then return false end

    local function collectionHasItem(collection)
        if type(collection) ~= 'table' then return false end
        for _, entry in pairs(collection) do
            if type(entry) == 'table' then
                if normalizeItemName(entry.name) == cacheKey then
                    return true
                end
                if collectionHasItem(entry) then
                    return true
                end
            end
        end
        return false
    end

    for _, data in pairs(BotInventory.bot_inventories or {}) do
        if collectionHasItem(data.equipped) or collectionHasItem(data.bags) or collectionHasItem(data.bank) then
            return false
        end
    end

    BotInventory.item_cache_by_name[cacheKey] = nil
    return true
end

local function normalizePathSeparators(path)
    return path and path:gsub('\\\\', '/') or nil
end

local function trimTrailingSlash(path)
    if not path then return nil end
    return path:gsub('/+$', '')
end

local function detectResourcesDir()
    if BotInventory._resources_dir ~= nil then
        return BotInventory._resources_dir
    end

    local resolved

    if mq and mq.TLO and mq.TLO.MacroQuest and mq.TLO.MacroQuest.Path then
        local ok, result = pcall(function()
            local tlo = mq.TLO.MacroQuest.Path('Resources')
            if tlo and tlo() and tlo() ~= '' then
                return tlo()
            end
            return nil
        end)
        if ok and result and result ~= '' then
            resolved = result
        end
    end

    if (not resolved) and mq and mq.luaDir then
        local ok, result = pcall(function()
            if type(mq.luaDir) == 'function' then
                return mq.luaDir()
            end
            return mq.luaDir
        end)
        if ok and result and result ~= '' then
            local normalized = trimTrailingSlash(normalizePathSeparators(tostring(result)))
            if normalized then
                local root = normalized:match('^(.*)/lua$')
                if root and root ~= '' then
                    resolved = root .. '/Resources'
                end
            end
        end
    end

    if not resolved then
        local info = debug.getinfo(detectResourcesDir, 'S')
        local source = info and info.source
        if source and source:sub(1, 1) == '@' then
            local normalized = normalizePathSeparators(source:sub(2))
            if normalized then
                local root = normalized:match('^(.*)/lua/')
                if root and root ~= '' then
                    resolved = root .. '/Resources'
                end
            end
        end
    end

    if resolved then
        resolved = trimTrailingSlash(normalizePathSeparators(resolved))
    end

    BotInventory._resources_dir = resolved
    return BotInventory._resources_dir
end

-- Convert itemID to a clickable web URL based on the selected export option
local function createItemURL(itemID)
    if not itemID or itemID == 0 then return "" end
    
    -- Determine server to select appropriate URL
    local serverName = ""
    if mq and mq.TLO and mq.TLO.EverQuest and mq.TLO.EverQuest.Server then
        local ok, server = pcall(function() return mq.TLO.EverQuest.Server() end)
        if ok and server then
            serverName = tostring(server)
        end
    end
    
    -- Return URL based on server
    if serverName == "Karana" then
        return string.format("https://karanaeq.com/Alla/?a=item&id=%s", tostring(itemID))
    elseif serverName == "Shadowed Eclipse" then
        return string.format("http://shadowedeclipse.com/?a=item&id=%s", tostring(itemID))
    else
        -- For other servers, return empty string to skip hyperlinks
        return ""
    end
end

local function cloneItemForExport(item)
    if not item then return nil end

    local copy = {
        name = item.name,
        slotid = item.slotid,
        slotname = item.slotname,
        itemID = item.itemID,
        icon = item.icon,
        stackSize = item.stackSize,
        charges = item.charges,
        ac = item.ac,
        hp = item.hp,
        mana = item.mana,
        damage = item.damage,
        delay = item.delay,
        qty = item.qty,
        nodrop = item.nodrop,
    }

    -- Replace in-game itemlink with URL based on the server if we have an itemID
    if item.itemID and tonumber(item.itemID) and tonumber(item.itemID) > 0 then
        copy.itemlink = createItemURL(item.itemID)
    elseif type(item.itemlink) == "string" then
        copy.itemlink = item.itemlink  -- Fallback to original link if no itemID
    end
    
    if type(item.rawline) == "string" then
        copy.rawline = item.rawline
    end

    return copy
end

local function copyItemListForExport(source)
    local result = {}
    if not source then return result end

    for _, item in ipairs(source) do
        local sanitized = cloneItemForExport(item)
        if sanitized then
            table.insert(result, sanitized)
        end
    end

    return result
end

local function buildExportSnapshot()
    local snapshot = {}

    for botName, data in pairs(BotInventory.bot_inventories or {}) do
        local entry = {
            name = data and data.name or botName,
            equipped = copyItemListForExport(data and data.equipped),
            bags = copyItemListForExport(data and data.bags),
            bank = copyItemListForExport(data and data.bank),
        }

        snapshot[#snapshot + 1] = entry
    end

    table.sort(snapshot, function(a, b)
        local nameA = (a and a.name) or ""
        local nameB = (b and b.name) or ""
        return nameA:lower() < nameB:lower()
    end)

    return snapshot
end

local function targetBotByName(botName)
    if not botName or botName == "" then return end

    local spawnLookup = mq.TLO.Spawn(string.format("= %s", botName))
    local ok, spawnId = pcall(function()
        return spawnLookup and spawnLookup.ID and spawnLookup.ID()
    end)

    if ok and spawnId and spawnId > 0 then
        mq.cmdf("/target id %d", spawnId)
    else
        mq.cmdf('/target "%s"', botName)
    end
end

local function defaultExportFilename(format)
    local ext = (format and format:lower()) or "json"
    local timestamp = os.date("%Y%m%d_%H%M%S")
    return string.format("bot_inventories_%s.%s", timestamp, ext)
end

local function resolveExportPath(format, customPath)
    if customPath and customPath ~= "" then return customPath end

    local resourcesDir = detectResourcesDir()
    if resourcesDir and resourcesDir ~= "" then
        return string.format("%s/%s", resourcesDir, defaultExportFilename(format))
    end

    return defaultExportFilename(format)
end

local function writeFile(path, contents)
    local file, err = io.open(path, "w")
    if not file then
        return false, err or "Unable to open file"
    end

    file:write(contents or "")
    file:close()
    return true
end

local function encodeSnapshotAsJSON(snapshot)
    local payload = {
        exported_at = os.date("%Y-%m-%d %H:%M:%S"),
        bot_count = #snapshot,
        bots = snapshot,
    }

    local encoded, err = json.encode(payload, { indent = true })
    if not encoded then
        return false, err or "Failed to encode JSON"
    end
    return encoded
end

local function encodeSnapshotAsCSV(snapshot)
    headers = {
            "BotName",
            "Location",
            "SlotID",
            "SlotName",
            "ItemName",
            "ItemID",
            "AC",
            "HP",
            "Mana",
            "Damage",
            "Delay",
            "Icon",
            "Quantity",
            "Charges",
            "StackSize",
            "NoDrop",
            "ItemURL",
        }

    local function csvEscape(value)
        if value == nil then return "" end
        local str = tostring(value)
        if str:find('[",\n]') then
            str = '"' .. str:gsub('"', '""') .. '"'
        end
        return str
    end

    local lines = {}
    lines[#lines + 1] = table.concat(headers, ",")

    local function appendItems(location, items, botName)
        for _, item in ipairs(items or {}) do
            local url = item and item.itemlink or nil
            local hyperlink = nil
            if url and tostring(url):match('^https?://') then
                local text = item and item.name or url
                hyperlink = string.format('=HYPERLINK("%s","%s")', tostring(url), tostring(text))
            end
            
            local columns = {
                csvEscape(botName),
                csvEscape(location),
                csvEscape(item.slotid),
                csvEscape(item.slotname),
                csvEscape(item.name),
                csvEscape(item.itemID),
                csvEscape(item.ac),
                csvEscape(item.hp),
                csvEscape(item.mana),
                csvEscape(item.damage),
                csvEscape(item.delay),
                csvEscape(item.icon),
                csvEscape(item.qty),
                csvEscape(item.charges),
                csvEscape(item.stackSize),
                csvEscape(item.nodrop),
                csvEscape(hyperlink or url or ""),
            }
            lines[#lines + 1] = table.concat(columns, ",")
        end
    end

    for _, bot in ipairs(snapshot) do
        local botName = bot.name or "Unknown"
        appendItems("Equipped", bot.equipped, botName)
        appendItems("Bag", bot.bags, botName)
        appendItems("Bank", bot.bank, botName)
    end

    return table.concat(lines, "\n") .. "\n"
end

function BotInventory.exportBotInventories(format, path)
    local exportFormat = (format and format:lower()) or "json"
    if exportFormat ~= "json" and exportFormat ~= "csv" then
        local message = string.format("[BotInventory] Unsupported export format: %s", tostring(format))
        print(message)
        return false, message
    end

    local snapshot = buildExportSnapshot()
    local targetPath = resolveExportPath(exportFormat, path)

    local contents
    if exportFormat == "json" then
        local encoded, err = encodeSnapshotAsJSON(snapshot)
        if not encoded then
            local message = string.format("[BotInventory] Failed to encode JSON: %s", tostring(err))
            print(message)
            return false, message
        end
        contents = encoded
    else
        contents = encodeSnapshotAsCSV(snapshot)
    end

    local ok, err = writeFile(targetPath, contents)
    if not ok then
        local message = string.format("[BotInventory] Failed to write export file '%s': %s", targetPath, tostring(err))
        print(message)
        return false, message
    end

    local successMessage = string.format("[BotInventory] Exported bot inventories to %s", targetPath)
    print(successMessage)
    return true, targetPath
end

BotInventory.buildExportSnapshot = buildExportSnapshot

function BotInventory.parseItemLinkData(itemLinkString)
    if not itemLinkString or itemLinkString == "" then return nil end
    
    local links = mq.ExtractLinks(itemLinkString)
    for _, link in ipairs(links) do
        if link.type == mq.LinkTypes.Item then
            local parsed = mq.ParseItemLink(link.link)
            -- Best-effort extraction: treat missing fields as nil (unknown)
            local ac, hp, mana, damage, delay = nil, nil, nil, nil, nil
            if parsed then
                -- First, try fields directly present on parsed
                ac   = parsed.ac or parsed.AC or ac
                hp   = parsed.hp or parsed.HP or hp
                mana = parsed.mana or parsed.Mana or parsed.MANA or mana
                damage = parsed.damage or parsed.Damage or damage
                delay = parsed.delay or parsed.Delay or delay
            end
            local iconID = 0
            if parsed then
                iconID = tonumber(parsed.iconID or parsed.IconID or parsed.icon or parsed.Icon or 0) or 0
                if iconID == 0 and link.icon then
                    iconID = tonumber(link.icon) or 0
                end
            end

            return {
                itemID  = parsed and parsed.itemID or nil,
                iconID  = iconID,
                icon    = iconID,
                linkData = link,
                ac = ac ~= nil and (tonumber(ac) or 0) or nil,
                hp = hp ~= nil and (tonumber(hp) or 0) or nil,
                mana = mana ~= nil and (tonumber(mana) or 0) or nil,
                damage = damage ~= nil and (tonumber(damage) or 0) or nil,
                delay = delay ~= nil and (tonumber(delay) or 0) or nil,
            }
        end
    end
    return nil
end

function BotInventory.getBotListEvent(line, botIndex, botName, level, gender, race, class)
    if not BotInventory.refreshing_bot_list then return end
    -- Normalize name from token or table
    if type(botName) == "table" and botName.text then botName = botName.text end
    if not botName or botName == "" then return end

    local s = tostring(line or "")
    local parsedLevel, tail = s:match("is a Level%s+(%d+)%s+(.+)%s+owned by You%.")
    if not parsedLevel then
        parsedLevel, tail = s:match("is a Level%s+(%d+)%s+(.+)%s+owned by You")
    end

    local parsedGender, parsedRace, parsedClass
    if tail then
        parsedGender, tail = tail:match("^(%S+)%s+(.+)$")
        if parsedGender and tail then
            parsedClass = tail:match("(%S+)$")
            if parsedClass then
                parsedRace = tail:sub(1, #tail - #parsedClass - 1)
                parsedRace = parsedRace and parsedRace:match("^%s*(.-)%s*$") or nil
            end
        end
    end
    -- Fallbacks to provided tokens if parsing failed
    parsedLevel = tonumber(parsedLevel) or tonumber(level) or nil
    parsedGender = parsedGender or gender
    parsedRace = parsedRace or race
    parsedClass = parsedClass or class

    if not BotInventory.bot_list_capture_set[botName] then
        BotInventory.bot_list_capture_set[botName] = {
            Name = botName,
            Index = tonumber(botIndex),
            Level = parsedLevel,
            Gender = parsedGender,
            Race = parsedRace,
            Class = parsedClass,
        }
    else
        local e = BotInventory.bot_list_capture_set[botName]
        e.Level = e.Level or parsedLevel
        e.Gender = e.Gender or parsedGender
        e.Race = e.Race or parsedRace
        e.Class = e.Class or parsedClass
    end
end

local function displayBotInventory(line, slotNum, slotName)
    if not BotInventory.current_bot_request then return end
    
    local botName = BotInventory.current_bot_request
    
    -- Verify current target matches expected bot to prevent data crossover
    local currentTarget = mq.TLO.Target
    local targetName = currentTarget and currentTarget.Name and currentTarget.Name() or ""
    if targetName ~= botName then
        print(string.format("[BotInventory] WARNING: Target mismatch! Expected '%s' but target is '%s'. Ignoring inventory data.", botName, targetName))
        return
    end
    
    local itemlink = (mq.ExtractLinks(line) or {})[1] or { text = "Empty", link = "N/A" }

    debugPrintf(
        'Received inventory line for %s slot %s: text="%s", link="%s"',
        botName,
        tostring(slotName or slotNum),
        tostring(itemlink.text or 'nil'),
        tostring(itemlink.link or 'nil')
    )

    if not BotInventory.bot_inventories[botName] then
        BotInventory.bot_inventories[botName] = {
            name = botName,
            equipped = {},
            bags = {},
            bank = {}
        }
    end

    if itemlink.text ~= "Empty" and itemlink.link ~= "N/A" then
        local parsedItem = BotInventory.parseItemLinkData(line)

        debugPrintf(
            'Parsed link for %s slot %s: itemID=%s, icon=%s, ac=%s, hp=%s, mana=%s, damage=%s, delay=%s',
            botName,
            tostring(slotName or slotNum),
            parsedItem and tostring(parsedItem.itemID) or 'nil',
            parsedItem and tostring(parsedItem.iconID or parsedItem.icon) or '0',
            parsedItem and tostring(parsedItem.ac) or 'nil',
            parsedItem and tostring(parsedItem.hp) or 'nil',
            parsedItem and tostring(parsedItem.mana) or 'nil',
            parsedItem and tostring(parsedItem.damage) or 'nil',
            parsedItem and tostring(parsedItem.delay) or 'nil'
        )

        local newItem = {
            name = itemlink.text,
            slotid = tonumber(slotNum),
            slotname = slotName,
            itemlink = line,
            rawline = line,
            itemID = parsedItem and parsedItem.itemID or nil,
            icon = (parsedItem and (parsedItem.iconID or parsedItem.icon or 0)) or 0,
            stackSize = parsedItem and parsedItem.stackSize or nil,
            charges = parsedItem and parsedItem.charges or nil,
            ac = parsedItem and parsedItem.ac or nil,
            hp = parsedItem and parsedItem.hp or nil,
            mana = parsedItem and parsedItem.mana or nil,
            damage = parsedItem and parsedItem.damage or nil,
            delay = parsedItem and parsedItem.delay or nil,
            qty = 1,
            nodrop = 1
        }
        -- Merge behavior: replace per-slot, but preserve existing non-zero stats if new are zero
        local eq = BotInventory.bot_inventories[botName].equipped
        local replaced = false
        for i = 1, #eq do
            local it = eq[i]
            if tonumber(it.slotid) == tonumber(slotNum) then
                -- Preserve stats if new values are zero
                if (newItem.ac == nil) or ((newItem.ac or 0) == 0 and (it.ac or 0) ~= 0) then newItem.ac = newItem.ac ~= nil and newItem.ac or it.ac end
                if (newItem.hp == nil) or ((newItem.hp or 0) == 0 and (it.hp or 0) ~= 0) then newItem.hp = newItem.hp ~= nil and newItem.hp or it.hp end
                if (newItem.mana == nil) or ((newItem.mana or 0) == 0 and (it.mana or 0) ~= 0) then newItem.mana = newItem.mana ~= nil and newItem.mana or it.mana end
                if (newItem.icon or 0) == 0 and (it.icon or 0) ~= 0 then newItem.icon = it.icon end
                if (newItem.damage == nil) or ((newItem.damage or 0) == 0 and (it.damage or 0) ~= 0) then newItem.damage = newItem.damage ~= nil and newItem.damage or it.damage end
                if (newItem.delay == nil) or ((newItem.delay or 0) == 0 and (it.delay or 0) ~= 0) then newItem.delay = newItem.delay ~= nil and newItem.delay or it.delay end
                eq[i] = newItem
                replaced = true
                break
            end
        end
        if not replaced then table.insert(eq, newItem) end

        local needsScan = BotInventory.ensure_item_cached(newItem)
        newItem.needsScan = needsScan

        debugPrintf(
            'Post-processing state for %s slot %s: needsScan=%s, cacheMiss=%s',
            botName,
            tostring(slotName or slotNum),
            needsScan and 'yes' or 'no',
            newItem._cacheMiss and 'yes' or 'no'
        )

        -- Count capture lines for this request
        BotInventory._capture_count[botName] = (BotInventory._capture_count[botName] or 0) + 1

        -- Debug output to track inventory storage (disabled to reduce spam)
        -- print(string.format("[BotInventory DEBUG] Stored item: %s (ID: %s, Icon: %s) in slot %s for bot %s",
        --     item.name,
        --     item.itemID or "N/A",
        --     item.icon or "N/A",
        --     slotName,
        --     botName))
    else
        debugPrintf(
            'Slot %s for %s is empty. Raw line: %s',
            tostring(slotName or slotNum),
            botName,
            tostring(line or '')
        )
    end
end

function BotInventory.getAllBots()
    local names = {}
    if BotInventory.bot_list_capture_set then
        for name, botData in pairs(BotInventory.bot_list_capture_set) do
            table.insert(names, name)
        end
    end
    table.sort(names)
    return names
end

function BotInventory.refreshBotList()
    if BotInventory.refreshing_bot_list then
        return 
    end

    print("[BotInventory] Refreshing bot list...")
    BotInventory.refreshing_bot_list = true
    BotInventory.bot_list_capture_set = {}
    BotInventory.bot_list_start_time = os.time()

    mq.cmd("/say ^botlist")
end

function BotInventory.processBotListResponse()
    if BotInventory.refreshing_bot_list and BotInventory.bot_list_start_time then
        local elapsed = os.time() - BotInventory.bot_list_start_time
        
        if elapsed >= 3 then
            BotInventory.refreshing_bot_list = false
            BotInventory.cached_bot_list = {}
            for botName, botData in pairs(BotInventory.bot_list_capture_set) do
                table.insert(BotInventory.cached_bot_list, botName)
            end
            
            --print(string.format("[BotInventory] Found %d bots: %s", #BotInventory.cached_bot_list, table.concat(BotInventory.cached_bot_list, ", ")))
            BotInventory.bot_list_start_time = nil
        end
    end
end

-- Global skip check function (will be set by UI)
BotInventory.skipCheckFunction = nil

function BotInventory.requestBotInventory(botName)
    -- Check if bot should be skipped before starting request
    if BotInventory.skipCheckFunction and BotInventory.skipCheckFunction(botName) then
        print(string.format("[BotInventory] Skipping bot %s due to failure history", botName))
        return false
    end
    
    if BotInventory.current_bot_request == botName and BotInventory.bot_request_phase ~= 0 then 
        return false 
    end

    -- Start request without destroying existing cache; track capture count for this request
    BotInventory._capture_count[botName] = 0
    BotInventory.current_bot_request = botName
    BotInventory.bot_request_start_time = os.time()
    BotInventory.spawn_issued_time = nil
    BotInventory.target_issued_time = os.clock()
    BotInventory.invlist_issued_time = nil
    BotInventory.bot_request_phase = 1

    targetBotByName(botName)
    --print(string.format("[BotInventory DEBUG] Issued initial target attempt for %s", botName))
    return true
end

function BotInventory.processBotInventoryResponse()
    if BotInventory.current_bot_request and BotInventory.bot_request_start_time then
        local elapsed = os.time() - BotInventory.bot_request_start_time
        local botName = BotInventory.current_bot_request
        if elapsed >= 10 then
            print(string.format("[BotInventory] Timeout waiting for inventory from %s", botName))
            -- Notify skip system of failure if available
            if BotInventory.onBotFailure then
                BotInventory.onBotFailure(botName, "Timeout waiting for inventory")
            end
            BotInventory.current_bot_request = nil
            BotInventory.bot_request_start_time = nil
            BotInventory.bot_request_phase = 0
            BotInventory.spawn_issued_time = nil
            BotInventory.target_issued_time = nil
            return
        end
        if (BotInventory._capture_count[botName] or 0) > 0 then
            -- Check for mismatches with previously cached data
            local oldData = nil
            local newData = BotInventory.bot_inventories[botName]
            
            -- Try to get old data from database first
            if db and db.load_all then
                local dbData = db.load_all() or {}
                oldData = dbData[botName]
            end
            
            -- Compare and detect mismatches
            if oldData and newData then
                local mismatches = BotInventory.compareInventoryData(botName, oldData, newData)
                if #mismatches > 0 then
                    print(string.format("[BotInventory] Detected %d mismatched item(s) for %s, queueing for scan", #mismatches, botName))
                    
                    -- Queue mismatched items for scanning if scan callback is available
                    if BotInventory.onMismatchDetected then
                        for _, mismatch in ipairs(mismatches) do
                            print(string.format("[BotInventory] Queueing %s (slot %s) for scan: %s", 
                                mismatch.item.name or "unknown", 
                                tostring(mismatch.slotId), 
                                mismatch.reason))
                            BotInventory.onMismatchDetected(mismatch.item, botName, mismatch.reason)
                        end
                    end
                end
            end
            
            -- Persist to SQLite before clearing request state
            local meta = BotInventory.bot_list_capture_set and BotInventory.bot_list_capture_set[botName] or nil
            local ok, err = db.save_bot_inventory(botName, BotInventory.bot_inventories[botName], meta)
            if not ok then
                print(string.format("[BotInventory][DB] Failed to save inventory for %s: %s", botName, tostring(err)))
            else
                --print(string.format("[BotInventory][DB] Saved inventory for %s", botName))
            end

            --print(string.format("[BotInventory] Successfully captured inventory for %s (%d items)", botName, #BotInventory.bot_inventories[botName].equipped))
            BotInventory.current_bot_request = nil
            BotInventory._capture_count[botName] = 0
            BotInventory.bot_request_start_time = nil
            BotInventory.bot_request_phase = 0
            BotInventory.spawn_issued_time = nil
            BotInventory.target_issued_time = nil
            BotInventory.invlist_issued_time = nil
            return
        end
    end

    if not BotInventory.current_bot_request then
        return
    end

    local botName = BotInventory.current_bot_request

    if BotInventory.bot_request_phase == 1 and BotInventory.target_issued_time then
        if os.clock() - BotInventory.target_issued_time >= 0.5 then
            local currentTarget = mq.TLO.Target
            local targetName = currentTarget and currentTarget.Name and currentTarget.Name()
            if targetName == botName then
                mq.cmd("/say ^invlist")
                BotInventory.invlist_issued_time = os.clock()
                BotInventory.target_issued_time = nil
                BotInventory.bot_request_phase = 4
            else
                mq.cmdf("/say ^spawn %s", botName)
                BotInventory.spawn_issued_time = os.clock()
                BotInventory.bot_request_phase = 2
            end
        end
    elseif BotInventory.bot_request_phase == 2 and BotInventory.spawn_issued_time then
        if os.clock() - BotInventory.spawn_issued_time >= 2.0 then
            targetBotByName(botName)
            BotInventory.target_issued_time = os.clock()
            BotInventory.spawn_issued_time = nil
            BotInventory.bot_request_phase = 3
        end
    elseif BotInventory.bot_request_phase == 3 and BotInventory.target_issued_time then
        local currentTarget = mq.TLO.Target
        local targetName = currentTarget and currentTarget.Name and currentTarget.Name()
        if targetName == botName then
            if os.clock() - BotInventory.target_issued_time >= 1.0 then
                mq.cmd("/say ^invlist")
                BotInventory.invlist_issued_time = os.clock()
                BotInventory.target_issued_time = nil
                BotInventory.bot_request_phase = 4
            end
        elseif os.clock() - BotInventory.target_issued_time >= 3.0 then
            print(string.format("[BotInventory DEBUG] Failed to target %s after 3 seconds. Aborting.", botName))
            -- Notify skip system of failure if available
            if BotInventory.onBotFailure then
                BotInventory.onBotFailure(botName, "Failed to target after 3 seconds")
            end
            BotInventory.bot_request_phase = 0
            BotInventory.current_bot_request = nil
            BotInventory.spawn_issued_time = nil
            BotInventory.target_issued_time = nil
            BotInventory.invlist_issued_time = nil
        end
    end
end

local function displayBotUnequipResponse(line, slotNum, itemName)
    if not BotInventory.current_bot_request then return end
    
    local botName = BotInventory.current_bot_request
    print(string.format("[BotInventory] %s unequipped %s from slot %s", botName, itemName or "item", slotNum or "unknown"))
    
    -- Remove the item from our cached inventory if we have it
    if BotInventory.bot_inventories[botName] and BotInventory.bot_inventories[botName].equipped then
        local removed = false
        for i = #BotInventory.bot_inventories[botName].equipped, 1, -1 do
            local item = BotInventory.bot_inventories[botName].equipped[i]
            if tonumber(item.slotid) == tonumber(slotNum) then
                local removedItemName = item.name
                table.remove(BotInventory.bot_inventories[botName].equipped, i)
                print(string.format("[BotInventory] Removed %s from cached inventory", item.name or "item"))
                if removedItemName then
                    BotInventory.invalidate_item_cache_if_unused(removedItemName)
                end
                removed = true
                break
            end
        end
        if removed then
            local meta = BotInventory.bot_list_capture_set and BotInventory.bot_list_capture_set[botName] or nil
            local ok, err = db.save_bot_inventory(botName, BotInventory.bot_inventories[botName], meta)
            if not ok then
                print(string.format("[BotInventory][DB] Failed to persist after unequip for %s: %s", botName, tostring(err)))
            end
        end
    end
end

function BotInventory.requestBotUnequip(botName, slotID)
    if not botName or not slotID then
        print("[BotInventory] Error: botName and slotID required for unequip")
        return false
    end

    local botSpawn = mq.TLO.Spawn(string.format("= %s", botName))
    if botSpawn() then
        print(string.format("[BotInventory] Targeting and issuing unequip to %s at ID %d", botName, botSpawn.ID()))
        mq.cmdf("/target id %d", botSpawn.ID())
        mq.delay(500)
        mq.cmdf("/say ^invremove %s", slotID)
        return true
    else
        print(string.format("[BotInventory] Could not find bot spawn for unequip command: %s", botName))
        return false
    end
end


function BotInventory.getBotEquippedItem(botName, slotID)
    if not BotInventory.bot_inventories[botName] or not BotInventory.bot_inventories[botName].equipped then
        return nil
    end
    
    for _, item in ipairs(BotInventory.bot_inventories[botName].equipped) do
        if tonumber(item.slotid) == tonumber(slotID) then
            return item
        end
    end
    return nil
end

function BotInventory.process()
    BotInventory.processBotListResponse()
    BotInventory.processBotInventoryResponse()
end

function BotInventory.executeItemLink(item)
    if not item then
        print("[BotInventory DEBUG] No item provided.")
        return false
    end
    print(string.format("[BotInventory DEBUG] Raw line: %s", item.rawline or "nil"))
    local links = mq.ExtractLinks(item.rawline or "")
    if not links or #links == 0 then
        print("[BotInventory DEBUG] No links extracted.")
        return false
    end
    print(string.format("[BotInventory DEBUG] Extracted %d link(s):", #links))
    for i, link in ipairs(links) do
        local txt = link.text or "<nil>"
        local lnk = link.link or "<nil>"
        print(string.format("  [%d] Text: '%s' | Link: '%s'", i, txt, lnk))
        if link.type == mq.LinkTypes.Item then
            local parsedItem = mq.ParseItemLink(link.link)
            if parsedItem then
                print(string.format("    Item ID: %s, Icon ID: %s", 
                    parsedItem.itemID or "N/A", 
                    parsedItem.iconID or "N/A"))
            end
        end
    end
    return true
end

function BotInventory.onItemClick(item)
    if item then
        return BotInventory.executeItemLink(item)
    end
    return false
end

function BotInventory.getBotInventory(botName)
    return BotInventory.bot_inventories[botName]
end

-- Apply a known equipped item change using the cursor item data (no ^invlist roundtrip)
-- Replaces the equipped item in the given slot and persists to SQLite immediately.
-- Parameters:
--  botName   - target bot name
--  slotID    - numeric slot id
--  slotName  - human readable slot name
--  itemID    - numeric itemID of the cursor item
--  itemName  - name of the cursor item
--  ac,hp,mana,icon (numbers) - optional stats/icon to set; nil treated as 0
--  damage,delay (numbers) - optional weapon stats; nil treated as 0
function BotInventory.applySwapFromCursor(botName, slotID, slotName, itemID, itemName, ac, hp, mana, icon, damage, delay)
    if not botName or slotID == nil then return false, 'bad args' end

    -- Ensure bot cache exists
    BotInventory.bot_inventories[botName] = BotInventory.bot_inventories[botName] or {
        name = botName,
        equipped = {},
        bags = {},
        bank = {},
    }

    local eq = BotInventory.bot_inventories[botName].equipped

    local newItem = {
            name = itemName or 'Item',
            slotid = tonumber(slotID),
            slotname = slotName or tostring(slotID),
            itemlink = nil,
            rawline = nil,
            itemID = tonumber(itemID) or 0,
            icon = tonumber(icon or 0) or 0,
            ac = tonumber(ac or 0) or 0,
            hp = tonumber(hp or 0) or 0,
            mana = tonumber(mana or 0) or 0,
            damage = tonumber(damage or 0) or 0,
            delay = tonumber(delay or 0) or 0,
            qty = 1,
            nodrop = 1,
        }

    -- Replace existing slot entry or insert
    local replaced = false
    for i = 1, #eq do
        local it = eq[i]
        if tonumber(it.slotid) == tonumber(slotID) then
            eq[i] = newItem
            replaced = true
            break
        end
    end
    if not replaced then table.insert(eq, newItem) end

    local needsScan = BotInventory.ensure_item_cached(newItem)
    newItem.needsScan = needsScan

    -- Persist to DB with available bot meta
    local meta = BotInventory.bot_list_capture_set and BotInventory.bot_list_capture_set[botName] or nil
    local ok, err = db.save_bot_inventory(botName, BotInventory.bot_inventories[botName], meta)
    if not ok then
        print(string.format('[BotInventory][DB] Failed to persist swap for %s: %s', botName, tostring(err)))
        return false, err
    end

    return true
end

-- Compare items and detect mismatches that need re-scanning
function BotInventory.compareInventoryData(botName, oldData, newData)
    if not oldData or not newData then return {} end
    if not oldData.equipped or not newData.equipped then return {} end
    
    local mismatches = {}
    local oldBySlot = {}
    local newBySlot = {}
    
    -- Index old items by slot ID
    for _, item in ipairs(oldData.equipped) do
        if item.slotid then
            oldBySlot[tonumber(item.slotid)] = item
        end
    end
    
    -- Index new items by slot ID
    for _, item in ipairs(newData.equipped) do
        if item.slotid then
            newBySlot[tonumber(item.slotid)] = item
        end
    end

    local function statsFullyMissing(item)
        if not item then return true end
        local ac = tonumber(item.ac) or 0
        local hp = tonumber(item.hp) or 0
        local mana = tonumber(item.mana) or 0
        local damage = tonumber(item.damage) or 0
        local delay = tonumber(item.delay) or 0
        return ac == 0 and hp == 0 and mana == 0 and damage == 0 and delay == 0
    end

    -- Compare items in each slot
    for slotId, newItem in pairs(newBySlot) do
        local oldItem = oldBySlot[slotId]
        local cacheMiss = BotInventory.ensure_item_cached(newItem)
        local needsScan = false
        local reason = ""

        if not oldItem then
            if cacheMiss or statsFullyMissing(newItem) then
                needsScan = true
                reason = "new item with missing stats"
            end
        elseif oldItem.name ~= newItem.name or oldItem.itemID ~= newItem.itemID then
            if cacheMiss or statsFullyMissing(newItem) then
                needsScan = true
                reason = string.format("item changed from '%s' to '%s'", oldItem.name or "unknown", newItem.name or "unknown")
            end
        else
            if not statsFullyMissing(oldItem) and statsFullyMissing(newItem) then
                needsScan = true
                reason = "stats missing from fresh data"
            elseif (cacheMiss or statsFullyMissing(newItem)) and (not newItem.itemlink or newItem.itemlink == "") then
                needsScan = true
                reason = "missing stats and itemlink"
            end
        end

        local slotIsWeapon = slotId == 11 or slotId == 13 or slotId == 14
        if slotIsWeapon then
            local damageZero = (tonumber(newItem.damage or 0) == 0)
            local delayZero = (tonumber(newItem.delay or 0) == 0)
            if damageZero or delayZero then
                needsScan = true
                if reason == "" then
                    reason = "missing weapon stats"
                end
            end
        end

        newItem.needsScan = needsScan

        if needsScan then
            table.insert(mismatches, {
                item = newItem,
                slotId = slotId,
                reason = reason,
                botName = botName
            })
        end
    end
    
    return mismatches
end

function BotInventory.init()
    if BotInventory.initialized then return true end

    mq.event("GetBotList", "Bot #1# #*# #2# is a Level #3# #4# #5# #6# owned by You.#*", BotInventory.getBotListEvent)
    mq.event("BotInventory", "Slot #1# (#2#) #*#", displayBotInventory, { keepLinks = true })
    mq.event("BotUnequip", "#1# unequips #2# from slot #3#", displayBotUnequipResponse)

    -- Initialize database and pre-load prior state
    local ok, err = db.init()
    if not ok then
        print(string.format("[BotInventory][DB] Initialization failed: %s", tostring(err)))
    else
        local loaded = db.load_all() or {}
        for name, data in pairs(loaded) do
            BotInventory.bot_inventories[name] = data
            if data then
                if data.equipped then
                    for _, item in ipairs(data.equipped) do
                        BotInventory.ensure_item_cached(item)
                    end
                end
                if data.bags then
                    for _, bag in pairs(data.bags) do
                        if type(bag) == 'table' then
                            if bag.itemID or bag.slotid then
                                BotInventory.ensure_item_cached(bag)
                            else
                                for _, bagItem in ipairs(bag) do
                                    if type(bagItem) == 'table' then
                                        BotInventory.ensure_item_cached(bagItem)
                                    end
                                end
                            end
                        end
                    end
                end
                if data.bank then
                    for _, item in ipairs(data.bank) do
                        BotInventory.ensure_item_cached(item)
                    end
                end
            end
            -- Seed capture set so UI can list bots immediately
            if not BotInventory.bot_list_capture_set[name] then
                BotInventory.bot_list_capture_set[name] = { Name = name }
            end
        end
        print(string.format("[BotInventory][DB] Loaded %d bot(s) from persistence", (function(t) local c=0 for _ in pairs(t) do c=c+1 end return c end)(loaded)))
    end

    print("[BotInventory] Bot inventory system initialized")
    
    BotInventory.cached_bot_list = {}
    BotInventory.initialized = true
    return true
end

return BotInventory
