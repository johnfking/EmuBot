local mock_imgui = {}

local unpack = table.unpack or unpack

local state = {}

local function reset_state()
    state.calls = {}
    state.call_sequence = {}
    state.return_queue = {}
    state.default_returns = {}
    state.handlers = {}
end

reset_state()

local function clone_table(value)
    if type(value) ~= 'table' then return value end
    local copy = {}
    for k, v in pairs(value) do
        copy[k] = clone_table(v)
    end
    return copy
end

local function record_call(name, args)
    if not state.calls[name] then
        state.calls[name] = {}
    end
    table.insert(state.calls[name], { args = args })
    table.insert(state.call_sequence, { name = name, args = args })
end

local function resolve_return(name, args)
    local queue = state.return_queue[name]
    if queue and #queue > 0 then
        local entry = table.remove(queue, 1)
        return entry
    end
    local handler = state.handlers[name]
    if handler then
        return { handler(table.unpack(args)) }
    end
    local default = state.default_returns[name]
    if default == nil then return nil end
    if type(default) == 'function' then
        return { default(table.unpack(args)) }
    end
    return default
end

local function unpack_return(ret)
    if not ret then return nil end
    if type(ret) ~= 'table' then
        return ret
    end
    local prepared = {}
    for i = 1, #ret do
        prepared[i] = clone_table(ret[i])
    end
    return unpack(prepared)
end

local function normalize_values(...)
    local n = select('#', ...)
    if n == 0 then return {} end
    local values = { ... }
    return values
end

function mock_imgui.set_next_return(name, ...)
    if not state.return_queue[name] then
        state.return_queue[name] = {}
    end
    table.insert(state.return_queue[name], normalize_values(...))
end

function mock_imgui.set_default_return(name, ...)
    state.default_returns[name] = normalize_values(...)
end

function mock_imgui.set_handler(name, handler)
    state.handlers[name] = handler
end

function mock_imgui.clear_handler(name)
    state.handlers[name] = nil
end

function mock_imgui.get_calls(name)
    return state.calls[name] or {}
end

function mock_imgui.get_call_sequence()
    return state.call_sequence
end

function mock_imgui.clear_calls(name)
    if name then
        state.calls[name] = nil
    else
        state.calls = {}
        state.call_sequence = {}
    end
end

local draw_list_calls = {}

local draw_list = {}

local function log_draw_call(method, args)
    table.insert(draw_list_calls, { method = method, args = args })
end

function draw_list:AddQuadFilled(...)
    log_draw_call('AddQuadFilled', { ... })
end

function draw_list:AddQuad(...)
    log_draw_call('AddQuad', { ... })
end

function draw_list:AddNgonFilled(...)
    log_draw_call('AddNgonFilled', { ... })
end

function draw_list:AddNgon(...)
    log_draw_call('AddNgon', { ... })
end

function draw_list:AddTriangleFilled(...)
    log_draw_call('AddTriangleFilled', { ... })
end

function draw_list:AddTriangle(...)
    log_draw_call('AddTriangle', { ... })
end

function draw_list:AddRectFilled(...)
    log_draw_call('AddRectFilled', { ... })
end

function draw_list:AddRect(...)
    log_draw_call('AddRect', { ... })
end

function mock_imgui.get_draw_list_calls()
    return draw_list_calls
end

function mock_imgui.reset_draw_list()
    draw_list_calls = {}
end

local function apply_initial_defaults()
    mock_imgui.reset_draw_list()
    state.return_queue = {}
    state.handlers = {}
    state.default_returns = {}

    mock_imgui.set_default_return('Begin', true, true)
    mock_imgui.set_default_return('BeginChild', false)
    mock_imgui.set_default_return('BeginTabBar', false)
    mock_imgui.set_default_return('BeginTabItem', false)
    mock_imgui.set_default_return('BeginTable', false)
    mock_imgui.set_default_return('BeginMenuBar', false)
    mock_imgui.set_default_return('BeginMenu', false)
    mock_imgui.set_default_return('BeginPopupContextWindow', false)
    mock_imgui.set_default_return('BeginPopupContextItem', false)
    mock_imgui.set_default_return('BeginPopupModal', false)
    mock_imgui.set_default_return('BeginTooltip', true)
    mock_imgui.set_default_return('Button', false)
    mock_imgui.set_default_return('SmallButton', false)
    mock_imgui.set_default_return('InvisibleButton', false)
    mock_imgui.set_handler('Checkbox', function(_, value) return value, false end)
    mock_imgui.set_handler('Combo', function(_, current) return current, false end)
    mock_imgui.set_handler('ColorEdit4', function(_, color) return color, false end)
    mock_imgui.set_handler('InputText', function(_, value) return value, false end)
    mock_imgui.set_handler('InputTextMultiline', function(_, value) return value, false end)
    mock_imgui.set_handler('InputTextWithHint', function(_, _, value) return value, false end)
    mock_imgui.set_handler('SliderFloat', function(_, value) return value, false end)
    mock_imgui.set_handler('SliderInt', function(_, value) return value, false end)
    mock_imgui.set_default_return('CollapsingHeader', false)
    mock_imgui.set_default_return('TreeNode', false)
    mock_imgui.set_default_return('Selectable', false)
    mock_imgui.set_default_return('MenuItem', false)
    mock_imgui.set_default_return('IsItemHovered', false)
    mock_imgui.set_default_return('IsItemActive', false)
    mock_imgui.set_default_return('IsItemClicked', false)
    mock_imgui.set_default_return('IsMouseClicked', false)
    mock_imgui.set_default_return('IsWindowHovered', false)
    mock_imgui.set_default_return('GetStyle', { ItemSpacing = { x = 4, y = 4 } })
    mock_imgui.set_default_return('GetTextLineHeight', 14)
    mock_imgui.set_default_return('GetWindowDrawList', draw_list)
    mock_imgui.set_default_return('GetWindowWidth', 600)
    mock_imgui.set_default_return('GetWindowHeight', 400)
    mock_imgui.set_default_return('GetContentRegionAvail', 0, 0)
    mock_imgui.set_default_return('GetCursorPosY', 0)
    mock_imgui.set_default_return('GetItemRectMin', { x = 0, y = 0 })
    mock_imgui.set_default_return('GetItemRectMax', { x = 0, y = 0 })
    mock_imgui.set_default_return('GetWindowPosVec', { x = 0, y = 0 })
    mock_imgui.set_default_return('GetWindowPos', { x = 0, y = 0 })
    mock_imgui.set_default_return('CalcTextSize', { x = 0, y = 0 })
    mock_imgui.set_default_return('GetColorU32', 0)
