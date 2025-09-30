-- emubot/modules/bot_management.lua
-- Simple bot management tab: list bots with quick actions (spawn, invite to group, camp)

local mq = require('mq')
local bot_inventory = require('EmuBot.modules.bot_inventory')

local M = {}

-- Bot creation state
M.showCreateDialog = false
M.newBotName = ""
M.selectedClass = 0  -- 0-based for ImGui combo (WAR)
M.selectedRace = 0   -- 0-based for ImGui combo (HUM)
M.selectedGender = 0 -- 0-based for ImGui combo (Male)

-- Available options from the bot creation dialog
M.classes = {
    "WAR", "CLR", "PAL", "RNG", "SHD", "DRU", "MNK", "BRD",
    "ROG", "SHM", "NEC", "WIZ", "MAG", "ENC", "BST", "BER"
}

M.races = {
    "HUM", "BAR", "ERU", "ELF", "HIE", "DEF", "HEF", "DWF",
    "TRL", "OGR", "HFL", "GNM", "IKS", "VAH", "FRG", "DRK"
}

M.genders = {
    "Male", "Female"
}

-- Convert selections to numeric IDs for ^botcreate command
-- Based on EverQuest class IDs
M.classIDs = {
    ["WAR"] = 1, ["CLR"] = 2, ["PAL"] = 3, ["RNG"] = 4,
    ["SHD"] = 5, ["DRU"] = 6, ["MNK"] = 7, ["BRD"] = 8,
    ["ROG"] = 9, ["SHM"] = 10, ["NEC"] = 11, ["WIZ"] = 12,
    ["MAG"] = 13, ["ENC"] = 14, ["BST"] = 15, ["BER"] = 16
}

-- Based on EverQuest race IDs
M.raceIDs = {
    ["HUM"] = 1, ["BAR"] = 2, ["ERU"] = 3, ["ELF"] = 4,
    ["HIE"] = 5, ["DEF"] = 6, ["HEF"] = 7, ["DWF"] = 8,
    ["TRL"] = 9, ["OGR"] = 10, ["HFL"] = 11, ["GNM"] = 12,
    ["IKS"] = 128, ["VAH"] = 130, ["FRG"] = 330, ["DRK"] = 522
}

M.genderIDs = {
    ["Male"] = 0, ["Female"] = 1
}

local function printf(fmt, ...)
    if mq.printf then mq.printf(fmt, ...) else print(string.format(fmt, ...)) end
end

local function is_bot_spawned(name)
    local s = mq.TLO.Spawn(string.format('= %s', name))
    return s and s.ID and s.ID() and s.ID() > 0
end

local function target_bot(name)
    -- Non-blocking targeting (no mq.delay in ImGui thread)
    local s = mq.TLO.Spawn(string.format('= %s', name))
    if s and s.ID and s.ID() and s.ID() > 0 then
        mq.cmdf('/target id %d', s.ID())
        return true
    end
    mq.cmdf('/target "%s"', name)
    -- Return optimistically; the client will target shortly
    return true
end

local function action_spawn(name)
    mq.cmdf('/say ^spawn %s', name)
end

local function action_invite(name)
    if target_bot(name) then
        mq.cmd('/invite')
    else
        printf('[EmuBot] Could not target %s to invite', name)
    end
end

local function action_camp(name)
    if target_bot(name) then
        mq.cmd('/say ^botcamp')
    else
        printf('[EmuBot] Could not target %s to camp', name)
    end
end

local function action_create_bot(name, class, race, gender)
    if not name or name == '' then
        printf('[EmuBot] Bot name cannot be empty')
        return false
    end
    
    local classID = M.classIDs[class] or 1
    local raceID = M.raceIDs[race] or 1
    local genderID = M.genderIDs[gender] or 0
    
    local command = string.format('/say ^botcreate %s %d %d %d', name, classID, raceID, genderID)
    printf('[EmuBot] Creating bot: %s', command)
    mq.cmd(command)
    
    -- Schedule a delayed refresh to pick up the new bot
    if _G.enqueueTask then
        _G.enqueueTask(function()
            mq.delay(2000)
            bot_inventory.refreshBotList()
        end)
    end
    
    return true
