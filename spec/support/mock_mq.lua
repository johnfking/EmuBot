local mock_mq = {}

local unpack = table.unpack or unpack

-- Internal state for commands, events, and fixtures
local state = {}

-- Sentinel used to represent an explicit nil return for TLO calls
local TLO_NIL = {}

local function new_tlo_node()
    return {
        value = nil,
        has_value = false,
        children = {},
        proxy = nil,
    }
end

local function reset_state()
    state.commands = {}
    state.commandf = {}
    state.delays = {}
    state.delay_handler = nil
    state.delay_results = {}
    state.doevents_calls = {}
    state.doevents_handler = nil
    state.printf_log = {}
    state.events = {}
    state.event_log = {}
    state.binds = {}
    state.bind_log = {}
    state.unbind_log = {}
    state.event_fire_log = {}
    state.extract_links_log = {}
    state.extract_links_handler = nil
    state.parse_item_link_log = {}
    state.parse_item_link_handler = nil
    state.execute_text_link_log = {}
    state.gettime_handler = nil
    state.gettime_log = {}
    state.lua_dir = './lua'
    state.config_dir = './config'
    state.texture_animations = {}
    state.texture_animation_log = {}
    state.imgui_registry = {}
    state.imgui_log = {}
    state.link_types = {
        Item = 'item',
        Spell = 'spell',
        Augment = 'augment',
        Unknown = 'unknown',
    }
    state.icon_store = {}
end

reset_state()
mock_mq.configDir = state.config_dir

local tlo_root = new_tlo_node()

local function create_tlo_proxy(node)
    if node.proxy then return node.proxy end
    local proxy = {}
    setmetatable(proxy, {
        __call = function(_, ...)
            if node.has_value then
                if node.value == TLO_NIL then
                    return nil
                end
                if type(node.value) == 'function' then
                    return node.value(...)
                end
                return node.value
            end
            return nil
        end,
        __index = function(_, key)
            local child = node.children[key]
            if not child then
                child = new_tlo_node()
                if node.has_value and type(node.value) == 'table' then
                    local child_value = node.value[key]
                    if child_value ~= nil then
                        child.value = child_value
                        child.has_value = true
                    end
                end
                node.children[key] = child
            end
            return create_tlo_proxy(child)
        end,
    })
    node.proxy = proxy
    return proxy
end

mock_mq.TLO = create_tlo_proxy(tlo_root)
mock_mq.NULL = setmetatable({}, { __tostring = function() return 'mock_mq.NULL' end })

local function traverse_path(path, create_missing)
    assert(type(path) == 'string' and path ~= '', 'path must be a non-empty string')
    local node = tlo_root
    local parent = nil
    local last_key = nil
    for part in string.gmatch(path, '[^%.]+') do
        parent = node
        last_key = part
        local child = node.children[part]
        if not child then
            if not create_missing then
                return nil, parent, last_key
            end
            child = new_tlo_node()
            node.children[part] = child
        end
        node = child
    end
    return node, parent, last_key
end

function mock_mq.set_tlo(path, value)
    local node, parent, key = traverse_path(path, true)
    if value == nil then
        -- Clearing the node resets its value and children
        local replacement = new_tlo_node()
        if parent and key then
            parent.children[key] = replacement
            node = replacement
        else
            tlo_root = replacement
            mock_mq.TLO = create_tlo_proxy(tlo_root)
        end
        return
    end
    if value == mock_mq.NULL then
        node.value = TLO_NIL
        node.has_value = true
    else
        node.value = value
        node.has_value = true
    end
    node.children = {}
    -- Reset cached proxy so new value is reflected when accessed
    node.proxy = nil
end

function mock_mq.get_tlo(path)
    local node = traverse_path(path, false)
    if not node or not node.has_value then return nil end
    if node.value == TLO_NIL then return nil end
    return node.value
end

function mock_mq.clear_tlo(path)
    mock_mq.set_tlo(path, nil)
end

