local addonName, ns = ...

-- Player-supplied sounds bound to game moments. The addon ships no audio: players drop files
-- named after each sound (e.g. FinishHim.ogg) into the Media folder and restart the game (the
-- client only sees files that existed at launch).
--
-- Adapters (event handlers) are the only code that reads the WoW API. They publish non-secret
-- facts as runtime rows; the sounds are rules over those rows.
--
--   targetSerial      bumps on every target change.
--   targetEnemyPlayer the target is an attackable player.
--   targetDied        the enemy player target died while targeted (not a corpse you selected).
--   executeRange      warriors: Execute is usable on the enemy player target, i.e. it is below
--                     20% health. Enemy players' health is restricted, but spell usability isn't.
--   flawless          out of combat: you are at full health. In combat: you started at full health
--                     and no UNIT_HEALTH event has fired for you since. Health is secret in combat,
--                     so the value is never compared there; the event firing is the signal.

local MEDIA_FOLDER = "Interface\\AddOns\\" .. addonName .. "\\Media\\"
local EXTENSIONS = { ".ogg", ".mp3" }
local FADE_OUT_MS = 1000
local DESTINY_COOLDOWN_SECONDS = 10
local EXECUTE_SPELL_ID = 5308

local C_Spell, GetTime, PlaySoundFile, StopSound = C_Spell, GetTime, PlaySoundFile, StopSound
local issecretvalue, UnitCanAttack, UnitClass, UnitExists = issecretvalue, UnitCanAttack, UnitClass, UnitExists
local UnitHealth, UnitHealthMax, UnitIsDead, UnitIsDeadOrGhost = UnitHealth, UnitHealthMax, UnitIsDead, UnitIsDeadOrGhost
local UnitIsFeignDeath, UnitIsPlayer = UnitIsFeignDeath, UnitIsPlayer

local SOUNDS = {
    { key = "combatStart", file = "CombatStart", word = "start", label = "Combat start",
        description = "When you enter combat." },
    { key = "chooseYourDestiny", file = "ChooseYourDestiny", word = "destiny", label = "Choose your destiny",
        description = "When you target a living enemy player (at most every 10 seconds)." },
    { key = "flawlessVictory", file = "FlawlessVictory", word = "flawless", label = "Flawless victory",
        description = "When your enemy player target dies and you started the fight at full health without taking a hit." },
    { key = "finishHim", file = "FinishHim", word = "finish", label = "Finish him",
        description = "Warriors only: when Execute becomes usable on your enemy player target (below 20% health). Execute isn't usable in Defensive Stance." },
}
local soundByWord = {}
for _, sound in ipairs(SOUNDS) do
    soundByWord[sound.word] = sound
end

local rows = {
    { name = "channel", kind = "string", default = "Master", values = { "Master", "SFX", "Music", "Ambience", "Dialog" },
        label = "Sound channel", description = "Volume channel your sounds play on. Master plays even when game music is off." },
}
for _, sound in ipairs(SOUNDS) do
    rows[#rows + 1] = {
        name = sound.key, kind = "boolean", default = true, label = sound.label .. " sound",
        description = ("%s Put %s.ogg or %s.mp3 in the addon's Media folder, then restart the game. Test with /tlk sound %s.")
            :format(sound.description, sound.file, sound.file, sound.word),
    }
    if sound.key == "combatStart" then
        rows[#rows + 1] = { name = "stopOnCombatEnd", kind = "boolean", default = true,
            label = "Stop combat start sound when combat ends", description = "Fade out the combat start sound when you leave combat." }
    end
