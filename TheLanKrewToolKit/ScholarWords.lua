local addonName, ns = ...

-- Word banks and flavor text for the Scholar puzzles, as ns.ScholarWords: the puzzle files (ScholarPuzzles.lua and its
-- generators) read it; this file only holds data. Everything is original, kid-friendly plain ASCII. The reading
-- riddles' text and banks are ns.ScholarReadingWords (ScholarReadingWords.lua) and ns.ScholarStoryWords
-- (ScholarStoryWords.lua), and the math riddles' are ns.ScholarMathWords (ScholarMathWords.lua); their kinds and titles
-- are here.
--
-- Word problems use {hero} and {place}; the stock ones below fill in when the player's context doesn't. Quest riddles
-- (ScholarQuests.lua) ask about the player's own quests, in the words below; their banks are wrong answers to mix in
-- when the player's own quests don't give three.

-- order: grouped by subject and grade, beside the words each group's puzzles read
ns.ScholarWords = {
    -- The kinds whose riddle is heard, not read: Scholar asks them only while the client has a text-to-speech voice.
    heard = { ["reading.listen"] = true, ["reading.listenSound"] = true, ["reading.listenStory"] = true },
    -- The kinds built from the player's own quests: Scholar asks them only while the quest book holds one.
    fromQuests = { ["math.quest"] = true },
    -- Puzzle kinds per subject and grade. A kind is listed from the grade it fits and a grade below it: its steps and
    -- worked explanations make it approachable early.
    kinds = {
        math = {
            [0] = {
                "math.count", "math.add", "math.subtract", "math.compare", "math.placeValue", "math.time", "math.numberLine",
                "math.quest",
            },
            { "math.add", "math.subtract", "math.missing", "math.placeValue", "math.time", "math.numberLine", "math.quest" },
            {
                "math.add", "math.subtract", "math.skip", "math.coins", "math.placeValue", "math.time", "math.numberLine",
                "math.quest",
            },
            { "math.multiply", "math.divide", "math.groups", "math.placeValue", "math.time", "math.numberLine", "math.quest" },
            { "math.multiply", "math.remainder", "math.money", "math.placeValue", "math.numberLine", "math.quest" },
            { "math.fraction", "math.multistep", "math.decimal", "math.quest" },
            { "math.percent", "math.ratio", "math.order", "math.quest" },
        },
        reading = {
            [0] = {
                "reading.rhyme", "reading.sound", "reading.sight", "reading.cvc", "reading.digraph", "reading.listen",
                "reading.listenSound", "reading.listenStory",
            },
            {
                "reading.rhyme", "reading.sound", "reading.sight", "reading.cvc", "reading.digraph", "reading.blend",
                "reading.listen", "reading.listenSound", "reading.listenStory",
            },
            {
                "reading.unscramble", "reading.synonym", "reading.antonym", "reading.spelling", "reading.digraph",
                "reading.blend", "reading.story",
            },
            { "reading.unscramble", "reading.synonym", "reading.antonym", "reading.spelling", "reading.story" },
            { "reading.vocab", "reading.blank", "reading.story" },
            { "reading.vocab", "reading.blank", "reading.story" },
            { "reading.vocab", "reading.blank", "reading.story" },
        },
    },
    -- Each hero is { first mention, later mentions }.
    heroes = {
        { "Pip the gnome", "Pip" }, { "Brom the dwarf", "Brom" }, { "Mira the night elf", "Mira" },
        { "Tavi the tauren", "Tavi" }, { "Zix the goblin", "Zix" }, { "Elly the paladin", "Elly" },
        { "Gruk the orc", "Gruk" }, { "Wren the hunter", "Wren" },
    },
    places = {
        "Goldshire", "Stormwind", "Ironforge", "Orgrimmar", "Thunder Bluff", "Darnassus", "the Barrens",
        "Elwynn Forest", "Westfall", "Booty Bay", "Loch Modan", "Mulgore", "Durotar", "Teldrassil",
    },
    -- Each item is { one, many }.
    items = {
        adventure = {
            { "potion", "potions" }, { "arrow", "arrows" }, { "candle", "candles" }, { "scroll", "scrolls" },
            { "gear", "gears" }, { "mushroom", "mushrooms" }, { "feather", "feathers" }, { "seashell", "seashells" },
            { "apple", "apples" }, { "gem", "gems" }, { "carrot", "carrots" }, { "pie", "pies" },
        },
        small = {
            { "apple", "apples" }, { "fish", "fish" }, { "egg", "eggs" }, { "frog", "frogs" },
            { "gem", "gems" }, { "acorn", "acorns" }, { "carrot", "carrots" }, { "cookie", "cookies" },
        },
    },
    classNouns = {
        DRUID = "druid", HUNTER = "hunter", MAGE = "mage", PALADIN = "paladin", PRIEST = "priest", ROGUE = "rogue",
        SHAMAN = "shaman", WARLOCK = "warlock", WARRIOR = "warrior",
    },
    classItems = {
        DRUID = { "acorn", "acorns" }, HUNTER = { "arrow", "arrows" }, MAGE = { "magic muffin", "magic muffins" },
        PALADIN = { "hammer", "hammers" }, PRIEST = { "bandage", "bandages" }, ROGUE = { "lockpick", "lockpicks" },
        SHAMAN = { "totem", "totems" }, WARLOCK = { "candle", "candles" }, WARRIOR = { "shield", "shields" },
    },

    -- Praise for a first-try right on a kind with no praise of its own: it names the careful work, never the child.
    praise = {
        "You read it carefully and worked it out.", "Step by step, that's how scholars do it.",
        "You checked it, and it was right.", "Careful thinking found that one.", "You took your time, and it paid off.",
        "That's solid work, hero.",
    },
    -- Praise for a right answer after a miss: it names the not giving up.
    persistence = {
        "You kept trying and found it.", "A miss, then the answer: that's how heroes learn.",
        "You stuck with it, and now you know it.", "Mistakes teach, and you learned from yours.",
        "You didn't give up. The Owl Sage noticed.",
    },
    hintFallback = "Take a slow breath and try once more. Heroes learn step by step!",
    titles = {
        ["math.count"] = { "Counting with the Owl Sage", "How Many Can You Spot?", "Count Them Up!" },
        ["math.add"] = { "Loot Pile Math", "Adding Adventure", "More Treasure!" },
        ["math.subtract"] = { "Take-Away Time", "How Many Are Left?", "The Owl Sage Subtracts" },
        ["math.compare"] = { "Which Is Biggest?", "Number Showdown", "The Owl Sage Compares" },
        ["math.missing"] = { "The Missing Number", "Fill the Gap!", "A Number Went Hiding" },
        ["math.skip"] = { "Skip Counting Hop", "Follow the Pattern", "What Comes Next?" },
        ["math.coins"] = { "Copper Counting", "Coin Purse Puzzle", "Shopkeeper Sums" },
        ["math.multiply"] = { "Times Table Trial", "Multiply Magic", "The Owl Sage Multiplies" },
        ["math.divide"] = { "Fair Shares", "Divide the Loot", "Sharing Is Caring" },
        ["math.groups"] = { "Groups of Goodies", "Count the Bundles", "Stacks and Stacks" },
        ["math.remainder"] = { "Leftover Loot", "Packing Puzzle", "What's Left Over?" },
        ["math.money"] = { "Silver and Copper", "The Merchant's Math", "Coin Purse Challenge" },
        ["math.fraction"] = { "Fraction Feast", "Slice of the Loot", "A Piece of the Pile" },
        ["math.multistep"] = { "A Two-Step Quest", "The Quartermaster's Question", "Think in Steps!" },
        ["math.decimal"] = { "Decimal Discovery", "Tenths Trek", "Decimal Dash" },
        ["math.percent"] = { "Percent Puzzle", "Out of a Hundred", "The Owl Sage's Percents" },
        ["math.ratio"] = { "Recipe Ratios", "For Every One...", "Perfect Proportions" },
        ["math.order"] = { "The Order of Operations", "Solve in Order!", "The Owl Sage's Rules" },
        ["math.placeValue"] = { "What's It Worth?", "Tens and Ones", "The Place Value Vault" },
        ["math.time"] = { "Tick Tock, Hero!", "What Time Is It?", "The Owl Sage's Clock" },
        ["math.numberLine"] = { "The Number Line", "Near or Far?", "Find the Spot" },
        ["math.quest"] = { "Quest Log Math", "Counting for Your Quest", "The Quest Giver's Sums" },
        ["reading.rhyme"] = { "Rhyme Time!", "The Owl Sage's Rhyme Game", "Hoot and Rhyme" },
        ["reading.sound"] = { "Sound Detective", "First Sound Fun", "Listen Closely!" },
        ["reading.sight"] = { "Word Watcher", "Words by Heart", "The Word Scroll" },
        ["reading.cvc"] = { "Sound It Out", "Word Builder", "Letter Magic" },
        ["reading.listen"] = { "Listen Closely!", "The Owl Sage Whispers", "Ears of a Hero" },
        ["reading.listenSound"] = { "First Sound Hunt", "Listen for the Letter", "Owl Ears" },
        ["reading.listenStory"] = { "Story Time, Ears Open!", "The Owl Sage Tells a Tale", "Listen to the Story" },
        ["reading.digraph"] = { "Letter Teams", "Two Letters, One Sound", "Sound Partners" },
        ["reading.blend"] = { "Blend It Together", "Sound Slide", "The Blend Builder" },
        ["reading.unscramble"] = { "Scrambled Scroll", "A Gnome Mixed Up the Letters!", "Unscramble It!" },
        ["reading.synonym"] = { "Word Twins", "Meaning Match", "Same-Same Words" },
        ["reading.antonym"] = { "Opposite Day", "Flip It Around", "Opposites Attract" },
        ["reading.spelling"] = { "The Spelling Challenge", "Spot the Right Spelling", "The Scribe's Test" },
        ["reading.vocab"] = { "Word Wizard", "The Vocabulary Vault", "Words of Wisdom" },
        ["reading.blank"] = { "Fill the Blank", "The Missing Word", "Finish the Sentence" },
        ["reading.story"] = { "Story Time with the Owl Sage", "Tales of Azeroth", "A Riddle from the Owl Sage" },
        ["quest.giver"] = { "Who Sent You?", "Remember Your Quest", "The Quest Giver" },
        ["quest.ender"] = { "Mission Accomplished", "Who Was Waiting?", "Quest Complete!" },
        ["quest.place"] = { "Where It Began", "Remember the Road", "Map of Memories" },
        ["quest.endPlace"] = { "Journey's End", "Where You Finished", "Back to the Map" },
        ["quest.count"] = { "Count Your Quest", "How Many Again?", "Quest Arithmetic" },
        ["quest.objective"] = { "Your Orders", "What Was the Task?", "Read Your Quest" },
        ["quest.title"] = { "Name That Quest", "Quest Log Quiz", "Which Quest Was It?" },
        ["quest.blank"] = { "The Quest Text", "Every Word Counts", "Read It Closely" },
    },

    -- Quest riddle text. {title} is the quest's title, and the quest book holds every answer: a hint says where to look
    -- in it, a step walks to the line, and an explanation quotes it. A prompt names the quest by its title, or (bare)
    -- as the quest in the book when the title would give the answer away. A wrong choice says why: one from another of
    -- the player's quests by from (where it came from, {other}), this quest's own giver, taker or place asked the other
    -- way round by mixup, and any other by the kind's wrong.
    quest = {
        blank = {
            bare = "From the quest in your quest book:\n\"{sentence}\"\nWhich word is missing?",
            explain = "The quest book says: \"{filled}\"",
            hint = "Open the quest book and find that sentence.",
            other = "\"{choice}\" is in the quest, but in another sentence.",
            praise = "You found the sentence in the quest book.",
            prompt = "From the quest \"{title}\":\n\"{sentence}\"\nWhich word is missing?",
            step = "In the quest book, find \"{lead}\": the missing word is just {side} it.",
            wrong = "The quest book has another word just {side} \"{lead}\".",
        },
        -- Objectives by kind: an item to bring, a foe to defeat, or a task to do. A wrong count says which way the
        -- book's number is, or whose number it is when it's another objective's.
        count = {
            foe = {
                explain = "The quest book shows \"{objective} ({answer})\": it asked you to defeat {answer} {objective}.",
                hint = "Open the quest book: the Defeat line says how many.",
                praise = "You found the number in the quest book.",
                prompt = "The quest \"{title}\" asked you to defeat \"{objective}\". How many?",
                step = "Find {objective} on the quest book's Defeat line: the number after it is how many.",
            },
            item = {
                explain = "The quest book shows \"{objective} ({answer})\": it asked you to bring {answer} {objective}.",
                hint = "Open the quest book: the Bring line says how many.",
                praise = "You found the number in the quest book.",
                prompt = "The quest \"{title}\" asked you to bring \"{objective}\". How many?",
                step = "Find {objective} on the quest book's Bring line: the number after it is how many.",
            },
            task = {
                explain = "The quest book shows \"{objective} ({answer})\": it asked for {answer}.",
                hint = "Open the quest book: the Do line says how many.",
                praise = "You found the number in the quest book.",
                prompt = "The quest \"{title}\" asked for \"{objective}\". How many?",
                step = "Find {objective} on the quest book's Do line: the number after it is how many.",
            },
            whys = {
                fewer = "The quest book shows a bigger number after {objective}.",
                more = "The quest book shows a smaller number after {objective}.",
                other = "That's the number after {other}, not after {objective}.",
            },
        },
        ender = {
            bare = "You turned in the quest in your quest book. Who did you turn it in to?",
            explain = "The quest book's last line says you turned \"{title}\" in to {answer}.",
            hint = "Open the quest book: who did you talk to at the end?",
            mixup = "{choice} gave you this quest, but you turned it in to someone else.",
            praise = "You read the quest book right to its last line.",
            prompt = "Who did you turn in the quest \"{title}\" to?",
            step = "Find the quest book's line that starts \"Turned in to\": the name after it took the quest.",
            wrong = "The quest book doesn't say you turned it in to {choice}.",
        },
        endPlace = {
            bare = "Where did you turn in the quest in your quest book?",
            explain = "The quest book's last line says you turned \"{title}\" in at {answer}.",
            hint = "Open the quest book: where were you when you finished?",
            mixup = "{choice} is where this quest began, but you finished somewhere else.",
            praise = "You read the quest book right to its last line.",
            prompt = "Where did you turn in the quest \"{title}\"?",
            step = "Find the quest book's line that starts \"Turned in\": the place after \"at\" is where you finished.",
            wrong = "The quest book doesn't say you finished at {choice}.",
        },
        -- Why a choice from another of the player's quests is wrong, by the field it came from: {other} is that quest's
        -- title (its giver, for a title).
        from = {
            ender = "You turned in a different quest to {choice}: \"{other}\".",
            endPlace = "You turned in a different quest at {choice}: \"{other}\".",
            giver = "{choice} gave you a different quest: \"{other}\".",
            objective = "{choice} was for a different quest: \"{other}\".",
            place = "You took a different quest in {choice}: \"{other}\".",
            title = "\"{choice}\" is a quest from {other}.",
        },
        giver = {
            bare = "Who gave you the quest in your quest book?",
            explain = "Under its name, the quest book says \"From {answer}\": {answer} gave you \"{title}\".",
            hint = "Open the quest book: who did you talk to first?",
            mixup = "You turned this quest in to {choice}, but someone else gave it to you.",
            praise = "You checked the quest book for who sent you.",
            prompt = "Who gave you the quest \"{title}\"?",
            step = "Look just under the quest's name in the quest book: the name after \"From\" sent you.",
            wrong = "The quest book doesn't say it's from {choice}.",
        },
        objective = {
            foe = {
                bare = "Which enemy did the quest in your quest book ask you to defeat?",
                explain = "The quest book's Defeat line names {answer}: that's who \"{title}\" asked you to defeat.",
                hint = "Open the quest book: the Defeat line says who to defeat.",
                praise = "You read the quest's orders closely.",
                prompt = "Which enemy did the quest \"{title}\" ask you to defeat?",
                step = "Find the quest book's line that starts \"Defeat:\": the names after it are who to defeat.",
                wrong = "The quest book doesn't ask you to defeat {choice}.",
            },
            item = {
                bare = "What did the quest in your quest book ask you to bring?",
                explain = "The quest book's Bring line names {answer}: that's what \"{title}\" asked you to bring.",
                hint = "Open the quest book: the Bring line says what to bring.",
                praise = "You read the quest's orders closely.",
                prompt = "What did the quest \"{title}\" ask you to bring?",
                step = "Find the quest book's line that starts \"Bring:\": the things after it are what to bring.",
                wrong = "The quest book doesn't ask you to bring {choice}.",
            },
            task = {
                bare = "What did the quest in your quest book ask you to do?",
                explain = "The quest book's Do line says \"{answer}\": that's what \"{title}\" asked you to do.",
                hint = "Open the quest book: the Do line says what to do.",
                praise = "You read the quest's orders closely.",
                prompt = "What did the quest \"{title}\" ask you to do?",
                step = "Find the quest book's line that starts \"Do:\": what comes after it is what to do.",
                wrong = "The quest book doesn't ask you to do that.",
            },
        },
        place = {
            bare = "Where were you when you took the quest in your quest book?",
            explain = "Under its name, the quest book says you took \"{title}\" in {answer}.",
            hint = "Open the quest book: where were you when it began?",
            mixup = "You turned this quest in at {choice}, but it began somewhere else.",
            praise = "You found where it began in the quest book.",
            prompt = "Where were you when you took the quest \"{title}\"?",
            step = "Look just under the quest's name in the quest book: the place after \"in\" is where it began.",
            wrong = "The quest book doesn't say it began in {choice}.",
        },
        title = {
            explain = "The name at the top of the quest book is \"{answer}\", and it says it's from {giver}.",
            hint = "Open the quest book: its name is at the very top.",
            praise = "You matched the quest giver to the quest.",
            prompt = "{giver} gave you a quest. Which one?",
            step = "The quest book's first line, in quotation marks, is the quest's name.",
            wrong = "{giver} didn't give you \"{choice}\".",
        },
    },
    -- Wrong answers for quest riddles, by the player's faction (Alliance when it's unknown): the real givers, quests
    -- (each with its real giver, so one is never offered as another quest of the riddle's own giver), places (never a
    -- whole zone, which could be true of the right place too) and objectives of the lands a new character of that
    -- faction quests in. nameWords and placeWords are single words of those names and places: a capitalized word of a
    -- quest's text in one of them can be its missing word, with the others of its list as wrong answers.
    questBanks = {
        Alliance = {
            foes = {
                "Kobold Vermin", "Young Wolf", "Defias Thug", "Murloc Forager", "Mangy Wolf", "Kobold Worker",
                "Kobold Laborer", "Frostmane Troll Whelp",
            },
            -- Objectives of each kind: items to bring, foes to defeat, tasks.
            items = {
                "Tough Wolf Meat", "Kobold Candle", "Gold Dust", "Murloc Fin", "Linen Cloth", "Red Burlap Bandana",
                "Milly's Harvest", "Wolf Fang",
            },
            names = {
                "Marshal Dughan", "Deputy Willem", "Marshal McBride", "Brother Paxton", "Eagan Peltskinner",
                "Innkeeper Farley", "Farmer Saldean", "Gryan Stoutmantle", "Captain Grayson", "Guard Thomas",
            },
            nameWords = {
                "Dughan", "Willem", "McBride", "Paxton", "Eagan", "Peltskinner", "Farley", "Saldean", "Stoutmantle",
                "Grayson", "Thomas", "Billy", "Milly",
            },
            places = {
                "Northshire Abbey", "Goldshire", "Fargodeep Mine", "Jasperlode Mine", "Eastvale Logging Camp",
                "Kharanos", "Coldridge Valley", "Shadowglen", "Dolanaar", "Sentinel Hill",
            },
            placeWords = {
                "Elwynn", "Northshire", "Goldshire", "Stormwind", "Westfall", "Redridge", "Duskwood", "Fargodeep",
                "Jasperlode", "Eastvale", "Stonefield", "Ironforge", "Kharanos", "Coldridge", "Teldrassil", "Shadowglen",
                "Dolanaar", "Darnassus",
            },
            tasks = {
                "Report to Marshal Dughan", "Sit near the campfire", "Speak with the innkeeper", "Light the signal fire",
                "Search the old wagon", "Find the lost necklace",
            },
            titles = {
                { "Kobold Camp Cleanup", "Marshal McBride" }, { "Wolves Across the Border", "Eagan Peltskinner" },
                { "The Fargodeep Mine", "Marshal Dughan" }, { "Report to Goldshire", "Marshal McBride" },
                { "The Jasperlode Mine", "Marshal Dughan" }, { "A Threat Within", "Deputy Willem" },
                { "Lost Necklace", "Billy Maclure" }, { "Bounty on Murlocs", "Guard Thomas" },
            },
        },
        Horde = {
            foes = {
                "Mottled Boar", "Scorpid Worker", "Vile Familiar", "Adult Plainstrider", "Battleboar",
                "Rattlecage Soldier", "Mindless Zombie", "Scarlet Convert",
            },
            items = {
                "Scorpid Worker Tail", "Cactus Apple", "Plainstrider Meat", "Plainstrider Feather", "Duskbat Pelt",
                "Coarse Thread", "Doom Weed", "Embalming Ichor",
            },
            names = {
                "Gornek", "Kaltunk", "Hana'zua", "Zureetha Fargaze", "Foreman Thazz'ril", "Galgar", "Grull Hawkwind",
                "Greatmother Hawkwind", "Shadow Priest Sarvis", "Executor Arren", "Gretchen Dedmar", "Innkeeper Renee",
            },
            nameWords = {
                "Gornek", "Kaltunk", "Zureetha", "Fargaze", "Galgar", "Grull", "Hawkwind", "Sarvis", "Arren", "Gretchen",
                "Dedmar", "Renee",
            },
            places = {
                "Valley of Trials", "Razor Hill", "Sen'jin Village", "Burning Blade Coven", "Camp Narache",
                "Bloodhoof Village", "Red Cloud Mesa", "Deathknell", "Brill", "Night Web's Hollow",
            },
            placeWords = {
                "Durotar", "Orgrimmar", "Mulgore", "Tirisfal", "Barrens", "Undercity", "Deathknell", "Bloodhoof",
                "Narache", "Silverpine", "Kalimdor", "Brill",
            },
            tasks = {
                "Report to Gornek", "Sit near the campfire", "Speak with the innkeeper", "Light the signal fire",
                "Search the old wagon", "Wake the lazy peons",
            },
            titles = {
                { "Your Place In The World", "Kaltunk" }, { "Cutting Teeth", "Gornek" },
                { "Sting of the Scorpid", "Gornek" }, { "Sarkoth", "Hana'zua" }, { "Vile Familiars", "Zureetha Fargaze" },
                { "Lazy Peons", "Foreman Thazz'ril" }, { "Galgar's Cactus Apple Surprise", "Galgar" },
                { "The Hunt Begins", "Grull Hawkwind" }, { "A Humble Task", "Greatmother Hawkwind" },
                { "Rattling the Rattlecages", "Shadow Priest Sarvis" }, { "Night Web's Hollow", "Executor Arren" },
                { "The Chill of Death", "Gretchen Dedmar" },
            },
        },
    },
    -- Words too plain to blank out of a quest's text.
    stopWords = {
        about = true, after = true, again = true, anything = true, around = true, before = true, being = true,
        below = true, could = true, during = true, early = true, evening = true, every = true, everything = true,
        family = true, first = true, little = true, morning = true, never = true, nothing = true, other = true,
        should = true, since = true, something = true, their = true, there = true, these = true, thing = true,
        those = true, through = true, ["until"] = true, where = true, which = true, ["while"] = true, would = true,
        yourself = true,
    },
    -- How ScholarQuests.lua tells a missing word's kind, so its wrong answers are the same kind (a noun for a noun): a
    -- word right after a nounStarts word ("the ___") is a noun when punctuation or a nounEnds word follows it ("the ___
    -- will"), and otherwise describes the noun after it and isn't asked; one ending in -ed, -ing or -ly is that kind;
    -- and one ending in -er is a comparing word when it's a comparable word plus -er ("bold", "bolder"). kinds holds
    -- wrong answers of each kind, for when the quest's own text has too few.
    questWords = {
        comparable = {
            angry = true, big = true, bold = true, brave = true, bright = true, calm = true, clever = true,
            close = true, cold = true, dark = true, deep = true, easy = true, fast = true, fierce = true,
            great = true, happy = true, hard = true, heavy = true, high = true, hungry = true, kind = true,
            large = true, late = true, light = true, long = true, loud = true, low = true, mighty = true, near = true,
            old = true, quick = true, quiet = true, rich = true, safe = true, sharp = true, short = true, slow = true,
            small = true, smart = true, soft = true, strong = true, sweet = true, tall = true, thick = true,
            tough = true, warm = true, weak = true, wild = true, wise = true, young = true,
        },
        kinds = {
            ed = {
                "chased", "buried", "guarded", "wandered", "gathered", "followed", "burned", "climbed", "scared",
                "painted", "fixed", "dropped", "hunted", "rescued",
            },
            er = {
                "braver", "louder", "colder", "hungrier", "quieter", "stronger", "darker", "wiser", "faster",
                "calmer", "angrier", "fiercer", "taller", "warmer",
            },
            ing = {
                "running", "hiding", "singing", "digging", "waiting", "sleeping", "fishing", "climbing", "howling",
                "marching", "dancing", "shouting",
            },
            ly = {
                "quickly", "quietly", "slowly", "bravely", "gently", "loudly", "safely", "sadly", "softly",
                "proudly", "kindly", "boldly",
            },
            noun = {
                "river", "tower", "forest", "candle", "shield", "basket", "lantern", "meadow", "bridge", "cabin",
                "wagon", "cottage", "barrel", "hammer", "garden", "castle",
            },
            nouns = {
                "rivers", "towers", "candles", "shields", "baskets", "lanterns", "wagons", "barrels", "hunters",
                "miners", "traders", "soldiers", "gardens", "castles", "turtles", "kittens",
            },
        },
        nounEnds = {
            again = true, also = true, ["and"] = true, are = true, as = true, at = true, before = true, but = true,
            by = true, can = true, could = true, did = true, ["for"] = true, from = true, had = true, has = true,
            have = true, he = true, here = true, ["in"] = true, into = true, is = true, it = true, may = true,
            must = true, near = true, now = true, of = true, off = true, on = true, ["or"] = true, out = true,
            she = true, should = true, so = true, that = true, ["then"] = true, they = true, to = true, too = true,
            up = true, was = true, we = true, were = true, which = true, who = true, will = true, with = true,
            would = true, you = true,
        },
        nounStarts = {
            a = true, an = true, any = true, each = true, every = true, few = true, his = true, its = true,
            many = true, my = true, our = true, some = true, the = true, their = true, these = true, this = true,
            those = true, your = true,
        },
    },
}
