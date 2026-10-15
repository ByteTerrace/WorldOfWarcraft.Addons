local addonName, ns = ...

-- Development only; never shipped. Two commands record facts about the client, and /reload afterwards writes them to
-- WTF\Account\<account>\SavedVariables\ByteTerrace_DevTools.lua:
--
--   /btdev dump        every global the client exposes (name, type, and for plain tables their
--                      member names), plus the build it came from, for
--                      `node tools/tlk.mjs api-sync --globals <that file>` (tools/api/forever.json).
--   /btdev probe       every calibration probe (Probes.lua and the files it names) whose needs are
--                      met right now, folded into the probes already recorded (Probes.Keep: the
--                      same result adds its context, another result replaces the record, an
--                      accumulating probe's result merges), for
--                      `node tools/tlk.mjs probes --import` (tools/api/probes.json). Probes it
--                      skips are printed with what they need.
--   /btdev probe list  the probes with no result for this build yet, grouped by what they need,
--                      in the order one play session in a starting zone reaches them (Probes.Steps).
--   /btdev rumble      plays four vibration types in turn (ProbesInput.lua), for gamePad.vibration;
--                      /btdev rumble <type> [intensity] [seconds] plays one, and stop stops it.
--                      What a vibration feels like is for the player to say.
--
-- From load it also listens for UNIT_COMBAT on the player and the target, for the unitCombat.seen probe
-- (Probes.NoteUnitCombat keeps the payloads' shapes), for the kill events, for kills.seen (Probes.NoteKill), and for
-- chat events' senders, for names.chatSenders (Probes.NoteSender keeps their shapes, never the names) and their
-- discordInfo, for names.chatDiscordInfo (Probes.NoteDiscordInfo), for addon messages' field shapes, for
-- comms.addonMessageInLockdown (Probes.NoteAddonMessage), for UNIT_AURA on the player and the target, for
-- units.secretTokenInAuraEvent (Probes.NoteAuraToken), for the steps into and out of combat and every restriction
-- change, for combat.edges and the restrictions the others key by (Probes.NoteCombatEdge, NoteRestriction,
-- SyncRestrictions), for leaving combat in a PvP match, for damageMeter.pvpSecrecy (Probes.NotePvPLeftCombat reads the
-- meter's totals then and a few seconds later), for your deaths and the damage meter's updates after them, for
-- damageMeter.afterDeath (Probes.NoteDeath, NoteMeterUpdate), and for boss encounters' starts and warnings, for
-- encounterWarning.seen (Probes.NoteEncounterStart, NoteEncounterWarning), and for controller and interface events, for
-- input.events (Probes.NoteInputEvent).
--
-- Only the client's own names are dumped. A global or table member any addon set is tainted by that addon
-- (issecurevariable), so it's counted under `skipped` instead, per addon: other addons' keys in Blizzard tables
-- (SlashCmdList.MYADDON) never reach the snapshot.
--
-- Tables listed in Nested are dumped one level deeper: `tables` maps each member that is itself a table to its member
-- names, so the gate can check Enum.PowerType.Energy.
--
-- ByteTerraceDevToolsDB holds build, globals and skipped (the dump, what api-sync reads) and probes (probe name ->
-- record, what `tlk probes` reads). Each command replaces only its own part.

local Nested = { Enum = true }
local Prefix = "ByteTerrace DevTools: "
local Probes = ns.Probes

-- [addon name] = tainted keys skipped, for the dump in progress.
local Skipped

-- Files a probe under the play-session step that meets all its needs, and a text.
local function AddToGroup(groups, probe, text)
    local step = Probes.Step(probe)

    groups[step] = (groups[step] or {})
    groups[step][text] = (groups[step][text] or {})
    table.insert(groups[step][text], probe.name)
end

-- A set of contexts as text, sorted and joined by "; " (a context's restrictions hold commas).
local function ContextList(contexts)
    return Probes.Joined(contexts, "; ")
end

local function Database()
    ByteTerraceDevToolsDB = (((type(ByteTerraceDevToolsDB) == "table") and ByteTerraceDevToolsDB) or {})

    return ByteTerraceDevToolsDB
end

-- Prints groups ({ [step] = { [text] = { probe name, ... } } }) as "     text: name, name" under
-- each step's heading ("  2. at a quest giver"), steps in order and texts sorted within a step.
local function PrintGroups(groups)
    for step, name in ipairs(Probes.Steps) do
        local texts = {}

        for text in pairs(groups[step] or {}) do
            texts[#texts + 1] = text
        end

        table.sort(texts)

        if #texts > 0 then
            print(("  %d. %s"):format(step, name))
        end

        for _, text in ipairs(texts) do
            print(("     %s: %s"):format(text, table.concat(groups[step][text], ", ")))
        end
    end
end

local function Say(text)
    print(Prefix .. text)
end

local function Help()
    Say("commands:")
    print("  /btdev probe - record calibration probes for the test harness, then /reload")
    print("  /btdev probe list - the probes that still need a result, and what each needs, in play-session order")
    print("  /btdev dump - record the client's globals for tlk api-sync, then /reload")
    print("  /btdev rumble - play four vibration types in turn, for gamePad.vibration")
    print("  /btdev rumble <type> [intensity 0-1] [seconds] - one vibration; without seconds it plays until it stops by itself")
    print("  /btdev rumble stop - stop any vibration")
end

local function ListProbes()
    local probes = (((type(ByteTerraceDevToolsDB) == "table") and (type(ByteTerraceDevToolsDB.probes) == "table")
        and ByteTerraceDevToolsDB.probes) or {})

    local build, missing, count = Probes.Build(), {}, 0

    for _, probe in ipairs(Probes.List) do
        local record = probes[probe.name]

        if not Probes.IsCurrent(probe, record) or (record.build ~= build) then
            count = (count + 1)
            AddToGroup(missing, probe, Probes.NeedsText(probe))
        end
    end

    if count == 0 then
        Say(("every probe has a result for %s."):format(build))

        return
    end

    Say(("%d of %d probes have no result for %s yet. Each needs, in play-session order:"):format(count,
        #Probes.List, build))

    PrintGroups(missing)
end

-- /btdev rumble's arguments, as typed (vibration types may be case-sensitive).
local function RumbleCommand(args)
    if args == "" then
        Say("playing High, Low, LTrigger and RTrigger, 1.5 seconds apart: note what each one felt like, then /btdev probe.")
        Probes.RumbleCandidates(Say)

        return
    end

    if args:lower() == "stop" then
        Probes.StopRumble()
        Say("rumble stopped.")

        return
    end

    local kind, intensityText, secondsText = args:match("^(%S+)%s*(%S*)%s*(%S*)$")
    local intensity = tonumber((((intensityText ~= "") and intensityText) or "1"))
    local seconds = (((secondsText ~= "") and tonumber(secondsText)) or nil)

    if not kind or not intensity or (intensity < 0) or (intensity > 1) or ((secondsText ~= "") and (not seconds or (seconds <= 0))) then
        Say("usage: /btdev rumble <type> [intensity 0-1] [seconds], or /btdev rumble stop")

        return
    end

    local ok, problem = Probes.Rumble(kind, intensity, seconds)

    if not ok then
        Say(("the client refused %s: %s"):format(kind, tostring(problem)))
    elseif seconds then
        Say(("rumble %s at %s for %s seconds."):format(kind, intensity, seconds))
    else
        Say(("rumble %s at %s, until it stops by itself (or /btdev rumble stop)."):format(kind, intensity))
    end
end

local function RunProbes()
    local db = Database()

    db.probes = (((type(db.probes) == "table") and db.probes) or {})
    local recorded, added, changed, confirmed, skipped, failed = 0, 0, 0, 0, {}, 0
    local build = Probes.Build()

    for _, probe in ipairs(Probes.List) do
        local met, unmet = Probes.Check(probe)
        local saved = db.probes[probe.name]

        if not met then
            -- Only probes still without a result for this build are left to do.
            if not (Probes.IsCurrent(probe, saved) and (saved.build == build)) then
                AddToGroup(skipped, probe, unmet)
            end
        else
            local record, problem = Probes.Record(probe)

            if not record then
                failed = (failed + 1)
                Say(("probe %s failed: %s"):format(probe.name, problem))
            else
                -- A changed answer is news; a new context alone (combat now, idle before) is only counted, so it
                -- doesn't bury the answers that did change.
                local kept, outcome, differences = Probes.Keep(probe, saved, record)

                if outcome == "new" then
                    added = (added + 1)
                elseif outcome == "confirmed" then
                    confirmed = (confirmed + 1)
                elseif outcome == "changed" then
                    changed = (changed + 1)

                    for _, difference in ipairs(differences) do
                        Say(("probe %s changed at result.%s: was %s, now %s"):format(probe.name, difference.path,
                            Probes.Show(difference.a), Probes.Show(difference.b)))
                    end

                    local dropped = {}

                    for context in pairs(((type(saved.contexts) == "table") and saved.contexts) or {}) do
                        if not kept.contexts[context] then
                            dropped[context] = true
                        end
                    end

                    if next(dropped) then
                        Say(("probe %s now holds only %s; the new result replaced %s"):format(probe.name,
                            ContextList(kept.contexts), ContextList(dropped)))
                    end
                end

                db.probes[probe.name] = kept
                recorded = (recorded + 1)
            end
        end
    end

    Say(("recorded %d probes (%d new, %d changed, %d confirmed in a new context or build)%s. /reload to write them.")
        :format(recorded, added, changed, confirmed, ((failed > 0) and (", " .. failed .. " failed")) or ""))

    if next(skipped) then
        print("  Skipped until their need is met, in play-session order; set it up and type /btdev probe again:")
        PrintGroups(skipped)
    end
end

local function Skip(taintedBy)
    local owner = (taintedBy or "?")

    Skipped[owner] = ((Skipped[owner] or 0) + 1)
end

-- Secure string keys of a table, sorted. A table whose keys can't be read securely (a forbidden or proxied table)
-- records none.
local function SecureKeys(tbl)
    local keys = {}

    local ok = pcall(function()
        for key in pairs(tbl) do
            if type(key) == "string" then
                local secure, taintedBy = issecurevariable(tbl, key)

                if secure then
                    keys[#keys + 1] = key
                else
                    Skip(taintedBy)
                end
            end
        end
    end)

    if not ok then
        return {}
    end

    table.sort(keys)

    return keys
end

local function DescribeTable(name, value)
    if value == _G then
        -- _G's members are the dump itself.
        return { type = "table" }
    end

    if (type(rawget(value, 0)) == "userdata") and (type(value.GetObjectType) == "function") then
        return { type = "frame" }
    end

    local members = SecureKeys(value)
    local entry = { members = members, type = "table" }

    if Nested[name] then
        entry.tables = {}

        for _, key in ipairs(members) do
            local nested = value[key]

            if type(nested) == "table" then
                entry.tables[key] = SecureKeys(nested)
            end
        end
    end

    return entry
end

local function Dump()
    local globals, count = {}, 0

    Skipped = {}

    for name, value in pairs(_G) do
        if type(name) == "string" then
            local secure, taintedBy = issecurevariable(name)

            if secure then
                local kind = type(value)

                globals[name] = (((kind == "table") and DescribeTable(name, value)) or { type = kind })
                count = (count + 1)
            else
                Skip(taintedBy)
            end
        end
    end

    local version, build, _, interface = GetBuildInfo()
    local db = Database()

    db.build = { build = build, interface = interface, version = version }
    db.globals = globals
    db.skipped = Skipped
    Say(("recorded %d client globals from %s (%s). /reload to write them."):format(count, version, build))
end

SLASH_BYTETERRACEDEVTOOLS1 = "/btdev"

SlashCmdList.BYTETERRACEDEVTOOLS = function(input)
    local typed = strtrim(input or "")
    local command = typed:lower()

    if (command == "rumble") or (command:sub(1, 7) == "rumble ") then
        RumbleCommand(strtrim(typed:sub(7)))
    elseif command == "dump" then
        Dump()
    elseif command == "probe" then
        RunProbes()
    elseif command == "probe list" then
        ListProbes()
    else
        Help()
    end
end

-- UNIT_COMBAT for unitCombat.seen, from load; RegisterUnitEvent keeps it to the two units.
local CombatListener = CreateFrame("Frame")

CombatListener:RegisterUnitEvent("UNIT_COMBAT", "player", "target")

CombatListener:SetScript("OnEvent", function(_, _, ...)
    Probes.NoteUnitCombat(...)
end)

-- Chat events' senders for names.chatSenders, from load.
local ChatListener = CreateFrame("Frame")

for _, event in ipairs({ "CHAT_MSG_ADDON", "CHAT_MSG_SAY", "CHAT_MSG_YELL", "CHAT_MSG_CHANNEL", "CHAT_MSG_PARTY",
    "CHAT_MSG_RAID", "CHAT_MSG_GUILD", "CHAT_MSG_WHISPER" }) do
    ChatListener:RegisterEvent(event)
end

ChatListener:SetScript("OnEvent", function(_, event, ...)
    if event == "CHAT_MSG_ADDON" then
        local _, _, _, sender = ...

        Probes.NoteSender(event, sender)
        Probes.NoteAddonMessage(...)
    else
        local _, author = ...

        Probes.NoteSender(event, author)
        Probes.NoteDiscordInfo(event, (select(18, ...)))
    end
end)

-- The restrictions in force, kept from load for the listeners that key by them, and the steps into and out of combat
-- for combat.edges.
Probes.SyncRestrictions()
local RestrictionListener = CreateFrame("Frame")

RestrictionListener:RegisterEvent("ADDON_RESTRICTION_STATE_CHANGED")
RestrictionListener:RegisterEvent("PLAYER_REGEN_DISABLED")
RestrictionListener:RegisterEvent("PLAYER_REGEN_ENABLED")
RestrictionListener:RegisterEvent("PLAYER_ENTERING_WORLD")

RestrictionListener:SetScript("OnEvent", function(_, event, kind, state)
    if event == "PLAYER_ENTERING_WORLD" then
        Probes.SyncRestrictions()
    elseif event == "ADDON_RESTRICTION_STATE_CHANGED" then
        Probes.NoteRestriction(kind, state)

        if kind == Enum.AddOnRestrictionType.Combat then
            Probes.NoteCombatEdge(event, state)
        end
    else
        Probes.NoteCombatEdge(event)

        if event == "PLAYER_REGEN_ENABLED" then
            Probes.NotePvPLeftCombat()
        end
    end
end)

-- UNIT_AURA's unit token for units.secretTokenInAuraEvent; RegisterUnitEvent keeps it to two units.
local AuraListener = CreateFrame("Frame")

AuraListener:RegisterUnitEvent("UNIT_AURA", "player", "target")

AuraListener:SetScript("OnEvent", function(_, _, unit)
    Probes.NoteAuraToken(unit)
end)

-- Your deaths and the damage meter's updates after them, for damageMeter.afterDeath, from load.
local MeterListener = CreateFrame("Frame")

MeterListener:RegisterEvent("PLAYER_DEAD")
MeterListener:RegisterEvent("DAMAGE_METER_COMBAT_SESSION_UPDATED")

MeterListener:SetScript("OnEvent", function(_, event, meterType)
    if event == "PLAYER_DEAD" then
        Probes.NoteDeath()
    else
        Probes.NoteMeterUpdate(meterType)
    end
end)

-- The kill events for kills.seen, from load.
local KillListener = CreateFrame("Frame")

KillListener:RegisterEvent("PARTY_KILL")
KillListener:RegisterEvent("PLAYER_TARGET_DIED")
KillListener:RegisterEvent("UNIT_DIED")

KillListener:SetScript("OnEvent", function(_, event, ...)
    Probes.NoteKill(event, ...)
end)

-- Controller and interface events for input.events, from load, and the first PLAYER_ENTERING_WORLD, so it can say which
-- fired before it.
local InputListener = CreateFrame("Frame")

for _, event in ipairs(Probes.InputEvents) do
    InputListener:RegisterEvent(event)
end

InputListener:RegisterEvent("PLAYER_ENTERING_WORLD")

InputListener:SetScript("OnEvent", function(self, event, ...)
    if event == "PLAYER_ENTERING_WORLD" then
        Probes.NoteWorldEntered()
        self:UnregisterEvent("PLAYER_ENTERING_WORLD")
    else
        Probes.NoteInputEvent(event, ...)
    end
end)

-- Boss encounters' starts and warnings for encounterWarning.seen, from load.
local EncounterListener = CreateFrame("Frame")

EncounterListener:RegisterEvent("ENCOUNTER_START")
EncounterListener:RegisterEvent("ENCOUNTER_WARNING")

EncounterListener:SetScript("OnEvent", function(_, event, info)
    if event == "ENCOUNTER_START" then
        Probes.NoteEncounterStart()
    else
        Probes.NoteEncounterWarning(info)
    end
end)
