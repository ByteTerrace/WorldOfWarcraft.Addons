local addonName, ns = ...

-- The toolkit's addon. The TOC loads this file first; every other file declares its modules on
-- ns.Addon, which compiles on ADDON_LOADED (ByteTerrace_Core's AddOn.lua).
--
-- Slash commands are /tlk and /lankrew. The combat and afk facts publish combat.active and
-- afk.active for any module to read.

ns.Addon = ByteTerrace.NewAddOn({
    name = addonName,
    savedVariable = "TheLanKrewToolKitDB",
    savedVariablePerCharacter = "TheLanKrewToolKitCharDB",
    slash = { "/tlk", "/lankrew" },
    facts = { "combat", "afk" },
})

--- Opens the toolkit's settings; the TOC's AddonCompartmentFunc.
function TheLanKrewToolKit_OnAddonCompartmentClick()
    ns.Addon:OpenSettings()
end
