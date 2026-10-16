-- Spoken text in the fake client: combat audio alerts (C_CombatAudioAlert) and text to speech (C_VoiceChat,
-- C_TTSSettings). See wow.lua for the rest. Every call that speaks lands in h.spoken = { { api, text, ... }, ... } in
-- call order. [D] marks a documented decision, [G] a guess.
--
--   C_CombatAudioAlert.SpeakText(text, category [, allowOverlap = true]) -> utteranceID
--     [D] SecretArguments AllowedWhenUntainted: addon code can't speak a secret this way.
--     [D] category is an Enum.CombatAudioAlertCategory (anything else is a harness error).
--     [D] IsEnabled() is the player's Combat Audio Alerts setting (the CAAEnabled CVar, "0" by
--         default: off until the player turns it on). Blizzard_CombatAudioAlerts checks IsEnabled
--         before every alert. [G] While disabled, SpeakText speaks nothing and returns nothing
--         (the doc says it MayReturnNothing). Harness.New{ combatAudioAlerts = true } or
--         h.combatAudioAlerts turns it on. Recorded: { api = "C_CombatAudioAlert.SpeakText",
--         text, category, allowOverlap, utteranceID }. Utterance IDs count up from 1.
--     [G] The player's per-category voice, volume and speed apply in the client; the harness
--         doesn't model them.
--   C_VoiceChat.SpeakText(voiceID, text, rate, volume [, overlap = false]) returns nothing.
--     [D] SecretArguments AllowedWhenTainted, text ConditionalSecret: addon code may speak a
--         secret text (a name read in combat). voiceID, rate, volume, and overlap are NeverSecret:
--         a secret one is an error ([G] that the client refuses it rather than ignoring it).
--     [D] Blizzard's chat narration (TextToSpeechFrame.lua) speaks with the player's settings:
--         voiceID from C_TTSSettings.GetVoiceOptionID(Enum.TtsVoiceType.Standard) (falling back
--         to the first of C_VoiceChat.GetTtsVoices()), C_TTSSettings.GetSpeechRate() and
--         GetSpeechVolume(). [G] Harness defaults: one voice { voiceID = 0, name = "Harness
--         Voice" }, both voice options 0, rate 0, volume 100 (h.ttsVoices, h.tts). It speaks
--         whether or not chat narration (the textToSpeech CVar) is on. Recorded: { api =
--         "C_VoiceChat.SpeakText", voiceID, text, rate, volume, overlap }. [G] The playback
--         events (VOICE_CHAT_TTS_PLAYBACK_STARTED / _FINISHED) aren't fired.

local Snapshot = __snapshot
local Categories = Snapshot.enums.CombatAudioAlertCategory

local function IsCategory(value)
    for _, known in pairs(Categories) do
        if known == value then return true end
    end

    return false
end

function Harness:InitSpeech(player)
    self.spoken = {}
    self.combatAudioAlerts = (player.combatAudioAlerts == true)
    self.ttsVoices = { { name = "Harness Voice", voiceID = 0 } }
    self.tts = { rate = 0, voices = { [0] = 0, [1] = 0 }, volume = 100 }
    self.utteranceSerial = 0
end

-- The speech fakes, merged into the env (env.lua) before it wraps them.
function Harness:SpeechFakes()
    local h = self

    return {
        C_CombatAudioAlert = {
            IsEnabled = function() return h.combatAudioAlerts end,
            SpeakText = function(text, category, allowOverlap)
                assert(type(text) == "string", "C_CombatAudioAlert.SpeakText: text must be a string")
                assert(IsCategory(category), "C_CombatAudioAlert.SpeakText: unknown category " .. tostring(category))

                if not h.combatAudioAlerts then
                    return
                end

                h.utteranceSerial = (h.utteranceSerial + 1)

                if allowOverlap == nil then allowOverlap = true end

                h.spoken[#h.spoken + 1] = {
                    allowOverlap = ((allowOverlap and true) or false), api = "C_CombatAudioAlert.SpeakText",
                    category = category, text = text, utteranceID = h.utteranceSerial,
                }

                return h.utteranceSerial
            end,
        },
        C_TTSSettings = {
            GetSpeechRate = function() return h.tts.rate end,
            GetSpeechVolume = function() return h.tts.volume end,
            GetVoiceOptionID = function(voiceType)
                local id = h.tts.voices[voiceType]

                assert(id, "C_TTSSettings.GetVoiceOptionID: unknown TtsVoiceType " .. tostring(voiceType))

                return id
            end,
        },
        C_VoiceChat = {
            GetTtsVoices = function()
                local voices = {}

                for i, voice in ipairs(h.ttsVoices) do
                    voices[i] = { name = voice.name, voiceID = voice.voiceID }
                end

                return voices
            end,
            SpeakText = function(voiceID, text, rate, volume, overlap)
                for i, value in ipairs({ voiceID, rate, volume }) do
                    if IsSecret(value) then
                        error("C_VoiceChat.SpeakText: argument " .. ({ 1, 3, 4 })[i] .. " is NeverSecret", 3)
                    end
                end

                if IsSecret(overlap) then
                    error("C_VoiceChat.SpeakText: argument 5 is NeverSecret", 3)
                end

                assert((type(voiceID) == "number") and (type(rate) == "number") and (type(volume) == "number"),
                    "C_VoiceChat.SpeakText(voiceID, text, rate, volume [, overlap])")

                assert(type(Reveal(text)) == "string", "C_VoiceChat.SpeakText: text must be a string")

                h.spoken[#h.spoken + 1] = {
                    api = "C_VoiceChat.SpeakText", overlap = (overlap == true), rate = rate, text = text,
                    voiceID = voiceID, volume = volume,
                }
            end,
        },
    }
end
