-- The quest book on Scholar's riddle screen (ScholarView.lua): it opens below the riddle's story, as a page that
-- scrolls, and the panel fits the screen at any size and UI scale, with feedback that fits its row.

local Kit = use("scholar")
local Accept = Kit.Accept
local LoadKid = Kit.LoadKid
local Watch = Kit.Watch

local Wolves = {
    goal = "Bring 8 Tough Wolf Meat to Eagan Peltskinner.", header = "Elwynn Forest", id = 33,
    objectives = { { required = 8, text = "Tough Wolf Meat" } },
    text = ("The wolves of Elwynn grow bolder every night. Yesterday they carried off a sheep from the Stonefield farm. "
        .. "Bring me their meat, and the farmers will sleep easier."),
    title = "Wolves Across the Border",
}

test("the quest book opens below the riddle with the quest's text, and closes the same way", function()
    local h, _, ns = LoadKid()

    Watch(ns)
    Accept(h, Wolves)
    h:Slash("/tlk puzzle")
    local overlay = rawget(h.env, "TheLanKrewToolKitScholar")

    truthy(Reveal(Harness.State(overlay.Hint.Label).text):find("Quest book", 1, true), "the hint is the book")
    h:Key("H", true)
    truthy(ns.ScholarView.BookOpen())
    truthy(Reveal(Harness.State(overlay.BookText).text):find("Stonefield", 1, true), "the quest's text")
    truthy(overlay.Book:IsShown())
    h:Key("H", true)
    falsy(ns.ScholarView.BookOpen())
end)

test("a quest book too long for the screen scrolls, by wheel, arrow keys and D-pad, and the riddle fits", function()
    local h, _, ns = LoadKid()

    -- A controller is connected.
    h.labelStyle = "Letters"
    -- A short screen: the harness's 14 px lines are shorter than the real font's.
    h.env.UIParent:SetSize(1366, 600)

    local paragraph = ("Greetings, rogue. I can see you've got the look of an adventurer about you. This is good. "
        .. "The world needs more of us restless souls, seeking fortune and glory. ")

    local long = {
        goal = "Sit near Eleanor's Basic Campfire and wait until you receive the Boosted Rest buff.",
        header = "Tirisfal Glades", id = 34,
        objectives = { { required = 1, text = "Sit near the campfire", type = "log" }, { required = 1, text = "Gain the Boosted Rest buff", type = "log" } },
        text = (paragraph:rep(20) .. "Have a seat near the fire and get comfortable."), title = "The Great Outdoors",
    }

    Accept(h, long, "Eleanor Shackleton")
    h:Slash("/tlk puzzle")
    local overlay = rawget(h.env, "TheLanKrewToolKitScholar")
    local book = overlay.Book
    local screen = h.env.UIParent:GetHeight()

    local function Fits(what)
        truthy(overlay.Panel:GetHeight() <= (screen - 40), ("%s: the panel (%d) fits the screen (%d)"):format(what,
            overlay.Panel:GetHeight(), screen))
    end

    Fits("the riddle")
    falsy(book:IsShown(), "the book waits to be opened")
    local hadStory = overlay.Story:IsShown()

    h:Key("H", true)
    truthy(ns.ScholarView.BookOpen())
    truthy(book:IsShown(), "the book opens")
    eq(overlay.Story:IsShown(), hadStory, "and the riddle's story stays as it was, above it")
    Fits("the open book")
    local text = Reveal(Harness.State(overlay.BookText).text)

    truthy(text:find("Eleanor Shackleton", 1, true) and text:find("get comfortable.", 1, true), "the whole quest, scrolled")
    truthy(Reveal(Harness.State(overlay.Hint.Label).text):find("Close book", 1, true), "the button closes it")
    local range = book:GetVerticalScrollRange()

    truthy(range > 0, "more text than room")
    eq(book:GetVerticalScroll(), 0, "it opens at the top")

    local function Offset() return book:GetVerticalScroll() end

    truthy(h:MouseWheel(book, -1), "the book takes the wheel")
    local step = Offset()

    truthy(step > 0, "the wheel scrolls down")
    h:MouseWheel(book, 1)
    eq(Offset(), 0, "and back up")
    h:MouseWheel(book, 1)
    eq(Offset(), 0, "never above the top")
    h:Key("DOWN", true)
    eq(Offset(), step, "the Down arrow scrolls like a notch")
    h:Key("UP", true)
    eq(Offset(), 0)
    h:Gamepad("PADDDOWN", true)
    h:Gamepad("PADDDOWN", false)
    eq(Offset(), step, "a D-pad press scrolls a notch")
    h:Gamepad("PADDDOWN", true)
    h:Advance(1)
    truthy(Offset() > (2 * step), "held, it keeps scrolling")
    h:Gamepad("PADDDOWN", false)
    local held = Offset()

    h:Advance(1)
    eq(Offset(), held, "let go, it stops")

    for _ = 1, 100 do h:MouseWheel(book, -1) end

    eq(Offset(), range, "never below the end")
    h:Key("H", true)
    falsy(ns.ScholarView.BookOpen())
    falsy(book:IsShown(), "closed")
    eq(overlay.Story:IsShown(), hadStory, "the riddle is as it was")
    Fits("the riddle again")
    h:Key("H", true)
    eq(Offset(), 0, "opened again, it starts at the top")
end)

