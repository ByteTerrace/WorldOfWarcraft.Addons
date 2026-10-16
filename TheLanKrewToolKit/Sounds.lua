local addonName, ns = ...

-- Sounds: player-supplied sounds bound to game moments. The addon ships no audio: players drop files named after each
-- sound into the Media folder. ByteTerrace_Core's SoundBank.lua has the rules: .ogg or .mp3, numbered variants, and a
-- restart to see new files.
--
-- ns.SoundBank is the toolkit's bank, the one way any feature plays them. Define sounds at file load, before a module's
-- state uses SoundBank:Row.
--
-- Modules:
--   Sounds            the master switch, the channel, and the combat start sound's settings.
--   CombatStartSound  plays CombatStart when combat starts. Its variants make a battle playlist.
--
-- Test a sound with /tlk sound <word> [variant] (always available, even with the master switch off).

local Addon = ns.Addon

local SoundBank = ByteTerrace.NewSoundBank(Addon, { channel = "Sounds.channel", master = "Sounds.enabled" })

ns.SoundBank = SoundBank

local CombatStartHandle

local function StopCombatStart()
    if CombatStartHandle then
        SoundBank:Stop(CombatStartHandle)
        CombatStartHandle = nil
    end
end

SoundBank:Define("combatStart", { file = "CombatStart", label = "Combat start", row = "Sounds.combatStart", word = "start" })

Addon:Module("Sounds", {
    commands = {
        { always = true, label = "List or test your sounds: sound [name] [variant]", name = "test",
            run = function(arg) SoundBank:Test(arg) end, slash = "sound" },
    },
    description = "Play your own sounds for game moments. Each sound also has its own toggle below.",
    label = "Sounds",
    page = "Sounds",
    state = {
        { default = "Master",
            description = "Volume channel your sounds play on. Master plays even when game music is off.",
            kind = "string", label = "Sound channel", name = "channel",
            valueLabels = { Ambience = "Ambience", Dialog = "Dialog", Master = "Master", Music = "Music", SFX = "Sound effects" },
            values = { "Master", "SFX", "Music", "Ambience", "Dialog" } },
        SoundBank:Row("combatStart", "Combat start sound",
            "When you enter combat. Give it variants for a battle playlist: each fight picks one.", { "combatStart" }),
        { default = true, description = "Fade out the combat start sound when you leave combat.", kind = "boolean",
            label = "Stop combat start sound when combat ends", name = "stopOnCombatEnd" },
    },
})

Addon:Module("CombatStartSound", {
    active = SoundBank:WhileOn("combatStart"),
    -- Turning the sound off stops it mid-play.
    OnDisable = StopCombatStart,
    OnEnable = function(module)
        local combat = module:Id("combat.active")

        module:Rule({
            changed = function(active)
                if active then
                    StopCombatStart()
                    CombatStartHandle = SoundBank:Play("combatStart")
                elseif Addon.State:Get("Sounds.stopOnCombatEnd") then
                    StopCombatStart()
                end
            end,
            reads = { combat }, when = function(state) return state.Values[combat] end,
        })
    end,
    toggle = false,
})
