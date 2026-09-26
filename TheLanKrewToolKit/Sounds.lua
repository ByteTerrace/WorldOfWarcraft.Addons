local addonName, ns = ...

-- Sounds: player-supplied sounds bound to game moments. The addon ships no audio: players drop
-- files named after each sound into the Media folder (ByteTerrace_Core's SoundBank.lua has the
-- rules: .ogg or .mp3, numbered variants, a restart to see new files).
--
-- ns.SoundBank is the toolkit's bank, the one way any feature plays them. Define sounds at file
-- load, before a module's state uses SoundBank:Row.
--
-- Modules:
--   Sounds            the master switch, the channel, and the combat start sound's settings.
--   CombatStartSound  plays CombatStart when combat starts. Its variants make a battle playlist.
--
-- Test a sound with /tlk sound <word> [variant] (always available, even with the master switch off).

local Addon = ns.Addon

local SoundBank = ByteTerrace.NewSoundBank(Addon, { master = "Sounds.enabled", channel = "Sounds.channel" })
ns.SoundBank = SoundBank

local CombatStartHandle

local function StopCombatStart()
    if CombatStartHandle then
        SoundBank:Stop(CombatStartHandle)
        CombatStartHandle = nil
    end
end

SoundBank:Define("combatStart", { file = "CombatStart", word = "start", label = "Combat start", row = "Sounds.combatStart" })

Addon:Module("Sounds", {
    label = "Sounds",
    page = "Sounds",
    description = "Play your own sounds for game moments. Each sound also has its own toggle below.",
    state = {
        { name = "channel", kind = "string", default = "Master", values = { "Master", "SFX", "Music", "Ambience", "Dialog" },
            valueLabels = { Master = "Master", SFX = "Sound effects", Music = "Music", Ambience = "Ambience", Dialog = "Dialog" },
            label = "Sound channel", description = "Volume channel your sounds play on. Master plays even when game music is off." },
        SoundBank:Row("combatStart", "Combat start sound",
            "When you enter combat. Give it variants for a battle playlist: each fight picks one.", { "combatStart" }),
        { name = "stopOnCombatEnd", kind = "boolean", default = true,
            label = "Stop combat start sound when combat ends", description = "Fade out the combat start sound when you leave combat." },
    },
    commands = {
        { name = "test", slash = "sound", label = "List or test your sounds: sound [name] [variant]", always = true,
            run = function(arg) SoundBank:Test(arg) end },
    },
})

Addon:Module("CombatStartSound", {
    toggle = false,
    active = SoundBank:WhileOn("combatStart"),
    OnEnable = function(module)
        local combat = module:Id("combat.active")
        module:Rule({
            reads = { combat }, when = function(state) return state.Values[combat] end,
            changed = function(active)
                if active then
                    StopCombatStart()
                    CombatStartHandle = SoundBank:Play("combatStart")
                elseif Addon.State:Get("Sounds.stopOnCombatEnd") then
                    StopCombatStart()
                end
            end,
        })
    end,
    OnDisable = StopCombatStart, -- turning the sound off stops it mid-play
})
