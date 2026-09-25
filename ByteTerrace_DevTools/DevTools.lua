-- Development only; never shipped. `/btdev dump` records every global the client exposes
-- (name, type, and for plain tables their member names), plus the build it came from.
-- /reload afterwards writes it to WTF\Account\<account>\SavedVariables\ByteTerrace_DevTools.lua,
-- which `node tools/tlk.mjs api-sync --globals <that file>` turns into tools/api/forever.json.

local function DescribeTable(value)
    if value == _G then
        return { type = "table" } -- its members are the dump itself
    end
    if type(value.GetObjectType) == "function" then
        return { type = "frame" }
    end
    local members = {}
    for key in pairs(value) do
        if type(key) == "string" then
            members[#members + 1] = key
        end
    end
    table.sort(members)
    return { type = "table", members = members }
end

-- Only the client's own globals are recorded: a global any addon set is tainted by that addon
-- (issecurevariable), and is counted under `skipped` instead, per addon.
local function Dump()
    local globals, skipped, count = {}, {}, 0
    for name, value in pairs(_G) do
        if type(name) == "string" then
            local secure, taintedBy = issecurevariable(name)
            if secure then
                local kind = type(value)
                globals[name] = kind == "table" and DescribeTable(value) or { type = kind }
                count = count + 1
            else
                local owner = taintedBy or "?"
                skipped[owner] = (skipped[owner] or 0) + 1
            end
        end
    end
    local version, build, _, interface = GetBuildInfo()
    ByteTerraceDevToolsDB = {
        build = { version = version, build = build, interface = interface },
        globals = globals,
        skipped = skipped,
    }
    print(("ByteTerrace DevTools: recorded %d client globals from %s (%s). /reload to write them."):format(count, version, build))
end

SLASH_BYTETERRACEDEVTOOLS1 = "/btdev"
SlashCmdList.BYTETERRACEDEVTOOLS = function(input)
    if strtrim(input or ""):lower() == "dump" then
        Dump()
    else
        print("ByteTerrace DevTools: /btdev dump")
    end
end
