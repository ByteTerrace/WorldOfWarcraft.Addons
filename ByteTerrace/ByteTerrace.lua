---@generic TemplateType
---@alias ButtonFromTemplate Button | TemplateType

GAMEPAD_GENERIC = 0
GAMEPAD_MICROSOFT_XBOX_SERIESX = 1
GAMEPAD_NINTENDO_SWITCH_PRO = 2
GAMEPAD_SONY_PLAYSTATION_DUALSENSE5 = 3

local api = {
    Colors = {
        AwayFromKeyboard = CreateColorFromBytes(255, 255, 0, 255),
        InCombat = CreateColorFromBytes(255, 0, 0, 255),
        Neutral = CreateColorFromBytes(0, 255, 0, 255),
    },
    Console = {},
    Events = {},
    GamePad = {},
    System = {},
    UserInterface = {},
}
local eventFrame = CreateFrame("Frame", "ByteTerraceEventFrame", UIParent, "SecureHandlerBaseTemplate")
---@type table<string, table<function, function>>
local eventMap = {}
local hiddenFrame = CreateFrame("Frame", "ByteTerraceHiddenFrame", UIParent, "SecureHandlerStateTemplate")
---@type table<integer, table<string, any>>
local knownGamePadTypes = {
    [GAMEPAD_GENERIC] = {
        BindingOverrides = {},
    },
    [GAMEPAD_MICROSOFT_XBOX_SERIESX] = {
        BindingOverrides = {},
    },
    [GAMEPAD_NINTENDO_SWITCH_PRO] = {
        BindingOverrides = {},
    },
    [GAMEPAD_SONY_PLAYSTATION_DUALSENSE5] = {
        BindingOverrides = {
            ["PADBACK"] = "PADSOCIAL",
        },
    },
}
---@type table<integer, integer>
local vendorIdToGamePadTypeMap = {
    [1118] = GAMEPAD_MICROSOFT_XBOX_SERIESX,
    [1356] = GAMEPAD_SONY_PLAYSTATION_DUALSENSE5,
    [1406] = GAMEPAD_NINTENDO_SWITCH_PRO,
}

---@param variableMap table<string, string|number>
function api.Console.SetVariables(variableMap)
    for key, value in pairs(variableMap) do
        local valueType = type(value)

        if ("boolean" == valueType) then
            value = (value and "1" or "0")
        elseif ("number" == valueType) then
            value = tostring(value)
        end

        C_CVar.SetCVar(key, value)
    end
end
---@param eventHandlerMap table<string, function>
function api.Events.Register(eventHandlerMap)
    for eventName, eventHandler in pairs(eventHandlerMap) do
        local handlerMap = eventMap[eventName]

        if (nil == handlerMap) then
            eventFrame:RegisterEvent(eventName)

            handlerMap = {}
            eventMap[eventName] = handlerMap
        end

        handlerMap[eventHandler] = eventHandler
    end
end
---@param deviceId integer
---@return integer, table<string, any>
function api.GamePad.GetType(deviceId)
    local gamePadId
    local gamePadType = knownGamePadTypes[0]
    local rawState = C_GamePad.GetDeviceRawState(deviceId)

    if (nil ~= rawState) then
        gamePadId = vendorIdToGamePadTypeMap[rawState.vendorID]
        gamePadType = knownGamePadTypes[gamePadId]
    end

    return gamePadId, gamePadType
end
function api.System.IsClassic()
    return (WOW_PROJECT_CLASSIC == WOW_PROJECT_ID)
end
function api.System.IsMainline()
    return (WOW_PROJECT_MAINLINE == WOW_PROJECT_ID)
end
---@param object ScriptRegion
function api.UserInterface.ForceHide(object)
    object:SetParent(hiddenFrame --[[@as Frame]])
end

eventFrame:HookScript("OnEvent", function (_, eventName, ...)
    local handlerMap = eventMap[eventName]

    for _, eventHandler in pairs(handlerMap) do
        eventHandler(...)

        if ("ADDON_LOADED" == eventName) then
            handlerMap[eventHandler] = nil
        end
    end
end)
hiddenFrame:Hide()

_G["ByteTerrace"] = api
