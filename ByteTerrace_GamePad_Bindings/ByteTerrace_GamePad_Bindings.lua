---@type string
local addOnName = select(1, ...)
local api = ByteTerrace
---@param secureButton ButtonFromTemplate
local initializeDriver = function (secureButton)
    secureButton:EnableGamePadButton(true)
    secureButton:RegisterForClicks("AnyDown", "AnyUp")
    secureButton:SetAttribute("action", 1)
    secureButton:SetAttribute("ActionBarPage-State1", 1)
    secureButton:SetAttribute("ActionBarPage-State2", 6)
    secureButton:SetAttribute("ActionBarPage-State3", 5)
    secureButton:SetAttribute("ActionBarPage-State4", 4)
    secureButton:SetAttribute("ActionBarPage-State5", 3)
    secureButton:SetAttribute("type", "actionbar")
    ---@diagnostic disable-next-line: undefined-field
    secureButton:WrapScript(secureButton, "OnClick", [[
        local modifier1 = self:GetAttribute("Modifier1-Input")
        local modifier2 = self:GetAttribute("Modifier2-Input")
        local state = 1

        if (not down) then
            self:SetAttribute(modifier1, false)
            self:SetAttribute(modifier2, false)
        else
            self:SetAttribute(button, true)

            if (modifier1 == button) then
                if self:GetAttribute(modifier2) then
                    state = 4
                else
                    state = 2
                end
            elseif (modifier2 == button) then
                if self:GetAttribute(modifier1) then
                    state = 5
                else
                    state = 3
                end
            end
        end

        self:SetAttribute("action", self:GetAttribute("ActionBarPage-State" .. tostring(state)))
        self:SetBinding(true, self:GetAttribute("Action5-Input"), self:GetAttribute("Action5-State" .. tostring(state)))
        self:SetBinding(true, self:GetAttribute("Action9-Input"), self:GetAttribute("Action9-State" .. tostring(state)))
        self:SetBinding(true, self:GetAttribute("Action11-Input"), self:GetAttribute("Action11-State" .. tostring(state)))
        self:SetBinding(true, self:GetAttribute("Action13-Input"), self:GetAttribute("Action13-State" .. tostring(state)))
        self:SetBinding(true, self:GetAttribute("Action14-Input"), self:GetAttribute("Action14-State" .. tostring(state)))
    ]])

    if api.System.IsMainline() then
        secureButton:SetAttribute("pressAndHoldAction", true)
        secureButton:SetAttribute("typerelease", "actionbar")
    end
