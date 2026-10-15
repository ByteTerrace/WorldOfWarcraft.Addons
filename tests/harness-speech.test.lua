-- The harness's fidelity rules for spoken text (tests/harness/speech.lua): combat audio alerts and text to speech.

test("combat audio alerts speak only when the player turned them on, and refuse secret text", function()
    local h = Harness.New()
    local env = h.env
    local alerts, category = env.C_CombatAudioAlert, env.Enum.CombatAudioAlertCategory.General

    falsy(alerts.IsEnabled(), "off by default (CAAEnabled is 0)")
    eq(select("#", alerts.SpeakText("Incoming", category)), 0, "disabled: nothing spoken, nothing returned")
    eq(#h.spoken, 0)
    h.combatAudioAlerts = true
    truthy(alerts.IsEnabled())
    eq(alerts.SpeakText("Incoming", category), 1)
    eq(alerts.SpeakText("Again", category, false), 2)
    eq(#h.spoken, 2)
    eq(h.spoken[1].api, "C_CombatAudioAlert.SpeakText")
    eq(h.spoken[1].text, "Incoming")
    eq(h.spoken[1].category, category)
    eq(h.spoken[1].allowOverlap, true, "allowOverlap defaults to true")
    eq(h.spoken[2].allowOverlap, false)
    eq(h.spoken[2].utteranceID, 2)
    throws(function() alerts.SpeakText("x", 99) end, "unknown category")
    throws(function() alerts.SpeakText(Secret("Bob"), category) end, "secret argument #1 refused")
    local on = Harness.New({ combatAudioAlerts = true })

    truthy(on.env.C_CombatAudioAlert.IsEnabled())
end)

test("text to speech speaks with the player's settings and takes a secret text", function()
    local h = Harness.New()
    local env = h.env
    local voiceID = env.C_TTSSettings.GetVoiceOptionID(env.Enum.TtsVoiceType.Standard)
    local voices = env.C_VoiceChat.GetTtsVoices()

    eq(#voices, 1)
    eq(voices[1].voiceID, voiceID)
    eq(env.C_TTSSettings.GetSpeechRate(), 0)
    eq(env.C_TTSSettings.GetSpeechVolume(), 100)
    eq(select("#", env.C_VoiceChat.SpeakText(voiceID, "Bob is here", 0, 100)), 0, "returns nothing")
    local spoken = h.spoken[1]

    eq(spoken.api, "C_VoiceChat.SpeakText")
    eq(spoken.text, "Bob is here")
    eq(spoken.voiceID, voiceID)
    eq(spoken.rate, 0)
    eq(spoken.volume, 100)
    eq(spoken.overlap, false)
    h:SetTarget({ name = "Hogger" })
    h:SetRestriction("Encounter", true)
    local name = env.UnitName("target")

    truthy(env.issecretvalue(name), "an NPC's name is secret in an encounter")
    env.C_VoiceChat.SpeakText(voiceID, name, 0, 100, true)
    truthy(IsSecret(h.spoken[2].text), "the secret text is spoken as is")
    eq(Reveal(h.spoken[2].text), "Hogger")
    eq(h.spoken[2].overlap, true)
    throws(function() env.C_VoiceChat.SpeakText(Secret(0), "x", 0, 100) end, "NeverSecret")
    throws(function() env.C_VoiceChat.SpeakText(voiceID, "x", 0, Secret(100)) end, "NeverSecret")
end)
