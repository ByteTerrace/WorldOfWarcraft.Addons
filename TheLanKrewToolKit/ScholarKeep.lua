local addonName, ns = ...

-- ScholarKeep: keeps the riddle on screen in the Scholar module's riddle row (ScholarSettings.lua) until it's solved or
-- skipped, so a /reload, a relog, or the challenge switched off and on brings back the same riddle, with its misses and
-- missed answers. A riddle is plain data (strings, numbers, booleans, and tables of them), written as text by a small
-- codec. Reading saved text only ever decodes data: nothing in it runs.
--
--   ns.ScholarKeep.Encode(value) -> text or nil     nil when value holds anything but plain data, or a secret
--   ns.ScholarKeep.Decode(text) -> value or nil     nil for any text Encode couldn't have written
--   ns.ScholarKeep.Save(module, puzzle, wrongs, missed)
--                                                    keeps the riddle, its miss count, and its missed answers
--                                                    (a set of indices), or clears the row if it can't be written
--   ns.ScholarKeep.Winks                             what the Owl says, playfully, to a riddle a /reload or relog
--                                                    brought back: it noticed, and it's glad to see you
--   ns.ScholarKeep.Take(module) -> puzzle, wrongs, missed or nil
--                                                    the kept riddle, or nil (clearing the row) when there's none
--                                                    or it isn't a riddle Save wrote

-- How deep tables nest before Decode refuses the text.
local MaxDepth = 12

local Winks = {
    "Hoo! You vanished and came back, but so did I. Same riddle, little wizard!",
    "Poof, you're back! I kept your riddle warm for you.",
    "Whooo's that sneaking back in? It's you! Your riddle missed you.",
}

local concat = table.concat
local format = string.format
local huge = math.huge
local ipairs = ipairs
local issecretvalue = issecretvalue
local pairs = pairs
local sort = table.sort
local sub = string.sub
local tonumber = tonumber
local type = type

-- Whether n is a whole number from 1 to 4: an answer's index.
local function IsChoice(n)
    return ((type(n) == "number") and (n >= 1) and (n <= 4) and ((n % 1) == 0))
end

-- Whether puzzle has what the riddle screen needs: a prompt, four choices, its answer among them, a kind, a subject,
-- and the reasons wrong choices are wrong.
local function IsRiddle(puzzle)
    if (type(puzzle) ~= "table") or (type(puzzle.prompt) ~= "string") or (type(puzzle.kind) ~= "string")
        or (type(puzzle.subject) ~= "string") or (type(puzzle.choices) ~= "table") or (type(puzzle.whys) ~= "table")
        or not IsChoice(puzzle.answer) then
        return false
    end

    for i = 1, 4 do
        if type(puzzle.choices[i]) ~= "string" then
            return false
        end
    end

    return true
end

