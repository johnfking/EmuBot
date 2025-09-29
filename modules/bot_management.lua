-- emubot/modules/bot_management.lua
-- Simple bot management tab: list bots with quick actions (spawn, invite to group, camp)

local mq = require('mq')
local bot_inventory = require('EmuBot.modules.bot_inventory')

local M = {}

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

function M.draw()
    -- Header controls
    if ImGui.Button('Refresh Bot List##mgmt') then
        bot_inventory.refreshBotList()
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
end

return M
