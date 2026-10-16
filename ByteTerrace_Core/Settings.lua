-- Settings: ByteTerrace.SettingsPages lays out pages from the state schema, and SettingsWindow.lua draws them in the
-- addon's own window. Every labeled persisted row appears, organized so a player finds a setting by name:
--
--   Pages     the main page, named by the addon's title, comes first; the other pages follow in
--             alphabetical order. A module's page puts its settings on a page of that name.
--   Sections  a setting's section is its row's section, else the last section an earlier row of
--             its module named, else the module's section, else its label. A section that repeats
--             its page's name, or a module with neither, puts the setting at the top of its page,
--             under no header. On a page, the top comes first, then the sections in alphabetical
--             order, and last the addon's own (addon.debug's Advanced).
--   Settings  within a section, alphabetical by label, except that a section's first-declared
--             setting stays first when it's a module's on/off switch: the switch leads what it
--             turns on. Several modules may share a section; then only the first one's switch leads.
--
-- Names sort ignoring case, and equal names keep their declared order.
--
-- Blizzard's settings panel gets no controls of the addon's: its controller navigation freezes the client on addon-made
-- controls (evidence: tools/api/forbidden.json). SettingsWindow.lua shows the same view there instead, as a canvas page
-- the controller UI ignores.

local ByteTerrace = ByteTerrace
local ipairs = ipairs
local lower = string.lower
local pairs = pairs
local sort = table.sort

-- Whether a's name comes before b's, ignoring case, then a's declared order before b's.
local function Before(a, b)
    local left = lower(a.key)
    local right = lower(b.key)

    if left ~= right then
        return (left < right)
    end

    return (a.order < b.order)
end

--- Returns the page layout the addon's window draws (see the header). A page is { name, entries }, and an entry is {
--- header = text } or { id, name, spec } for a setting row.
---@param addon table the AddOn, compiled
---@return table[] pages
local function SettingsPages(addon)
    local state = addon.State
    local main = { groups = {}, name = addon.Title, order = 0 }
    local pages = { main }
    local byName = {}
    -- The section each module's rows are in so far.
    local current = {}

    for order, name in ipairs(state.Order) do
        local id = state.Ids[name]
        local spec = state.Specs[id]

        if spec.label and spec.persist then
            local moduleName = name:match("^([^.]+)%.")
            local module = addon.Modules[moduleName]
            local moduleSpec = (module and module.Spec)
            local pageName = (moduleSpec and moduleSpec.page)
            local page = main

            -- A page named for the addon is the main page.
            if pageName and (pageName ~= addon.Title) then
                page = byName[pageName]

                if not page then
                    page = { groups = {}, name = pageName, order = order }
                    byName[pageName] = page
                    pages[#pages + 1] = page
                end
            end

            local header = (spec.section or current[moduleName])

            if (header == nil) and moduleSpec then
                header = (moduleSpec.section or moduleSpec.label)
            end

            current[moduleName] = header

            if header == page.name then
                header = nil
            end

            local key = (header or "")
            local group = page.groups[key]

            if not group then
                -- The addon's own rows close the page, after every module's sections.
                group = { entries = {}, header = header, key = key, last = (module == nil), order = order }
                page.groups[key] = group
            end

            local entry = { id = id, key = spec.label, name = name, order = order, spec = spec }

            entry.leads = ((#group.entries == 0) and (name == (moduleName .. ".enabled")))
            group.entries[#group.entries + 1] = entry
        end
    end

    local first = table.remove(pages, 1)

    sort(pages, function(a, b) return Before({ key = a.name, order = a.order }, { key = b.name, order = b.order }) end)
    table.insert(pages, 1, first)
    local laid = {}

    for _, page in ipairs(pages) do
        local groups = {}

        for _, group in pairs(page.groups) do
            groups[#groups + 1] = group
        end

        sort(groups, function(a, b)
            if (a.key == "") ~= (b.key == "") then
                return (a.key == "")
            elseif a.last ~= b.last then
                return b.last
            end

            return Before(a, b)
        end)

        local entries = {}

        for _, group in ipairs(groups) do
            if group.header then
                entries[#entries + 1] = { header = group.header }
            end

            sort(group.entries, function(a, b)
                if a.leads ~= b.leads then
                    return a.leads
                end

                return Before(a, b)
            end)

            for _, entry in ipairs(group.entries) do
                entries[#entries + 1] = { id = entry.id, name = entry.name, spec = entry.spec }
            end
        end

        laid[#laid + 1] = { entries = entries, name = page.name }
    end

    return laid
end

ByteTerrace.SettingsPages = SettingsPages
