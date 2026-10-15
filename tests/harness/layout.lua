-- Layout of the fake client's widgets (widgets.lua uses it): deterministic stand-ins for the sizes the client computes.
-- A FontString's text is CharWidth px per character (the longest line) by LineHeight px per line, wrapped at character
-- boundaries to its width unless SetWordWrap(false); a region's size along an axis is its anchored size (two opposite
-- anchors on the same relative region, or SetAllPoints), else its set size, else 0 (a FontString falls back to its
-- string size).
--
--   Harness.Layout.Anchor(state, point, ...)            SetPoint's arguments as an anchor; a point replaces the same one
--   Harness.Layout.Size(widget, axis)                   a widget's size along Axes.x or Axes.y
--   Harness.Layout.Lines(state, bound)                  a FontString's line lengths in characters, wrapped at bound
--   Harness.Layout.Anchored, Axes, LineHeight, Longest  the pieces Size is built from
--   h:WidgetWidth(widget), h:WidgetHeight(widget)

local State = Harness.State

local Bottom = { BOTTOM = true, BOTTOMLEFT = true, BOTTOMRIGHT = true }
local CharWidth, LineHeight = 7, 14
local Left = { BOTTOMLEFT = true, LEFT = true, TOPLEFT = true }
local Right = { BOTTOMRIGHT = true, RIGHT = true, TOPRIGHT = true }
local Top = { TOP = true, TOPLEFT = true, TOPRIGHT = true }

local Axes = {
    x = { high = Right, low = Left, offset = "x", size = "width" },
    y = { high = Top, low = Bottom, offset = "y", size = "height" },
}

local Size

-- SetPoint(point [, relativeTo [, relativePoint]] [, x, y]); a point replaces the same point.
local function Anchor(s, point, a, b, c, d)
    local relativeTo, relativePoint, x, y

    if (a == nil) or (type(a) == "number") then
        x, y = a, b
    else
        relativeTo = a

        if type(b) == "string" then relativePoint, x, y = b, c, d else x, y = b, c end
    end

    local anchor = { point = point, relativePoint = (relativePoint or point), relativeTo = relativeTo, x = (x or 0), y = (y or 0) }

    s.allPoints = nil

    for i, existing in ipairs(s.points) do
        if existing.point == point then
            s.points[i] = anchor

            return
        end
    end

    s.points[#s.points + 1] = anchor
end

-- Where a point sits along an axis of a region of the given size (low edge 0).
local function Edge(axis, point, size)
    if axis.low[point] then return 0 elseif axis.high[point] then return size end

    return (size / 2)
end

-- The size along an axis that two opposite anchors on the same relative region give, or nil.
local function Anchored(s, axis, depth)
    if s.allPoints then
        return Size(s.allPoints, axis, depth + 1)
    end

    local low, high

    for _, p in ipairs(s.points) do
        if axis.low[p.point] then low = p elseif axis.high[p.point] then high = p end
    end

    local relative = (low and high and (low.relativeTo or s.parent))

    if not relative or ((high.relativeTo or s.parent) ~= relative) or (type(relative) ~= "table") or not State(relative) then
        return nil
    end

    local size = Size(relative, axis, depth + 1)
    local span = ((Edge(axis, high.relativePoint, size) + high[axis.offset]) - (Edge(axis, low.relativePoint, size) + low[axis.offset]))

    return math.max(span, 0)
end

-- Line lengths (in characters) of a FontString's text, wrapped at bound (0 = unbounded).
local function Lines(s, bound)
    local text = Reveal(s.text)

    if (text == nil) or (text == "") then
        return {}
    end

    local lines, perLine = {}, (((bound > 0) and (s.wordWrap ~= false) and math.max(1, math.floor(bound / CharWidth))) or nil)

    for line in (tostring(text) .. "\n"):gmatch("(.-)\n") do
        line = line:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
        local n = select(2, line:gsub("[^\128-\191]", ""))

        while perLine and (n > perLine) do
            lines[#lines + 1] = perLine
            n = (n - perLine)
        end

        lines[#lines + 1] = n
    end

    return lines
end

local function Longest(lines)
    local longest = 0

    for _, n in ipairs(lines) do longest = math.max(longest, n) end

    return (longest * CharWidth)
end

-- A FontString's own text size, for an axis it has no set or anchored size on.
local function StringSize(s, axis, depth)
    if axis == Axes.x then
        return Longest(Lines(s, 0))
    end

    return (#Lines(s, Anchored(s, Axes.x, depth) or s.width or 0) * LineHeight)
end

function Harness:WidgetHeight(widget) return Size(widget, Axes.y) end

function Harness:WidgetWidth(widget) return Size(widget, Axes.x) end

function Size(widget, axis, depth)
    depth = (depth or 0)

    if depth > 20 then
        return 0
    end

    local s = State(widget)
    local anchored = Anchored(s, axis, depth)

    if anchored then
        return anchored
    end

    local set = s[axis.size]

    if set then
        return set
    end

    if s.widgetType == "FontString" then
        return StringSize(s, axis, depth)
    end

    return 0
end

Harness.Layout = {
    Anchor = Anchor, Anchored = Anchored, Axes = Axes, LineHeight = LineHeight, Lines = Lines, Longest = Longest, Size = Size,
}
