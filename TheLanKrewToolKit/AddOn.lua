local addonName, ns = ...

ns.addon = ByteTerrace.NewAddOn({
    name = addonName,
    savedVariable = "TheLanKrewToolKitDB",
    slash = { "/tlk", "/lankrew" },
    facts = { "combat", "afk" },
})

function TheLanKrewToolKit_OnAddonCompartmentClick()
    ns.addon:OpenSettings()
end
