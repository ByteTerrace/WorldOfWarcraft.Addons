local addonName, ns = ...

-- Development only; never shipped. Two commands record facts about the client, and /reload
-- afterwards writes them to WTF\Account\<account>\SavedVariables\ByteTerrace_DevTools.lua:
--
--   /btdev dump        every global the client exposes (name, type, and for plain tables their
--                      member names), plus the build it came from, for
--                      `node tools/tlk.mjs api-sync --globals <that file>` (tools/api/forever.json).
--   /btdev probe       every calibration probe (Probes.lua and the files it names) whose needs are
--                      met right now, merged into the probes already recorded, for
--                      `node tools/tlk.mjs probes --import` (tools/api/probes.json). Probes it
--                      skips are printed with what they need.
--   /btdev probe list  the probes with no result for this build yet, grouped by what they need,
--                      in the order one play session in a starting zone reaches them (Probes.Steps).
--
-- From load it also listens for UNIT_COMBAT on the player and the target, for the unitCombat.seen
-- probe (Probes.NoteUnitCombat keeps the payloads' shapes), for the kill events, for
-- kills.seen (Probes.NoteKill), and for chat events' senders, for names.chatSenders
-- (Probes.NoteSender keeps their shapes, never the names).
--
-- Only the client's own names are dumped. A global or table member any addon set is tainted by
-- that addon (issecurevariable), so it's counted under `skipped` instead, per addon: other addons'
-- keys in Blizzard tables (SlashCmdList.MYADDON) never reach the snapshot.
--
-- Tables listed in Nested are dumped one level deeper: `tables` maps each member that is itself a
-- table to its member names, so the gate can check Enum.PowerType.Energy.
--
-- ByteTerraceDevToolsDB holds build, globals and skipped (the dump, what api-sync reads) and
-- probes (probe name -> record, what `tlk probes` reads). Each command replaces only its own part.

local Nested = { Enum = true }
local Probes = ns.Probes
local Prefix = "ByteTerrace DevTools: "

-- [addon name] = tainted keys skipped, for the dump in progress.
local Skipped

local function Skip(taintedBy)
    local owner = taintedBy or "?"
    Skipped[owner] = (Skipped[owner] or 0) + 1
end

-- Secure string keys of a table, sorted. A table whose keys can't be read securely (a forbidden
-- or proxied table) records none.
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
        return { type = "table" } -- its members are the dump itself
    end
    if type(rawget(value, 0)) == "userdata" and type(value.GetObjectType) == "function" then
        return { type = "frame" }
    end
    local members = SecureKeys(value)
    local entry = { type = "table", members = members }
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

local function Database()
    ByteTerraceDevToolsDB = type(ByteTerraceDevToolsDB) == "table" and ByteTerraceDevToolsDB or {}
    return ByteTerraceDevToolsDB
end

local function Say(text)
    print(Prefix .. text)
end

local function Dump()
    local globals, count = {}, 0
    Skipped = {}
    for name, value in pairs(_G) do
        if type(name) == "string" then
            local secure, taintedBy = issecurevariable(name)
            if secure then
                local kind = type(value)
                globals[name] = kind == "table" and DescribeTable(name, value) or { type = kind }
                count = count + 1
            else
                Skip(taintedBy)
            end
        end
    end
    local version, build, _, interface = GetBuildInfo()
    local db = Database()
    db.build = { version = version, build = build, interface = interface }
    db.globals = globals
    db.skipped = Skipped
    Say(("recorded %d client globals from %s (%s). /reload to write them."):format(count, version, build))
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

-- Files a probe under the play-session step that meets all its needs, and a text.
local function AddToGroup(groups, probe, text)
    local step = Probes.Step(probe)
    groups[step] = groups[step] or {}
    groups[step][text] = groups[step][text] or {}
    table.insert(groups[step][text], probe.name)
end

local function RunProbes()
    local db = Database()
    db.probes = type(db.probes) == "table" and db.probes or {}
    local recorded, added, changed, skipped, failed = 0, 0, 0, {}, 0
    for _, probe in ipairs(Probes.List) do
        local met, unmet = Probes.Check(probe)
        if not met then
            AddToGroup(skipped, probe, unmet)
        else
            local record, problem = Probes.Record(probe)
            if not record then
                failed = failed + 1
                Say(("probe %s failed: %s"):format(probe.name, problem))
            else
                local previous = db.probes[probe.name]
                if not Probes.IsCurrent(probe, previous) then
                    previous = nil -- an older version's record answered another question
                end
                local differences = previous and Probes.Diff(previous, record) or {}
                if not previous then
                    added = added + 1
                elseif #differences > 0 then
                    changed = changed + 1
                    for _, difference in ipairs(differences) do
                        Say(("probe %s changed at %s: was %s, now %s"):format(probe.name, difference.path,
                            Probes.Show(difference.a), Probes.Show(difference.b)))
                    end
                end
                db.probes[probe.name] = record
                recorded = recorded + 1
            end
        end
    end
    Say(("recorded %d probes (%d new, %d changed)%s. /reload to write them."):format(recorded, added, changed,
        failed > 0 and (", " .. failed .. " failed") or ""))
    if next(skipped) then
        print("  Skipped until their need is met, in play-session order; set it up and type /btdev probe again:")
        PrintGroups(skipped)
    end
end

local function ListProbes()
    local probes = type(ByteTerraceDevToolsDB) == "table" and type(ByteTerraceDevToolsDB.probes) == "table"
        and ByteTerraceDevToolsDB.probes or {}
    local build, missing, count = Probes.Build(), {}, 0
    for _, probe in ipairs(Probes.List) do
        local record = probes[probe.name]
        if not Probes.IsCurrent(probe, record) or record.build ~= build then
            count = count + 1
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

local function Help()
    Say("commands:")
    print("  /btdev probe - record calibration probes for the test harness, then /reload")
    print("  /btdev probe list - the probes that still need a result, and what each needs, in play-session order")
    print("  /btdev dump - record the client's globals for tlk api-sync, then /reload")
end

SLASH_BYTETERRACEDEVTOOLS1 = "/btdev"
SlashCmdList.BYTETERRACEDEVTOOLS = function(input)
    local command = strtrim(input or ""):lower()
    if command == "dump" then
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
    else
        local _, author = ...
        Probes.NoteSender(event, author)
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