-- Reads one value from text at i, returning it and the position after it, or nil when the text is malformed.
local function Read(text, i, depth)
    local tag = sub(text, i, i)

    if tag == "s" then
        local colon = text:find(":", i + 1, true)
        local length = (colon and sub(text, i + 1, colon - 1):match("^%d+$") and tonumber(sub(text, i + 1, colon - 1)))

        if not length or ((colon + length) > #text) then
            return nil
        end

        return sub(text, colon + 1, colon + length), ((colon + length) + 1)
    elseif tag == "n" then
        local semicolon = text:find(";", i + 1, true)
        local number = (semicolon and tonumber(sub(text, i + 1, semicolon - 1)))

        if not number or (number ~= number) or (number == huge) or (number == -huge) then
            return nil
        end

        return number, (semicolon + 1)
    elseif (tag == "T") or (tag == "F") then
        return (tag == "T"), (i + 1)
    elseif (tag == "{") and (depth < MaxDepth) then
        local value = {}

        i = (i + 1)

        while sub(text, i, i) ~= "}" do
            local key, after = Read(text, i, depth)

            if (type(key) ~= "string") and (type(key) ~= "number") then
                return nil
            end

            local item, next = Read(text, after, depth + 1)

            if item == nil then
                return nil
            end

            value[key], i = item, next
        end

        return value, (i + 1)
    end

    return nil
end

--- Returns the value text holds, or nil for any text Encode couldn't have written, including text with anything after
--- its value.
---@param text string
---@return any
local function Decode(text)
    if (type(text) ~= "string") or (text == "") then
        return nil
    end

    local value, after = Read(text, 1, 0)

    return ((((value ~= nil) and (after == (#text + 1))) and value) or nil)
end

--- Returns the kept riddle, how many of its tries missed, and its missed answers as a set, or nil when none is kept.
--- Text that isn't a riddle Save wrote is cleared.
---@param module table the Scholar module
---@return table|nil puzzle, number wrongs, table missed
local function Take(module)
    local text = module:Get("riddle")

    if text == "" then
        return nil
    end

    local kept = Decode(text)
    local wrongs = ((type(kept) == "table") and kept.wrongs)

    if (type(kept) ~= "table") or not IsRiddle(kept.puzzle) or (type(wrongs) ~= "number") or (wrongs < 0) or ((wrongs % 1) ~= 0)
        or (type(kept.missed) ~= "table") then
        module:Set("riddle", "")

        return nil
    end

    local missed = {}

    for _, i in ipairs(kept.missed) do
        if IsChoice(i) then
            missed[i] = true
        end
    end

    return kept.puzzle, wrongs, missed
end

-- Appends value's encoding to parts, returning false when value can't be written.
local function Write(value, parts, depth)
    local kind = type(value)

    if (kind == "string") or (kind == "number") then
        if issecretvalue(value) then
            return false
        end
    end

    if kind == "string" then
        parts[#parts + 1] = ("s" .. #value .. ":" .. value)
    elseif kind == "number" then
        if (value ~= value) or (value == huge) or (value == -huge) then
            return false
        end

        parts[#parts + 1] = ("n" .. format("%.17g", value) .. ";")
    elseif kind == "boolean" then
        parts[#parts + 1] = ((value and "T") or "F")
    elseif (kind == "table") and (depth < MaxDepth) then
        local keys = {}

        for key in pairs(value) do
            local keyKind = type(key)

            if (keyKind ~= "string") and (keyKind ~= "number") then
                return false
            end

            keys[#keys + 1] = key
        end

        -- Sorted, so the same riddle always writes the same text.
        sort(keys, function(a, b)
            if type(a) == type(b) then
                return (a < b)
            end

            return (type(a) == "number")
        end)

        parts[#parts + 1] = "{"

        for _, key in ipairs(keys) do
            if not Write(key, parts, depth) or not Write(value[key], parts, depth + 1) then
                return false
            end
        end

        parts[#parts + 1] = "}"
    else
        return false
    end

    return true
end

--- Returns value written as text, or nil when it holds anything but strings, finite numbers, booleans, and tables of
--- them keyed by strings and numbers, or a secret value.
---@param value any
---@return string|nil
local function Encode(value)
    local parts = {}

    return ((Write(value, parts, 0) and concat(parts)) or nil)
end

--- Keeps the riddle on screen in the module's riddle row: the riddle, how many of its tries missed, and which answers
--- missed. A riddle that can't be written clears the row, so a /reload asks a fresh one.
---@param module table the Scholar module
---@param puzzle table the riddle
---@param wrongs number how many of its tries missed
---@param missed table [index] = true for each missed answer
local function Save(module, puzzle, wrongs, missed)
    local list = {}

    for i = 1, 4 do
        if missed[i] then
            list[#list + 1] = i
        end
    end

    module:Set("riddle", (Encode({ missed = list, puzzle = puzzle, wrongs = wrongs }) or ""))
end

ns.ScholarKeep = { Decode = Decode, Encode = Encode, Save = Save, Take = Take, Winks = Winks }
