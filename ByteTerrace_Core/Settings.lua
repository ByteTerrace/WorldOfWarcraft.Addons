-- Settings: the options panel is generated from the state schema. Every persisted row with a
-- label gets a control, in declaration order: a checkbox for booleans, a dropdown for enums.
-- Controls are proxy settings, so a change from the panel goes through State:Set like any other
-- write and reaches the same watchers.

local ByteTerrace = ByteTerrace
local Refuse = ByteTerrace.Refuse
local Settings = Settings
local ipairs = ipairs

function ByteTerrace.BuildSettings(addon)
    local state, problems = addon.state, {}
    local category = Settings.RegisterVerticalLayoutCategory(addon.title)
    for _, name in ipairs(state.order) do
        local id = state.ids[name]
        local spec = state.specs[id]
        if spec.label and spec.persist then
            local setting = Settings.RegisterProxySetting(category, addon.name .. "_" .. name, spec.kind, spec.label,
                spec.default, function() return state.values[id] end, function(value) state:Set(id, value) end)
            if spec.values then
                local function GetOptions()
                    local container = Settings.CreateControlTextContainer()
                    for _, value in ipairs(spec.values) do
                        container:Add(value, spec.valueLabels and spec.valueLabels[value] or value)
                    end
                    return container:GetData()
                end
                Settings.CreateDropdown(category, setting, GetOptions, spec.description)
            elseif spec.kind == "boolean" then
                Settings.CreateCheckbox(category, setting, spec.description)
            else
                problems[#problems + 1] = name .. ": no settings control for a labeled " .. spec.kind .. " row"
            end
        end
    end
    Refuse(addon.name .. " settings", problems)
    Settings.RegisterAddOnCategory(category)
    return category:GetID()
end
