local mock_mq = require('spec.support.mock_mq')
local mock_imgui = require('spec.support.mock_imgui')

local function register_globals()
    package.loaded['mq'] = mock_mq
    package.loaded['mq.imgui'] = mock_mq.imgui
    package.loaded['mq.icons'] = mock_mq.icons
    _G.mq = mock_mq

    package.loaded['ImGui'] = mock_imgui
    _G.ImGui = mock_imgui

    for name, value in pairs(mock_imgui.constants) do
        package.loaded[name] = value
        _G[name] = value
    end

    package.loaded['ImVec2'] = mock_imgui.ImVec2
    _G.ImVec2 = mock_imgui.ImVec2
end

local function setup_mocks()
    mock_mq.reset()
    mock_imgui.reset()
    register_globals()
    return mock_mq, mock_imgui
end

local function reset_mocks()
    mock_mq.reset()
    mock_imgui.reset()
    if mock_mq.imgui and mock_mq.imgui.reset then
        mock_mq.imgui.reset()
    end
    return mock_mq, mock_imgui
end

return {
    mock_mq = mock_mq,
    mock_imgui = mock_imgui,
    setup_mocks = setup_mocks,
    reset_mocks = reset_mocks,
    register_globals = register_globals,
}
