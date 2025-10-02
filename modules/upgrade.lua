-- emubot/modules/upgrade.lua
-- EmuBot Upgrades: determine which bots can use the cursor item and allow swapping

local mq = require('mq')
local bot_inventory = require('EmuBot.modules.bot_inventory')

local U = {}

U._candidates = {}
U._show_compare = false
U._pending_refresh = {}

-- Forward declaration so functions defined earlier can call it safely
local get_cursor_stats

local function printf(fmt, ...)
    if mq.printf then mq.printf(fmt, ...) else print(string.format(fmt, ...)) end
end

local slotNames = {
    [0] = 'Charm', [1] = 'Left Ear', [2] = 'Head', [3] = 'Face', [4] = 'Right Ear',
    [5] = 'Neck', [6] = 'Shoulders', [7] = 'Arms', [8] = 'Back', [9] = 'Left Wrist',
    [10] = 'Right Wrist', [11] = 'Range', [12] = 'Hands', [13] = 'Primary', [14] = 'Secondary',
    [15] = 'Left Ring', [16] = 'Right Ring', [17] = 'Chest', [18] = 'Legs', [19] = 'Feet',
    [20] = 'Waist', [21] = 'Power Source', [22] = 'Ammo',
}

local classMap = {
    ["WAR"] = "WARRIOR",
    ["CLR"] = "CLERIC",
    ["PAL"] = "PALADIN",
    ["RNG"] = "RANGER",
    ["SHD"] = "SHADOW KNIGHT", ["SK"] = "SHADOW KNIGHT", ["SHADOWKNIGHT"] = "SHADOW KNIGHT",
    ["DRU"] = "DRUID",
    ["MNK"] = "MONK",
    ["BRD"] = "BARD",
    ["ROG"] = "ROGUE",
    ["SHM"] = "SHAMAN",
    ["NEC"] = "NECROMANCER",
    ["WIZ"] = "WIZARD",
    ["MAG"] = "MAGICIAN",
    ["ENC"] = "ENCHANTER",
    ["BST"] = "BEASTLORD", ["BEAST"] = "BEASTLORD", ["BL"] = "BEASTLORD",
    ["BER"] = "BERSERKER",
}

local function normalize_class(name)
    if not name then return nil end
    local up = tostring(name):upper()
    return classMap[up] or up
end

local function extract_class_abbreviation(classString)
    if not classString then return 'UNK' end
    local str = tostring(classString):upper()
    
    -- Check if it's already a 3-letter abbreviation we recognize
    for abbrev, _ in pairs(classMap) do
        if str == abbrev then return abbrev end
    end
    
    -- Extract class from "Race Class" format by looking for class keywords
    local classKeywords = {
        'WARRIOR', 'CLERIC', 'PALADIN', 'RANGER', 'SHADOW KNIGHT', 'SHADOWKNIGHT',
        'DRUID', 'MONK', 'BARD', 'ROGUE', 'SHAMAN', 'NECROMANCER', 'WIZARD',
        'MAGICIAN', 'ENCHANTER', 'BEASTLORD', 'BERSERKER'
    }
    
    for _, class in ipairs(classKeywords) do
        if str:find(class) then
            -- Find the abbreviation for this class
            for abbrev, fullName in pairs(classMap) do
                if fullName == class then
                    return abbrev
                end
            end
        end
    end
    
    return 'UNK'
end

local function can_item_be_used_by_class(itemTLO, className)
    if not itemTLO or not itemTLO() or not className then return false end
    local normalized = normalize_class(className)
    local classCount = tonumber(itemTLO.Classes() or 0) or 0
    if classCount == 0 then return false end
    if classCount >= 16 then return true end
    for i = 1, classCount do
        local ok, itemClass = pcall(function() return itemTLO.Class(i)() end)
        if ok and itemClass then
            local a = normalize_class(itemClass)
            if a == normalized then return true end
        end
    end
    return false
end

local function get_worn_slot_ids(itemTLO)
    local ids = {}
    local count = tonumber(itemTLO.WornSlots() or 0) or 0
    for i = 1, count do
        local ok, sid = pcall(function() return itemTLO.WornSlot(i).ID() end)
        if ok and sid ~= nil then table.insert(ids, tonumber(sid)) end
    end
    return ids