local function reset_tlo_node(node)
    node.value = nil
    node.has_value = false
    for _, child in pairs(node.children) do
        reset_tlo_node(child)
    end
    node.children = {}
    node.proxy = nil
end

function mock_mq.reset_tlo()
    reset_tlo_node(tlo_root)
end

function mock_mq.reset_state()
    reset_state()
    mock_mq.configDir = state.config_dir
end

function mock_mq.reset()
    mock_mq.reset_state()
    mock_mq.reset_tlo()
end

function mock_mq.get_state()
    return state
end

function mock_mq.cmd(command)
    table.insert(state.commands, command)
end

function mock_mq.get_cmd_calls()
    return state.commands
end

function mock_mq.cmdf(fmt, ...)
    local ok, formatted = pcall(string.format, fmt, ...)
    if not ok then
        formatted = fmt
    end
    table.insert(state.commandf, { fmt = fmt, args = { ... }, output = formatted })
    table.insert(state.commands, formatted)
end

function mock_mq.get_cmdf_calls()
    return state.commandf
end

function mock_mq.printf(fmt, ...)
    local ok, rendered = pcall(string.format, fmt, ...)
    if not ok then
        rendered = fmt
    end
    table.insert(state.printf_log, { fmt = fmt, args = { ... }, output = rendered })
end

function mock_mq.get_printf_log()
    return state.printf_log
end

function mock_mq.set_delay_handler(handler)
    state.delay_handler = handler
end

function mock_mq.delay(duration, predicate)
    local entry = { duration = duration, predicate = predicate }
    table.insert(state.delays, entry)
    if state.delay_handler then
        entry.result = state.delay_handler(duration, predicate)
        return entry.result
    end
    if predicate then
        local ok, result = pcall(predicate)
        entry.result = ok and result or false
        return entry.result
    end
    entry.result = true
    return true
end

function mock_mq.get_delay_calls()
    return state.delays
end

function mock_mq.set_doevents_handler(handler)
    state.doevents_handler = handler
end

function mock_mq.doevents()
    table.insert(state.doevents_calls, os.clock())
    if state.doevents_handler then
        return state.doevents_handler()
    end
    return true
end

function mock_mq.get_doevents_calls()
    return state.doevents_calls
end

function mock_mq.event(name, pattern, callback)
    state.events[name] = { pattern = pattern, callback = callback }
    table.insert(state.event_log, { action = 'register', name = name, pattern = pattern, callback = callback })
end

function mock_mq.unevent(name)
    if state.events[name] then
        state.events[name] = nil
    end
    table.insert(state.event_log, { action = 'unregister', name = name })
end

function mock_mq.get_events()
    return state.events
end

function mock_mq.get_event_log()
    return state.event_log
end

function mock_mq.trigger_event(name, ...)
    local entry = state.events[name]
    if not entry then return nil end
    table.insert(state.event_fire_log, { name = name, args = { ... } })
    if entry.callback then
        return entry.callback(...)
    end
    return nil
end

function mock_mq.get_triggered_events()
    return state.event_fire_log
end

function mock_mq.bind(command, handler)
    state.binds[command] = handler
    table.insert(state.bind_log, { command = command, handler = handler })
end

function mock_mq.unbind(command)
    if state.binds[command] then
        state.binds[command] = nil
    end
    table.insert(state.unbind_log, { command = command })
end

function mock_mq.get_binds()
    return state.binds
end

function mock_mq.get_bind_log()
    return state.bind_log
end

function mock_mq.get_unbind_log()
    return state.unbind_log
end

function mock_mq.invoke_bind(command, ...)
    local handler = state.binds[command]
    if handler then
        return handler(...)
    end
    return nil
end

function mock_mq.set_extract_links(handler)
    state.extract_links_handler = handler
end

function mock_mq.ExtractLinks(link)
    table.insert(state.extract_links_log, link)
    if state.extract_links_handler then
        if type(state.extract_links_handler) == 'function' then
            return state.extract_links_handler(link)
        end
        return state.extract_links_handler
    end
    return {}
end