end
---@generic FrameTemplateType
---@param bindings table
---@param secureButton ButtonFromTemplate
local setBindings = function (bindings, secureButton)
    SetOverrideBinding(secureButton, true, bindings.Action1.Input, bindings.Action1.States[1])
    SetOverrideBinding(secureButton, true, bindings.Action2.Input, bindings.Action2.States[1])
    SetOverrideBinding(secureButton, true, bindings.Action3.Input, bindings.Action3.States[1])
    SetOverrideBinding(secureButton, true, bindings.Action4.Input, bindings.Action4.States[1])
    SetOverrideBinding(secureButton, true, bindings.Action5.Input, bindings.Action5.States[1])
    SetOverrideBinding(secureButton, true, bindings.Action6.Input, bindings.Action6.States[1])
    SetOverrideBinding(secureButton, true, bindings.Action7.Input, bindings.Action7.States[1])
    SetOverrideBinding(secureButton, true, bindings.Action8.Input, bindings.Action8.States[1])
    SetOverrideBinding(secureButton, true, bindings.Action9.Input, bindings.Action9.States[1])
    SetOverrideBinding(secureButton, true, bindings.Action10.Input, bindings.Action10.States[1])
    SetOverrideBinding(secureButton, true, bindings.Action11.Input, bindings.Action11.States[1])
    SetOverrideBinding(secureButton, true, bindings.Action12.Input, bindings.Action12.States[1])
    SetOverrideBinding(secureButton, true, bindings.Action13.Input, bindings.Action13.States[1])
    SetOverrideBinding(secureButton, true, bindings.Action14.Input, bindings.Action14.States[1])
    SetOverrideBindingClick(secureButton, true, bindings.Modifier1.Input, secureButton:GetName(), bindings.Modifier1.Input)
    SetOverrideBindingClick(secureButton, true, bindings.Modifier2.Input, secureButton:GetName(), bindings.Modifier2.Input)

    secureButton:SetAttribute("Action5-Input", bindings.Action5.Input)
    secureButton:SetAttribute("Action5-State1", bindings.Action5.States[1])
    secureButton:SetAttribute("Action5-State2", bindings.Action5.States[2])
    secureButton:SetAttribute("Action5-State3", bindings.Action5.States[3])
    secureButton:SetAttribute("Action5-State4", bindings.Action5.States[4])
    secureButton:SetAttribute("Action5-State5", bindings.Action5.States[5])
    secureButton:SetAttribute("Action9-Input", bindings.Action9.Input)
    secureButton:SetAttribute("Action9-State1", bindings.Action9.States[1])
    secureButton:SetAttribute("Action9-State2", bindings.Action9.States[2])
    secureButton:SetAttribute("Action9-State3", bindings.Action9.States[3])
    secureButton:SetAttribute("Action9-State4", bindings.Action9.States[4])
    secureButton:SetAttribute("Action9-State5", bindings.Action9.States[5])
    secureButton:SetAttribute("Action11-Input", bindings.Action11.Input)
    secureButton:SetAttribute("Action11-State1", bindings.Action11.States[1])
    secureButton:SetAttribute("Action11-State2", bindings.Action11.States[2])
    secureButton:SetAttribute("Action11-State3", bindings.Action11.States[3])
    secureButton:SetAttribute("Action11-State4", bindings.Action11.States[4])
    secureButton:SetAttribute("Action11-State5", bindings.Action11.States[5])
    secureButton:SetAttribute("Action13-Input", bindings.Action13.Input)
    secureButton:SetAttribute("Action13-State1", bindings.Action13.States[1])
    secureButton:SetAttribute("Action13-State2", bindings.Action13.States[2])
    secureButton:SetAttribute("Action13-State3", bindings.Action13.States[3])
    secureButton:SetAttribute("Action13-State4", bindings.Action13.States[4])
    secureButton:SetAttribute("Action13-State5", bindings.Action13.States[5])
    secureButton:SetAttribute("Action14-Input", bindings.Action14.Input)
    secureButton:SetAttribute("Action14-State1", bindings.Action14.States[1])
    secureButton:SetAttribute("Action14-State2", bindings.Action14.States[2])
    secureButton:SetAttribute("Action14-State3", bindings.Action14.States[3])
    secureButton:SetAttribute("Action14-State4", bindings.Action14.States[4])
    secureButton:SetAttribute("Action14-State5", bindings.Action14.States[5])
    secureButton:SetAttribute("Modifier1-Input", bindings.Modifier1.Input)
    secureButton:SetAttribute("Modifier2-Input", bindings.Modifier2.Input)
end

