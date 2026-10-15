-- SoundBank: player-supplied sounds bound to game moments. An addon ships no audio: players drop files named after each
-- sound (FinishHim.ogg; .ogg wins if both exist) into the addon's media folder and restart the game (the client only
-- sees files that existed at launch). Numbered copies up to MaxVariants (FinishHim2.ogg ... FinishHim5.ogg) are
-- variants: each time a sound plays, one of its present files is picked at random. Which files are present comes from
-- C_UIFileAsset.IsKnownFile, as boss mods check external sounds (it knows loose addon files, probed in game), asked
-- once per sound. PlaySoundFile also says no for a muted channel, so its answer alone can't tell a missing file from a
-- muted one.
--
--   local sounds = ByteTerrace.NewSoundBank(addon, { master = "Sounds.enabled", channel = "Sounds.channel",
--                                                     folder = "Interface\\AddOns\\MyAddon\\Media\\" }) -- optional
--   sounds:Define(key, spec)   at file load. spec: file, word (for Test), label, row (the boolean
--                              setting that switches it; sounds may share one), needs (optional: a
--                              row that must also be true, such as a class check) and cooldown
--                              (optional: seconds before it plays again).
--   sounds:Row(name, label, description, keys)   the setting row spec for one sound or a family
--                              sharing it; its description names their files.
--   sounds:IsOn(key)           the master switch, its row and its needs row are on.
--   sounds:Play(key)           plays a variant if IsOn and off cooldown; returns the sound handle,
--                              nil when nothing played (off, cooling down, or no file).
--   sounds:WhileOn(keys...)    an active rule for a module that only serves these sounds.
--   sounds:Stop(handle)        fades a sound out.
--   sounds:Test(arg)           the "<word> [variant]" test command: plays regardless of switches
--                              and says why nothing played; no word lists every sound.
--
-- The master option names the boolean row that switches every sound, and channel the string row naming the volume
-- channel they play on (Master, SFX, Music, Ambience, Dialog).

local Extensions = { ".ogg", ".mp3" }
local FadeOutMilliseconds = 1000
local MaxVariants = 5

local ByteTerrace = ByteTerrace
local C_UIFileAsset, GetTime, PlaySoundFile, StopSound = C_UIFileAsset, GetTime, PlaySoundFile, StopSound
local concat = table.concat
local ipairs, pairs, print, random, select = ipairs, pairs, print, math.random, select
local tonumber, tostring, type = tonumber, tostring, type

local SoundBank = {}

SoundBank.__index = SoundBank

local function Applies(state, sound)
    return ((state:Get(sound.row) and (not sound.needs or state:Get(sound.needs)) and true) or false)
end

local function FileName(sound, variant)
    return (((variant == 1) and sound.file) or (sound.file .. variant))
end

