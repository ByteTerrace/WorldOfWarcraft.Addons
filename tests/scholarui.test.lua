-- Scholar's challenge: scheduling, the overlay, input capture, rewards and the parent lock.

local function Load(saved)
    local h = Harness.New({ saved = saved or {} })
    h:SeedRandom(7)
    local ns = h:LoadAddon("TheLanKrewToolKit")
    return h, ns.Addon
end

-- A child's character with the challenge on.
local function LoadKid(extra)
    local char = { ["Scholar.enabled"] = true }
    for key, value in pairs(extra or {}) do char[key] = value end
    return Load({ TheLanKrewToolKitCharDB = char })
end

local function Overlay(h)
    return rawget(h.env, "TheLanKrewToolKitScholar")
end

local function Showing(h)
    local overlay = Overlay(h)
    return overlay ~= nil and overlay:IsShown()
end

test("off by default: nothing ever appears", function()
    local h = Load()
    h:Advance(3 * 3600)
    falsy(Showing(h))
end)

test("a riddle appears after the interval of play and holds the keyboard and mouse", function()
    local h, addon = LoadKid()
    h:Advance(29 * 60)
    falsy(Showing(h))
    h:Advance(60)
    truthy(Showing(h))
    truthy(h:WorldClickBlocked(), "clicks don't reach the world")
    h:Key("W", true)
    eq(#h.propagatedKeys, 0, "movement keys are held")
end)

test("the right answer earns a star, closes the riddle and resets the timer", function()
    local h, addon = LoadKid({ ["Scholar.pending"] = true })
    truthy(Showing(h), "a pending riddle appears at login")
    -- Try every key; exactly one is right.
    for key = 1, 4 do
        h:Key(tostring(key), true)
    end
    h:Advance(2)
    falsy(Showing(h))
    eq(addon.State:Get("Scholar.stars"), 1)
    eq(addon.State:Get("Scholar.pending"), false)
    eq(addon.State:Get("Scholar.elapsed"), 0)
end)

test("turning the challenge off right after a right answer still finishes the riddle", function()
    local h, addon = LoadKid({ ["Scholar.pending"] = true })
    for key = 1, 4 do
        h:Key(tostring(key), true)
    end
    eq(addon.State:Get("Scholar.stars"), 1)
    addon.State:Set("Scholar.enabled", false)
    eq(addon.State:Get("Scholar.pending"), false, "the solved riddle isn't due again")
    eq(addon.State:Get("Scholar.elapsed"), 0)
    addon.State:Set("Scholar.enabled", true)
    falsy(Showing(h), "no riddle reappears")
end)

test("a riddle never appears in combat, steps aside when a fight starts, and comes back after", function()
    local h = LoadKid()
    h:EnterCombat()
    h:Advance(31 * 60)
    falsy(Showing(h), "not during combat")
    h:LeaveCombat()
    truthy(Showing(h), "after the fight")
    h:EnterCombat()
    falsy(Showing(h), "steps aside")
    eq(#h.blocked, 0, "no protected call was blocked")
    h:LeaveCombat()
    truthy(Showing(h), "comes back")
end)

test("a riddle that comes back after a fight keeps its wrong answers and its Skip", function()
    local h, addon = LoadKid({ ["Scholar.mode"] = "gentle", ["Scholar.level"] = 2 })
    local view, puzzle = h.ns.ScholarView, nil
    local show = view.Show
    view.Show = function(shown, info)
        puzzle = shown
        return show(shown, info)
    end
    h:Slash("/tlk puzzle")
    local wrong = puzzle.answer == 1 and 2 or 1
    h:Key(tostring(wrong), true)
    local frame = Overlay(h)
    eq(frame.Buttons[wrong].State, "wrong")
    h:EnterCombat()
    h:LeaveCombat()
    truthy(Showing(h), "it came back")
    eq(frame.Buttons[wrong].State, "wrong", "still marked")
    h:Key(tostring(wrong), true)
    eq(addon.State:Get("Scholar.level"), 2, "and it can't be picked again: one miss doesn't make riddles easier")
    truthy(frame.Skip:IsShown(), "gentle mode still offers Skip")
end)

test("relogging doesn't skip a riddle", function()
    local h = LoadKid()
    h:Advance(31 * 60)
    truthy(Showing(h))
    h:Relog(60)
    truthy(Showing(h))
end)

test("the gate mode offers no skip; gentle mode does after one try", function()
    local h = LoadKid({ ["Scholar.pending"] = true })
    h:Key("ESCAPE", true)
    truthy(Showing(h), "gate: escape does nothing")
    local h2 = LoadKid({ ["Scholar.pending"] = true, ["Scholar.mode"] = "gentle" })
    h2:Key("ESCAPE", true)
    truthy(Showing(h2), "no skip before a try")
end)

test("the controller answers with face buttons", function()
    local h, addon = LoadKid({ ["Scholar.pending"] = true })
    for _, key in ipairs({ "PAD1", "PAD2", "PAD3", "PAD4" }) do
        h:Gamepad(key, true)
        h:Gamepad(key, false)
    end
    h:Advance(2)
    eq(addon.State:Get("Scholar.stars"), 1)
    falsy(Showing(h))
end)

test("a level-up brings a riddle when that's on", function()
    local h = LoadKid()
    h.player.level = h.player.level + 1
    h:Fire("PLAYER_LEVEL_UP", h.player.level)
    truthy(Showing(h))
end)

test("a parent's PIN locks the settings until unlocked", function()
    local h, addon = LoadKid()
    h:Slash("/tlk lock 2468")
    h:Slash("/tlk set Scholar.grade 5")
    eq(addon.State:Get("Scholar.grade"), "2", "locked")
    h:Slash("/tlk toggle Scholar.enabled")
    eq(addon.State:Get("Scholar.enabled"), true, "can't be switched off")
    local window = addon.SettingsWindow
    for i, page in ipairs(window.Pages) do
        if page.name == "Scholar's challenge" then window:Show(i) end
    end
    local button = window.Controls[addon.State:Id("Scholar.mode")]
    local label = button.Label:GetText()
    button:Click()
    eq(addon.State:Get("Scholar.mode"), "gate", "the window can't change it either")
    eq(button.Label:GetText(), label, "the locked value stays visible")
    h:Slash("/tlk unlock 1111")
    eq(addon.State:Get("Scholar.locked"), true, "wrong PIN")
    h:Slash("/tlk unlock 2468")
    h:Slash("/tlk set Scholar.grade 5")
    eq(addon.State:Get("Scholar.grade"), "5")
end)

test("an unlock lasts the session, a /reload included; the lock comes back at the next login", function()
    local h = LoadKid()
    h:Slash("/tlk lock 2468")
    h:Slash("/tlk unlock 2468")
    h:Reload()
    eq(h.ns.Addon.State:Get("Scholar.locked"), false, "a /reload continues the session")
    h:Relog(60)
    eq(h.ns.Addon.State:Get("Scholar.locked"), true)
end)

test("switching the challenge back on mid-session locks it again", function()
    local h = LoadKid()
    h:Slash("/tlk lock 2468")
    h:Slash("/tlk unlock 2468")
    h:Slash("/tlk toggle Scholar.enabled")
    h:Slash("/tlk toggle Scholar.enabled")
    eq(h.ns.Addon.State:Get("Scholar.locked"), true)
end)

test("while locked, a new PIN can't replace the parent's", function()
    local h, addon = LoadKid()
    h:Slash("/tlk lock 2468")
    h:Slash("/tlk lock 1111")
    h:Slash("/tlk unlock 1111")
    eq(addon.State:Get("Scholar.locked"), true, "the child's PIN doesn't unlock")
    h:Slash("/tlk toggle Scholar.enabled")
    eq(addon.State:Get("Scholar.enabled"), true, "so Scholar stays on")
    truthy(addon.State:IsLocked("Scholar.pin"), "the PIN row itself is locked")
    h:Slash("/tlk unlock 2468")
    eq(addon.State:Get("Scholar.locked"), false, "the parent's PIN still works")
    h:Slash("/tlk lock 1357")
    h:Slash("/tlk unlock 2468")
    eq(addon.State:Get("Scholar.locked"), true, "unlocked, the parent can change the PIN")
    h:Slash("/tlk unlock 1357")
    eq(addon.State:Get("Scholar.locked"), false)
end)

test("three wrong PINs make unlocking wait a minute, even across a /reload", function()
    local h, addon = LoadKid()
    h:Slash("/tlk lock 2468")
    h:Slash("/tlk unlock 0001")
    h:Slash("/tlk unlock 0002")
    h:Reload()
    h:Slash("/tlk unlock 0003")
    h:Slash("/tlk unlock 2468")
    eq(h.ns.Addon.State:Get("Scholar.locked"), true, "the right PIN waits too, so guessing gains nothing")
    h:Reload()
    h:Advance(30)
    h:Slash("/tlk unlock 2468")
    eq(h.ns.Addon.State:Get("Scholar.locked"), true, "a /reload doesn't end the wait")
    h:Advance(31)
    h:Slash("/tlk unlock 2468")
    eq(h.ns.Addon.State:Get("Scholar.locked"), false, "after a minute the right PIN unlocks")
end)

test("time AFK doesn't count toward the next riddle", function()
    local h, addon = LoadKid()
    h.player.afk = true
    h:Fire("PLAYER_FLAGS_CHANGED", "player")
    h:Advance(2 * 3600)
    falsy(Showing(h))
    eq(addon.State:Get("Scholar.elapsed"), 0)
    h.player.afk = false
    h:Fire("PLAYER_FLAGS_CHANGED", "player")
    h:Advance(29 * 60)
    falsy(Showing(h))
    h:Advance(60)
    truthy(Showing(h), "play time counts again")
end)

test("the play clock writes nothing while it runs, and runs no timer while a riddle waits or you're AFK", function()
    local h, addon = LoadKid()
    local scholar = addon.Modules.Scholar
    local version = addon.State:Version("Scholar.elapsed")
    h:Advance(10 * 60)
    eq(addon.State:Version("Scholar.elapsed"), version, "playing writes nothing")
    h:Slash("/tlk scholar")
    truthy(h.printed[#h.printed]:find("Next riddle in about 20 min", 1, true), h.printed[#h.printed])
    h.player.afk = true
    h:Fire("PLAYER_FLAGS_CHANGED", "player")
    eq(addon.State:Get("Scholar.elapsed"), 600, "going AFK saves the play so far")
    eq(scholar:PendingTimers(), 0, "no clock runs while AFK")
    h.player.afk = false
    h:Fire("PLAYER_FLAGS_CHANGED", "player")
    h:Slash("/tlk puzzle")
    truthy(Showing(h))
    eq(scholar:PendingTimers(), 0, "nor while a riddle waits")
end)

test("play before a relog counts toward the next riddle", function()
    local h = LoadKid()
    h:Advance(20 * 60)
    h:Relog(60)
    h:Advance(9 * 60)
    falsy(Showing(h))
    h:Advance(61)
    truthy(Showing(h), "20 minutes before and 10 after")
end)

test("with both subjects off, no riddle comes due and the timer holds", function()
    local h, addon = LoadKid({ ["Scholar.math"] = false, ["Scholar.reading"] = false })
    h:Advance(3 * 3600)
    falsy(Showing(h))
    eq(addon.State:Get("Scholar.elapsed"), 0, "no time piles up")
    eq(addon.State:Get("Scholar.pending"), false)
    addon.State:Set("Scholar.math", true)
    h:Advance(31 * 60)
    truthy(Showing(h), "a riddle comes after an interval of play with a subject on")
end)

test("a /reload during the celebration doesn't ask another riddle", function()
    local h, addon = LoadKid({ ["Scholar.pending"] = true })
    for key = 1, 4 do
        h:Key(tostring(key), true)
    end
    truthy(Showing(h), "the celebration is still on screen")
    eq(h.env.TheLanKrewToolKitCharDB["Scholar.pending"], nil, "the riddle is no longer due in the saved variables")
    h:Reload()
    falsy(Showing(h))
    eq(h.ns.Addon.State:Get("Scholar.stars"), 1)
end)

test("a fight during the celebration sends it away for good", function()
    local h, addon = LoadKid({ ["Scholar.pending"] = true })
    for key = 1, 4 do
        h:Key(tostring(key), true)
    end
    h:EnterCombat()
    falsy(Showing(h), "steps aside")
    h:LeaveCombat()
    falsy(Showing(h), "the solved riddle doesn't come back")
    h:Advance(2)
    falsy(Showing(h))
    eq(addon.State:Get("Scholar.stars"), 1)
end)

test("stars reach the Krew", function()
    local h, addon = LoadKid({ ["Scholar.pending"] = true })
    h:JoinGroup("party", { "Mom" })
    for key = 1, 4 do
        h:Key(tostring(key), true)
    end
    h:Advance(3)
    local shared = false
    for _, message in ipairs(h.addonMessages) do
        if message.message == "SCHOLAR:1" then shared = true end
    end
    truthy(shared)
end)

local Shares = {
    subject = "math", kind = "math.divide", title = "Fair Shares",
    prompt = "20 carrots are shared equally by 4 hunters. How many carrots does each hunter get?",
    choices = { "9", "6", "5", "4" }, answer = 3, hint = "Think: 4 times what number makes 20?",
    explanation = "20 / 4 = 5.",
}

local function Screen()
    local h = Harness.New()
    local ns = h:LoadAddon("TheLanKrewToolKit")
    local view = ns.ScholarView
    view.Show(Shares, { stars = 2, rank = "Apprentice", nextRank = "Journeyman", nextAt = 10, progress = 0.2, streak = 2,
        gentle = false, canSpeak = true, keys = { "1", "2", "3", "4" } })
    return h, view, view.Frame()
end

local function Text(fontString)
    return Reveal(Harness.State(fontString).text)
end

test("each answer's key sits in its own keycap, apart from the answer", function()
    local h, view, frame = Screen()
    eq(Text(frame.Buttons[1].Key), "1")
    eq(Text(frame.Buttons[1].Text), "9", "the answer alone: never \"1 9\"")
    eq(Text(frame.Buttons[4].Key), "4")
    eq(Text(frame.Buttons[4].Text), "4")
end)

test("the question stands apart from the story, with its numbers highlighted", function()
    local h, view, frame = Screen()
    eq(Text(frame.Story), "|cffffd10020|r carrots are shared equally by |cffffd1004|r hunters.")
    eq(Text(frame.Question), "How many carrots does each hunter get?")
    truthy(Text(frame.Tag):find("MATH", 1, true))
    truthy(Text(frame.Tag):find("Fair Shares", 1, true))
    eq(Text(frame.Asks), "The Owl Sage asks...")
end)

test("a question alone has no story line", function()
    local h, view = Screen()
    eq(select(1, view.Split("Which word rhymes with \"cat\"?")), "")
    eq(select(2, view.Split("The Owl Sage has a rhyme game!\nWhich word rhymes with \"cat\"?")), "Which word rhymes with \"cat\"?")
    eq(select(2, view.Split("Spell the word you hear.")), "Spell the word you hear.")
end)

test("highlighting keeps full stops and never colors its own color codes", function()
    local h, view = Screen()
    eq(view.Emphasize("It costs 3.5 gold."), "It costs |cffffd1003.5|r gold.")
    eq(view.Emphasize("25% of 1,000"), "|cffffd10025%|r of |cffffd1001,000|r")
    eq(view.Emphasize("Which word rhymes with \"cat\"?"), "Which word rhymes with |cff7fe0ff\"cat\"|r?")
end)

test("right and wrong answers look different, and the hint says so", function()
    local h, view, frame = Screen()
    view.Wrong(1, Shares.hint, false)
    falsy(frame.Buttons[1]:IsEnabled())
    truthy(Text(frame.Feedback.Text):find("Hint:", 1, true))
    eq(frame.Buttons[1].State, "wrong")
    view.Correct(3, Shares.explanation, { stars = 3, rank = "Apprentice", nextRank = "Journeyman", nextAt = 10, progress = 0.3,
        streak = 3, earned = 1, levelUp = true })
    truthy(Text(frame.Feedback.Text):find("Correct!", 1, true))
    eq(frame.Buttons[3].State, "right")
    eq(frame.Buttons[2].State, "dim")
end)

test("long answers get a smaller font than short ones", function()
    local h, view, frame = Screen()
    local short = Harness.State(frame.Buttons[1].Text).fontObject
    view.Show({ subject = "reading", kind = "reading.vocab", title = "Word Wizard", prompt = "What does \"brave\" mean?",
        choices = { "ready to face danger", "sleepy", "hungry", "tiny" }, answer = 1, hint = "", explanation = "" },
        { stars = 0, rank = "Apprentice", gentle = true, keys = { "1", "2", "3", "4" } })
    truthy(Harness.State(frame.Buttons[1].Text).fontObject ~= short)
    truthy(Text(frame.Tag):find("READING", 1, true))
end)

test("the header shows how close the next rank is, and the streak", function()
    local h, view, frame = Screen()
    eq(Text(frame.Stars), "2")
    truthy(Text(frame.Rank):find("8 more to Journeyman", 1, true), Text(frame.Rank))
    eq(Harness.State(frame.Progress).value, 0.2)
    eq(Text(frame.Streak), "2 in a row")
end)

test("a right answer raises a +1 and the streak says the riddles got harder", function()
    local h, view, frame = Screen()
    view.Correct(3, Shares.explanation, { stars = 3, rank = "Apprentice", nextRank = "Journeyman", nextAt = 10, progress = 0.3,
        streak = 3, earned = 1, levelUp = true })
    eq(Text(frame.Gain), "+1")
    truthy(frame.Rise:IsPlaying())
    eq(Text(frame.Stars), "3")
    truthy(Text(frame.Streak):find("harder riddles", 1, true))
    for _, button in ipairs(frame.Buttons) do
        falsy(button:IsEnabled(), "no more answers after the right one")
    end
end)

test("a wrong answer shakes", function()
    local h, view, frame = Screen()
    view.Wrong(2, Shares.hint, false)
    truthy(frame.Buttons[2].Shake:IsPlaying())
end)

test("the hint button shows the hint in the footer's place", function()
    local h, view, frame = Screen()
    falsy(frame.Feedback:IsShown())
    truthy(frame.Hint:IsShown())
    view.Hint(Shares.hint)
    truthy(frame.Feedback:IsShown())
    falsy(frame.Hint:IsShown(), "the banner takes the footer's place")
    truthy(Text(frame.Feedback.Text):find("times what number makes", 1, true))
end)

test("the Owl Sage's portrait is cropped to a circle", function()
    local h, view, frame = Screen()
    eq(frame.Portrait:GetNumMaskTextures(), 1)
end)

test("a groups riddle is drawn as bags of items", function()
    local h, view, frame = Screen()
    view.Show({ subject = "math", kind = "math.groups", title = "Stacks and Stacks",
        prompt = "Pip the gnome fills 5 bags with 6 apples in each bag. How many apples is that?",
        choices = { "35", "29", "30", "25" }, answer = 3, hint = "", explanation = "",
        picture = { kind = "groups", groups = 5, each = 6, item = "apple" } },
        { stars = 3, rank = "Apprentice", keys = { "1", "2", "3", "4" } })
    local shown = 0
    for _, icon in ipairs(frame.Pictures.Icons) do
        if icon:IsShown() then
            shown = shown + 1
            truthy(Harness.State(icon).texture:find("INV_Misc_Food_19", 1, true), "apples look like apples")
        end
    end
    eq(shown, 30)
    local bags = 0
    for _, card in ipairs(frame.Pictures.Cards) do
        if card:IsShown() then bags = bags + 1 end
    end
    eq(bags, 5)
    view.Show(Shares, { stars = 3, rank = "Apprentice", keys = { "1", "2", "3", "4" } })
    falsy(frame.Pictures:IsShown(), "no picture, no picture area")
end)

test("a picture draws the riddle's own item, whatever words its story uses", function()
    local h, view, frame = Screen()
    local function Textures()
        local seen = {}
        for _, icon in ipairs(frame.Pictures.Icons) do
            if icon:IsShown() then seen[Harness.State(icon).texture] = true end
        end
        local list = {}
        for texture in pairs(seen) do list[#list + 1] = texture end
        return table.concat(list, ",")
    end
    local riddle = { subject = "math", kind = "math.add", title = "Add Them Up",
        prompt = "In Barrow Den, Pip picks 3 mushrooms. Then Pip picks 2 more. How many mushrooms is that?",
        choices = { "5", "6", "4", "7" }, answer = 1, hint = "", explanation = "",
        picture = { kind = "join", a = 3, b = 2, item = "mushroom" } }
    view.Show(riddle, { stars = 3, rank = "Apprentice", keys = { "1", "2", "3", "4" } })
    eq(Textures(), "Interface\\Icons\\INV_Mushroom_11", "mushrooms, never arrows from \"Barrow\"")
    riddle.picture.item = "cookie"
    view.Show(riddle, { stars = 3, rank = "Apprentice", keys = { "1", "2", "3", "4" } })
    eq(Textures(), "Interface\\TargetingFrame\\UI-RaidTargetingIcon_1", "an item without an icon is a star")
end)

test("taking away crosses out the ones taken", function()
    local h, view, frame = Screen()
    view.Show({ subject = "math", kind = "math.subtract", title = "Take Away",
        prompt = "A basket holds 7 apples. A grumpy murloc grabs 3 and waddles away. How many apples are left?",
        choices = { "4", "5", "3", "10" }, answer = 1, hint = "", explanation = "",
        picture = { kind = "take", a = 7, b = 3 } },
        { stars = 3, rank = "Apprentice", keys = { "1", "2", "3", "4" } })
    local crossed = 0
    for _, icon in ipairs(frame.Pictures.Icons) do
        if icon:IsShown() and icon.Cross:IsShown() then crossed = crossed + 1 end
    end
    eq(crossed, 3)
end)

test("Read aloud speaks the riddle and its choices with the player's voice settings", function()
    local h, addon = LoadKid({ ["Scholar.pending"] = true })
    local frame = Overlay(h)
    h:Click(frame.Speak)
    local spoken = h.spoken[#h.spoken]
    truthy(spoken, "something was spoken")
    truthy(spoken.text:find(" Is it ", 1, true), spoken.text)
end)

test("the hint button costs nothing: the streak survives", function()
    local h, addon = LoadKid({ ["Scholar.pending"] = true, ["Scholar.streak"] = 2 })
    h:Click(Overlay(h).Hint)
    eq(addon.State:Get("Scholar.streak"), 2)
    truthy(Overlay(h).Feedback:IsShown())
end)

local function PadKid(extra)
    local char = { ["Scholar.enabled"] = true, ["Scholar.pending"] = true }
    for key, value in pairs(extra or {}) do char[key] = value end
    local h = Harness.New({ saved = { TheLanKrewToolKitCharDB = char } })
    h.labelStyle = "Letters"
    h:SeedRandom(7)
    local ns = h:LoadAddon("TheLanKrewToolKit")
    return h, ns.Addon
end

local function Press(h, key)
    h:Gamepad(key, true)
    h:Gamepad(key, false)
end

test("with a controller, every button names its controller button", function()
    local h = PadKid()
    local frame = Overlay(h)
    eq(Text(frame.Buttons[1].Key), "A")
    eq(Text(frame.Buttons[4].Key), "Y")
    truthy(Text(frame.Hint.Label):find("LB", 1, true), Text(frame.Hint.Label))
    truthy(Text(frame.Speak.Label):find("RB", 1, true), Text(frame.Speak.Label))
    eq(Text(frame.Buttons[2].Key), "B")
end)

test("the left shoulder asks for the hint and the right shoulder reads aloud", function()
    local h = PadKid()
    local frame = Overlay(h)
    Press(h, "PADLSHOULDER")
    truthy(frame.Feedback:IsShown())
    truthy(Text(frame.Feedback.Text):find("Hint:", 1, true))
    local before = #h.spoken
    Press(h, "PADRSHOULDER")
    eq(#h.spoken, before + 1)
end)

test("Back skips in Gentle mode after a try, and never in gate mode", function()
    local h = PadKid({ ["Scholar.mode"] = "gentle" })
    local frame = Overlay(h)
    Press(h, "PADBACK")
    truthy(Showing(h), "no skip before a try")
    Press(h, "PAD1")
    eq(frame.Buttons[1].State, "wrong", "seed 7's riddle doesn't have A as its answer")
    Press(h, "PADBACK")
    falsy(Showing(h), "skipped after a wrong try")
    local gate = PadKid({ ["Scholar.mode"] = "gate" })
    Press(gate, "PADBACK")
    truthy(Showing(gate), "gate mode has no skip")
end)

test("on a keyboard, H asks for the hint and R reads aloud", function()
    local h = LoadKid({ ["Scholar.pending"] = true })
    local frame = Overlay(h)
    truthy(Text(frame.Hint.Label):find("H", 1, true))
    h:Key("H", true)
    truthy(frame.Feedback:IsShown())
    local before = #h.spoken
    h:Key("R", true)
    eq(#h.spoken, before + 1)
end)

local function Point(region)
    local point, relativeTo, relativePoint, x, y = region:GetPoint(1)
    return { point = point, relativeTo = relativeTo, relativePoint = relativePoint, x = x, y = y }
end

test("Read aloud and Skip live in the footer, never over the question", function()
    local h, view, frame = Screen()
    view.Show({ subject = "reading", kind = "reading.rhyme", title = "Rhyme Time", prompt = "Which word rhymes with \"cat\"?",
        choices = { "hat", "dog", "sun", "cup" }, answer = 1, hint = "", explanation = "" },
        { stars = 1, rank = "Apprentice", canSpeak = true, keys = { "1", "2", "3", "4" }, actions = { hint = "H", speak = "R", skip = "Esc" } })
    local speak, hint = Point(frame.Speak), Point(frame.Hint)
    eq(speak.point, "TOPRIGHT")
    eq(speak.y, hint.y, "Read aloud sits on the footer row with Need a hint?")
    truthy(speak.y < Point(frame.Buttons[3]).y, "below the answers")
end)

test("the feedback banner stops short of the footer's right-hand buttons", function()
    local h, view, frame = Screen()
    view.Wrong(1, Shares.hint, true)
    truthy(frame.Skip:IsShown())
    local banner = { frame.Feedback:GetPoint(2) }
    eq(banner[2], frame.Skip, "the banner ends at Skip, the leftmost right-hand button")
end)

test("an unscramble shows its letters as tiles, not in the question text", function()
    local h, view, frame = Screen()
    view.Show({ subject = "reading", kind = "reading.unscramble", title = "Scrambled Scroll",
        prompt = "A gnome mixed up the letters of a word!\nR O F E T S\nClue: Lots and lots of trees.\nWhich word is it?",
        tiles = { "R", "O", "F", "E", "T", "S" },
        choices = { "GRYPHON", "SILVER", "SWORD", "FOREST" }, answer = 4, hint = "Clue: Lots and lots of trees.", explanation = "" },
        { stars = 1, rank = "Apprentice", keys = { "1", "2", "3", "4" } })
    local letters = {}
    for _, tile in ipairs(frame.Pictures.Tiles) do
        if tile:IsShown() then letters[#letters + 1] = Text(tile.Letter) end
    end
    eq(table.concat(letters), "ROFETS")
    eq(Text(frame.Question), "Which word is it?")
    falsy(Text(frame.Story):find("R O F", 1, true), "the letters aren't repeated in the text")
    truthy(Text(frame.Clue):find("Clue: Lots and lots of trees.", 1, true), "the clue sits under the tiles")
    falsy(Text(frame.Story):find("Clue:", 1, true))
    view.Wrong(1, "Clue: Lots and lots of trees.", false)
    falsy(Text(frame.Feedback.Text):find("Clue:", 1, true), "no \"Hint: Clue:\"")
end)

test("a counting riddle draws its items instead of a row of symbols", function()
    local h, view, frame = Screen()
    view.Show({ subject = "math", kind = "math.count", title = "Count Them",
        prompt = "Count the stars:\n* * * *\nHow many stars are there?", picture = { kind = "count", n = 4, row = "* * * *" },
        choices = { "4", "5", "3", "6" }, answer = 1, hint = "", explanation = "" },
        { stars = 1, rank = "Apprentice", keys = { "1", "2", "3", "4" } })
    local shown = 0
    for _, icon in ipairs(frame.Pictures.Icons) do
        if icon:IsShown() then shown = shown + 1 end
    end
    eq(shown, 4)
    falsy(Text(frame.Story):find("*", 1, true))
end)

test("dimmed and wrong answers dim their keycaps too", function()
    local h, view, frame = Screen()
    local function Red(button)
        return Harness.State(button.Keycap).color[1]
    end
    local normal = Red(frame.Buttons[1])
    view.Wrong(1, Shares.hint, false)
    view.Correct(3, Shares.explanation, { stars = 3, rank = "Apprentice" })
    truthy(Red(frame.Buttons[1]) < normal, "the wrong answer's keycap dims")
    truthy(Red(frame.Buttons[2]) < normal, "a dimmed answer's keycap dims")
    eq(Red(frame.Buttons[3]), normal, "the right answer's keycap stays bright")
end)