test("on a tall screen the quest book is a page of at most BookHeight, scrolling the rest, not the screen's height", function()
    local h = LoadKid()

    -- A tall screen at UI scale 1: far more room than the book needs.
    h.env.UIParent:SetSize(2560, 1440)

    Accept(h, { goal = "Read it all.", header = "Tirisfal Glades", id = 36, objectives = {},
        text = ("The Scourge gathers in the north, and the Magistrate needs every agent he can find. "):rep(30), title = "Every Word" })

    h:Slash("/tlk puzzle")
    local overlay = rawget(h.env, "TheLanKrewToolKitScholar")
    local closed = overlay.Panel:GetHeight()

    h:Key("H", true)
    eq(overlay.Book:GetHeight(), 240, "a page's worth in view")
    truthy(overlay.BookCase:IsShown() and overlay.Book:IsShown(), "the book opens on its page")
    truthy(overlay.Book:GetVerticalScrollRange() > 0, "and the rest scrolls")

    truthy(overlay.Panel:GetHeight() < (closed + 300), ("the panel grows by about a page, not the screen: %d, then %d")
        :format(closed, overlay.Panel:GetHeight()))
end)

test("with a UI scale below 1, the open book still fits the screen: the riddle doesn't take the UI scale", function()
    local h, _, ns = LoadKid()

    -- UI scale 0.7: UIParent is 600 / 0.7 of its own units tall, and the riddle, which has no parent, 600 of its own.
    h.env.UIParent:SetScale(0.7)
    h.env.UIParent:SetSize(1366 / 0.7, 600 / 0.7)

    Accept(h, { goal = "Read it all.", header = "Tirisfal Glades", id = 37, objectives = {},
        text = ("Bethor Iceshard, a high-ranking and powerful mage in the Undercity, sends word. "):rep(30),
        title = "The Prodigal Lich" })

    h:Slash("/tlk puzzle")
    local overlay = rawget(h.env, "TheLanKrewToolKitScholar")

    h:Key("H", true)
    truthy(ns.ScholarView.BookOpen())

    truthy(overlay.Panel:GetHeight() <= (600 - 40), ("the panel (%d) fits the screen as the riddle measures it (%d)")
        :format(overlay.Panel:GetHeight(), 600 - 40))
end)

test("feedback too long for its row grows the footer down to fit, and the panel with it", function()
    local h, _, ns = LoadKid()
    local shown = Watch(ns)

    Accept(h, Wolves)
    h:Slash("/tlk puzzle")
    local overlay = rawget(h.env, "TheLanKrewToolKitScholar")
    local before = overlay.Panel:GetHeight()

    ns.ScholarView.Wrong(Kit.WrongAnswer(shown[1]), ('"details" is in the quest, but in another sentence. '):rep(3),
        "Hint", "Open the quest book and find that sentence.", false)

    local banner = overlay.Feedback
    local text = banner.Text:GetStringHeight()

    truthy(text > 44, "the message takes more than one row: " .. text)
    eq(banner:GetHeight(), text + 20, "the banner fits it")
    eq(overlay.Panel:GetHeight(), (before + (text + 20)) - 44, "and the panel grows by what the footer did")
end)

-- A quest riddle with a story above its question, and a book long enough to scroll.
local function BookRiddle(h, ns)
    local giver = "Magistrate Sevren"

    local book = ('"The Prodigal Lich"\nFrom ' .. giver .. ", in Brill Town Hall.\n\n"
        .. ("Bethor Iceshard, a high-ranking and powerful mage in the Undercity, sends word. "):rep(30))

    ns.ScholarView.Show({
        answer = 4, book = book, choices = { "The Cult of the Damned", "Delivery to Silverpine Forest",
            "Whispering Horror Residue", "The Prodigal Lich" },
        explanation = "The name at the top of the quest book is \"The Prodigal Lich\".", hint = "Open the quest book.",
        kind = "quest.title", prompt = (giver .. " gave you a quest. Which one?"), subject = "quest",
        title = "Quest Log Quiz",
    }, { actions = {}, book = true, keys = { "1", "2", "3", "4" }, rank = "Adept", stars = 25 })

    ns.ScholarView.ToggleBook()

    return rawget(h.env, "TheLanKrewToolKitScholar")
end

test("the riddle's story stays above the open book, so the question still says what to pick", function()
    local h, _, ns = LoadKid()
    local overlay = BookRiddle(h, ns)

    truthy(overlay.Book:IsShown(), "the book is open")
    truthy(overlay.Story:IsShown(), "and the story is still there")
    truthy(Reveal(Harness.State(overlay.Story).text):find("Magistrate Sevren gave you a quest.", 1, true))

    truthy(select(5, overlay.Story:GetPoint(1)) > select(5, overlay.BookCase:GetPoint(1)), "the story is above the book")
end)

test("long feedback with the book open shrinks the book, so the panel still fits the screen", function()
    local h, _, ns = LoadKid()

    h.env.UIParent:SetSize(1366, 600)
    local overlay = BookRiddle(h, ns)
    local before = overlay.Book:GetHeight()

    for i = 1, 3 do
        ns.ScholarView.Wrong(i, ('"Choice" is a different quest in your quest book. '):rep(3), "Here's how",
            "The name at the top of the quest book is the answer, and it says who it's from.", false, ((i == 3) and 4) or nil)
    end

    truthy(overlay.Panel:GetHeight() <= (600 - 40), ("the panel (%d) fits the screen (%d)"):format(overlay.Panel:GetHeight(), 560))
    truthy(overlay.Book:GetHeight() < before, "the book gave up the room")
    eq(overlay.Book:GetVerticalScroll() <= overlay.Book:GetVerticalScrollRange(), true, "and its scroll stays in range")
end)
