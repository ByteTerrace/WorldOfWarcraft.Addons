-- Blizzard UI the fake client models for addons that extend it: right-click and context menus
-- (Menu, MenuUtil), class colors (RAID_CLASS_COLORS, C_ClassColor, C_ColorUtil) and the unit
-- tooltip (GameTooltip, TooltipDataProcessor). See wow.lua for the rest.
--
-- Menus (Blizzard_Menu: Menu.lua, MenuUtil.lua, MenuTemplates.lua):
--   * Menu.ModifyMenu(tag, callback) registers callback(owner, rootDescription, contextData) and
--     returns a handle with Unregister(). Like the client it runs the callback at once against
--     the last menu generated with that tag, if any.
--   * h:OpenMenu(tag, contextData [, owner]) generates a menu with that tag: a root description
--     holding Blizzard's title, then every registered callback in registration order (an error is
--     reported and the rest still run). For a MENU_UNIT_<WHICH> tag the harness completes
--     contextData like UnitPopupManager:OpenMenu: which, and for a unit, name and surname (the
--     realm of another realm's player, else nil) from the unit. Blizzard's own entries after the
--     title (Set Focus, Inspect, ...) aren't modeled. It returns a menu: menu:Click(text) picks the
--     first element with that text, depth first, like a mouse click (MenuInputContext.MouseButton,
--     "LeftButton"): a disabled element does nothing and returns false; otherwise the responder
--     runs as responder(data, { context, buttonName }, menuProxy) and Click returns true and the
--     response (the responder's, else the element's default: MenuResponse.Refresh for a checkbox).
--     menu:Find(text) returns the element description; menu:Texts() lists the texts in order.
--     Clicking text no element has is an error.
--   * h:OpenTargetMenu() opens the target frame's menu: TargetFrame_OpenMenu's choice of which
--     (SELF, PARTY, RAID_PLAYER, PLAYER, ENEMY_PLAYER or TARGET, see TargetMenuWhich) with
--     contextData { fromTargetFrame = true, unit = "target" }. [G] The owner (TargetFrame) and
--     ownerFrame are nil.
--   Tags (the forever branch): the target frame builds MENU_UNIT_ENEMY_PLAYER for an enemy player,
--   MENU_UNIT_PLAYER for a friendly one outside the group, MENU_UNIT_PARTY / MENU_UNIT_RAID_PLAYER
--   for group members, MENU_UNIT_TARGET for an NPC and MENU_UNIT_SELF for the player, whose own
--   frame builds MENU_UNIT_SELF too. Nameplates open no menu.
--   * MenuUtil.CreateContextMenu(ownerRegion, generator, ...) is MenuUtil.lua's: a nil owner is
--     UIParent (GetAppropriateTopLevelParent), a root description (no title) goes to
--     generator(ownerRegion, rootDescription, ...) (an error is reported and it carries on, like
--     securecallfunction), then, if the generator tagged it (SetTag), the Menu.ModifyMenu callbacks
--     for that tag run. Opening closes any open context menu. A description with no elements
--     opens nothing and returns nil (MenuManagerMixin:GenerateMenuInternal); otherwise it plays
--     SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON (in h.soundKits) and returns the menu's proxy, whose
--     methods the harness doesn't model. h:OpenContextMenu() returns the open context menu (an
--     error when none is open), a menu like h:OpenMenu's; clicking an element whose response is
--     nil, Close or CloseAll closes it (MenuManagerMixin's response handling), Refresh and Open
--     keep it open.
--   Descriptions support the element methods addons use: CreateButton, CreateTitle, CreateDivider,
--   CreateSpacer, CreateCheckbox, CreateRadio (each inserts and returns the new element, which
--   takes the same inserters to build a submenu), Insert, QueueTitle / QueueDivider / QueueSpacer
--   (inserted before the next inserted element, dropped otherwise), SetTag / GetTag, SetEnabled /
--   IsEnabled, SetData / GetData, SetResponder / HasResponder, SetResponse, SetCanSelect /
--   CanSelect, SetIsSelected / IsSelected, AddInitializer, SetTooltip, SetOnEnter / SetOnLeave,
--   EnumerateElementDescriptions, HasElements and Pick. Any other method is an error.
--
-- Class colors (Blizzard_SharedXML/ClassColors.lua, Blizzard_SharedXMLBase/Color.lua):
--   * RAID_CLASS_COLORS holds C_ClassColor.GetClassColor(class) for each class the client has (the
--     dump lists the nine Classic classes), each with colorStr = GenerateHexColor(); any other key
--     reads nil, like the plain table it is.
--   * [G] The values are the ChrClasses colors warcraft.wiki.gg lists (Class colors), converted
--     byte / 255; the Forever client's values weren't read in game (/dump RAID_CLASS_COLORS).
--   * A color carries ColorMixin's methods: GetRGB, GetRGBA, GetRGBAsBytes, GetRGBAAsBytes, SetRGB,
--     SetRGBA, IsRGBEqualTo, IsEqualTo, GenerateHexColor, GenerateHexColorNoAlpha,
--     GenerateHexColorMarkup and WrapTextInColorCode (GetHSL is an error: not modeled). The hex
--     and wrapping methods call C_ColorUtil like Color.lua: GenerateTextColorCode gives "aarrggbb"
--     in lower case ([G] the case), WrapTextInColor gives "|c" .. code .. text .. "|r". Both take
--     secrets (AllowedWhenTainted): a secret text gives a secret string.
--   * C_ClassColor.GetClassColor(className) returns a new color, or nothing for a class the client
--     doesn't have (MayReturnNothing). [G] The tintColor argument isn't modeled (an error).
--
-- Tooltips (Blizzard_SharedXMLGame/Tooltip, Blizzard_GameTooltip):
--   * TooltipDataProcessor.AddTooltipPostCall(tooltipType, fn) records fn (a nil type is ignored,
--     like InternalAddCall). TooltipDataProcessor.AllTypes ("ALL") calls run before the type's own.
--   * h:ShowUnitTooltip(token) is what hovering a unit does: GameTooltip is anchored to UIParent,
--     then GameTooltip:SetUnit(token) builds the unit's TooltipData, adds its lines, runs the post
--     calls with (GameTooltip, data) (an error is reported and the rest still run) and shows the
--     tooltip. A token with no unit hides it instead. Returns the data.
--   * Unit TooltipData: { type = Enum.TooltipDataType.Unit, dataInstanceID, guid, lines = { {
--     type = Enum.TooltipDataLineType.UnitName, leftText = name, unitToken = token } } }.
--     [G] guid is secret when UnitGUID(token) would be and leftText when UnitName(token) would be;
--     only the name line is modeled.
--   * GameTooltip:GetUnit() is TooltipUtil.GetDisplayedUnit: for a unit tooltip it returns
--     UnitName(unit), unit, guid with unit = UnitTokenFromGUID(guid), so for an NPC all three are
--     secret and for a player all three are plain (the token may differ from the one shown, see
--     units.lua). Other tooltips return nothing.
--   * GameTooltip's lines: Harness.State(GameTooltip).lines is a list of texts (a double line's is
--     "left<TAB>right"; a secret side makes it secret), .lineInfo the same lines as { left, right,
--     r, g, b, wrap }. AddLine and AddDoubleLine append, ClearLines empties, NumLines counts,
--     SetOwner(owner, anchor) clears the lines and the tooltip's data ([G]), SetText replaces the
--     lines with one.
--     The lines SetUnit adds from data are written directly (Blizzard's AddLine calls aren't
--     counted). AddLine and AddDoubleLine are undocumented C methods, so they refuse secrets.