end

function M.draw()
    -- Header controls
    if ImGui.Button('Refresh Bot List##mgmt') then
        bot_inventory.refreshBotList()
    end
    ImGui.SameLine()
    if ImGui.Button('Create New Bot##mgmt') then
        M.showCreateDialog = true
    end
    if ImGui.IsItemHovered() then
        ImGui.SetTooltip('Open bot creation dialog to create a new bot with ^botcreate')
    end
    ImGui.SameLine()
    if ImGui.Button('Spawn All##mgmt') then
        local bots = bot_inventory.getAllBots() or {}
        for _, name in ipairs(bots) do
            action_spawn(name)
        end
    end
    ImGui.SameLine()
    if ImGui.Button('Invite All##mgmt') then
        local bots = bot_inventory.getAllBots() or {}
        for _, name in ipairs(bots) do
            action_invite(name)
        end
    end
    ImGui.SameLine()
    if ImGui.Button('Camp All##mgmt') then
        local bots = bot_inventory.getAllBots() or {}
        for _, name in ipairs(bots) do
            action_camp(name)
        end
    end

    ImGui.Separator()

    local bots = bot_inventory.getAllBots() or {}
    if #bots == 0 then
        ImGui.Text('No bots found. Click "Refresh Bot List" to capture bots.')
        return
    end

    if ImGui.BeginTable('BotManagementTable', 4, ImGuiTableFlags.Borders + ImGuiTableFlags.RowBg + ImGuiTableFlags.Resizable) then
        ImGui.TableSetupColumn('Bot', ImGuiTableColumnFlags.WidthStretch)
        ImGui.TableSetupColumn('Status', ImGuiTableColumnFlags.WidthFixed, 100)
        ImGui.TableSetupColumn('Actions', ImGuiTableColumnFlags.WidthStretch)
        ImGui.TableSetupColumn('Target', ImGuiTableColumnFlags.WidthFixed, 70)
        ImGui.TableHeadersRow()

        for _, name in ipairs(bots) do
            ImGui.TableNextRow()
            ImGui.PushID('mgmt_' .. name)

            -- Bot name
            ImGui.TableNextColumn()
            ImGui.Text(name)

            -- Status
            ImGui.TableNextColumn()
            if is_bot_spawned(name) then
                ImGui.TextColored(0.2, 0.8, 0.2, 1.0, 'Spawned')
            else
                ImGui.TextColored(0.8, 0.2, 0.2, 1.0, 'Despawned')
            end

            -- Actions
            ImGui.TableNextColumn()
            if ImGui.SmallButton('Spawn') then action_spawn(name) end
            ImGui.SameLine()
            if ImGui.SmallButton('Invite') then action_invite(name) end
            ImGui.SameLine()
            if ImGui.SmallButton('Camp') then action_camp(name) end

            -- Target helper
            ImGui.TableNextColumn()
            if ImGui.SmallButton('Target') then
                target_bot(name)
            end

            ImGui.PopID()
        end

        ImGui.EndTable()
    end
    
    -- Inline Bot Creation Section
    if M.showCreateDialog then
        ImGui.Separator()
        ImGui.Text('Create New Bot:')
        
        -- Create form in a table layout for compactness
        if ImGui.BeginTable('CreateBotTable', 4, ImGuiTableFlags.None) then
            ImGui.TableSetupColumn('Label1', ImGuiTableColumnFlags.WidthFixed, 60)
            ImGui.TableSetupColumn('Input1', ImGuiTableColumnFlags.WidthFixed, 150)
            ImGui.TableSetupColumn('Label2', ImGuiTableColumnFlags.WidthFixed, 60)
            ImGui.TableSetupColumn('Input2', ImGuiTableColumnFlags.WidthFixed, 100)
            
            -- Row 1: Name and Class
            ImGui.TableNextRow()
            ImGui.TableNextColumn()
            ImGui.Text('Name:')
            ImGui.TableNextColumn()
            ImGui.PushItemWidth(-1)
            M.newBotName = ImGui.InputText('##BotName', M.newBotName or '')
            ImGui.PopItemWidth()
            ImGui.TableNextColumn()
            ImGui.Text('Class:')
            ImGui.TableNextColumn()
            ImGui.PushItemWidth(80)
            M.selectedClass = ImGui.Combo('##ClassCombo', M.selectedClass, M.classes, #M.classes)
            ImGui.PopItemWidth()
            
            -- Row 2: Race and Gender
            ImGui.TableNextRow()
            ImGui.TableNextColumn()
            ImGui.Text('Race:')
            ImGui.TableNextColumn()
            ImGui.PushItemWidth(-1)
            M.selectedRace = ImGui.Combo('##RaceCombo', M.selectedRace, M.races, #M.races)
            ImGui.PopItemWidth()
            ImGui.TableNextColumn()
            ImGui.Text('Gender:')
            ImGui.TableNextColumn()
            ImGui.PushItemWidth(80)
            M.selectedGender = ImGui.Combo('##GenderCombo', M.selectedGender, M.genders, #M.genders)
            ImGui.PopItemWidth()
            
            ImGui.EndTable()
        end
        
        -- Preview the command
        if M.newBotName and M.newBotName ~= '' then
            local selectedClassName = M.classes[M.selectedClass] or 'WAR'
            local selectedRaceName = M.races[M.selectedRace] or 'HUM'
            local selectedGenderName = M.genders[M.selectedGender] or 'Male'
            
            local classID = M.classIDs[selectedClassName] or 1
            local raceID = M.raceIDs[selectedRaceName] or 1
            local genderID = M.genderIDs[selectedGenderName] or 0
            
            local previewCommand = string.format('/say ^botcreate %s %d %d %d', 
                M.newBotName, classID, raceID, genderID)
            
            ImGui.TextColored(0.7, 0.7, 0.7, 1.0, 'Command:')
            ImGui.SameLine()
            ImGui.TextColored(0.9, 0.9, 0.5, 1.0, previewCommand)
            ImGui.SameLine()
            ImGui.TextColored(0.6, 0.6, 0.6, 1.0, string.format('(%s=%d, %s=%d, %s=%d)', 
                selectedClassName, classID, selectedRaceName, raceID, selectedGenderName, genderID))
        end
        
        -- Buttons
        local canCreate = M.newBotName and M.newBotName ~= ''
        
        if not canCreate then
            ImGui.PushStyleColor(ImGuiCol.Button, 0.5, 0.5, 0.5, 0.5)
            ImGui.PushStyleColor(ImGuiCol.ButtonHovered, 0.5, 0.5, 0.5, 0.5)
            ImGui.PushStyleColor(ImGuiCol.ButtonActive, 0.5, 0.5, 0.5, 0.5)
        end
        
        if ImGui.Button('Create Bot') then
            if canCreate then
                local selectedClassName = M.classes[M.selectedClass] or 'WAR'
                local selectedRaceName = M.races[M.selectedRace] or 'HUM'
                local selectedGenderName = M.genders[M.selectedGender] or 'Male'
                
                local success = action_create_bot(M.newBotName, selectedClassName, selectedRaceName, selectedGenderName)
                if success then
                    -- Reset form
                    M.newBotName = ''
                    M.selectedClass = 0
                    M.selectedRace = 0
                    M.selectedGender = 0
                    M.showCreateDialog = false
                end
            end
        end
        
        if not canCreate then
            ImGui.PopStyleColor(3)
        end
        
        if ImGui.IsItemHovered() and not canCreate then
            ImGui.SetTooltip('Please enter a bot name')
        end
        
        ImGui.SameLine()
        
        if ImGui.Button('Cancel') then
            M.showCreateDialog = false
            -- Reset form when canceling
            M.newBotName = ''
            M.selectedClass = 0
            M.selectedRace = 0
            M.selectedGender = 0
        end
        
        ImGui.Separator()
    end
end

return M