end

local stubs = {}

local function get_stub(name)
    local fn = stubs[name]
    if fn then return fn end
    fn = function(...)
        local args = { ... }
        record_call(name, args)
        local ret = resolve_return(name, args)
        return unpack_return(ret)
    end
    stubs[name] = fn
    return fn
end

setmetatable(mock_imgui, {
    __index = function(_, key)
        return get_stub(key)
    end,
})

function mock_imgui.reset()
    reset_state()
    stubs = {}
    apply_initial_defaults()
    if mock_imgui.mq_imgui then
        mock_imgui.mq_imgui.reset()
    end
end

mock_imgui.ImVec2 = function(x, y)
    return { x = x, y = y }
end

mock_imgui.constants = {
    ImGuiCond = {
        None = 0,
        FirstUseEver = 1,
        Always = 2,
    },
    ImGuiCol = {
        Text = 0,
        Button = 1,
        ButtonHovered = 2,
        ButtonActive = 3,
        WindowBg = 4,
        Border = 5,
    },
    ImGuiMouseButton = {
        Left = 0,
        Right = 1,
    },
    ImGuiWindowFlags = {
        None = 0,
        NoTitleBar = 1,
        NoResize = 2,
        NoScrollbar = 4,
        NoScrollWithMouse = 8,
        NoCollapse = 16,
        AlwaysAutoResize = 32,
        NoBackground = 64,
        NoDecoration = 128,
        MenuBar = 256,
        NoMove = 512,
    },
    ImGuiTabBarFlags = {
        Reorderable = 1,
    },
    ImGuiSelectableFlags = {
        None = 0,
    },
    ImGuiTableFlags = {
        None = 0,
        Borders = 1,
        RowBg = 2,
        Resizable = 4,
        Sortable = 8,
        SizingFixedFit = 16,
        BordersOuter = 32,
        BordersV = 64,
        BordersOuterH = 128,
    },
    ImGuiTableColumnFlags = {
        WidthStretch = 1,
        WidthFixed = 2,
    },
    ImGuiTableRowFlags = {
        None = 0,
    },
    ImGuiStyleVar = {
        WindowRounding = 0,
        ChildRounding = 1,
        FrameRounding = 2,
        GrabRounding = 3,
        TabRounding = 4,
        PopupRounding = 5,
        ScrollbarRounding = 6,
        WindowPadding = 7,
        WindowBorderSize = 8,
        FramePadding = 9,
        FrameBorderSize = 10,
        ItemSpacing = 11,
        CellPadding = 12,
    },
    ImGuiTreeNodeFlags = {
        None = 0,
        DefaultOpen = 1,
    },
    ImGuiChildFlags = {
        Border = 1,
    },
    ImGuiColorEditFlags = {
        NoInputs = 1,
        NoLabel = 2,
        NoOptions = 4,
        AlphaBar = 8,
        DisplayRGB = 16,
        InputRGB = 32,
    },
}

mock_imgui.mq_imgui = {
    init = function(name, draw_fn)
        record_call('mq.imgui.init', { name, draw_fn })
        mock_imgui.mq_imgui._registry[name] = draw_fn
        return true
    end,
    destroy = function(name)
        record_call('mq.imgui.destroy', { name })
        mock_imgui.mq_imgui._registry[name] = nil
    end,
    draw = function(name, ...)
        local fn = mock_imgui.mq_imgui._registry[name]
        if fn then
            return fn(...)
        end
        return nil
    end,
    list = function()
        local entries = {}
        for key, fn in pairs(mock_imgui.mq_imgui._registry) do
            table.insert(entries, { name = key, callback = fn })
        end
        table.sort(entries, function(a, b) return tostring(a.name) < tostring(b.name) end)
        return entries
    end,
    reset = function()
        mock_imgui.mq_imgui._registry = {}
    end,
    _registry = {},
}

mock_imgui.reset()

return mock_imgui
