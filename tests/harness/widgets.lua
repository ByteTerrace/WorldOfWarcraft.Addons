-- Widgets of the fake client: frames, regions, and animations. Every method must exist in the snapshot's widget API
-- tables for the widget's type. Each call is counted and runs through Harness:WrapApi (secrets.lua) with the method's
-- snapshot entry. Methods with a behavior below keep the state tests and addons read back. The rest only record the
-- call.
--
-- A widget is an empty table with a method metatable, like the client's: the addon owns every field on it (button.text,
-- f.shown, bar.value, g.events are the addon's). The harness keeps a widget's state in a weak side table. Tests read it
-- with Harness.State(widget) (or h:WidgetState(widget)): { widgetType, name, template, parent, children, shown, alpha,
-- text, value, min, max, width, height, points, scripts, events, calls, secretAspects, protected, ... }.
--
-- Sizes (GetWidth, GetHeight, a FontString's string size and lines) come from layout.lua's deterministic stand-ins: a
-- FontString's text is 7 px per character by 14 px per line.
--
-- A frame's strata is its own (SetFrameStrata), else its parent's, else MEDIUM. Its level is its own (SetFrameLevel),
-- else one above its parent's, else 0. Keyboard input (h:Key) follows them.
--
-- GetChildren / GetNumChildren list a frame's child frames and GetRegions / GetNumRegions its font strings and
-- textures, in creation order ([G] the order).
--
-- Visibility: [D] OnShow runs when a widget becomes visible (it and every ancestor shown) and OnHide when it stops
-- being visible, for the widget whose Show/Hide/SetShown changed it and each descendant whose visibility changed with
-- it; showing a shown widget, or showing one under a hidden parent, runs nothing. [G] The widget runs first, then its
-- descendants depth first in creation order. Reparenting (SetParent) runs neither.
--
-- Moving (warcraft.wiki.gg Frame:StartMoving, Frame:RegisterForDrag): SetMovable / IsMovable, SetClampedToScreen /
-- IsClampedToScreen ([G] clamping itself isn't modeled), SetUserPlaced / IsUserPlaced, and RegisterForDrag(...buttons)
-- (none clears; each call replaces the last) keep their state. [D] StartMoving on a frame that isn't movable is an
-- error ("Frame is not movable"); otherwise it marks the frame user placed and moving, and the frame follows the mouse
-- (h:Drag, input.lua) until StopMovingOrSizing or until it stops being visible. [G] The client re-anchors a moved frame
-- to the nearest screen corner; the harness has no screen coordinates, so a move shifts each of the frame's anchors by
-- the mouse's travel and keeps their points and relative regions. Verify saved positions in game.
--
-- Scrolling: a ScrollFrame shows its scroll child (SetScrollChild) through its own size, moved up by its vertical
-- scroll (SetVerticalScroll). [D] GetVerticalScrollRange is how far it can scroll: the child's height less the frame's,
-- never below 0 (SimpleScrollFrameAPI). [G] SetVerticalScroll keeps any offset; Blizzard's ScrollFrame_OnMouseWheel
-- clamps to the range itself. Which part of the child is visible isn't modeled. EnableMouseWheel / IsMouseWheelEnabled
-- keep their state, and h:MouseWheel (input.lua) turns the wheel over a frame.
--
-- GameTooltip and NamePlate are the client's own frame types (the env's GameTooltip, the plates C_NamePlate returns).
-- Methods the API docs don't list for a type come from Harness.TYPE_METHODS, with behaviors in Harness.TYPE_BEHAVIORS
-- (ui.lua).

local Snapshot = __snapshot
local State = Harness.State

local FrameScriptObject = { "SimpleObjectAPI", "SimpleFrameScriptObjectAPI" }
local ScriptRegion = { "SimpleScriptRegionAPI", "SimpleScriptRegionResizingAPI", "SimpleAnimatableObjectAPI" }

-- Most-derived API first: the first API that lists a method supplies its entry.
local function Chain(...)
    local out = {}

    for _, list in ipairs({ ... }) do
        for _, api in ipairs(((type(list) == "table") and list) or { list }) do
            out[#out + 1] = api
        end
    end

    return out
end

local WidgetApis = {
    Alpha = Chain("SimpleAnimAlphaAPI", "SimpleAnimAPI", FrameScriptObject),
    AnimationGroup = Chain("SimpleAnimGroupAPI", FrameScriptObject),
    Button = Chain("SimpleButtonAPI", "SimpleFrameAPI", ScriptRegion, FrameScriptObject),
    FontString = Chain("SimpleFontStringAPI", "SimpleRegionAPI", ScriptRegion, FrameScriptObject),
    Frame = Chain("SimpleFrameAPI", ScriptRegion, FrameScriptObject),
    -- The client's own frames of these types (GameTooltip, nameplates). Addons don't create them here.
    GameTooltip = Chain("FrameAPITooltip", "SimpleFrameAPI", ScriptRegion, FrameScriptObject),
    -- A mask shapes the textures it's added to. It has a texture's base API but no drawing of its own.
    MaskTexture = Chain("SimpleTextureBaseAPI", "SimpleRegionAPI", ScriptRegion, FrameScriptObject),
    NamePlate = Chain("FrameAPINamePlate", "SimpleFrameAPI", ScriptRegion, FrameScriptObject),
    Scale = Chain("SimpleAnimScaleAPI", "SimpleAnimAPI", FrameScriptObject),
    ScrollFrame = Chain("SimpleScrollFrameAPI", "SimpleFrameAPI", ScriptRegion, FrameScriptObject),
    StatusBar = Chain("SimpleStatusBarAPI", "SimpleFrameAPI", ScriptRegion, FrameScriptObject),
    Texture = Chain("SimpleTextureAPI", "SimpleTextureBaseAPI", "SimpleRegionAPI", ScriptRegion, FrameScriptObject),
    Translation = Chain("SimpleAnimTranslationAPI", "SimpleAnimAPI", FrameScriptObject),
}

Harness.WIDGET_APIS = WidgetApis

local IsFrame = { Button = true, Frame = true, GameTooltip = true, NamePlate = true, ScrollFrame = true, StatusBar = true }

-- Template-provided methods that aren't C API (BackdropTemplateMixin).
local TemplateMethods = { BackdropTemplate = { SetBackdrop = true, SetBackdropBorderColor = true, SetBackdropColor = true } }

-- Methods a widget type has that the generated API docs don't list, by kind: "C" for the client's undocumented C
-- methods (they get the undocumented default: no secret arguments), "Lua" for Blizzard's mixin methods (exempt, like
-- Harness.LUA_FAKES). GameTooltip's C methods are the ones Ketho/BlizzardInterfaceResources (forever branch, 1.60.1)
-- lists for GameTooltip; its Lua ones come from GameTooltipDataMixin and TooltipDataHandlerMixin (Blizzard_GameTooltip,
-- Blizzard_SharedXMLGame/Tooltip). ui.lua gives them their behaviors (Harness.TYPE_BEHAVIORS).
Harness.TYPE_METHODS = {
    GameTooltip = {
        AddDoubleLine = "C", AddLine = "C", ClearLines = "C", GetOwner = "C", GetPrimaryTooltipData = "Lua",
        GetTooltipData = "Lua", GetUnit = "Lua", IsOwned = "C", IsTooltipType = "Lua", NumLines = "C", SetOwner = "C",
        SetUnit = "Lua",
    },
}

-- Behaviors that differ by widget type (GameTooltip:SetText replaces its lines), over `Behaviors`.
Harness.TYPE_BEHAVIORS = { GameTooltip = {} }

-- The snapshot entry for a widget type's method and the API that documents it, or nil.
local function MethodEntry(widgetType, method)
    for _, api in ipairs(WidgetApis[widgetType]) do
        local methods = Snapshot.methods[api]
        local entry = (methods and methods[method])

        if entry then
            return entry, api
        end
    end
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

local Layout = Harness.Layout
local Anchor = Layout.Anchor
local Anchored = Layout.Anchored
local Axes = Layout.Axes
local LineHeight = Layout.LineHeight
local Lines = Layout.Lines
local Longest = Layout.Longest
local Size = Layout.Size

-- Each behavior is called as behavior(state, widget, ...args).
local Behaviors = {}

function Behaviors.GetAttribute(s, _, name) return (s.attributes or {})[name] end

function Behaviors.GetEffectiveScale(s)
    local scale = (s.scale or 1)

    if s.parent then
        scale = (scale * Behaviors.GetEffectiveScale(Harness.State(s.parent)))
    end

    return scale
end

-- [D] A FontString's line height and the spacing between its lines (SimpleFontStringAPI). [G] The line height is the
-- layout's LineHeight, and the spacing is kept but not added to the string's height.
function Behaviors.GetLineHeight() return LineHeight end

function Behaviors.GetMinMaxValues(s) return s.min, s.max end

function Behaviors.GetName(s) return s.name end

function Behaviors.GetNumLines(s) return #Lines(s, Anchored(s, Axes.x, 0) or s.width or 0) end

function Behaviors.GetObjectType(s) return s.widgetType end

function Behaviors.GetParent(s) return s.parent end

-- [D] A widget's scale is its own (SetScale, 1 unless set), and its effective scale that times its parent's
-- (SimpleFrameAPI). A parentless frame's effective scale is its own: the UI scale (UIParent's) doesn't reach it.
function Behaviors.GetScale(s) return (s.scale or 1) end

