-- Helpers for the framework's tests (framework*, modules, adversarial, facts): a bare addon
-- named TestApp on the framework alone, started by its ADDON_LOADED. A test file gets
-- the table with use("framework").

--- A harness with the framework loaded and a bare addon, not yet started. options' fields go on
--- the addon's spec, except harness, which is Harness.New's player.
---@return table h, table addon
local function NewAddOn(options)
    local h = Harness.New(options and options.harness)

    h:LoadFiles("ByteTerrace_Core")
    h.declared.TestDB = true
    rawset(h.env, "TestDB", h.saved.TestDB)
    local spec = { name = "TestApp", savedVariable = "TestDB", slash = { "/test" }, title = "Test AddOn", version = "1.0" }

    for key, value in pairs(options or {}) do
        if key ~= "harness" then spec[key] = value end
    end
    local addon = h.env.ByteTerrace.NewAddOn(spec)

    return h, addon
end

--- Starts TestApp: the client's ADDON_LOADED for it.
local function Start(h)
    h:Fire("ADDON_LOADED", "TestApp", false)
end

--- Starts an addon whose declarations are invalid and returns the refusal. Compile refuses; the
--- refusal reaches the error handler (the ADDON_LOADED dispatch isolates it) and the addon never
--- starts.
local function StartRefused(h, addon)
    h:ExpectErrors(1)
    Start(h)
    falsy(addon.Started, "addon must not start")
    return (h.errors[1] or "")
end

--- Everything printed so far, one print per line.
local function Printed(h)
    return table.concat(h.printed, "\n")
end

return { NewAddOn = NewAddOn, Printed = Printed, Start = Start, StartRefused = StartRefused }
