-- Widgets of the fake client: frames, regions and animations. Every method must exist in the
-- snapshot's widget API tables for the widget's type; each call is counted and runs through
-- Harness:WrapApi (secrets.lua) with the method's snapshot entry. Methods with a behavior below
-- keep the state tests and addons read back; the rest only record the call.
--
-- A widget is an empty table with a method metatable, like the client's: the addon owns every
-- field on it (button.text, f.shown, bar.value, g.events are the addon's). The harness keeps a
-- widget's state in a weak side table; tests read it with Harness.State(widget) (or
-- h:WidgetState(widget)): { widgetType, name, template, parent, children, shown, alpha, text,
-- value, min, max, width, height, points, scripts, events, calls, secretAspects, protected, ... }.
--
-- Sizes are deterministic stand-ins for layout: a FontString's text is 7 px per character (the
-- longest line) by 14 px per line, wrapped at character boundaries to its width (SetWidth, or
-- two horizontal anchors on the same relative region) unless SetWordWrap(false). A region's
-- GetWidth/GetHeight is its anchored size (two opposite anchors on the same relative region, or
-- SetAllPoints), else its set size, else 0 (a FontString falls back to its string size).
--
-- A frame's strata is its own (SetFrameStrata), else its parent's, else MEDIUM; its level is its
-- own (SetFrameLevel), else one above its parent's, else 0. Keyboard input (h:Key) follows them.
--
-- GetChildren / GetNumChildren list a frame's child frames and GetRegions / GetNumRegions its
-- font strings and textures, in creation order ([G] the order).
--
-- Visibility: [D] OnShow runs when a widget becomes visible (it and every ancestor shown) and
-- OnHide when it stops being visible, for the widget whose Show/Hide/SetShown changed it and each
-- descendant whose visibility changed with it; showing a shown widget, or showing one under a
-- hidden parent, runs nothing. [G] The widget runs first, then its descendants depth first in
-- creation order. Reparenting (SetParent) runs neither.
--
-- Moving (warcraft.wiki.gg Frame:StartMoving, Frame:RegisterForDrag): SetMovable / IsMovable,
-- SetClampedToScreen / IsClampedToScreen ([G] clamping itself isn't modeled), SetUserPlaced /
-- IsUserPlaced and RegisterForDrag(...buttons) (none clears; each call replaces the last) keep
-- their state. [D] StartMoving on a frame that isn't movable is an error ("Frame is not
-- movable"); otherwise it marks the frame user placed and moving, and the frame follows the
-- mouse (h:Drag, input.lua) until StopMovingOrSizing or until it stops being visible.
-- [G] The client re-anchors a moved frame to the nearest screen corner; the harness has no screen
-- coordinates, so a move shifts each of the frame's anchors by the mouse's travel and keeps their
-- points and relative regions. Verify saved positions in game.
--
-- Scrolling: a ScrollFrame shows its scroll child (SetScrollChild) through its own size, moved up
-- by its vertical scroll (SetVerticalScroll). [D] GetVerticalScrollRange is how far it can scroll:
-- the child's height less the frame's, never below 0 (SimpleScrollFrameAPI). [G] SetVerticalScroll
-- keeps any offset; Blizzard's ScrollFrame_OnMouseWheel clamps to the range itself. Which part of
-- the child is visible isn't modeled. EnableMouseWheel / IsMouseWheelEnabled keep their state, and
-- h:MouseWheel (input.lua) turns the wheel over a frame.
--
-- GameTooltip and NamePlate are the client's own frame types (the env's GameTooltip, the plates
-- C_NamePlate returns). Methods the API docs don't list for a type come from
-- Harness.TYPE_METHODS, with behaviors in Harness.TYPE_BEHAVIORS (ui.lua).

local Snapshot = __snapshot
local State = Harness.State

local FrameScriptObject = { "SimpleObjectAPI", "SimpleFrameScriptObjectAPI" }
local ScriptRegion = { "SimpleScriptRegionAPI", "SimpleScriptRegionResizingAPI", "SimpleAnimatableObjectAPI" }