api.Events.Register({
    ADDON_LOADED = function (name)
        if (addOnName == name) then
            local addOnSettings = _G[addOnName]
            local controllerButton = CreateFrame("Button", "ByteTerraceGamePadActionBarControllerButton", UIParent, "SecureActionButtonTemplate, SecureHandlerStateTemplate")

            if (nil == addOnSettings) then
                addOnSettings = {
                    Bindings = {
                        Action1 = {
                            Input = "PADDUP",
                            States = {
                                [1] = "ACTIONBUTTON1",
                            },
                        },
                        Action2 = {
                            Input = "PADDRIGHT",
                            States = {
                                [1] = "ACTIONBUTTON2",
                            },
                        },
                        Action3 = {
                            Input = "PADDDOWN",
                            States = {
                                [1] = "ACTIONBUTTON3",
                            },
                        },
                        Action4 = {
                            Input = "PADDLEFT",
                            States = {
                                [1] = "ACTIONBUTTON4",
                            },
                        },
                        Action5 = {
                            Input = "PADLSHOULDER",
                            States = {
                                [1] = "TARGETNEARESTENEMY",
                                [2] = "TARGETNEARESTFRIEND",
                                [3] = "UNBOUND",
                                [4] = "ACTIONBUTTON5",
                                [5] = "ACTIONBUTTON5",
                            },
                        },
                        Action6 = {
                            Input = "PADLSTICK",
                            States = {
                                [1] = "ACTIONBUTTON6",
                            },
                        },
                        Action7 = {
                            Input = "PAD4",
                            States = {
                                [1] = "ACTIONBUTTON7",
                            },
                        },
                        Action8 = {
                            Input = "PAD3",
                            States = {
                                [1] = "ACTIONBUTTON8",
                            },
                        },
                        Action9 = {
                            Input = "PAD1",
                            States = {
                                [1] = "JUMP",
                                [2] = "ACTIONBUTTON9",
                                [3] = "ACTIONBUTTON9",
                                [4] = "ACTIONBUTTON9",
                                [5] = "ACTIONBUTTON9",
                            },
                        },
                        Action10 = {
                            Input = "PAD2",
                            States = {
                                [1] = "ACTIONBUTTON10",
                            },
                        },
                        Action11 = {
                            Input = "PADRSHOULDER",
                            States = {
                                [1] = "INTERACTMOUSEOVER",
                                [2] = "TOGGLEAUTORUN",
                                [3] = "FLIPCAMERAYAW",
                                [4] = "ACTIONBUTTON11",
                                [5] = "ACTIONBUTTON11",
                            },
                        },
                        Action12 = {
                            Input = "PADRSTICK",
                            States = {
                                [1] = "ACTIONBUTTON12",
                            },
                        },
                        Action13 = {
                            Input = "PADSOCIAL",
                            States = {
                                [1] = "TOGGLEWORLDMAP",
                                [2] = "OPENALLBAGS",
                                [3] = "TOGGLECHARACTER0",
                                [4] = "TOGGLESOCIAL",
                                [5] = "TOGGLESPELLBOOK",
                            },
                        },
                        Action14 = {
                            Input = "PADFORWARD",
                            States = {
                                [1] = "TOGGLEGAMEMENU",
                                [2] = "TOGGLEGAMEMENU",
                                [3] = "TOGGLEGAMEMENU",
                                [4] = "TOGGLEGAMEMENU",
                                [5] = "TOGGLEGAMEMENU",
                            },
                        },
                        Modifier1 = {
                            Input = "PADLTRIGGER",
                        },
                        Modifier2 = {
                            Input = "PADRTRIGGER",
                        },
                    },
                    ConsoleVariables = {
                        GamePadAnalogMovement = true,
                        GamePadCameraPitchSpeed = 1.5,
                        GamePadCameraYawSpeed = 2.25,
                        GamePadCursorAutoDisableJump = true,
                        GamePadCursorAutoDisableSticks = "2",
                        GamePadCursorAutoEnable = false,
                        GamePadCursorCenteredEmulation = false,
                        GamePadCursorCentering = false,
                        GamePadCursorForTargeting = false,
                        GamePadCursorLeftClick = "NONE",
                        GamePadCursorOnLogin = true,
                        GamePadCursorRightClick = "NONE",
                        GamePadEmulateAlt = "NONE",
                        GamePadEmulateCtrl = "NONE",
                        GamePadEmulateShift = "NONE",
                        GamePadEmulateTapWindowMs = 350,
                        GamePadEnable = true,
                        GamePadFaceMovementMaxAngle = 115.0,
                        GamePadFaceMovementMaxAngleCombat = 115.0,
                        GamePadFactionColor = false,
                        GamePadOverlapMouseMs = 2000,
                        GamePadRunThreshold = 0.65,
                        GamePadStickAxisButtons = false,
                        GamePadTankTurnSpeed = 0.0,
                        GamePadTouchCursorEnable = false,
                        GamePadTurnWithCamera = "2",
                        GamePadVibrationStrength = 1.0,
                        SoftTargetEnemy = "1",
                        SoftTargetEnemyArc = "1",
                        SoftTargetEnemyRange = 30.0,
                        SoftTargetFriend = "1",
                        SoftTargetFriendArc = "1",
                        SoftTargetFriendRange = 10.0,
                        SoftTargetForce = "0",
                        SoftTargetInteract = "1",
                        SoftTargetInteractArc = "1",
                        SoftTargetInteractRange = 2.5,
                    },
                }

                _G[addOnName] = addOnSettings
            end

            initializeDriver(controllerButton)
            setBindings(addOnSettings.Bindings, controllerButton)
        end
    end,
    PLAYER_ENTERING_WORLD = function (isInitialLogin, isReloadingUi)
        if (isInitialLogin or isReloadingUi) then
            api.Console.SetVariables(_G[addOnName].ConsoleVariables)
        end
    end,
})
