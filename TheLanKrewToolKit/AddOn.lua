local addonName, ns = ...

-- The toolkit's addon. The TOC loads this file first. Every other file declares its modules on ns.Addon, which compiles
-- on ADDON_LOADED (ByteTerrace_Core's AddOn.lua).
--
-- Slash commands are /tlk and /lankrew. The combat, afk, and controller facts publish combat.active, afk.active, and
-- controller.connected for any module to read. The target, kills, and death facts run while a module that uses them runs (ByteTerrace_Core's Facts.lua).

ns.Addon = ByteTerrace.NewAddOn({
    facts = { "combat", "afk", "controller", "target", "kills", "death" },
    name = addonName,
    savedVariable = "TheLanKrewToolKitDB",
    savedVariablePerCharacter = "TheLanKrewToolKitCharDB",
    slash = { "/tlk", "/lankrew" },
})

--- Opens the toolkit's settings. This is the TOC's AddonCompartmentFunc.
function TheLanKrewToolKit_OnAddonCompartmentClick()
    ns.Addon:ToggleSettings()
end