end

local function clear_candidates()
    U._candidates = {}
end

local function add_candidate(c)
    U._candidates[#U._candidates + 1] = c
end

-- Queue a timed inventory refresh for a bot (non-blocking); retries spaced by delaySec
function U.queue_refresh(botName, delaySec, retries)
    if not botName or botName == '' then return end
    U._pending_refresh[botName] = U._pending_refresh[botName] or { nextAt = 0, left = 0, delay = delaySec or 0.8 }
    local entry = U._pending_refresh[botName]
    entry.left = math.max(tonumber(retries or 1) or 1, entry.left)
    entry.delay = tonumber(delaySec or entry.delay or 0.8) or 0.8
    entry.nextAt = os.clock() + entry.delay
end

local function process_pending_refreshes()
    if not bot_inventory or not bot_inventory.requestBotInventory then return end
    local now = os.clock()
    for name, entry in pairs(U._pending_refresh) do
        if entry and (entry.left or 0) > 0 and now >= (entry.nextAt or 0) then
            bot_inventory.requestBotInventory(name)
            entry.left = (entry.left or 1) - 1
            entry.nextAt = now + (entry.delay or 0.8)
            if entry.left <= 0 then U._pending_refresh[name] = nil end
        end
    end
end

local function compute_local_candidates_from_cursor()
    clear_candidates()
    local cur = mq.TLO.Cursor
    if not cur() then
        printf('[EmuBot] No item on cursor for upgrade scan.')
        return 0
    end
    local itemName = cur.Name() or 'Unknown Item'
    local itemID = tonumber(cur.ID() or 0) or 0
    local slotIDs = get_worn_slot_ids(cur)
    if #slotIDs == 0 then
        printf('[EmuBot] Cursor item has no wearable slots.')
        return 0
    end
    local bots = bot_inventory.getAllBots() or {}
    for _, botName in ipairs(bots) do
        local meta = bot_inventory.bot_list_capture_set and bot_inventory.bot_list_capture_set[botName]
        local botClass = meta and meta.Class or nil
        local classOK = can_item_be_used_by_class(cur, botClass)
        if classOK then
            for _, sid in ipairs(slotIDs) do
                local slotName = slotNames[sid] or ('Slot ' .. tostring(sid))
                local classAbbrev = extract_class_abbreviation(botClass)
                add_candidate({ bot = botName, class = classAbbrev, slotid = sid, slotname = slotName, itemID = itemID, itemName = itemName })
            end
        end
    end
    return #U._candidates
end

local function ensure_item_on_cursor(itemID)
    if mq.TLO.Cursor() then
        local cid = tonumber(mq.TLO.Cursor.ID() or 0) or 0
        if cid == itemID then return true end
        -- Try to autoinventory to free cursor
        mq.cmd('/autoinventory')
        mq.delay(200)
    end
    -- Find item in inventory
    local fi = mq.TLO.FindItem(itemID)
    if not fi() then return false end
    local packSlot = tonumber(fi.ItemSlot() or 0) or 0
    local subSlot = tonumber(fi.ItemSlot2() or -1) or -1
    if packSlot >= 23 and subSlot >= 0 then
        mq.cmdf('/itemnotify in pack%i %i leftmouseup', (packSlot - 22), (subSlot + 1))
        mq.delay(200)
    else
        -- It may be in main inventory (not inside bag)
        if packSlot >= 23 and subSlot < 0 then
            -- click the top-level slot
            mq.cmdf('/itemnotify in pack%i 1 leftmouseup', (packSlot - 22))
            mq.delay(200)
        end
    end
    return mq.TLO.Cursor() and tonumber(mq.TLO.Cursor.ID() or 0) == itemID
end

local function swap_to_bot(botName, itemID, slotID, slotName)
    -- UI enforces that the cursor already holds the correct item before enabling Swap.
    -- So we avoid any blocking/delay here.
    if not mq.TLO.Cursor() or tonumber(mq.TLO.Cursor.ID() or 0) ~= tonumber(itemID or 0) then
        printf('[EmuBot] Swap requires the upgrade item on your cursor.')
        return false
    end
    mq.cmdf('/say ^ig byname %s', botName)

    -- Optimistically update cache/DB using cursor data to avoid ^invlist roundtrip
    local ac, hp, mana = get_cursor_stats()
    local icon = 0
    local ok_icon, icon_val = pcall(function()
        if mq.TLO.Cursor.Icon then return tonumber(mq.TLO.Cursor.Icon() or 0) or 0 end
        return 0
    end)
    if ok_icon and icon_val then icon = icon_val end
    if bot_inventory and bot_inventory.applySwapFromCursor and slotID ~= nil then
        bot_inventory.applySwapFromCursor(botName, slotID, slotName, tonumber(itemID) or 0,
            mq.TLO.Cursor.Name() or 'Item', ac, hp, mana, icon)
    end
    return true
end

function U.poll_iu()
    clear_candidates()
    if not mq.TLO.Cursor() then
        printf('[EmuBot] Put the upgrade item on your cursor before polling.')
        return
    end
    printf('[EmuBot] Polling bots with ^iu ...')
    U._show_compare = true
    mq.cmd('/say ^iu')
    -- ^iu responses will be captured by registered events (see U.init()). As a fallback, you may also click Scan Locally.
end

function U.scan_locally()
    local n = compute_local_candidates_from_cursor()
    printf('[EmuBot] Local scan complete. %d candidate upgrade placements found.', n)
end

function U.clear()
    clear_candidates()
end

-- Helper to read cursor item basic stats safely
get_cursor_stats = function()
    local cur = mq.TLO.Cursor
    if not cur or not cur() then return 0, 0, 0 end
    local ac = tonumber(cur.AC() or 0) or 0
    local hp = tonumber(cur.HP() or 0) or 0
    local mana = tonumber(cur.Mana() or 0) or 0
    -- Fallbacks where available (DisplayItem -> Item totals) to reduce 0 stats
    if (ac == 0 or hp == 0 or mana == 0) and mq.TLO.DisplayItem and mq.TLO.DisplayItem()
        and mq.TLO.DisplayItem.Item and mq.TLO.DisplayItem.Item() then
        local di = mq.TLO.DisplayItem.Item
        local function safe_num(getter)
            if not getter then return 0 end
            local ok, v = pcall(function() return tonumber(getter()) or 0 end)
            return ok and v or 0
        end
        if ac == 0 then
            ac = safe_num(di.AC)
            if ac == 0 and di.TotalAC then ac = safe_num(di.TotalAC) end
        end
        if hp == 0 then
            hp = safe_num(di.HP)
            if hp == 0 and di.HitPoints then hp = safe_num(di.HitPoints) end
        end
        if mana == 0 then mana = safe_num(di.Mana) end
    end
    return ac, hp, mana
end

function U.draw_tab()
    process_pending_refreshes()
    ImGui.Text('Cursor Item:')
    if mq.TLO.Cursor() then
        ImGui.SameLine()
        ImGui.TextColored(0.9, 0.8, 0.2, 1.0, mq.TLO.Cursor.Name() or 'Unknown')
    else
        ImGui.SameLine()
        ImGui.TextColored(0.9, 0.3, 0.3, 1.0, 'None')
    end

    if ImGui.Button('Poll (^iu)##upgrade') then U.poll_iu() end
    ImGui.SameLine()
    if ImGui.Button('Scan Locally##upgrade') then U.scan_locally() end
    ImGui.SameLine()
    if ImGui.Button('Clear##upgrade') then U.clear() end
    ImGui.SameLine()
    if ImGui.Button('Open Compare##upgrade') then U._show_compare = true end

    ImGui.Separator()

    if #U._candidates == 0 then
        ImGui.Text('No upgrade candidates yet. Use Poll (^iu) or Scan Locally.')
        -- Still draw compare window if user opened it (to show empty state)
        if U._show_compare then U.draw_compare_window() end
        return
    end

    if ImGui.BeginTable('EmuBotUpgradeTable', 8, ImGuiTableFlags.Borders + ImGuiTableFlags.RowBg + ImGuiTableFlags.Resizable) then
        ImGui.TableSetupColumn('Bot', ImGuiTableColumnFlags.WidthFixed, 120)
        ImGui.TableSetupColumn('Class', ImGuiTableColumnFlags.WidthFixed, 60)
        ImGui.TableSetupColumn('Slot', ImGuiTableColumnFlags.WidthFixed, 120)
        ImGui.TableSetupColumn('Item', ImGuiTableColumnFlags.WidthStretch)
        ImGui.TableSetupColumn('Δ AC', ImGuiTableColumnFlags.WidthFixed, 60)
        ImGui.TableSetupColumn('Δ HP', ImGuiTableColumnFlags.WidthFixed, 60)
        ImGui.TableSetupColumn('Δ Mana', ImGuiTableColumnFlags.WidthFixed, 70)
        ImGui.TableSetupColumn('Action', ImGuiTableColumnFlags.WidthFixed, 120)
        ImGui.TableHeadersRow()

        for i, row in ipairs(U._candidates) do
            ImGui.TableNextRow()
            ImGui.PushID('upg_' .. tostring(i))

            ImGui.TableNextColumn()
            if ImGui.Selectable((row.bot or 'Unknown') .. '##maintarget_' .. tostring(i), false, ImGuiSelectableFlags.None) then
                -- Target the bot when clicked
                local botName = row.bot
                if botName then
                    local s = mq.TLO.Spawn(string.format('= %s', botName))
                    if s and s.ID and s.ID() and s.ID() > 0 then
                        mq.cmdf('/target id %d', s.ID())
                        printf('[EmuBot] Targeting %s', botName)
                    else
                        mq.cmdf('/target "%s"', botName)
                        printf('[EmuBot] Attempting to target %s', botName)
                    end
                end
            end
            if ImGui.IsItemHovered() then
                ImGui.SetTooltip('Click to target ' .. (row.bot or 'bot'))
            end

            ImGui.TableNextColumn()
            ImGui.Text(row.class or 'UNK')

            ImGui.TableNextColumn()
            ImGui.Text(row.slotname or ('Slot ' .. tostring(row.slotid or '?')))

            ImGui.TableNextColumn()
            ImGui.Text(row.itemName or 'Upgrade Item')

            -- Compute deltas for quick glance in the main table
            local upgAC, upgHP, upgMana = get_cursor_stats()
            local cAC, cHP, cMana = 0, 0, 0
            if bot_inventory and bot_inventory.getBotEquippedItem and row.bot and row.slotid ~= nil then
                local curItem = bot_inventory.getBotEquippedItem(row.bot, row.slotid)
                cAC = tonumber(curItem and curItem.ac or 0) or 0
                cHP = tonumber(curItem and curItem.hp or 0) or 0
                cMana = tonumber(curItem and curItem.mana or 0) or 0
            end
            local dAC = (upgAC or 0) - cAC
            local dHP = (upgHP or 0) - cHP
            local dMana = (upgMana or 0) - cMana

            local function colortext(delta)
                if delta > 0 then ImGui.TextColored(0.0, 0.9, 0.0, 1.0, '+' .. tostring(delta))
                elseif delta < 0 then ImGui.TextColored(0.9, 0.0, 0.0, 1.0, tostring(delta))
                else ImGui.Text('0') end
            end

            ImGui.TableNextColumn(); colortext(dAC)
            ImGui.TableNextColumn(); colortext(dHP)
            ImGui.TableNextColumn(); colortext(dMana)

            ImGui.TableNextColumn()
            if ImGui.SmallButton('Swap') then
                local ok = swap_to_bot(row.bot, tonumber(row.itemID or 0) or 0, row.slotid, row.slotname)
                if ok then
                    -- Remove this candidate (assumes single item usage)
                    table.remove(U._candidates, i)
                end
            end

            ImGui.PopID()
        end

        ImGui.EndTable()
    end

    if U._show_compare then U.draw_compare_window() end
end

local function slot_from_phrase(phrase)
    if not phrase then return nil end
    local p = tostring(phrase):lower()
    local map = {
        ['head']=2, ['face']=3, ['neck']=5, ['shoulders']=6, ['arms']=7, ['back']=8,
        ['range']=11, ['hands']=12, ['primary']=13, ['secondary']=14, ['chest']=17,
        ['legs']=18, ['feet']=19, ['waist']=20, ['power source']=21, ['ammo']=22, ['charm']=0,
    }
    -- Fingers/Ears/Wrists with index
    local function with_index(base, one, two)
        if p:find(base) then
            local id = nil
            if p:find('1') then id = one elseif p:find('2') then id = two end
            return id
        end
        return nil
    end
    local id = with_index('finger', 15, 16) or with_index('ear', 1, 4) or with_index('wrist', 9, 10) or map[p]
    if not id then return nil end
    return id, slotNames[id] or phrase
end

local function on_iu_basic(line, name, slotPhrase)
    local itemID = tonumber(mq.TLO.Cursor.ID() or 0) or 0
    local itemName = mq.TLO.Cursor.Name() or 'Item'
    local sid, sname = slot_from_phrase(slotPhrase)
    if not sid then return end
    
    -- Get bot class from metadata if available
    local botClass = 'UNK'
    if bot_inventory and bot_inventory.bot_list_capture_set and bot_inventory.bot_list_capture_set[name] then
        botClass = bot_inventory.bot_list_capture_set[name].Class or 'UNK'
    end
    local classAbbrev = extract_class_abbreviation(botClass)
    
    add_candidate({ bot = name, class = classAbbrev, slotid = sid, slotname = sname, itemID = itemID, itemName = itemName })
    U._show_compare = true
end

local function on_iu_instead(line, name, slotPhrase, currentItem)
    -- We currently resolve current item via bot_inventory; still capture name/slot
    on_iu_basic(line, name, slotPhrase)
end

function U.init()
    if U._events_inited then return end
    -- Examples from screenshot:
    -- Cadwen says, 'I can use that for my Finger 1! Would you like to give it to me?'
    -- Dragkan says, 'I can use that for my Finger 1 instead of my Elegant Adept's Ring! Would you like to remove my item?'
    -- Fixed: Made patterns mutually exclusive to prevent duplicate slot capture
    mq.event('EmuBot_IU_Give', "#1# says, 'I can use that for my #2#! Would you like to give it to me?'", on_iu_basic)
    mq.event('EmuBot_IU_Replace', "#1# says, 'I can use that for my #2# instead of my #3#! #*", on_iu_instead)
    U._events_inited = true
end

-- Draw a comparison window showing current equipped vs upgrade stats (AC/HP/Mana), with quick swap per row
function U.draw_compare_window()
    if not U._show_compare then return end
    process_pending_refreshes()
    local wndFlags = ImGuiWindowFlags.None
    local isOpen, visible = ImGui.Begin('Upgrade Comparison##EmuBot', true, wndFlags)
    if not isOpen then
        U._show_compare = false
        ImGui.End()
        return
    end

    -- Gather upgrade stats from cursor
    local cur = mq.TLO.Cursor
    local upgName = cur() and (cur.Name() or 'Upgrade Item') or 'Upgrade Item'
    local upgAC = cur() and tonumber(cur.AC() or 0) or 0
    local upgHP = cur() and tonumber(cur.HP() or 0) or 0
    local upgMana = cur() and tonumber(cur.Mana() or 0) or 0

    ImGui.Text('Upgrade Item: ' .. tostring(upgName))
    ImGui.SameLine()
    ImGui.Text(string.format('(AC %d  HP %d  Mana %d)', upgAC, upgHP, upgMana))
    ImGui.Separator()

    if #U._candidates == 0 then
        ImGui.Text('No candidates to compare.')
        ImGui.End()
        return
    end

    if ImGui.BeginTable('EmuBotUpgradeCompare', 9, ImGuiTableFlags.Borders + ImGuiTableFlags.RowBg + ImGuiTableFlags.Resizable) then
        ImGui.TableSetupColumn('Bot', ImGuiTableColumnFlags.WidthFixed, 120)
        ImGui.TableSetupColumn('Class', ImGuiTableColumnFlags.WidthFixed, 60)
        ImGui.TableSetupColumn('Slot', ImGuiTableColumnFlags.WidthFixed, 120)
        ImGui.TableSetupColumn('Current', ImGuiTableColumnFlags.WidthStretch)
        ImGui.TableSetupColumn('Upgrade', ImGuiTableColumnFlags.WidthStretch)
        ImGui.TableSetupColumn('Δ AC', ImGuiTableColumnFlags.WidthFixed, 60)
        ImGui.TableSetupColumn('Δ HP', ImGuiTableColumnFlags.WidthFixed, 60)
        ImGui.TableSetupColumn('Δ Mana', ImGuiTableColumnFlags.WidthFixed, 70)
        ImGui.TableSetupColumn('Action', ImGuiTableColumnFlags.WidthFixed, 90)
        ImGui.TableHeadersRow()

        for i, row in ipairs(U._candidates) do
            ImGui.TableNextRow()
            ImGui.PushID('cmp_' .. tostring(i))

            -- Resolve current equipped item for this bot/slot
            local curItem = nil
            if bot_inventory and bot_inventory.getBotEquippedItem and row.bot and row.slotid ~= nil then
                curItem = bot_inventory.getBotEquippedItem(row.bot, row.slotid)
            end
            local cAC = tonumber(curItem and curItem.ac or 0) or 0
            local cHP = tonumber(curItem and curItem.hp or 0) or 0
            local cMana = tonumber(curItem and curItem.mana or 0) or 0

            local dAC = (upgAC or 0) - cAC
            local dHP = (upgHP or 0) - cHP
            local dMana = (upgMana or 0) - cMana

            ImGui.TableNextColumn()
            if ImGui.Selectable((row.bot or 'Unknown') .. '##target_' .. tostring(i), false, ImGuiSelectableFlags.None) then
                -- Target the bot when clicked
                local botName = row.bot
                if botName then
                    local s = mq.TLO.Spawn(string.format('= %s', botName))
                    if s and s.ID and s.ID() and s.ID() > 0 then
                        mq.cmdf('/target id %d', s.ID())
                        printf('[EmuBot] Targeting %s', botName)
                    else
                        mq.cmdf('/target "%s"', botName)
                        printf('[EmuBot] Attempting to target %s', botName)
                    end
                end
            end
            if ImGui.IsItemHovered() then
                ImGui.SetTooltip('Click to target ' .. (row.bot or 'bot'))
            end
            ImGui.TableNextColumn(); ImGui.Text(row.class or 'UNK')
            ImGui.TableNextColumn(); ImGui.Text(row.slotname or ('Slot ' .. tostring(row.slotid or '?')))

            -- Current (name only)
            ImGui.TableNextColumn()
            if curItem and curItem.name and curItem.name ~= '' then
                ImGui.Text(curItem.name)
            else
                ImGui.Text('--')
            end

            -- Upgrade (name only)
            ImGui.TableNextColumn()
            ImGui.Text(upgName)

            -- Deltas (colored)
            local function colortext(delta)
                if delta > 0 then ImGui.TextColored(0.0, 0.9, 0.0, 1.0, '+' .. tostring(delta))
                elseif delta < 0 then ImGui.TextColored(0.9, 0.0, 0.0, 1.0, tostring(delta))
                else ImGui.Text('0') end
            end

            ImGui.TableNextColumn(); colortext(dAC)
            ImGui.TableNextColumn(); colortext(dHP)
            ImGui.TableNextColumn(); colortext(dMana)

            -- Action (inline)
            ImGui.TableNextColumn()
            local canSwap = mq.TLO.Cursor() and (tonumber(mq.TLO.Cursor.ID() or 0) == tonumber(row.itemID or 0))
            if not canSwap then ImGui.BeginDisabled(true) end
            if ImGui.SmallButton('Swap##cmp' .. tostring(i)) then
                if swap_to_bot(row.bot, tonumber(row.itemID or 0) or 0, row.slotid, row.slotname) then
                    table.remove(U._candidates, i)
                end
            end
            if not canSwap then ImGui.EndDisabled() end

            ImGui.PopID()
        end

        ImGui.EndTable()
    end

    ImGui.End()
end

return U
