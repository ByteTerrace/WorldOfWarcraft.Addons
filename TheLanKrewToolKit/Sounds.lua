local addonName, ns = ...

-- Sounds: player-supplied sounds bound to game moments, and ns.SoundBank, the one way any feature
-- plays them. The addon ships no audio: players drop files named after each sound (FinishHim.ogg;
-- .ogg wins if both exist) into the Media folder and restart the game (the client only sees files
-- that existed at launch). Numbered copies up to MaxVariants (FinishHim2.ogg ... FinishHim5.ogg)
-- are variants: each time a sound plays, one of its present files is picked at random. Which files
-- are present comes from C_UIFileAsset.IsKnownFile, as boss mods check external sounds; when it
-- knows none of a sound's files, the variants are simply tried (PlaySoundFile also says no for a
-- muted channel, so its answer alone can't tell a missing file from a muted one).
--
-- ns.SoundBank (define sounds at file load, before a module's state uses Row):
--   Define(key, spec)   adds a sound. spec: file, word (for /tlk sound), label, row (the id of the
--                       boolean setting that switches it, "Kombat.fatality"; sounds may share one),
--                       needs (optional: a row that must also be true, such as a class check) and
--                       cooldown (optional: seconds before it plays again).
--   Row(name, label, description, keys)   the setting row for one sound or a family sharing it,
--                       naming its files.
--   IsOn(key)           the master switch, its row and its needs row are on.
--   Play(key)           plays a variant if IsOn and off cooldown; returns the sound handle, nil
--                       when nothing played (off, cooling down, or no file).
--   WhileOn(keys...)    an active rule for a module that only serves these sounds.
--   Stop(handle)        fades a sound out.
--
-- Modules:
--   Sounds            the master switch, the channel, and the combat start sound's settings.
--   CombatStartSound  plays CombatStart when combat starts. Its variants make a battle playlist.
--
-- Test a sound with /tlk sound <word> [variant] (always available, even with the master switch off).

local MediaFolder = "Interface\\AddOns\\" .. addonName .. "\\Media\\"
local Extensions = { ".ogg", ".mp3" }
local MaxVariants = 5
local FadeOutMilliseconds = 1000

local C_UIFileAsset, GetTime, PlaySoundFile, StopSound = C_UIFileAsset, GetTime, PlaySoundFile, StopSound
local random, tonumber = math.random, tonumber

local Addon = ns.Addon

local Catalog = {}     -- [key] = the sound's spec
local Order = {}       -- keys in definition order, for /tlk sound
local ByWord = {}      -- [word] = spec
local LastPlayed = {}  -- [key] = GetTime() when it last played, for cooldowns
local Shuffled = {}    -- scratch: the variants in the order the next play tries them
local Known = {}       -- scratch: the known files of the sound being played
local CombatStartHandle

local function FileName(sound, variant)
    return variant == 1 and sound.file or (sound.file .. variant)
end

-- Plays one variant's file on channel, .ogg first. Returns whether it played, and its handle.
local function TryVariant(sound, variant, channel)
    local name = MediaFolder .. FileName(sound, variant)
    for _, extension in ipairs(Extensions) do
        local willPlay, handle = PlaySoundFile(name .. extension, channel)
        if willPlay then
            return true, handle
        end
    end
    return false
end

-- The path of a variant's file the client knows (.ogg first), or nil.
local function KnownFile(sound, variant)
    local name = MediaFolder .. FileName(sound, variant)
    for _, extension in ipairs(Extensions) do
        if C_UIFileAsset.IsKnownFile(name .. extension) then
            return name .. extension
        end
    end
    return nil
end

-- Collects the known files of a sound's variants into Known and returns how many.
local function KnownFiles(sound)
    local count = 0
    for variant = 1, MaxVariants do
        local path = KnownFile(sound, variant)
        if path then
            count = count + 1
            Known[count] = path
        end
    end
    return count
end

-- Plays a present variant at random: one of the known files, or, when the client knows none, the
-- variants tried in a shuffled order until one plays.
local function PlayAny(sound)
    local channel = Addon.State:Get("Sounds.channel")
    local known = KnownFiles(sound)
    if known > 0 then
        local willPlay, handle = PlaySoundFile(Known[random(known)], channel)
        return willPlay and true or false, handle
    end
    for i = 1, MaxVariants do
        local j = random(i)
        Shuffled[i] = Shuffled[j]
        Shuffled[j] = i
    end
    for i = 1, MaxVariants do
        local played, handle = TryVariant(sound, Shuffled[i], channel)
        if played then
            return true, handle
        end
    end
    return false
end

local function Applies(state, sound)
    return state:Get(sound.row) and (not sound.needs or state:Get(sound.needs)) and true or false
end

--- Adds a sound to the bank.
---@param key string
---@param spec table { file, word, label, row, needs?, cooldown? }
local function Define(key, spec)
    if Catalog[key] or ByWord[spec.word] then
        error("SoundBank: " .. key .. " (" .. spec.word .. ") is already defined", 2)
    end
    spec.key = key
    Catalog[key] = spec
    ByWord[spec.word] = spec
    Order[#Order + 1] = key
end

--- The boolean setting row that switches one sound, or a family of sounds sharing it; its
--- description names their files.
---@param name string the row's name in its module
---@param label string
---@param description string when the sounds play
---@param keys string[] the sounds it switches
---@return table row
local function Row(name, label, description, keys)
    local files = {}
    for i, key in ipairs(keys) do
        files[i] = Catalog[key].file
    end
    local howTo
    if #keys == 1 then
        local sound = Catalog[keys[1]]
        howTo = ("Put %s.ogg or %s.mp3 in the addon's Media folder (%s2 to %s%d for variety), then restart the game. Test with /tlk sound %s.")
            :format(sound.file, sound.file, sound.file, sound.file, MaxVariants, sound.word)
    else
        howTo = ("Files: %s (.ogg or .mp3; numbered copies add variety) in the addon's Media folder, then restart the game.")
            :format(table.concat(files, ", "))
    end
    return { name = name, kind = "boolean", default = true, label = label, description = description .. " " .. howTo }
end

--- Whether a sound would play now, cooldown aside: the master switch, its row and its needs row.
---@param key string
---@return boolean
local function IsOn(key)
    local state = Addon.State
    return state:Get("Sounds.enabled") and Applies(state, Catalog[key])
end

--- Plays a variant of a sound if it's on and off cooldown.
---@param key string
---@return integer? handle nil when nothing played
local function Play(key)
    local sound = Catalog[key]
    if not IsOn(key) then
        return nil
    end
    local now = GetTime()
    if sound.cooldown and LastPlayed[key] and now - LastPlayed[key] < sound.cooldown then
        return nil
    end
    local played, handle = PlayAny(sound)
    if played then
        LastPlayed[key] = now
        Addon:Debug("Sound:", sound.label)
    end
    return handle
end

--- An active rule: the master switch, and any of the sounds' rows (with their needs) on. A module
--- that serves only these sounds registers nothing while none of them could play.
---@param ... string sound keys
---@return table rule { reads, when }
local function WhileOn(...)
    local sounds = {}
    local reads, seen = { "Sounds.enabled" }, { ["Sounds.enabled"] = true }
    for i = 1, select("#", ...) do
        local sound = Catalog[(select(i, ...))]
        sounds[i] = sound
        for _, id in ipairs({ sound.row, sound.needs }) do
            if not seen[id] then
                seen[id] = true
                reads[#reads + 1] = id
            end
        end
    end
    return {
        reads = reads,
        when = function(state)
            if not state:Get("Sounds.enabled") then
                return false
            end
            for _, sound in ipairs(sounds) do
                if Applies(state, sound) then
                    return true
                end
            end
            return false
        end,
    }
end

--- Fades out a sound that Play started.
---@param handle integer
local function Stop(handle)
    StopSound(handle, FadeOutMilliseconds)
end

local function TestSound(arg)
    local word, which = (arg or ""):match("^%s*(%S*)%s*(%d*)")
    local sound = ByWord[word]
    if not sound then
        Addon:Print("Test a sound with " .. Addon.Slash[1] .. " sound <name> [variant]:")
        for _, key in ipairs(Order) do
            print(("  %s - %s.ogg or .mp3"):format(Catalog[key].word, Catalog[key].file))
        end
        return
    end
    local channel = Addon.State:Get("Sounds.channel")
    local variant = tonumber(which)
    local played
    if variant and variant >= 1 and variant <= MaxVariants then
        played = TryVariant(sound, variant, channel)
    else
        variant = nil
        played = PlayAny(sound)
    end
    local file = variant and FileName(sound, variant) or sound.file
    if played then
        Addon:Print("Playing", sound.label, "on the", channel, "channel.")
    elseif (variant and KnownFile(sound, variant)) or (not variant and KnownFiles(sound) > 0) then
        Addon:Print(("No sound played, though its file is there. Check that sound is on and the %s channel isn't muted.")
            :format(channel))
    else
        Addon:Print(("No sound played. Put %s.ogg or %s.mp3 in Interface\\AddOns\\%s\\Media, restart the game, and check the %s channel isn't muted.")
            :format(file, file, addonName, channel))
    end
end

local function StopCombatStart()
    if CombatStartHandle then
        Stop(CombatStartHandle)
        CombatStartHandle = nil
    end
end

ns.SoundBank = { Define = Define, Row = Row, IsOn = IsOn, Play = Play, WhileOn = WhileOn, Stop = Stop }

Define("combatStart", { file = "CombatStart", word = "start", label = "Combat start", row = "Sounds.combatStart" })

Addon:Module("Sounds", {
    label = "Sounds",
    page = "Sounds",
    description = "Play your own sounds for game moments. Each sound also has its own toggle below.",
    state = {
        { name = "channel", kind = "string", default = "Master", values = { "Master", "SFX", "Music", "Ambience", "Dialog" },
            valueLabels = { Master = "Master", SFX = "Sound effects", Music = "Music", Ambience = "Ambience", Dialog = "Dialog" },
            label = "Sound channel", description = "Volume channel your sounds play on. Master plays even when game music is off." },
        Row("combatStart", "Combat start sound",
            "When you enter combat. Give it variants for a battle playlist: each fight picks one.", { "combatStart" }),
        { name = "stopOnCombatEnd", kind = "boolean", default = true,
            label = "Stop combat start sound when combat ends", description = "Fade out the combat start sound when you leave combat." },
    },
    commands = {
        { name = "test", slash = "sound", label = "List or test your sounds: sound [name] [variant]", run = TestSound, always = true },
    },
})

Addon:Module("CombatStartSound", {
    toggle = false,
    active = WhileOn("combatStart"),
    OnEnable = function(module)
        local combat = module:Id("combat.active")
        module:Rule({
            reads = { combat }, when = function(state) return state.Values[combat] end,
            changed = function(active)
                if active then
                    StopCombatStart()
                    CombatStartHandle = Play("combatStart")
                elseif Addon.State:Get("Sounds.stopOnCombatEnd") then
                    StopCombatStart()
                end
            end,
        })
    end,
    OnDisable = StopCombatStart, -- turning the sound off stops it mid-play
})
