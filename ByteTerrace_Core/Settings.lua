-- Settings: ByteTerrace.SettingsPages lays out pages from the state schema, and SettingsWindow.lua draws them in the
-- addon's own window. Labeled persisted rows appear in declaration order.
--
-- The main page is named by the addon's title. A module's page puts its settings on a subpage of that name; subpages
-- appear in first-declared order. A module's section, or else its label, supplies its section header. A row's section
-- starts a header before that row. A header that repeats its page's name is left out.
--
-- Blizzard's settings panel gets no controls of the addon's: its controller navigation freezes the client on addon-made
-- controls (evidence: tools/api/forbidden.json). SettingsWindow.lua shows the same view there instead, as a canvas page
-- the controller UI ignores.

local ByteTerrace = ByteTerrace
local ipairs = ipairs

--- The page layout the addon's window draws: the main page (named by the addon's title), then each subpage in the order
--- its first setting is declared. A page is { name, entries }, and an entry is { header = text } or { id, name, spec }
--- for a setting row.
---@param addon table the AddOn, compiled
---@return table[] pages
local function SettingsPages(addon)
    local state = addon.State
    local main = { entries = {}, name = addon.Title }
    local pages, byName = { main }, {}

    local function AddHeader(page, text)
        if text and (text ~= page.name) then
            page.entries[#page.entries + 1] = { header = text }
        end
    end

    for _, name in ipairs(state.Order) do
        local id = state.Ids[name]
        local spec = state.Specs[id]

        if spec.label and spec.persist then
            local moduleName = name:match("^([^.]+)%.")
            local module = addon.Modules[moduleName]
            local moduleSpec = (module and module.Spec)
            local pageName = (moduleSpec and moduleSpec.page)
            local page = main

            -- a page named for the addon is the main page
            if pageName and (pageName ~= addon.Title) then
                page = byName[pageName]

                if not page then
                    page = { entries = {}, name = pageName }
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

ByteTerrace.SettingsPages = SettingsPages
