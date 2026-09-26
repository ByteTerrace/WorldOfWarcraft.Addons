-- Settings: the options panel, generated from the state schema by ByteTerrace.BuildSettings
-- when the addon starts.
--
-- Every persisted row with a label gets a control, in declaration order: a checkbox for booleans,
-- a dropdown for enums, a slider for bounded numbers (State:Compile refuses a labeled row with no
-- fitting control). Controls are proxy settings, so a change from the panel goes through
-- State:Set like any other write; a change from anywhere else (slash, bindings, rules) refreshes
-- the control.
--
-- Pages: the addon's own category, named by its title, is the main page. A module whose spec
-- has page = "<name>" puts its settings on a subcategory of that name instead; subcategories are
-- created in the order their first settings are declared. On its page, a module's settings sit
-- under a section header: spec.section, or else the module's label. A row with
-- section = "<text>" starts a new header before that row. A header that would repeat its page's
-- name is left out. Only the main category is registered with RegisterAddOnCategory; the client
-- lists its subcategories under it.

local ByteTerrace = ByteTerrace
local CreateSettingsListSectionHeaderInitializer, Settings = CreateSettingsListSectionHeaderInitializer, Settings
local ipairs = ipairs

-- Settings.CreateCheckbox, CreateDropdown and CreateSlider add their control to the category's
-- layout themselves (Blizzard_Settings.lua), so controls and headers keep the order they're made in.
local function AddControl(category, setting, spec)
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
        local options = Settings.CreateSliderOptions(spec.min, spec.max, spec.step or 1)
        options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right)
        Settings.CreateSlider(category, setting, options, spec.description)
    end
end

-- A proxy setting for row id: reads the row, and writes through State:Set unless it's locked.
local function AddSetting(addon, category, name, id, spec)
    local state = addon.State
    local variable = addon.Name .. "_" .. name
    local fromPanel = false
    local setting = Settings.RegisterProxySetting(category, variable, spec.kind, spec.label, spec.default,
        function() return state.Values[id] end,
        function(value)
            if state:IsLocked(id) then
                addon:Print(spec.label .. " is locked.")
                Settings.NotifyUpdate(variable) -- show the unchanged value again
                return
            end
            fromPanel = true -- the panel already knows; don't notify it back
            local ok, err = pcall(state.Set, state, id, value)
            fromPanel = false
            if not ok then
                Settings.NotifyUpdate(variable)
                error(err, 0)
            end
        end)
    state:Watch({ id }, function()
        if not fromPanel then
            Settings.NotifyUpdate(variable)
        end
    end, true)
    return setting
end

local function AddHeader(page, text)
    if text and text ~= page.name then
        page.layout:AddInitializer(CreateSettingsListSectionHeaderInitializer(text))
    end
end

--- Builds and registers the addon's settings category, its subcategory pages and every control.
--- Runs once, after the state compiles.
---@param addon table the AddOn
---@return integer categoryID for Settings.OpenToCategory
function ByteTerrace.BuildSettings(addon)
    local state = addon.State
    local category, layout = Settings.RegisterVerticalLayoutCategory(addon.Title)
    local main = { name = addon.Title, category = category, layout = layout }
    local pages = {}
    for _, name in ipairs(state.Order) do
        local id = state.Ids[name]
        local spec = state.Specs[id]
        if spec.label and spec.persist then
            local moduleName = name:match("^([^.]+)%.")
            local module = addon.Modules[moduleName]
            local moduleSpec = module and module.Spec
            local pageName = moduleSpec and moduleSpec.page
            local page = main
            if pageName then
                page = pages[pageName]
                if not page then
                    local subcategory, subLayout = Settings.RegisterVerticalLayoutSubcategory(category, pageName)
                    page = { name = pageName, category = subcategory, layout = subLayout }
                    pages[pageName] = page
                end
            end
            if page.module ~= moduleName then
                page.module = moduleName
                if moduleSpec then
                    AddHeader(page, moduleSpec.section or moduleSpec.label)
                end
            end
            if spec.section then
                AddHeader(page, spec.section)
            end
            AddControl(page.category, AddSetting(addon, page.category, name, id, spec), spec)
        end
    end
    Settings.RegisterAddOnCategory(category)
    return category:GetID()
end
