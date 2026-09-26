-- Settings: the settings pages, generated from the state schema. ByteTerrace.SettingsPages lays
-- them out once; ByteTerrace.BuildSettings registers them with Blizzard's settings panel (the
-- AddOns tab) and SettingsWindow.lua draws the addon's own window from the same pages.
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
--
-- Addon code never opens Blizzard's panel: opening it taints the panel, so its close runs
-- ToggleGameMenu tainted and protected calls are blocked; with Forever's controller UI on, the
-- blocked-action popups then loop until the client freezes (tools/api/forbidden.json). The player
-- reaches these pages through Esc > Options > AddOns, and the addon's own command opens its window.

local ByteTerrace = ByteTerrace
local CreateSettingsListSectionHeaderInitializer, Settings = CreateSettingsListSectionHeaderInitializer, Settings
local ipairs = ipairs

--- The addon's settings pages, in order: the main page (named by the addon's title), then each
--- subcategory page in the order its first setting is declared. A page is { name, entries }, and
--- an entry is { header = text } or { id, name, spec } for a setting row.
---@param addon table the AddOn, compiled
---@return table[] pages
local function SettingsPages(addon)
    local state = addon.State
    local main = { name = addon.Title, entries = {} }
    local pages, byName = { main }, {}
    local function AddHeader(page, text)
        if text and text ~= page.name then
            page.entries[#page.entries + 1] = { header = text }
        end
    end
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
                page = byName[pageName]
                if not page then
                    page = { name = pageName, entries = {} }
                    byName[pageName] = page
                    pages[#pages + 1] = page
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
            page.entries[#page.entries + 1] = { id = id, name = name, spec = spec }
        end
    end
    for _, page in ipairs(pages) do
        page.module = nil
    end
    return pages
end

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

--- Registers the addon's settings category, its subcategory pages and every control with
--- Blizzard's settings panel. Runs once, after the state compiles.
---@param addon table the AddOn
---@param pages table[] from SettingsPages
local function BuildSettings(addon, pages)
    local category
    for i, page in ipairs(pages) do
        local pageCategory, pageLayout
        if i == 1 then
            category, pageLayout = Settings.RegisterVerticalLayoutCategory(page.name)
            pageCategory = category
        else
            pageCategory, pageLayout = Settings.RegisterVerticalLayoutSubcategory(category, page.name)
        end
        for _, entry in ipairs(page.entries) do
            if entry.header then
                pageLayout:AddInitializer(CreateSettingsListSectionHeaderInitializer(entry.header))
            else
                AddControl(pageCategory, AddSetting(addon, pageCategory, entry.name, entry.id, entry.spec), entry.spec)
            end
        end
    end
    Settings.RegisterAddOnCategory(category)
end

ByteTerrace.SettingsPages = SettingsPages
ByteTerrace.BuildSettings = BuildSettings