-- Most-derived API first: the first API that lists a method supplies its entry.
local function Chain(...)
    local out = {}
    for _, list in ipairs({ ... }) do
        for _, api in ipairs(type(list) == "table" and list or { list }) do
            out[#out + 1] = api
        end
    end
    return out
end

local WidgetApis = {
    Frame = Chain("SimpleFrameAPI", ScriptRegion, FrameScriptObject),
    Button = Chain("SimpleButtonAPI", "SimpleFrameAPI", ScriptRegion, FrameScriptObject),
    StatusBar = Chain("SimpleStatusBarAPI", "SimpleFrameAPI", ScriptRegion, FrameScriptObject),
    ScrollFrame = Chain("SimpleScrollFrameAPI", "SimpleFrameAPI", ScriptRegion, FrameScriptObject),
    FontString = Chain("SimpleFontStringAPI", "SimpleRegionAPI", ScriptRegion, FrameScriptObject),
    Texture = Chain("SimpleTextureAPI", "SimpleTextureBaseAPI", "SimpleRegionAPI", ScriptRegion, FrameScriptObject),
    -- A mask shapes the textures it's added to; it has a texture's base API but no drawing of its own.
    MaskTexture = Chain("SimpleTextureBaseAPI", "SimpleRegionAPI", ScriptRegion, FrameScriptObject),
    AnimationGroup = Chain("SimpleAnimGroupAPI", FrameScriptObject),
    Alpha = Chain("SimpleAnimAlphaAPI", "SimpleAnimAPI", FrameScriptObject),
    Translation = Chain("SimpleAnimTranslationAPI", "SimpleAnimAPI", FrameScriptObject),
    Scale = Chain("SimpleAnimScaleAPI", "SimpleAnimAPI", FrameScriptObject),
    -- The client's own frames of these types (GameTooltip, nameplates); addons don't create them here.
    GameTooltip = Chain("FrameAPITooltip", "SimpleFrameAPI", ScriptRegion, FrameScriptObject),
    NamePlate = Chain("FrameAPINamePlate", "SimpleFrameAPI", ScriptRegion, FrameScriptObject),
}
Harness.WIDGET_APIS = WidgetApis

local IsFrame = { Frame = true, Button = true, StatusBar = true, ScrollFrame = true, GameTooltip = true, NamePlate = true }

-- Template-provided methods that aren't C API (BackdropTemplateMixin).
local TemplateMethods = { BackdropTemplate = { SetBackdrop = true, SetBackdropColor = true, SetBackdropBorderColor = true } }

-- Methods a widget type has that the generated API docs don't list, by kind: "C" for the client's
-- undocumented C methods (they get the undocumented default: no secret arguments), "Lua" for
-- Blizzard's mixin methods (exempt, like Harness.LUA_FAKES). GameTooltip's C methods are the ones
-- Ketho/BlizzardInterfaceResources (forever branch, 1.60.1) lists for GameTooltip; its Lua ones
-- come from GameTooltipDataMixin and TooltipDataHandlerMixin (Blizzard_GameTooltip,
-- Blizzard_SharedXMLGame/Tooltip). ui.lua gives them their behaviors (Harness.TYPE_BEHAVIORS).
Harness.TYPE_METHODS = {
    GameTooltip = {
        AddLine = "C", AddDoubleLine = "C", ClearLines = "C", NumLines = "C", SetOwner = "C", GetOwner = "C",
        IsOwned = "C",
        SetUnit = "Lua", GetUnit = "Lua", GetPrimaryTooltipData = "Lua", GetTooltipData = "Lua", IsTooltipType = "Lua",
    },
}
-- Behaviors that differ by widget type (GameTooltip:SetText replaces its lines), over `Behaviors`.
Harness.TYPE_BEHAVIORS = { GameTooltip = {} }

-- The snapshot entry for a widget type's method and the API that documents it, or nil.
local function MethodEntry(widgetType, method)
    for _, api in ipairs(WidgetApis[widgetType]) do
        local methods = Snapshot.methods[api]
        local entry = methods and methods[method]
        if entry then
            return entry, api
        end
    end
end

-- Shown, and every ancestor shown (IsVisible).
function Harness:IsVisibleWidget(widget)
    while widget do
        local s = State(widget)
        if not s.shown then
            return false
        end
        widget = s.parent
    end
    return true
end

-- Protected: created from a Secure template, or the parent of a protected frame.
function Harness:IsProtectedWidget(widget)
    local s = State(widget)
    if s.protected then
        return true
    end
    for _, child in ipairs(s.children) do
        if self:IsProtectedWidget(child) then
            return true
        end
    end
    return false
end

local CharWidth, LineHeight = 7, 14
local Left = { LEFT = true, TOPLEFT = true, BOTTOMLEFT = true }
local Right = { RIGHT = true, TOPRIGHT = true, BOTTOMRIGHT = true }
local Top = { TOP = true, TOPLEFT = true, TOPRIGHT = true }
local Bottom = { BOTTOM = true, BOTTOMLEFT = true, BOTTOMRIGHT = true }
local Axes = {
    x = { low = Left, high = Right, offset = "x", size = "width" },
    y = { low = Bottom, high = Top, offset = "y", size = "height" },
}

local Size

-- Where a point sits along an axis of a region of the given size (low edge 0).
local function Edge(axis, point, size)
    if axis.low[point] then return 0 elseif axis.high[point] then return size end
    return size / 2
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
    local relative = low and high and (low.relativeTo or s.parent)
    if not relative or (high.relativeTo or s.parent) ~= relative or type(relative) ~= "table" or not State(relative) then
        return nil
    end
    local size = Size(relative, axis, depth + 1)
    local span = (Edge(axis, high.relativePoint, size) + high[axis.offset]) - (Edge(axis, low.relativePoint, size) + low[axis.offset])
    return math.max(span, 0)
end

-- Line lengths (in characters) of a FontString's text, wrapped at bound (0 = unbounded).
local function Lines(s, bound)
    local text = Reveal(s.text)
    if text == nil or text == "" then
        return {}
    end
    local lines, perLine = {}, bound > 0 and s.wordWrap ~= false and math.max(1, math.floor(bound / CharWidth)) or nil
    for line in (tostring(text) .. "\n"):gmatch("(.-)\n") do
        line = line:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
        local n = select(2, line:gsub("[^\128-\191]", ""))
        while perLine and n > perLine do
            lines[#lines + 1] = perLine
            n = n - perLine
        end
        lines[#lines + 1] = n
    end
    return lines
end

local function Longest(lines)
    local longest = 0
    for _, n in ipairs(lines) do longest = math.max(longest, n) end
    return longest * CharWidth
end

-- A FontString's own text size, for an axis it has no set or anchored size on.
local function StringSize(s, axis, depth)
    if axis == Axes.x then
        return Longest(Lines(s, 0))
    end
    return #Lines(s, Anchored(s, Axes.x, depth) or s.width or 0) * LineHeight
end

function Size(widget, axis, depth)
    depth = depth or 0
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

function Harness:WidgetWidth(widget) return Size(widget, Axes.x) end
function Harness:WidgetHeight(widget) return Size(widget, Axes.y) end

-- SetPoint(point [, relativeTo [, relativePoint]] [, x, y]); a point replaces the same point.
local function Anchor(s, point, a, b, c, d)
    local relativeTo, relativePoint, x, y
    if a == nil or type(a) == "number" then
        x, y = a, b
    else
        relativeTo = a
        if type(b) == "string" then relativePoint, x, y = b, c, d else x, y = b, c end
    end
    local anchor = { point = point, relativeTo = relativeTo, relativePoint = relativePoint or point, x = x or 0, y = y or 0 }
    s.allPoints = nil
    for i, existing in ipairs(s.points) do
        if existing.point == point then
            s.points[i] = anchor
            return
        end
    end
    s.points[#s.points + 1] = anchor
end

-- behavior(state, widget, ...args)
local Behaviors = {}
function Behaviors.Show(s, w) s.harness:SetWidgetShown(w, true) end
function Behaviors.Hide(s, w) s.harness:SetWidgetShown(w, false) end
function Behaviors.SetShown(s, w, shown) s.harness:SetWidgetShown(w, shown) end
function Behaviors.IsShown(s) return s.shown end
function Behaviors.IsVisible(s, w) return s.harness:IsVisibleWidget(w) end
function Behaviors.IsProtected(s, w) return s.harness:IsProtectedWidget(w), s.protected end
-- Attributes, as secure templates read them.
function Behaviors.SetAttribute(s, _, name, value)
    s.attributes = s.attributes or {}
    s.attributes[name] = value
end
function Behaviors.GetAttribute(s, _, name) return (s.attributes or {})[name] end
-- [G] No harness widget is forbidden: addon frames never are, and forbidden nameplates aren't modeled (units.lua).
function Behaviors.IsForbidden() return false end
function Behaviors.SetScript(s, _, script, fn) s.scripts[script] = fn end
function Behaviors.GetScript(s, _, script) return s.scripts[script] end
function Behaviors.HasScript(s, _, script) return s.scripts[script] ~= nil end
function Behaviors.HookScript(s, _, script, fn)
    local previous = s.scripts[script]
    s.scripts[script] = previous and function(...) previous(...); fn(...) end or fn
end
function Behaviors.SetText(s, _, text) s.text = text end
function Behaviors.GetText(s) return s.text end
-- The client formats secrets into a secret string (the method takes them when tainted).
function Behaviors.SetFormattedText(s, _, fmt, ...)
    s.text = SecretFormat(fmt, ...)
end
function Behaviors.GetStringWidth(s)
    local bound = s.wordWrap ~= false and (Anchored(s, Axes.x, 0) or s.width) or nil
    local width = Longest(Lines(s, 0))
    return bound and math.min(width, bound) or width
end
function Behaviors.GetUnboundedStringWidth(s) return Longest(Lines(s, 0)) end
function Behaviors.GetStringHeight(s) return #Lines(s, Anchored(s, Axes.x, 0) or s.width or 0) * LineHeight end
function Behaviors.GetNumLines(s) return #Lines(s, Anchored(s, Axes.x, 0) or s.width or 0) end
-- [D] A StatusBar's optional second argument is an Enum.StatusBarInterpolation: how the bar moves to
-- the value. [G] The harness keeps it (s.interpolation) and sets the value at once.
function Behaviors.SetValue(s, _, value, interpolation) s.value, s.interpolation = value, interpolation end
function Behaviors.GetValue(s) return s.value end
function Behaviors.SetMinMaxValues(s, _, min, max) s.min, s.max = min, max end
function Behaviors.GetMinMaxValues(s) return s.min, s.max end
function Behaviors.GetName(s) return s.name end
function Behaviors.GetObjectType(s) return s.widgetType end
function Behaviors.IsObjectType(s, _, kind) return s.widgetType == kind or (kind == "Frame" and IsFrame[s.widgetType]) or false end
function Behaviors.GetParent(s) return s.parent end
-- A frame's child frames (GetChildren) or its regions (GetRegions), in creation order ([G] the order).
local IsRegion = { FontString = true, Texture = true, MaskTexture = true }
local function Kids(s, wanted)
    local out = {}
    for _, child in ipairs(s.children) do
        local kind = State(child).widgetType
        if (wanted == "frame" and IsFrame[kind]) or (wanted == "region" and IsRegion[kind]) then
            out[#out + 1] = child
        end
    end
    return out
end
function Behaviors.GetChildren(s) return unpack(Kids(s, "frame")) end
function Behaviors.GetNumChildren(s) return #Kids(s, "frame") end
function Behaviors.GetRegions(s) return unpack(Kids(s, "region")) end
function Behaviors.GetNumRegions(s) return #Kids(s, "region") end
function Behaviors.SetParent(s, w, parent) s.harness:Adopt(w, parent) end
function Behaviors.SetAlpha(s, _, alpha) s.alpha = alpha end
function Behaviors.GetAlpha(s) return s.alpha end
function Behaviors.EnableMouseWheel(s, _, enabled) s.mouseWheel = enabled ~= false end
function Behaviors.IsMouseWheelEnabled(s) return s.mouseWheel == true end
function Behaviors.SetScrollChild(s, _, child) s.scrollChild = child end
function Behaviors.GetScrollChild(s) return s.scrollChild end
function Behaviors.SetVerticalScroll(s, _, offset) s.verticalScroll = offset end
function Behaviors.GetVerticalScroll(s) return s.verticalScroll or 0 end
function Behaviors.GetVerticalScrollRange(s, w)
    local child = s.scrollChild
    return child and math.max(0, Size(child, Axes.y) - Size(w, Axes.y)) or 0
end
function Behaviors.SetSize(s, _, width, height) s.width, s.height = width, height end
function Behaviors.SetWidth(s, _, width) s.width = width end
function Behaviors.SetHeight(s, _, height) s.height = height end
function Behaviors.GetWidth(_, w) return Size(w, Axes.x) end
function Behaviors.GetHeight(_, w) return Size(w, Axes.y) end
function Behaviors.GetSize(_, w) return Size(w, Axes.x), Size(w, Axes.y) end
function Behaviors.SetPoint(s, _, ...) Anchor(s, ...) end
function Behaviors.SetAllPoints(s, _, relativeTo)
    s.points = { { point = "TOPLEFT", relativeTo = relativeTo or s.parent, relativePoint = "TOPLEFT", x = 0, y = 0 },
        { point = "BOTTOMRIGHT", relativeTo = relativeTo or s.parent, relativePoint = "BOTTOMRIGHT", x = 0, y = 0 } }
    s.allPoints = relativeTo or s.parent
end
function Behaviors.ClearAllPoints(s) s.points, s.allPoints = {}, nil end
function Behaviors.GetNumPoints(s) return #s.points end
function Behaviors.GetPoint(s, _, index)
    local p = s.points[index or 1]
    if p then return p.point, p.relativeTo, p.relativePoint, p.x, p.y end
end
function Behaviors.SetTexture(s, _, texture) s.texture, s.atlas = texture, nil end
function Behaviors.GetTexture(s) return s.texture end
function Behaviors.SetAtlas(s, _, atlas) s.atlas, s.texture = atlas, nil end
function Behaviors.GetAtlas(s) return s.atlas end
function Behaviors.SetColorTexture(s, _, r, g, b, a) s.color = { r, g, b, a or 1 } end
-- [D] BackdropTemplateMixin (Blizzard_SharedXML/Backdrop.lua): the border color tints the border's
-- pieces, and does nothing before SetBackdrop gave the frame a backdrop.
function Behaviors.SetBackdrop(s, _, info) s.backdrop = info end
function Behaviors.SetBackdropBorderColor(s, _, r, g, b, a)
    if s.backdrop then s.borderColor = { r, g, b, a or 1 } end
end
function Behaviors.SetJustifyH(s, _, justify) s.justifyH = justify end
function Behaviors.GetJustifyH(s) return s.justifyH or "CENTER" end
function Behaviors.SetWordWrap(s, _, wrap) s.wordWrap = wrap and true or false end
function Behaviors.CanWordWrap(s) return s.wordWrap ~= false end
function Behaviors.SetFontObject(s, _, font) s.fontObject = font end
function Behaviors.GetFontObject(s) return s.fontObject end
function Behaviors.EnableMouse(s, _, enable) s.mouseEnabled = enable and true or false end
function Behaviors.IsMouseEnabled(s) return s.mouseEnabled end
function Behaviors.Enable(s) s.enabled = true end
function Behaviors.Disable(s) s.enabled = false end
function Behaviors.SetEnabled(s, _, enabled) s.enabled = enabled and true or false end
function Behaviors.IsEnabled(s) return s.enabled ~= false end
function Behaviors.Click(s, w, button) s.harness:Click(w, button) end
function Behaviors.SetToDefaults(s) s.secretAspects = {} end
function Behaviors.HasAnySecretAspect(s) return next(s.secretAspects) ~= nil end
function Behaviors.HasSecretValues(s) return next(s.secretAspects) ~= nil end
function Behaviors.CreateFontString(s, w, name) return s.harness:CreateWidget("FontString", name, w) end
function Behaviors.CreateTexture(s, w, name) return s.harness:CreateWidget("Texture", name, w) end
function Behaviors.CreateMaskTexture(s, w, name) return s.harness:CreateWidget("MaskTexture", name, w) end
-- A texture keeps its masks in the order they were added; adding one twice keeps one.
function Behaviors.AddMaskTexture(s, _, mask)
    s.masks = s.masks or {}
    for _, existing in ipairs(s.masks) do
        if existing == mask then return end
    end
    s.masks[#s.masks + 1] = mask
end
function Behaviors.RemoveMaskTexture(s, _, mask)
    for i, existing in ipairs(s.masks or {}) do
        if existing == mask then table.remove(s.masks, i) return end
    end
end
function Behaviors.GetNumMaskTextures(s) return #(s.masks or {}) end
function Behaviors.GetMaskTexture(s, _, index) return (s.masks or {})[index] end
function Behaviors.CreateAnimationGroup(s, w, name)
    local group = s.harness:CreateWidget("AnimationGroup", name, w)
    State(group).animations = {}
    return group
end
-- An event with HasRestrictions is Blizzard's alone: registering it is refused with
-- ADDON_ACTION_FORBIDDEN and nothing is registered. warcraft.wiki.gg (COMBAT_LOG_EVENT) documents
-- that for the combat log events; the harness applies it to every restricted event [C].
local function RefusedEvent(s, method, event)
    if not Snapshot.events[event].HasRestrictions then
        return false
    end
    s.harness:BlockAction("ADDON_ACTION_FORBIDDEN", ("Frame:%s(%s)"):format(method, event))
    return true
end
function Behaviors.RegisterEvent(s, _, event)
    assert(Snapshot.events[event], "RegisterEvent: unknown event " .. tostring(event))
    if RefusedEvent(s, "RegisterEvent", event) then
        return
    end
    s.events[event] = true
end
function Behaviors.RegisterUnitEvent(s, _, event, unit1, unit2)
    assert(Snapshot.events[event], "RegisterUnitEvent: unknown event " .. tostring(event))
    if RefusedEvent(s, "RegisterUnitEvent", event) then
        return
    end
    s.events[event] = { [unit1] = true, [unit2 or unit1] = true }
end
function Behaviors.UnregisterEvent(s, _, event) s.events[event] = nil end
function Behaviors.UnregisterAllEvents(s) s.events = {} end
function Behaviors.IsEventRegistered(s, _, event) return s.events[event] ~= nil end
function Behaviors.EnableGamePadButton(s, _, enable) s.gamepadButtons = enable end
function Behaviors.IsGamePadButtonEnabled(s) return s.gamepadButtons or false end
-- Keyboard input (see Harness:Key): off and not propagating until set, like the client.
function Behaviors.EnableKeyboard(s, _, enable) s.keyboardEnabled = enable and true or false end
function Behaviors.IsKeyboardEnabled(s) return s.keyboardEnabled or false end
function Behaviors.SetPropagateKeyboardInput(s, _, propagate) s.propagateKeyboard = propagate and true or false end
function Behaviors.GetPropagateKeyboardInput(s) return s.propagateKeyboard or false end

-- Moving: see the header.
function Behaviors.SetMovable(s, _, movable) s.movable = movable and true or false end
function Behaviors.IsMovable(s) return s.movable or false end
function Behaviors.SetClampedToScreen(s, _, clamped) s.clamped = clamped and true or false end
function Behaviors.IsClampedToScreen(s) return s.clamped or false end
function Behaviors.SetUserPlaced(s, _, placed) s.userPlaced = placed and true or false end
function Behaviors.IsUserPlaced(s) return s.userPlaced or false end
function Behaviors.RegisterForDrag(s, _, ...)
    s.dragButtons = {}
    for i = 1, select("#", ...) do
        s.dragButtons[(select(i, ...))] = true
    end
end
function Behaviors.StartMoving(s)
    if not s.movable then
        error("Frame:StartMoving(): Frame is not movable", 0)
    end
    s.moving, s.userPlaced = true, true
end
function Behaviors.StopMovingOrSizing(s) s.moving = false end

-- Every widget under (and including) widget that's visible, depth first in creation order.
local function VisibleTree(h, widget, out)
    if h:IsVisibleWidget(widget) then
        out[#out + 1] = widget
        for _, child in ipairs(State(widget).children) do
            VisibleTree(h, child, out)
        end
    end
    return out
end

-- Show/Hide/SetShown: sets the shown flag and runs OnShow or OnHide for every widget whose
-- visibility changed (see the header). A widget that stops being visible stops moving.
function Harness:SetWidgetShown(widget, shown)
    local s = State(widget)
    shown = shown and true or false
    if s.shown == shown then
        return
    end
    local parent = s.parent
    if parent and not self:IsVisibleWidget(parent) then
        s.shown = shown
        return
    end
    local changed
    if shown then
        s.shown = true
        changed = VisibleTree(self, widget, {})
    else
        changed = VisibleTree(self, widget, {})
        s.shown = false
    end
    local script = shown and "OnShow" or "OnHide"
    for _, w in ipairs(changed) do
        local state = State(w)
        if not shown then
            state.moving = false
        end
        local handler = state.scripts[script]
        if handler then
            self:Protect(handler, w)
        end
    end
end

-- The client's frame strata, bottom to top. SetFrameStrata with anything else is an error here.
local Strata = { "WORLD", "BACKGROUND", "LOW", "MEDIUM", "HIGH", "DIALOG", "FULLSCREEN", "FULLSCREEN_DIALOG", "TOOLTIP", "BLIZZARD" }
local StrataIndex = {}
for i, strata in ipairs(Strata) do StrataIndex[strata] = i end

-- A frame's strata: its own, else its parent's, else MEDIUM (UIParent's).
function Harness:FrameStrata(frame)
    local depth = 0
    while frame and depth < 100 do
        local s = State(frame)
        if s.strata then return s.strata end
        frame, depth = s.parent, depth + 1
    end
    return "MEDIUM"
end
function Harness:FrameStrataIndex(frame) return StrataIndex[self:FrameStrata(frame)] end

-- A frame's level: its own, else one above its parent's, else 0.
function Harness:FrameLevel(frame, depth)
    depth = depth or 0
    local s = State(frame)
    if s.level then return s.level end
    if s.parent and depth < 100 then return self:FrameLevel(s.parent, depth + 1) + 1 end
    return 0
end

function Behaviors.SetFrameStrata(s, _, strata)
    if not StrataIndex[strata] then
        error("SetFrameStrata: unknown strata " .. tostring(strata), 5)
    end
    s.strata = strata
end
function Behaviors.GetFrameStrata(s, w) return s.harness:FrameStrata(w) end
function Behaviors.SetFrameLevel(s, _, level) s.level = level end
function Behaviors.GetFrameLevel(s, w) return s.harness:FrameLevel(w) end

function Behaviors.CreateAnimation(s, group, animationType, name)
    assert(WidgetApis[animationType] and animationType ~= "AnimationGroup",
        "CreateAnimation: unsupported animation type " .. tostring(animationType))
    local animation = s.harness:CreateWidget(animationType, name, group)
    local a = State(animation)
    a.duration, a.startDelay, a.endDelay, a.order = 0, 0, 0, 1
    s.animations[#s.animations + 1] = animation
    return animation
end
function Behaviors.SetDuration(a, _, seconds) a.duration = seconds end
function Behaviors.SetStartDelay(a, _, seconds) a.startDelay = seconds end
function Behaviors.SetEndDelay(a, _, seconds) a.endDelay = seconds end
function Behaviors.SetOrder(a, _, order) a.order = order end
function Behaviors.GetOrder(a) return a.order end
function Behaviors.GetStartDelay(a) return a.startDelay end
function Behaviors.GetEndDelay(a) return a.endDelay end
function Behaviors.SetFromAlpha(a, _, alpha) a.fromAlpha = alpha end
function Behaviors.SetToAlpha(a, _, alpha) a.toAlpha = alpha end
function Behaviors.GetFromAlpha(a) return a.fromAlpha or 0 end
function Behaviors.SetOffset(a, _, x, y) a.offsetX, a.offsetY = x, y end
function Behaviors.GetOffset(a) return a.offsetX or 0, a.offsetY or 0 end
function Behaviors.SetScaleFrom(a, _, x, y) a.scaleFromX, a.scaleFromY = x, y end
function Behaviors.GetScaleFrom(a) return a.scaleFromX or 1, a.scaleFromY or 1 end
function Behaviors.SetScaleTo(a, _, x, y) a.scaleToX, a.scaleToY = x, y end
function Behaviors.GetScaleTo(a) return a.scaleToX or 1, a.scaleToY or 1 end
function Behaviors.GetToAlpha(a) return a.toAlpha or 0 end
function Behaviors.SetLooping(g, _, looping) g.looping = looping end
function Behaviors.GetLooping(g) return g.looping or "NONE" end
function Behaviors.SetToFinalAlpha(g, _, final) g.toFinalAlpha = final and true or false end
function Behaviors.IsSetToFinalAlpha(g) return g.toFinalAlpha or false end
function Behaviors.IsPlaying(s) return s.playing or false end

-- A group lasts the sum, over its orders, of the longest animation in each order.
local function GroupDuration(g)
    local longest = {}
    for _, animation in ipairs(g.animations) do
        local a = State(animation)
        longest[a.order] = math.max(longest[a.order] or 0, a.startDelay + a.duration + a.endDelay)
    end
    local total = 0
    for _, seconds in pairs(longest) do
        total = total + seconds
    end
    return total
end

local function FinishGroup(g, group, requested)
    g.playing, g.pending = false, nil
    if g.toFinalAlpha then
        local last
        for _, animation in ipairs(g.animations) do
            local a = State(animation)
            if a.toAlpha and (not last or a.order >= last.order) then
                last = a
            end
        end
        if last then
            State(g.parent).alpha = last.toAlpha
        end
    end
    local onFinished = g.scripts.OnFinished
    if onFinished then
        g.harness:Protect(onFinished, group, requested)
    end
end

local function Schedule(g, group)
    g.pending = g.harness:Schedule(GroupDuration(g), function()
        if g.looping == "REPEAT" or g.looping == "BOUNCE" then
            if g.scripts.OnLoop then g.harness:Protect(g.scripts.OnLoop, group, "FORWARD") end
            Schedule(g, group)
        else
            FinishGroup(g, group, false)
        end
    end)
end

function Behaviors.Play(g, group)
    if g.widgetType ~= "AnimationGroup" then
        g.playing = true
        return
    end
    if g.pending then
        g.pending.cancelled = true
    end
    g.playing = true
    if g.scripts.OnPlay then g.harness:Protect(g.scripts.OnPlay, group) end
    Schedule(g, group)
end
Behaviors.Restart = Behaviors.Play

function Behaviors.Stop(g, group)
    if g.pending then
        g.pending.cancelled = true
        g.pending = nil
    end
    local wasPlaying = g.playing
    g.playing = false
    if wasPlaying and g.scripts.OnStop then g.harness:Protect(g.scripts.OnStop, group, true) end
end

function Behaviors.Finish(g, group)
    if g.pending then
        g.pending.cancelled = true
        FinishGroup(g, group, true)
    end
end

-- Moves a widget under a new parent (nil detaches it).
function Harness:Adopt(widget, parent)
    local s = State(widget)
    local old = s.parent
    if old then
        local siblings = State(old).children
        for i, child in ipairs(siblings) do
            if child == widget then
                table.remove(siblings, i)
                break
            end
        end
    end
    s.parent = parent
    if parent then
        local children = State(parent).children
        children[#children + 1] = widget
    end
end

-- The callable for a widget type's method, built once per harness: counts the call, then runs
-- the behavior through the method's snapshot entry.
function Harness:Method(widgetType, template, method)
    local key = widgetType .. "|" .. (template or "") .. "|" .. method
    local cached = self.methodCache[key]
    if cached then
        return cached
    end
    local typeBehaviors = Harness.TYPE_BEHAVIORS[widgetType]
    local behavior = typeBehaviors and typeBehaviors[method] or Behaviors[method]
    local function Raw(w, ...)
        if behavior then
            return behavior(State(w), w, ...)
        end
    end
    local fn
    local entry, api = MethodEntry(widgetType, method)
    local typeMethod = Harness.TYPE_METHODS[widgetType] and Harness.TYPE_METHODS[widgetType][method]
    if entry then
        fn = self:WrapApi(widgetType .. ":" .. method .. " (" .. api .. ")", entry, Raw, true)
    elseif typeMethod == "C" then
        fn = self:WrapApi(widgetType .. ":" .. method .. " (undocumented)", nil, Raw, true)
    elseif typeMethod == "Lua" then
        fn = Raw
    elseif template and TemplateMethods[template] and TemplateMethods[template][method] then
        fn = Raw
    else
        return nil
    end
    local function Counted(w, ...)
        local calls = State(w).calls
        calls[method] = (calls[method] or 0) + 1
        return fn(w, ...)
    end
    self.methodCache[key] = Counted
    return Counted
end

function Harness:CreateWidget(widgetType, name, parent, template)
    assert(WidgetApis[widgetType], "CreateFrame: unsupported widget type " .. tostring(widgetType))
    local widget = {}
    Harness.widgetStates[widget] = {
        harness = self, widgetType = widgetType, name = name, template = template,
        shown = true, alpha = 1, scripts = {}, events = {}, calls = {}, points = {}, children = {},
        secretAspects = {},             -- aspect name -> true once a secret reached a setter for it
        mouseEnabled = widgetType == "Button",
        protected = type(template) == "string" and template:find("Secure") ~= nil,
    }
    local h = self
    setmetatable(widget, {
        -- Methods are capitalized; any other key is the addon's own (unset) field.
        __index = function(_, method)
            if type(method) ~= "string" or not method:find("^%u") then
                return nil
            end
            local fn = h:Method(widgetType, template, method)
            if not fn then
                error(("%s has no method %s"):format(widgetType, tostring(method)), 2)
            end
            return fn
        end,
    })
    self:Adopt(widget, parent)
    self.widgets[#self.widgets + 1] = widget
    if IsFrame[widgetType] then
        self.frames[#self.frames + 1] = widget
    end
    return widget
end