end
for _, fact in ipairs({ "targetEnemyPlayer", "targetDied", "executeRange", "flawless" }) do
    rows[#rows + 1] = { name = fact, kind = "boolean", default = false, persist = false }
end
rows[#rows + 1] = { name = "targetSerial", kind = "number", default = 0, persist = false }

-- Playback -----------------------------------------------------------------

local module -- set below; PlayFile reads the channel row

local function PlayFile(sound)
    local channel = module:Get("channel")
    for _, extension in ipairs(EXTENSIONS) do
        local willPlay, handle = PlaySoundFile(MEDIA_FOLDER .. sound.file .. extension, channel)
        if willPlay then
            return handle
        end
    end
end

local function Trigger(sound)
    if module:Get(sound.key) then
        module.addon:Debug("Sound:", sound.label)
        return PlayFile(sound)
    end
end

local function TestSound(word)
    local addon, sound = module.addon, soundByWord[word or ""]
    if not sound then
        addon:Print("Test a sound with " .. addon.slash[1] .. " sound <name>:")
        for _, entry in ipairs(SOUNDS) do
            print(("  %s - %s.ogg or .mp3"):format(entry.word, entry.file))
        end
        return
    end
    if PlayFile(sound) then
        addon:Print("Playing", sound.label, "on the", module:Get("channel"), "channel.")
    else
        addon:Print(("No sound played. Put %s.ogg or %s.mp3 in Interface\\AddOns\\%s\\Media, restart the game, and check the %s channel isn't muted.")
            :format(sound.file, sound.file, addonName, module:Get("channel")))
    end
end

-- Facts --------------------------------------------------------------------

local function IsTrue(value)
    return not issecretvalue(value) and value == true
end

-- nil when health can't be read (secret).
local function IsPlayerAtFullHealth()
    local health, maxHealth = UnitHealth("player"), UnitHealthMax("player") -- secret: guarded below
    if issecretvalue(health) or issecretvalue(maxHealth) then
        return nil
    end
    return health >= maxHealth
end

local function EnableFacts(m, state, combat)
    local enemy, died, execute, flawless, serial = m:Id("targetEnemyPlayer"), m:Id("targetDied"), m:Id("executeRange"), m:Id("flawless"), m:Id("targetSerial")
    local _, class = UnitClass("player")
    local executeName = (not issecretvalue(class) and class == "WARRIOR") and C_Spell.GetSpellName(EXECUTE_SPELL_ID) or nil

    local function UpdateExecute()
        local inRange = false
        if executeName and state.values[enemy] and not state.values[died] then
            local isUsable, insufficientPower = C_Spell.IsSpellUsable(executeName)
            inRange = IsTrue(isUsable) or IsTrue(insufficientPower)
        end
        state:Set(execute, inRange)
    end

    local function UpdateFlawless()
        local full = IsPlayerAtFullHealth()
        if full ~= nil then
            state:Set(flawless, full)
        end
    end

    -- A target that was already dead when selected can't "die while targeted".
    local deadWhenSelected = false
    m:On("PLAYER_TARGET_CHANGED", function()
        local isEnemy = IsTrue(UnitExists("target")) and IsTrue(UnitIsPlayer("target")) and IsTrue(UnitCanAttack("player", "target"))
        deadWhenSelected = isEnemy and IsTrue(UnitIsDeadOrGhost("target"))
        state:Set(serial, state.values[serial] + 1)
        state:Set(enemy, isEnemy)
        state:Set(died, false)
        UpdateExecute()
    end)
    m:On("UNIT_HEALTH", function()
        if deadWhenSelected and not IsTrue(UnitIsDeadOrGhost("target")) then
            deadWhenSelected = false -- resurrected: a death from here on counts
        end
        if state.values[enemy] and not state.values[died] and not deadWhenSelected
            and IsTrue(UnitIsDead("target")) and not IsTrue(UnitIsFeignDeath("target")) then
            state:Set(died, true)
        end
        UpdateExecute()
    end, "target")
    m:On("UNIT_HEALTH", function()
        if state.values[combat] then
            state:Set(flawless, false)
        else
            UpdateFlawless()
        end
    end, "player")
    m:On("UNIT_MAXHEALTH", function()
        if not state.values[combat] then
            UpdateFlawless()
        end
    end, "player")
    m:On("PLAYER_REGEN_ENABLED", UpdateFlawless)
    if executeName then
        m:On("SPELL_UPDATE_USABLE", UpdateExecute)
        m:On("UPDATE_SHAPESHIFT_FORM", UpdateExecute)
    end
    UpdateFlawless()
end

-- Module -------------------------------------------------------------------

local combatStartHandle

local function StopCombatStart()
    if combatStartHandle then
        StopSound(combatStartHandle, FADE_OUT_MS)
        combatStartHandle = nil
    end
end

module = ns.addon:Module("Sounds", {
    label = "Sounds",
    description = "Play your own sounds for game moments. Each sound also has its own toggle below.",
    state = rows,
    commands = {
        { name = "test", slash = "sound", label = "List or test your sounds: sound [name]", run = TestSound },
    },
    OnEnable = function(m)
        local state = m.addon.state
        local combat = m:Id("combat.active")
        EnableFacts(m, state, combat)

        m:Rule({
            reads = { combat }, when = function(s) return s.values[combat] end,
            changed = function(active)
                if active then
                    StopCombatStart()
                    combatStartHandle = Trigger(SOUNDS[1])
                elseif m:Get("stopOnCombatEnd") then
                    StopCombatStart()
                end
            end,
        })

        local serial, enemy, died = m:Id("targetSerial"), m:Id("targetEnemyPlayer"), m:Id("targetDied")
        local lastDestiny = -math.huge
        m:Watch({ serial }, function(s)
            if s.values[enemy] and not IsTrue(UnitIsDeadOrGhost("target")) then
                local now = GetTime()
                if now - lastDestiny >= DESTINY_COOLDOWN_SECONDS then
                    lastDestiny = now
                    Trigger(SOUNDS[2])
                end
            end
        end, true)

        local flawless = m:Id("flawless")
        m:Rule({
            reads = { died }, when = function(s) return s.values[died] end,
            changed = function(active, s)
                if active and s.values[flawless] then
                    Trigger(SOUNDS[3])
                end
            end,
        })

        -- Announce once per target per entry into Execute range.
        local execute, announcedSerial = m:Id("executeRange"), nil
        m:Watch({ execute, serial }, function(s)
            if not s.values[execute] then
                announcedSerial = nil
            elseif announcedSerial ~= s.values[serial] then
                announcedSerial = s.values[serial]
                Trigger(SOUNDS[4])
            end
        end, true)
    end,
    OnDisable = StopCombatStart,
})