function Behaviors.GetScript(s, _, script) return s.scripts[script] end

function Behaviors.GetSpacing(s) return (s.spacing or 0) end

function Behaviors.GetStringHeight(s) return (#Lines(s, Anchored(s, Axes.x, 0) or s.width or 0) * LineHeight) end

function Behaviors.GetStringWidth(s)
    local bound = (((s.wordWrap ~= false) and (Anchored(s, Axes.x, 0) or s.width)) or nil)
    local width = Longest(Lines(s, 0))

    return ((bound and math.min(width, bound)) or width)
end

function Behaviors.GetText(s) return s.text end

function Behaviors.GetUnboundedStringWidth(s) return Longest(Lines(s, 0)) end

function Behaviors.GetValue(s) return s.value end

function Behaviors.HasScript(s, _, script) return (s.scripts[script] ~= nil) end

function Behaviors.Hide(s, w) s.harness:SetWidgetShown(w, false) end

function Behaviors.HookScript(s, _, script, fn)
    local previous = s.scripts[script]

    s.scripts[script] = ((previous and function(...) previous(...); fn(...) end) or fn)
end

-- [G] No harness widget is forbidden: addon frames never are, and forbidden nameplates aren't modeled (units.lua).
function Behaviors.IsForbidden() return false end

function Behaviors.IsObjectType(s, _, kind) return ((s.widgetType == kind) or ((kind == "Frame") and IsFrame[s.widgetType]) or false) end

function Behaviors.IsProtected(s, w) return s.harness:IsProtectedWidget(w), s.protected end

function Behaviors.IsShown(s) return s.shown end

function Behaviors.IsVisible(s, w) return s.harness:IsVisibleWidget(w) end

-- Attributes, as secure templates read them.
function Behaviors.SetAttribute(s, _, name, value)
    s.attributes = (s.attributes or {})
    s.attributes[name] = value
end

-- The client formats secrets into a secret string (the method takes them when tainted).
function Behaviors.SetFormattedText(s, _, fmt, ...)
    s.text = SecretFormat(fmt, ...)
end

function Behaviors.SetMinMaxValues(s, _, min, max) s.min, s.max = min, max end

function Behaviors.SetScript(s, _, script, fn) s.scripts[script] = fn end

function Behaviors.SetShown(s, w, shown) s.harness:SetWidgetShown(w, shown) end

function Behaviors.SetSpacing(s, _, spacing) s.spacing = spacing end

function Behaviors.SetText(s, _, text) s.text = text end

-- [D] A StatusBar's optional second argument is an Enum.StatusBarInterpolation: how the bar moves to the value. [G] The
-- harness keeps it (s.interpolation) and sets the value at once.
function Behaviors.SetValue(s, _, value, interpolation) s.value, s.interpolation = value, interpolation end

function Behaviors.Show(s, w) s.harness:SetWidgetShown(w, true) end

-- A frame's child frames (GetChildren) or its regions (GetRegions), in creation order ([G] the order).
local IsRegion = { FontString = true, MaskTexture = true, Texture = true }

local function Kids(s, wanted)
    local out = {}

    for _, child in ipairs(s.children) do
        local kind = State(child).widgetType

        if ((wanted == "frame") and IsFrame[kind]) or ((wanted == "region") and IsRegion[kind]) then
            out[#out + 1] = child
        end
    end

    return out
end

-- An event with HasRestrictions is Blizzard's alone: registering it is refused with ADDON_ACTION_FORBIDDEN and nothing
-- is registered. warcraft.wiki.gg (COMBAT_LOG_EVENT) documents that for the combat log events; the harness applies it
-- to every restricted event [C].
local function RefusedEvent(s, method, event)
    if not Snapshot.events[event].HasRestrictions then
        return false
    end

    s.harness:BlockAction("ADDON_ACTION_FORBIDDEN", ("Frame:%s(%s)"):format(method, event))

    return true
end

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

-- A texture keeps its masks in the order they were added. Adding one twice keeps one.
function Behaviors.AddMaskTexture(s, _, mask)
    s.masks = (s.masks or {})

    for _, existing in ipairs(s.masks) do
        if existing == mask then return end
    end

    s.masks[#s.masks + 1] = mask
end

function Behaviors.CanWordWrap(s) return (s.wordWrap ~= false) end

function Behaviors.ClearAllPoints(s) s.points, s.allPoints = {}, nil end

function Behaviors.Click(s, w, button) s.harness:Click(w, button) end

function Behaviors.CreateAnimationGroup(s, w, name)
    local group = s.harness:CreateWidget("AnimationGroup", name, w)

    State(group).animations = {}

    return group
end

function Behaviors.CreateFontString(s, w, name) return s.harness:CreateWidget("FontString", name, w) end

function Behaviors.CreateMaskTexture(s, w, name) return s.harness:CreateWidget("MaskTexture", name, w) end

function Behaviors.CreateTexture(s, w, name) return s.harness:CreateWidget("Texture", name, w) end

function Behaviors.Disable(s) s.enabled = false end

function Behaviors.Enable(s) s.enabled = true end

function Behaviors.EnableGamePadButton(s, _, enable) s.gamepadButtons = enable end

-- Keyboard input (see Harness:Key): off and not propagating until set, like the client.
function Behaviors.EnableKeyboard(s, _, enable) s.keyboardEnabled = ((enable and true) or false) end

function Behaviors.EnableMouse(s, _, enable) s.mouseEnabled = ((enable and true) or false) end

function Behaviors.EnableMouseWheel(s, _, enabled) s.mouseWheel = (enabled ~= false) end

function Behaviors.GetAlpha(s) return s.alpha end

function Behaviors.GetAtlas(s) return s.atlas end

function Behaviors.GetChildren(s) return unpack(Kids(s, "frame")) end

function Behaviors.GetFontObject(s) return s.fontObject end

function Behaviors.GetHeight(_, w) return Size(w, Axes.y) end

function Behaviors.GetJustifyH(s) return (s.justifyH or "CENTER") end

function Behaviors.GetMaskTexture(s, _, index) return (s.masks or {})[index] end

function Behaviors.GetNumChildren(s) return #Kids(s, "frame") end

function Behaviors.GetNumMaskTextures(s) return #(s.masks or {}) end

function Behaviors.GetNumPoints(s) return #s.points end

function Behaviors.GetNumRegions(s) return #Kids(s, "region") end

function Behaviors.GetPoint(s, _, index)
    local p = s.points[index or 1]

    if p then return p.point, p.relativeTo, p.relativePoint, p.x, p.y end
end

function Behaviors.GetPropagateKeyboardInput(s) return (s.propagateKeyboard or false) end

function Behaviors.GetRegions(s) return unpack(Kids(s, "region")) end

function Behaviors.GetScrollChild(s) return s.scrollChild end

function Behaviors.GetSize(_, w) return Size(w, Axes.x), Size(w, Axes.y) end

function Behaviors.GetTexture(s) return s.texture end

function Behaviors.GetVerticalScroll(s) return (s.verticalScroll or 0) end

function Behaviors.GetVerticalScrollRange(s, w)
    local child = s.scrollChild

    return ((child and math.max(0, Size(child, Axes.y) - Size(w, Axes.y))) or 0)
end

function Behaviors.GetWidth(_, w) return Size(w, Axes.x) end

function Behaviors.HasAnySecretAspect(s) return (next(s.secretAspects) ~= nil) end

function Behaviors.HasSecretValues(s) return (next(s.secretAspects) ~= nil) end

function Behaviors.IsClampedToScreen(s) return (s.clamped or false) end

function Behaviors.IsEnabled(s) return (s.enabled ~= false) end

function Behaviors.IsEventRegistered(s, _, event) return (s.events[event] ~= nil) end

function Behaviors.IsGamePadButtonEnabled(s) return (s.gamepadButtons or false) end

function Behaviors.IsKeyboardEnabled(s) return (s.keyboardEnabled or false) end

function Behaviors.IsMouseEnabled(s) return s.mouseEnabled end

function Behaviors.IsMouseWheelEnabled(s) return (s.mouseWheel == true) end

function Behaviors.IsMovable(s) return (s.movable or false) end

function Behaviors.IsUserPlaced(s) return (s.userPlaced or false) end

function Behaviors.RegisterEvent(s, _, event)
    assert(Snapshot.events[event], "RegisterEvent: unknown event " .. tostring(event))

    if RefusedEvent(s, "RegisterEvent", event) then
        return
    end

    s.events[event] = true
end

function Behaviors.RegisterForDrag(s, _, ...)
    s.dragButtons = {}

    for i = 1, select("#", ...) do
        s.dragButtons[(select(i, ...))] = true
    end
end

function Behaviors.RegisterUnitEvent(s, _, event, unit1, unit2)
    assert(Snapshot.events[event], "RegisterUnitEvent: unknown event " .. tostring(event))

    if RefusedEvent(s, "RegisterUnitEvent", event) then
        return
    end

    s.events[event] = { [unit1] = true, [unit2 or unit1] = true }
end

function Behaviors.RemoveMaskTexture(s, _, mask)
    for i, existing in ipairs(s.masks or {}) do
        if existing == mask then table.remove(s.masks, i) return end
    end
end

function Behaviors.SetAllPoints(s, _, relativeTo)
    s.points = { { point = "TOPLEFT", relativePoint = "TOPLEFT", relativeTo = (relativeTo or s.parent), x = 0, y = 0 },
        { point = "BOTTOMRIGHT", relativePoint = "BOTTOMRIGHT", relativeTo = (relativeTo or s.parent), x = 0, y = 0 } }

    s.allPoints = (relativeTo or s.parent)
end

function Behaviors.SetAlpha(s, _, alpha) s.alpha = alpha end

function Behaviors.SetAtlas(s, _, atlas) s.atlas, s.texture = atlas, nil end

-- [D] BackdropTemplateMixin (Blizzard_SharedXML/Backdrop.lua): the border color tints the border's pieces, and does
-- nothing before SetBackdrop gave the frame a backdrop.
function Behaviors.SetBackdrop(s, _, info) s.backdrop = info end

function Behaviors.SetBackdropBorderColor(s, _, r, g, b, a)
    if s.backdrop then s.borderColor = { r, g, b, (a or 1) } end
end

function Behaviors.SetClampedToScreen(s, _, clamped) s.clamped = ((clamped and true) or false) end

function Behaviors.SetColorTexture(s, _, r, g, b, a) s.color = { r, g, b, (a or 1) } end

function Behaviors.SetEnabled(s, _, enabled) s.enabled = ((enabled and true) or false) end

function Behaviors.SetFontObject(s, _, font) s.fontObject = font end

function Behaviors.SetHeight(s, _, height) s.height = height end

function Behaviors.SetJustifyH(s, _, justify) s.justifyH = justify end

-- Moving: see the header.
function Behaviors.SetMovable(s, _, movable) s.movable = ((movable and true) or false) end

function Behaviors.SetParent(s, w, parent) s.harness:Adopt(w, parent) end

function Behaviors.SetPoint(s, _, ...) Anchor(s, ...) end

function Behaviors.SetPropagateKeyboardInput(s, _, propagate) s.propagateKeyboard = ((propagate and true) or false) end

-- [D] SetRotation(radians, normalizedRotationPoint?) (SimpleTextureBaseAPI): the harness keeps both; drawing isn't
-- modeled.
function Behaviors.SetRotation(s, _, radians, point) s.rotation, s.rotationPoint = radians, point end

function Behaviors.SetScale(s, _, scale) s.scale = scale end

function Behaviors.SetScrollChild(s, _, child) s.scrollChild = child end

function Behaviors.SetSize(s, _, width, height) s.width, s.height = width, height end

function Behaviors.SetTexture(s, _, texture) s.texture, s.atlas = texture, nil end

function Behaviors.SetToDefaults(s) s.secretAspects = {} end

function Behaviors.SetUserPlaced(s, _, placed) s.userPlaced = ((placed and true) or false) end

function Behaviors.SetVerticalScroll(s, _, offset) s.verticalScroll = offset end

function Behaviors.SetWidth(s, _, width) s.width = width end

function Behaviors.SetWordWrap(s, _, wrap) s.wordWrap = ((wrap and true) or false) end

function Behaviors.StartMoving(s)
    if not s.movable then
        error("Frame:StartMoving(): Frame is not movable", 0)
    end

    s.moving, s.userPlaced = true, true
end

function Behaviors.StopMovingOrSizing(s) s.moving = false end

function Behaviors.UnregisterAllEvents(s) s.events = {} end

function Behaviors.UnregisterEvent(s, _, event) s.events[event] = nil end

-- Show/Hide/SetShown: sets the shown flag and runs OnShow or OnHide for every widget whose visibility changed (see the
-- header). A widget that stops being visible stops moving.
function Harness:SetWidgetShown(widget, shown)
    local s = State(widget)

    shown = ((shown and true) or false)

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

    local script = ((shown and "OnShow") or "OnHide")

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

local function FinishGroup(g, group, requested)
    g.playing, g.pending = false, nil

    if g.toFinalAlpha then
        local last

        for _, animation in ipairs(g.animations) do
            local a = State(animation)

            if a.toAlpha and (not last or (a.order >= last.order)) then
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

-- A group lasts the sum, over its orders, of the longest animation in each order.
local function GroupDuration(g)
    local longest = {}

    for _, animation in ipairs(g.animations) do
        local a = State(animation)

        longest[a.order] = math.max(longest[a.order] or 0, (a.startDelay + a.duration) + a.endDelay)
    end

    local total = 0

    for _, seconds in pairs(longest) do
        total = (total + seconds)
    end

    return total
end

local function Schedule(g, group)
    g.pending = g.harness:Schedule(GroupDuration(g), function()
        if (g.looping == "REPEAT") or (g.looping == "BOUNCE") then
            if g.scripts.OnLoop then g.harness:Protect(g.scripts.OnLoop, group, "FORWARD") end

            Schedule(g, group)
        else
            FinishGroup(g, group, false)
        end
    end)
end

function Behaviors.CreateAnimation(s, group, animationType, name)
    assert(WidgetApis[animationType] and (animationType ~= "AnimationGroup"),
        "CreateAnimation: unsupported animation type " .. tostring(animationType))

    local animation = s.harness:CreateWidget(animationType, name, group)
    local a = State(animation)

    a.duration, a.startDelay, a.endDelay, a.order = 0, 0, 0, 1
    s.animations[#s.animations + 1] = animation

    return animation
end

function Behaviors.GetEndDelay(a) return a.endDelay end

function Behaviors.GetFrameLevel(s, w) return s.harness:FrameLevel(w) end

function Behaviors.GetFrameStrata(s, w) return s.harness:FrameStrata(w) end

function Behaviors.GetFromAlpha(a) return (a.fromAlpha or 0) end

function Behaviors.GetLooping(g) return (g.looping or "NONE") end

function Behaviors.GetOffset(a) return (a.offsetX or 0), (a.offsetY or 0) end

function Behaviors.GetOrder(a) return a.order end

function Behaviors.GetScaleFrom(a) return (a.scaleFromX or 1), (a.scaleFromY or 1) end

function Behaviors.GetScaleTo(a) return (a.scaleToX or 1), (a.scaleToY or 1) end

function Behaviors.GetStartDelay(a) return a.startDelay end

function Behaviors.GetToAlpha(a) return (a.toAlpha or 0) end

function Behaviors.IsPlaying(s) return (s.playing or false) end

function Behaviors.IsSetToFinalAlpha(g) return (g.toFinalAlpha or false) end

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

function Behaviors.SetDuration(a, _, seconds) a.duration = seconds end

function Behaviors.SetEndDelay(a, _, seconds) a.endDelay = seconds end

function Behaviors.SetFrameLevel(s, _, level) s.level = level end

function Behaviors.SetFrameStrata(s, _, strata)
    if not StrataIndex[strata] then
        error("SetFrameStrata: unknown strata " .. tostring(strata), 5)
    end

    s.strata = strata
end

function Behaviors.SetFromAlpha(a, _, alpha) a.fromAlpha = alpha end

function Behaviors.SetLooping(g, _, looping) g.looping = looping end

function Behaviors.SetOffset(a, _, x, y) a.offsetX, a.offsetY = x, y end

function Behaviors.SetOrder(a, _, order) a.order = order end

function Behaviors.SetScaleFrom(a, _, x, y) a.scaleFromX, a.scaleFromY = x, y end

function Behaviors.SetScaleTo(a, _, x, y) a.scaleToX, a.scaleToY = x, y end

function Behaviors.SetStartDelay(a, _, seconds) a.startDelay = seconds end

function Behaviors.SetToAlpha(a, _, alpha) a.toAlpha = alpha end

function Behaviors.SetToFinalAlpha(g, _, final) g.toFinalAlpha = ((final and true) or false) end

-- A frame's level: its own, else one above its parent's, else 0.
function Harness:FrameLevel(frame, depth)
    depth = (depth or 0)
    local s = State(frame)

    if s.level then return s.level end

    if s.parent and (depth < 100) then return (self:FrameLevel(s.parent, depth + 1) + 1) end

    return 0
end

-- A frame's strata: its own, else its parent's, else MEDIUM (UIParent's).
function Harness:FrameStrata(frame)
    local depth = 0

    while frame and (depth < 100) do
        local s = State(frame)

        if s.strata then return s.strata end

        frame, depth = s.parent, (depth + 1)
    end

    return "MEDIUM"
end

function Harness:FrameStrataIndex(frame) return StrataIndex[self:FrameStrata(frame)] end

Behaviors.Restart = Behaviors.Play

function Behaviors.Finish(g, group)
    if g.pending then
        g.pending.cancelled = true
        FinishGroup(g, group, true)
    end
end

function Behaviors.Stop(g, group)
    if g.pending then
        g.pending.cancelled = true
        g.pending = nil
    end

    local wasPlaying = g.playing

    g.playing = false

    if wasPlaying and g.scripts.OnStop then g.harness:Protect(g.scripts.OnStop, group, true) end
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

function Harness:CreateWidget(widgetType, name, parent, template)
    assert(WidgetApis[widgetType], "CreateFrame: unsupported widget type " .. tostring(widgetType))
    local widget = {}

    Harness.widgetStates[widget] = {
        alpha = 1,
        calls = {},
        children = {},
        events = {},
        harness = self,
        mouseEnabled = (widgetType == "Button"),
        name = name,
        points = {},
        protected = ((type(template) == "string") and (template:find("Secure") ~= nil)),
        scripts = {},
        -- Aspect name -> true once a secret reached a setter for it.
        secretAspects = {},
        shown = true,
        template = template,
        widgetType = widgetType,
    }

    local h = self

    setmetatable(widget, {
        -- Methods are capitalized; any other key is the addon's own (unset) field.
        __index = function(_, method)
            if (type(method) ~= "string") or not method:find("^%u") then
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

-- The callable for a widget type's method, built once per harness: counts the call, then runs the behavior through the
-- method's snapshot entry.
function Harness:Method(widgetType, template, method)
    local key = (widgetType .. "|" .. (template or "") .. "|" .. method)
    local cached = self.methodCache[key]

    if cached then
        return cached
    end

    local typeBehaviors = Harness.TYPE_BEHAVIORS[widgetType]
    local behavior = ((typeBehaviors and typeBehaviors[method]) or Behaviors[method])

    local function Raw(w, ...)
        if behavior then
            return behavior(State(w), w, ...)
        end
    end

    local fn
    local entry, api = MethodEntry(widgetType, method)
    local typeMethod = (Harness.TYPE_METHODS[widgetType] and Harness.TYPE_METHODS[widgetType][method])

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

        calls[method] = ((calls[method] or 0) + 1)

        return fn(w, ...)
    end

    self.methodCache[key] = Counted

    return Counted
end