local SNAPSHOT = __snapshot

-- Menus ---------------------------------------------------------------------

local ENUMS = SNAPSHOT.enums
local MENU_INPUT_CONTEXT = { None = 1, MouseButton = 2, MouseWheel = 3 }   -- MenuConstants.lua
local MENU_RESPONSE = { Open = 1, Refresh = 2, Close = 3, CloseAll = 4 }   -- MenuConstants.lua

-- A description's harness side: its kind and child elements (the private description).
local private = setmetatable({}, { __mode = "k" })

local METHODS = {}
local DescriptionMeta = {
    __index = function(_, key)
        local method = METHODS[key]
        if method then
            return method
        end
        if type(key) == "string" and key:find("^%u") then
            error("the harness doesn't model menu description method " .. key, 2)
        end
    end,
}

-- The harness generating a menu (descriptions created while its callbacks run belong to it).
local activeHarness

local function NewDescription(kind, text, data)
    local d = setmetatable({ text = text, data = data }, DescriptionMeta)
    private[d] = { kind = kind, elements = {}, initializers = {}, harness = activeHarness }
    return d
end

-- The element each MenuUtil inserter creates (MenuTemplates / MenuUtil).
local CREATORS = {
    CreateButton = function(text, callback, data)
        local d = NewDescription("button", text, data)
        d.responder = callback
        return d
    end,
    CreateTitle = function(text) return NewDescription("title", text) end,
    CreateDivider = function() return NewDescription("divider") end,
    CreateSpacer = function() return NewDescription("spacer") end,
    CreateCheckbox = function(text, isSelected, setSelected, data)
        local d = NewDescription("checkbox", text, data)
        d.isSelected, d.responder, d.defaultResponse = isSelected, setSelected, MENU_RESPONSE.Refresh
        return d
    end,
    CreateRadio = function(text, isSelected, setSelected, data)
        local d = NewDescription("radio", text, data)
        d.isSelected, d.responder = isSelected, setSelected
        return d
    end,
}