function mock_mq.get_extract_links_calls()
    return state.extract_links_log
end

function mock_mq.set_parse_item_link(handler)
    state.parse_item_link_handler = handler
end

function mock_mq.ParseItemLink(link)
    table.insert(state.parse_item_link_log, link)
    if state.parse_item_link_handler then
        if type(state.parse_item_link_handler) == 'function' then
            return state.parse_item_link_handler(link)
        end
        return state.parse_item_link_handler
    end
    return nil
end

function mock_mq.get_parse_item_link_calls()
    return state.parse_item_link_log
end

function mock_mq.ExecuteTextLink(link)
    table.insert(state.execute_text_link_log, link)
end

function mock_mq.get_execute_text_link_calls()
    return state.execute_text_link_log
end

local function new_texture_animation(name)
    local anim = { name = name, calls = {} }
    function anim:SetTextureCell(index)
        table.insert(self.calls, index)
        self.last_index = index
    end
    function anim:reset()
        self.calls = {}
        self.last_index = nil
    end
    return anim
end

function mock_mq.set_texture_animation(name, anim)
    state.texture_animations[name] = anim
end

function mock_mq.FindTextureAnimation(name)
    local anim = state.texture_animations[name]
    if not anim then
        anim = new_texture_animation(name)
        state.texture_animations[name] = anim
    end
    table.insert(state.texture_animation_log, name)
    return anim
end

function mock_mq.get_texture_animation(name)
    return state.texture_animations[name]
end

function mock_mq.get_texture_animation_calls()
    return state.texture_animation_log
end

function mock_mq.set_time_handler(handler)
    state.gettime_handler = handler
end

function mock_mq.gettime()
    table.insert(state.gettime_log, true)
    if state.gettime_handler then
        return state.gettime_handler()
    end
    return os.clock()
end

function mock_mq.get_gettime_calls()
    return state.gettime_log
end

function mock_mq.set_config_dir(path)
    state.config_dir = path
    mock_mq.configDir = path
end

function mock_mq.set_lua_dir(path)
    state.lua_dir = path
end

function mock_mq.luaDir()
    return state.lua_dir
end

local icons_proxy = setmetatable({}, {
    __index = function(_, key)
        if state.icon_store[key] == nil then
            state.icon_store[key] = key
        end
        return state.icon_store[key]
    end,
    __newindex = function(_, key, value)
        state.icon_store[key] = value
    end,
    __pairs = function()
        return pairs(state.icon_store)
    end,
})

mock_mq.icons = icons_proxy

local link_types_proxy = setmetatable({}, {
    __index = function(_, key)
        return state.link_types[key]
    end,
    __newindex = function(_, key, value)
        state.link_types[key] = value
    end,
    __pairs = function()
        return pairs(state.link_types)
    end,
})

mock_mq.LinkTypes = link_types_proxy

local mq_imgui = {}

function mq_imgui.init(name, draw_fn)
    state.imgui_registry[name] = { callback = draw_fn }
    table.insert(state.imgui_log, { action = 'init', name = name, callback = draw_fn })
    return true
end

function mq_imgui.destroy(name)
    if state.imgui_registry[name] then
        state.imgui_registry[name] = nil
        table.insert(state.imgui_log, { action = 'destroy', name = name })
    end
end

function mq_imgui.draw(name, ...)
    local entry = state.imgui_registry[name]
    if entry and entry.callback then
        return entry.callback(...)
    end
    return nil
end

function mq_imgui.list()
    local result = {}
    for key, value in pairs(state.imgui_registry) do
        table.insert(result, { name = key, callback = value.callback })
    end
    table.sort(result, function(a, b) return tostring(a.name) < tostring(b.name) end)
    return result
end

function mq_imgui.reset()
    state.imgui_registry = {}
    state.imgui_log = {}
end

mock_mq.imgui = mq_imgui

function mock_mq.get_imgui_registry()
    return state.imgui_registry
end

function mock_mq.get_imgui_log()
    return state.imgui_log
end

return mock_mq
