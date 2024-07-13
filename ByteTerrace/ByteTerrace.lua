---@generic TemplateType
---@alias ButtonFromTemplate Button | TemplateType

local api = {
    Colors = {
        IsAwayFromKeyboard = CreateColorFromBytes(255, 255, 0, 255),
        IsInCombat = CreateColorFromBytes(255, 0, 0, 255),
        IsNeutral = CreateColorFromBytes(0, 255, 0, 255),
    },
    Console = {},
    Events = {},
    System = {},
    UserInterface = {},
}
local eventFrame = CreateFrame("Frame", "ByteTerraceEventFrame", UIParent, "SecureHandlerBaseTemplate")
---@type table<string, table<function, function>>
local eventMap = {}
local hiddenFrame = CreateFrame("Frame", "ByteTerraceHiddenFrame", UIParent, "SecureHandlerStateTemplate")

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