function METHODS:Insert(description, index)
    local elements = private[self].elements
    local queued = self.queuedProxies
    self.queuedProxies = nil
    for _, q in ipairs(queued or {}) do
        elements[#elements + 1] = q
    end
    table.insert(elements, index or #elements + 1, description)
    return description
end
for name, create in pairs(CREATORS) do
    METHODS[name] = function(self, ...) return self:Insert(create(...)) end
end
function METHODS:AddQueuedDescription(description)
    self.queuedProxies = self.queuedProxies or {}
    table.insert(self.queuedProxies, description)
end
function METHODS:ClearQueuedDescriptions() self.queuedProxies = nil end
local function Queue(self, description, clear)
    if clear then self:ClearQueuedDescriptions() end
    self:AddQueuedDescription(description)
end
function METHODS:QueueTitle(text, _, clear) Queue(self, CREATORS.CreateTitle(text), clear) end
function METHODS:QueueDivider(clear) Queue(self, CREATORS.CreateDivider(), clear) end
function METHODS:QueueSpacer(_, clear) Queue(self, CREATORS.CreateSpacer(), clear) end
function METHODS:SetTag(tag, contextData) self.tag, self.contextData = tag, contextData end
function METHODS:GetTag() return self.tag, self.contextData end
function METHODS:SetEnabled(isEnabled) self.isEnabled = isEnabled end
function METHODS:IsEnabled()
    if self.isEnabled == nil then return true end
    if type(self.isEnabled) == "boolean" then return self.isEnabled end
    return self.isEnabled(self)
end
function METHODS:SetData(data) self.data = data end
function METHODS:GetData() return self.data end
function METHODS:SetResponder(callback) self.responder = callback end
function METHODS:HasResponder() return self.responder ~= nil end
function METHODS:SetResponse(response) self.defaultResponse = response end
function METHODS:SetCanSelect(canSelect) self.canSelect = canSelect end
function METHODS:CanSelect()
    if not self:IsEnabled() then return false end
    if self.canSelect == nil then return true end
    if type(self.canSelect) == "boolean" then return self.canSelect end
    return self.canSelect(self:GetData())
end
function METHODS:SetIsSelected(isSelected) self.isSelected = isSelected end
function METHODS:IsSelected()
    if self.isSelected == nil then return false end
    return self.isSelected(self:GetData())
end
function METHODS:AddInitializer(initializer) table.insert(private[self].initializers, initializer) end
function METHODS:SetTooltip(initializer) self.tooltipInitializer = initializer end
function METHODS:SetOnEnter(onEnter) self.onEnter = onEnter end
function METHODS:SetOnLeave(onLeave) self.onLeave = onLeave end
function METHODS:HasElements() return #private[self].elements > 0 end
METHODS.CanOpenSubmenu = METHODS.HasElements
function METHODS:EnumerateElementDescriptions() return ipairs(private[self].elements) end

-- The menu a responder receives: the harness models none of its methods.
local MenuProxyMeta = {
    __index = function(_, key)
        error("the harness doesn't model the menu's " .. tostring(key), 2)
    end,
}

-- MenuElementDescriptionProxyMixin:Pick: returns willRespond, response.
function METHODS:Pick(context, buttonName)
    assert(context, "Pick() called without an input context.")
    if not self:CanSelect() then
        return false
    end
    if not self:HasResponder() then
        return false
    end
    local response = self.defaultResponse
    local h = assert(private[self].harness, "Pick: this description wasn't made for a harness menu")
    local menuProxy = setmetatable({}, MenuProxyMeta)
    local override
    local ok = h:Protect(function()
        override = self.responder(self:GetData(), { context = context, buttonName = buttonName }, menuProxy)
    end)
    if ok and override then
        response = override
    end
    return true, response
end

-- Every element under a description, depth first.
local function Walk(description, out)
    for _, element in ipairs(private[description].elements) do
        out[#out + 1] = element
        Walk(element, out)
    end
    return out
end

local function NewMenu(h, root)
    local menu = { root = root }
    function menu:Find(text)
        for _, element in ipairs(Walk(root, {})) do
            if element.text == text then
                return element
            end
        end
    end
    function menu:Texts()
        local texts = {}
        for _, element in ipairs(Walk(root, {})) do
            if element.text ~= nil then texts[#texts + 1] = element.text end
        end
        return texts
    end
    function menu:Click(text)
        local element = self:Find(text)
        if not element then
            error(("menu %s has no element %q (it has: %s)"):format(tostring(root.tag), tostring(text),
                table.concat(self:Texts(), ", ")), 2)
        end
        return element:Pick(MENU_INPUT_CONTEXT.MouseButton, "LeftButton")
    end
    return menu
end

-- UnitPopupManager:OpenMenu's contextData completion for a MENU_UNIT_ tag.
local function CompleteUnitContext(h, which, contextData)
    contextData.which = which
    local unit = contextData.unit and h:Unit(contextData.unit)
    if unit then
        contextData.name = unit.name
        contextData.surname = unit.realm ~= nil and unit.realm ~= h.player.realm and unit.realm or nil
    end
end

-- Generates the menu tagged tag: Blizzard's title, then every Menu.ModifyMenu callback.
function Harness:OpenMenu(tag, contextData, owner)
    assert(type(tag) == "string", "OpenMenu: tag must be a string")
    contextData = contextData or {}
    local which = tag:match("^MENU_UNIT_(.+)$")
    if which then
        CompleteUnitContext(self, which, contextData)
    end
    local previous = activeHarness
    activeHarness = self
    local root = NewDescription("root")
    root:SetTag(tag, contextData)
    if which then
        root:CreateTitle() -- UnitPopupManager's title; its text comes from an initializer
    end
    self:ModifyMenu(tag, owner, root)
    activeHarness = previous
    return NewMenu(self, root)
end

-- SecureModifyMenu: remembers the tag's latest description and runs its callbacks.
function Harness:ModifyMenu(tag, owner, root)
    self.generatedMenus[tag] = { root = root, owner = owner }
    for _, registration in ipairs(self.menuCallbacks) do
        if registration.tag == tag and not registration.unregistered then
            self:Protect(registration.callback, owner, root, root.contextData)
        end
    end
end

-- The open context menu (MenuUtil.CreateContextMenu).
function Harness:OpenContextMenu()
    return assert(self.contextMenu, "OpenContextMenu: no context menu is open")
end

local CLOSING = { [MENU_RESPONSE.Close] = true, [MENU_RESPONSE.CloseAll] = true }

local function CreateContextMenu(h, ownerRegion, generator, ...)
    ownerRegion = ownerRegion or h.env.UIParent
    local previous = activeHarness
    activeHarness = h
    local root = NewDescription("root")
    h:Protect(generator, ownerRegion, root, ...)
    if root.tag then
        h:ModifyMenu(root.tag, ownerRegion, root)
    end
    activeHarness = previous
    h.contextMenu = nil
    if not root:HasElements() then
        return nil
    end
    local menu = NewMenu(h, root)
    local click = menu.Click
    function menu:Click(text)
        local responded, response = click(self, text)
        if responded and (response == nil or CLOSING[response]) and h.contextMenu == self then
            h.contextMenu = nil
        end
        return responded, response
    end
    h.contextMenu = menu
    h.env.PlaySound(h.env.SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
    return setmetatable({}, MenuProxyMeta)
end

-- TargetFrame_OpenMenu's which (Blizzard_UnitFrame/Mainline/TargetFrame.lua), for the target.
function Harness:TargetMenuWhich()
    local target = self.target
    assert(target, "OpenTargetMenu: no target")
    if target == self.player then return "SELF" end
    if target.isPlayer then
        local env = self.env
        if env.UnitInRaid("target") then return "RAID_PLAYER" end
        if env.UnitInParty("target") then return "PARTY" end
        local enemy = target.isEnemy
        if enemy == nil then enemy = target.canAttack end
        return enemy and "ENEMY_PLAYER" or "PLAYER"
    end
    return "TARGET"
end

function Harness:OpenTargetMenu()
    return self:OpenMenu("MENU_UNIT_" .. self:TargetMenuWhich(), { fromTargetFrame = true, unit = "target" })
end

local function MenuFakes(h)
    return {
        ModifyMenu = function(tag, callback)
            assert(type(tag) == "string")
            local registration = { tag = tag, callback = callback }
            local generated = h.generatedMenus[tag]
            if generated then
                callback(generated.owner, generated.root, generated.root.contextData)
            end
            h.menuCallbacks[#h.menuCallbacks + 1] = registration
            return { Unregister = function() registration.unregistered = true end }
        end,
    }
end

-- Class colors ---------------------------------------------------------------

-- ChrClasses colors in bytes (warcraft.wiki.gg Class colors), for the classes the client has.
local CLASS_COLOR_BYTES = {
    WARRIOR = { 198, 155, 109 }, PALADIN = { 244, 140, 186 }, HUNTER = { 170, 211, 114 }, ROGUE = { 255, 244, 104 },
    PRIEST = { 255, 255, 255 }, SHAMAN = { 0, 112, 221 }, MAGE = { 63, 199, 235 }, WARLOCK = { 135, 136, 238 },
    DRUID = { 255, 124, 10 },
}

local function Round(value) return math.floor(value + 0.5) end

-- C_ColorUtil.GenerateTextColorCode: "aarrggbb".
local function TextColorCode(color)
    return ("%.2x%.2x%.2x%.2x"):format(Round((color.a or 1) * 255), Round(color.r * 255), Round(color.g * 255),
        Round(color.b * 255))
end

-- A ColorMixin color (see the header); its hex and wrapping methods go through the env's C_ColorUtil.
local function MixinColor(h, r, g, b, a)
    local color = {}
    function color:SetRGBA(nr, ng, nb, na) self.r, self.g, self.b, self.a = nr, ng, nb, na or 1 end
    function color:SetRGB(nr, ng, nb) self:SetRGBA(nr, ng, nb, nil) end
    function color:GetRGB() return self.r, self.g, self.b end
    function color:GetRGBA() return self.r, self.g, self.b, self.a end
    function color:GetRGBAsBytes() return Round(self.r * 255), Round(self.g * 255), Round(self.b * 255) end
    function color:GetRGBAAsBytes()
        return Round(self.r * 255), Round(self.g * 255), Round(self.b * 255), Round((self.a or 1) * 255)
    end
    function color:IsRGBEqualTo(other) return self.r == other.r and self.g == other.g and self.b == other.b end
    function color:IsEqualTo(other) return self:IsRGBEqualTo(other) and self.a == other.a end
    function color:GenerateHexColor() return h.env.C_ColorUtil.GenerateTextColorCode(self) end
    function color:GenerateHexColorNoAlpha() return ("%.2X%.2X%.2X"):format(self:GetRGBAsBytes()) end
    function color:GenerateHexColorMarkup() return "|c" .. self:GenerateHexColor() end
    function color:WrapTextInColorCode(text) return h.env.C_ColorUtil.WrapTextInColor(text, self) end
    function color:GetHSL() error("the harness doesn't model ColorMixin:GetHSL", 2) end
    color:SetRGBA(r, g, b, a)
    return color
end

local function ClassColor(h, className)
    local bytes = CLASS_COLOR_BYTES[className]
    if bytes then
        return MixinColor(h, bytes[1] / 255, bytes[2] / 255, bytes[3] / 255)
    end
end

local function ColorFakes(h)
    local classColors = {}
    for className in pairs(CLASS_COLOR_BYTES) do
        local color = ClassColor(h, className)
        color.colorStr = TextColorCode(color)
        classColors[className] = color
    end
    return {
        RAID_CLASS_COLORS = classColors,
        C_ClassColor = {
            GetClassColor = function(className, tintColor)
                assert(tintColor == nil, "C_ClassColor.GetClassColor: the harness doesn't model tintColor")
                return ClassColor(h, Reveal(className))
            end,
        },
        C_ColorUtil = {
            GenerateTextColorCode = function(color) return TextColorCode(color) end,
            WrapTextInColor = function(text, color) return "|c" .. TextColorCode(color) .. Reveal(text) .. "|r" end,
            WrapTextInColorCode = function(text, code) return "|c" .. Reveal(code) .. Reveal(text) .. "|r" end,
        },
    }
end

-- Tooltips ------------------------------------------------------------------

local TOOLTIP_TYPES = ENUMS.TooltipDataType
local LINE_TYPES = ENUMS.TooltipDataLineType
local ALL_TYPES = "ALL" -- TooltipDataProcessor.AllTypes

-- The unit's TooltipData (see the header), with the secrecy the unit's identity APIs have.
function Harness:UnitTooltipData(token)
    local unit = self:Unit(token)
    if not unit then
        return nil
    end
    local env = self.env
    self.tooltipSerial = self.tooltipSerial + 1
    return {
        type = TOOLTIP_TYPES.Unit, dataInstanceID = self.tooltipSerial, guid = env.UnitGUID(token),
        lines = { { type = LINE_TYPES.UnitName, leftText = (env.UnitName(token)), unitToken = token } },
    }
end

local tooltipBehaviors = Harness.TYPE_BEHAVIORS.GameTooltip

-- A line's text for s.lines: the left text, or "left<TAB>right" (secret if either side is).
local function LineText(left, right)
    if right == nil then
        return left
    end
    local text = tostring(Reveal(left)) .. "\t" .. tostring(Reveal(right))
    return (IsSecret(left) or IsSecret(right)) and Secret(text) or text
end

local function AddTooltipLine(s, left, right, r, g, b, wrap)
    s.lines[#s.lines + 1] = LineText(left, right)
    s.lineInfo[#s.lineInfo + 1] = { left = left, right = right, r = r, g = g, b = b, wrap = wrap }
end

local function ClearTooltipLines(s)
    s.lines, s.lineInfo = {}, {}
end

function tooltipBehaviors.AddLine(s, _, text, r, g, b, wrap) AddTooltipLine(s, text, nil, r, g, b, wrap) end
function tooltipBehaviors.AddDoubleLine(s, _, left, right, r, g, b) AddTooltipLine(s, left, right, r, g, b) end
function tooltipBehaviors.ClearLines(s) ClearTooltipLines(s) end
function tooltipBehaviors.NumLines(s) return #s.lines end
function tooltipBehaviors.SetText(s, _, text, r, g, b, _, wrap)
    ClearTooltipLines(s)
    AddTooltipLine(s, text, nil, r, g, b, wrap)
end
function tooltipBehaviors.SetOwner(s, _, owner, anchor)
    s.owner, s.anchor, s.tooltipData = owner, anchor, nil
    ClearTooltipLines(s)
end
function tooltipBehaviors.GetOwner(s) return s.owner end
function tooltipBehaviors.IsOwned(s, _, frame) return s.owner == frame end
function tooltipBehaviors.GetPrimaryTooltipData(s) return s.tooltipData end
tooltipBehaviors.GetTooltipData = tooltipBehaviors.GetPrimaryTooltipData
function tooltipBehaviors.IsTooltipType(s, _, tooltipType)
    return s.tooltipData ~= nil and s.tooltipData.type == tooltipType
end
-- TooltipUtil.GetDisplayedUnit.
function tooltipBehaviors.GetUnit(s)
    local data = s.tooltipData
    if not data or data.type ~= TOOLTIP_TYPES.Unit then
        return
    end
    local env = s.harness.env
    local guid = data.guid
    local unit = guid and env.UnitTokenFromGUID(guid)
    local name = unit and env.UnitName(unit)
    return name, unit, guid
end
-- TooltipDataHandlerMixin:ProcessInfo for C_TooltipInfo.GetUnit's data.
function tooltipBehaviors.SetUnit(s, tooltip, token)
    local h = s.harness
    local data = h:UnitTooltipData(token)
    if not data then
        s.shown = false
        return false
    end
    ClearTooltipLines(s)
    s.tooltipData = data
    for _, line in ipairs(data.lines) do
        if line.leftText ~= nil then
            AddTooltipLine(s, line.leftText, line.rightText)
        end
    end
    for _, key in ipairs({ ALL_TYPES, data.type }) do
        for _, fn in ipairs(h.tooltipPostCalls[key] or {}) do
            h:Protect(fn, tooltip, data)
        end
    end
    s.shown = true
    return true
end

-- Hovering a unit: GameTooltip anchored to UIParent, then SetUnit(token). Returns the data.
function Harness:ShowUnitTooltip(token)
    local tooltip = self.env.GameTooltip
    local s = Harness.State(tooltip)
    tooltipBehaviors.SetOwner(s, tooltip, self.env.UIParent, "ANCHOR_NONE")
    tooltipBehaviors.SetUnit(s, tooltip, token)
    return s.tooltipData
end

local function TooltipFakes(h)
    return {
        AllTypes = ALL_TYPES,
        AddTooltipPostCall = function(tooltipType, fn)
            if tooltipType == nil then return end
            h.tooltipPostCalls[tooltipType] = h.tooltipPostCalls[tooltipType] or {}
            table.insert(h.tooltipPostCalls[tooltipType], fn)
        end,
    }
end

-- Fakes ---------------------------------------------------------------------

-- The UI fakes, merged into the env (env.lua). Registrations belong to the UI session: a reload
-- starts without them.
function Harness:InterfaceFakes(uiParent)
    self.menuCallbacks, self.generatedMenus = {}, {}
    self.tooltipPostCalls, self.tooltipSerial = {}, 0
    self.namePlateFrames = {}
    local tooltip = self:CreateWidget("GameTooltip", "GameTooltip", uiParent)
    local s = Harness.State(tooltip)
    s.shown = false
    ClearTooltipLines(s)
    self.contextMenu = nil
    local h = self
    local fakes = {
        Menu = MenuFakes(self),
        MenuUtil = { CreateContextMenu = function(...) return CreateContextMenu(h, ...) end },
        MenuInputContext = MENU_INPUT_CONTEXT,
        MenuResponse = MENU_RESPONSE,
        TooltipDataProcessor = TooltipFakes(self),
        GameTooltip = tooltip,
    }
    for name, value in pairs(ColorFakes(self)) do
        fakes[name] = value
    end
    return fakes
end