-- A sound's files, read once: the client only sees files that existed at launch. files[variant] is the path the client
-- knows for that variant (.ogg first) or false; present lists the known ones.
local function Files(self, sound)
    local files = sound.files

    if files then
        return files, sound.present
    end

    files, sound.present = {}, {}

    for variant = 1, MaxVariants do
        local name = (self.m_folder .. FileName(sound, variant))

        files[variant] = false

        for _, extension in ipairs(Extensions) do
            if C_UIFileAsset.IsKnownFile(name .. extension) then
                files[variant] = (name .. extension)
                sound.present[#sound.present + 1] = (name .. extension)

                break
            end
        end
    end

    sound.files = files

    return files, sound.present
end

-- Plays one of a sound's present files at random. Returns whether it played, and its handle.
local function PlayAny(self, sound)
    local _, present = Files(self, sound)

    if #present == 0 then
        return false
    end

    local willPlay, handle = PlaySoundFile(present[random(#present)], self.m_addon.State:Get(self.m_channel))

    return ((willPlay and true) or false), handle
end

--- Creates an addon's sound bank.
---@param addon table
---@param options table { master, channel, folder? }: row names, and the media folder (default:
---                     the addon's Media folder)
function ByteTerrace.NewSoundBank(addon, options)
    if (type(options.master) ~= "string") or (type(options.channel) ~= "string") then
        error("NewSoundBank needs the master and channel row names", 2)
    end

    return setmetatable({
        m_addon = addon,
        -- Maps each test word to its sound's spec.
        m_byWord = {},
        -- Maps each key to its sound's spec.
        m_catalog = {},
        m_channel = options.channel,
        m_folder = (options.folder or ("Interface\\AddOns\\" .. addon.Name .. "\\Media\\")),
        -- Maps each key to GetTime() when it last played, for cooldowns.
        m_lastPlayed = {},
        m_master = options.master,
        -- The keys in definition order, for Test.
        m_order = {},
    }, SoundBank)
end

--- Adds a sound. The spec is copied.
---@param key string
---@param spec table { file, word, label, row, needs?, cooldown? }
function SoundBank:Define(key, spec)
    if self.m_catalog[key] or self.m_byWord[spec.word] then
        error(self.m_addon.Name .. ": sound " .. key .. " (" .. tostring(spec.word) .. ") is already defined", 2)
    end

    local own = { key = key }

    for field, value in pairs(spec) do
        own[field] = value
    end

    self.m_catalog[key] = own
    self.m_byWord[own.word] = own
    self.m_order[#self.m_order + 1] = key
end

--- Whether a sound would play now, cooldown aside: the master switch, its row and its needs row.
---@param key string
---@return boolean
function SoundBank:IsOn(key)
    local state = self.m_addon.State

    return (state:Get(self.m_master) and Applies(state, self.m_catalog[key]))
end

--- Plays a variant of a sound if it's on and off cooldown.
---@param key string
---@return integer? handle nil when nothing played
function SoundBank:Play(key)
    local sound = self.m_catalog[key]

    if not self:IsOn(key) then
        return nil
    end

    local now = GetTime()
    local last = self.m_lastPlayed[key]

    if sound.cooldown and last and ((now - last) < sound.cooldown) then
        return nil
    end

    local played, handle = PlayAny(self, sound)

    if played then
        self.m_lastPlayed[key] = now
        self.m_addon:Debug("Sound:", sound.label)
    end

    return handle
end

--- The boolean setting row that switches one sound, or a family of sounds sharing it; its description names their
--- files.
---@param name string the row's name in its module
---@param label string
---@param description string when the sounds play
---@param keys string[] the sounds it switches
---@return table row
function SoundBank:Row(name, label, description, keys)
    local howTo

    if #keys == 1 then
        local sound = self.m_catalog[keys[1]]
        local slash = ((self.m_addon.Slash and self.m_addon.Slash[1]) or "")

        howTo = ("Put %s.ogg or %s.mp3 in the addon's Media folder (%s2 to %s%d for variety), then restart the game. Test with %s sound %s.")
            :format(sound.file, sound.file, sound.file, sound.file, MaxVariants, slash, sound.word)
    else
        local files = {}

        for i, key in ipairs(keys) do
            files[i] = self.m_catalog[key].file
        end

        howTo = ("Files: %s (.ogg or .mp3; numbered copies add variety) in the addon's Media folder, then restart the game.")
            :format(concat(files, ", "))
    end

    return { default = true, description = (description .. " " .. howTo), kind = "boolean", label = label, name = name }
end

--- Fades out a sound that Play started.
---@param handle integer
function SoundBank:Stop(handle)
    StopSound(handle, FadeOutMilliseconds)
end

--- The test command: "<word> [variant]" plays that sound (a variant, or one at random) whatever the switches say, and
--- says why when nothing played; no word lists every sound.
---@param arg string?
function SoundBank:Test(arg)
    local addon = self.m_addon
    local word, which = (arg or ""):match("^%s*(%S*)%s*(%d*)")
    local sound = self.m_byWord[word]

    if not sound then
        addon:Print("Test a sound with " .. ((addon.Slash and addon.Slash[1]) or "") .. " sound <name> [variant]:")

        for _, key in ipairs(self.m_order) do
            print(("  %s - %s.ogg or .mp3"):format(self.m_catalog[key].word, self.m_catalog[key].file))
        end

        return
    end

    local channel = addon.State:Get(self.m_channel)
    local files, present = Files(self, sound)
    local variant = tonumber(which)
    local played, known

    if variant and (variant >= 1) and (variant <= MaxVariants) then
        known = files[variant]
        played = (known and PlaySoundFile(known, channel))
    else
        variant = nil
        known = (#present > 0)
        played = PlayAny(self, sound)
    end

    local file = ((variant and FileName(sound, variant)) or sound.file)

    if played then
        addon:Print("Playing", sound.label, "on the", channel, "channel.")
    elseif known then
        addon:Print(("No sound played, though its file is there. Check that sound is on and the %s channel isn't muted.")
            :format(channel))
    else
        addon:Print(("No sound played. Put %s.ogg or %s.mp3 in %s, restart the game, and check the %s channel isn't muted.")
            :format(file, file, self.m_folder:sub(1, -2), channel))
    end
end

--- An active rule: the master switch, and any of the sounds' rows (with their needs) on. A module that serves only
--- these sounds registers nothing while none of them could play.
---@param ... string sound keys
---@return table rule { reads, when }
function SoundBank:WhileOn(...)
    local master, sounds = self.m_master, {}
    local reads, seen = { master }, { [master] = true }

    for i = 1, select("#", ...) do
        local sound = self.m_catalog[(select(i, ...))]

        sounds[i] = sound

        for _, row in ipairs({ sound.row, sound.needs }) do
            if not seen[row] then
                seen[row] = true
                reads[#reads + 1] = row
            end
        end
    end

    return {
        reads = reads,
        when = function(state)
            if not state:Get(master) then
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
