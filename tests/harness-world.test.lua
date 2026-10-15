-- The harness's fidelity rules for the world (tests/harness/world.lua): location, maps and
-- waypoints, honor and raid warnings.

local function Watch(h, ...)
    local seen = {}
    local frame = h.env.CreateFrame("Frame")

    for _, event in ipairs({ ... }) do
        frame:RegisterEvent(event)
    end
    frame:SetScript("OnEvent", function(_, event, ...)
        local parts = { event }

        for i = 1, select("#", ...) do
            parts[#parts + 1] = tostring(Reveal((select(i, ...))))
        end
        seen[#seen + 1] = table.concat(parts, ":")
    end)
    return seen
end

local Hillsbrad = 1424

local function WithMaps()
    local h = Harness.New()

    h:AddMap(Hillsbrad, { mapType = "Zone", name = "Hillsbrad Foothills", parentMapID = 1415 })
    h:AddMap(1415, { mapType = "Continent", name = "Eastern Kingdoms" })
    h:AddMap(229, { mapType = "Dungeon", name = "Deadmines" })
    return h
end

test("SetLocation: a new zone fires ZONE_CHANGED_NEW_AREA, a new subzone alone ZONE_CHANGED", function()
    local h = WithMaps()
    local env = h.env
    local seen = Watch(h, "ZONE_CHANGED", "ZONE_CHANGED_NEW_AREA")

    h:SetLocation({ mapID = Hillsbrad, subZone = "Southshore", x = 0.5, y = 0.25, zone = "Hillsbrad Foothills" })
    eq(env.GetRealZoneText(), "Hillsbrad Foothills")
    eq(env.GetSubZoneText(), "Southshore")
    h:SetLocation({ subZone = "Tarren Mill" })
    h:SetLocation({ subZone = "Tarren Mill" })
    eq(table.concat(seen, ","), "ZONE_CHANGED_NEW_AREA,ZONE_CHANGED", "no event without a change")
    eq(env.C_Map.GetBestMapForUnit("player"), Hillsbrad)
end)

test("GetPlayerMapPosition: a vector on the player's own map, nil elsewhere, in an instance and for strangers", function()
    local h = WithMaps()
    local env = h.env

    h:SetLocation({ mapID = Hillsbrad, x = 0.5, y = 0.25, zone = "Hillsbrad Foothills" })
    local position = env.C_Map.GetPlayerMapPosition(Hillsbrad, "player")
    local x, y = position:GetXY()

    eq(x, 0.5)
    eq(y, 0.25)
    eq(position.x, 0.5)
    eq(env.C_Map.GetPlayerMapPosition(1415, "player"), nil, "parent maps aren't projected")
    h:SetTarget({ canAttack = true, isPlayer = true, name = "Bob" })
    eq(env.C_Map.GetPlayerMapPosition(Hillsbrad, "target"), nil, "only the player and party members")
    eq(env.C_Map.GetBestMapForUnit("target"), nil)
    h:JoinGroup("party", { { mapID = Hillsbrad, mapPosition = { x = 0.1, y = 0.2 }, name = "Mom" } })
    eq(select(2, env.C_Map.GetPlayerMapPosition(Hillsbrad, "party1"):GetXY()), 0.2)
    h:SetLocation({ instance = "party", mapID = 229, zone = "The Deadmines" })
    eq(env.C_Map.GetBestMapForUnit("player"), 229, "the instance's map")
    eq(env.C_Map.GetPlayerMapPosition(229, "player"), nil, "no position in an instance")
    local inInstance, kind = env.IsInInstance()

    truthy(inInstance)
    eq(kind, "party")
    h:SetLocation({ instance = false })
    eq(select(2, env.IsInInstance()), "none")
end)

test("AddMap knows only Enum.UIMapType names", function()
    local h = Harness.New()

    throws(function() h:AddMap(1, { mapType = "Planet", name = "X" }) end, "unknown mapType")
end)

test("user waypoints: set on a map that allows them, USER_WAYPOINT_UPDATED, super tracked", function()
    local h = WithMaps()
    local env = h.env
    local seen = Watch(h, "USER_WAYPOINT_UPDATED", "SUPER_TRACKING_CHANGED")

    truthy(env.C_Map.CanSetUserWaypointOnMap(Hillsbrad))
    falsy(env.C_Map.CanSetUserWaypointOnMap(229), "not in a dungeon")
    env.C_SuperTrack.SetSuperTrackedUserWaypoint(true)
    falsy(h.superTracked, "nothing to super track")
    falsy(env.C_Map.SetUserWaypoint(env.UiMapPoint.CreateFromCoordinates(229, 0.5, 0.5)), "refused")
    eq(#seen, 0)
    truthy(env.C_Map.SetUserWaypoint(env.UiMapPoint.CreateFromCoordinates(Hillsbrad, 0.5, 0.25, 3)))
    eq(h.waypoint.uiMapID, Hillsbrad)
    eq(h.waypoint.x .. "," .. h.waypoint.y .. "," .. h.waypoint.z, "0.5,0.25,3")
    env.C_SuperTrack.SetSuperTrackedUserWaypoint(true)
    truthy(h.superTracked)
    eq(table.concat(seen, ","), "USER_WAYPOINT_UPDATED,SUPER_TRACKING_CHANGED")
    falsy(env.C_Map.CanSetUserWaypointOnMap(9999), "no such map")
    falsy(env.C_Map.SetUserWaypoint(env.UiMapPoint.CreateFromCoordinates(9999, 0.5, 0.5)))
end)

test("AlwaysAllowUserWaypoints and canSetWaypoint override the map type rule", function()
    local h = Harness.New()
    local flags = h.env.Enum.UIMapFlag

    h:AddMap(1, { flags = (flags.AlwaysAllowUserWaypoints + flags.NoHighlight), mapType = "Dungeon", name = "City" })
    h:AddMap(2, { canSetWaypoint = false, mapType = "Zone", name = "Blocked" })
    truthy(h.env.C_Map.CanSetUserWaypointOnMap(1))
    falsy(h.env.C_Map.CanSetUserWaypointOnMap(2))
end)

test("honorable kills fire CHAT_MSG_COMBAT_HONOR_GAIN with the Forever enUS text and 18 fields", function()
    local h = Harness.New()
    local env = h.env
    local got
    local frame = env.CreateFrame("Frame")

    frame:RegisterEvent("CHAT_MSG_COMBAT_HONOR_GAIN")
    frame:SetScript("OnEvent", function(_, _, ...) got = { n = select("#", ...), ... } end)
    eq(env.COMBATLOG_HONORGAIN, "%s dies (Honorable Kill: %s). You gain %d Honor.")
    eq(env.COMBATLOG_HONORGAIN_NO_RANK, "%s dies (Honorable Kill). You gain %d Honor.")
    eq(env.COMBATLOG_HONORAWARD, "You have been awarded %d Honor.")
    eq(h:HonorKill("Bob", "Sergeant", 12), "Bob dies (Honorable Kill: Sergeant). You gain 12 Honor.")
    eq(got.n, 18)
    eq(got[1], "Bob dies (Honorable Kill: Sergeant). You gain 12 Honor.")
    eq(got[2], "")
    eq(got[11], 1, "lineID")
    eq(got[12], "")
    eq(got[14], false)
    h:HonorKill("Bob", nil, 7)
    eq(got[1], "Bob dies (Honorable Kill). You gain 7 Honor.")
    eq(got[11], 2)
    h:AwardHonor(50)
    eq(got[1], "You have been awarded 50 Honor.")
end)

test("the honor message has no secret flags: plain even under chat lockdown", function()
    local h = Harness.New()
    local got
    local frame = h.env.CreateFrame("Frame")

    frame:RegisterEvent("CHAT_MSG_COMBAT_HONOR_GAIN")
    frame:SetScript("OnEvent", function(_, _, text) got = text end)
    h:SetRestriction("Chat", true)
    h:SetRestriction("PvPMatch", true)
    h:HonorKill("Bob", "Sergeant", 12)
    falsy(h.env.issecretvalue(got))
end)

test("RaidWarningUtil.AddMessage records the message with its color", function()
    local h = Harness.New()
    local env = h.env
    local color = env.ChatTypeInfo.RAID_WARNING

    eq(color.r, 1)
    eq(color.b, 0)
    env.RaidWarningUtil.AddMessage("RALLY!", color, 5)
    env.RaidWarningUtil.AddMessage("Second", { r = Secret(1), g = 0, b = 0 }) -- colors take secrets
    eq(#h.raidNotices, 2)
    eq(h.raidNotices[1].text, "RALLY!")
    eq(h.raidNotices[1].color, color)
    eq(h.raidNotices[1].displayTime, 5)
    throws(function() return env.ChatTypeInfo.SAY end, "isn't modeled")
end)

test("RaidWarningUtil.AddMessage refuses what RaidWarningFrame can't use: secret text or time, no color", function()
    local h = Harness.New()
    local env = h.env
    local color = env.ChatTypeInfo.RAID_WARNING

    throws(function() env.RaidWarningUtil.AddMessage(Secret("hidden"), color) end, "compute with a secret")
    throws(function() env.RaidWarningUtil.AddMessage("x", color, Secret(5)) end, "compare a secret")
    throws(function() env.RaidWarningUtil.AddMessage("x") end, "index local 'colorInfo'")
    eq(#h.raidNotices, 0)
end)
