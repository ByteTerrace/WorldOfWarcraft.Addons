local addonName, ns = ...

-- Word banks, stories and flavor text for the Scholar puzzles, as ns.ScholarWords: the puzzle files (ScholarPuzzles.lua
-- and its generators) read it; this file only holds data. Everything is original, kid-friendly plain ASCII.
--
-- A tier (t) scales difficulty inside a grade band: 1 is easiest. Story and sentence templates use {hero} and {place};
-- the defaults beside them fill in when the player's context doesn't. Quest riddles (ScholarQuests.lua) ask about the
-- player's own quests, in the words below; their banks are wrong answers to mix in when the player's own quests don't
-- give three.

-- order: grouped by subject and grade, beside the words each group's puzzles read
ns.ScholarWords = {
    -- Puzzle kinds per subject and grade.
    kinds = {
        math = {
            [0] = { "math.count", "math.add", "math.subtract", "math.compare" },
            { "math.add", "math.subtract", "math.missing" },
            { "math.add", "math.subtract", "math.skip", "math.coins" },
            { "math.multiply", "math.divide", "math.groups" },
            { "math.multiply", "math.remainder", "math.money" },
            { "math.fraction", "math.multistep", "math.decimal" },
            { "math.percent", "math.ratio", "math.order" },
        },
        reading = {
            [0] = { "reading.rhyme", "reading.sound", "reading.sight", "reading.cvc" },
            { "reading.rhyme", "reading.sound", "reading.sight", "reading.cvc" },
            { "reading.unscramble", "reading.synonym", "reading.antonym", "reading.spelling" },
            { "reading.unscramble", "reading.synonym", "reading.antonym", "reading.spelling" },
            { "reading.vocab", "reading.blank", "reading.story" },
            { "reading.vocab", "reading.blank", "reading.story" },
            { "reading.vocab", "reading.blank", "reading.story" },
        },
    },
    -- { first mention, later mentions }
    heroes = {
        { "Pip the gnome", "Pip" }, { "Brom the dwarf", "Brom" }, { "Mira the night elf", "Mira" },
        { "Tavi the tauren", "Tavi" }, { "Zix the goblin", "Zix" }, { "Elly the paladin", "Elly" },
        { "Gruk the orc", "Gruk" }, { "Wren the hunter", "Wren" },
    },
    places = {
        "Goldshire", "Stormwind", "Ironforge", "Orgrimmar", "Thunder Bluff", "Darnassus", "the Barrens",
        "Elwynn Forest", "Westfall", "Booty Bay", "Loch Modan", "Mulgore", "Durotar", "Teldrassil",
    },
    -- { one, many }
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
    -- Counting rows: { symbol, one, many }
    countables = { { "*", "star", "stars" }, { "o", "apple", "apples" }, { "@", "fish", "fish" } },
    gear = { "sword", "shield", "staff", "bow", "helmet", "cloak", "pair of boots", "wand" },
    -- Ratio pairs: { first, second, sentence }
    ratios = {
        { { "fish", "fish" }, { "clam", "clams" }, "Murloc soup uses {X} for every {Y}." },
        { { "apple", "apples" }, { "carrot", "carrots" }, "A horse treat uses {X} for every {Y}." },
        { { "red gem", "red gems" }, { "blue gem", "blue gems" }, "A crown has {X} for every {Y}." },
        { { "cog", "cogs" }, { "spring", "springs" }, "A gnome robot needs {X} for every {Y}." },
        { { "candle", "candles" }, { "flower", "flowers" }, "The festival table has {X} for every {Y}." },
    },
    ratioGroups = { { "gnomes", "goblins" }, { "owls", "ravens" }, { "dwarves", "elves" }, { "red kites", "blue kites" } },

    praise = {
        "Great job!", "You got it!", "Well done, hero!", "The Owl Sage is proud of you!", "Brilliant!",
        "Nicely done!", "Way to go!", "Hoot hoot, hooray!", "Your brain is mighty!", "Fantastic thinking!",
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
        ["math.percent"] = { "Big Sale at the Shop!", "Percent Puzzle", "Bargain Hunter" },
        ["math.ratio"] = { "Recipe Ratios", "For Every One...", "Perfect Proportions" },
        ["math.order"] = { "The Order of Operations", "Solve in Order!", "The Owl Sage's Rules" },
        ["reading.rhyme"] = { "Rhyme Time!", "The Owl Sage's Rhyme Game", "Hoot and Rhyme" },
        ["reading.sound"] = { "Sound Detective", "First Sound Fun", "Listen Closely!" },
        ["reading.sight"] = { "Word Watcher", "Spell It Right!", "The Word Scroll" },
        ["reading.cvc"] = { "Sound It Out", "Word Builder", "Letter Magic" },
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

    -- Puzzle text. {name} is filled from the puzzle's variables. In word problems a number {a} also comes counted with
    -- an item as {A} ("3 apples"), plus {Hero} (first mention), {hero}, {place} and {items}. expr is the calculation
    -- behind the answer, in ASCII.
    math = {
        addBig = {
            explain = "{a} + {b} = {v}.", expr = "{a} + {b}", hint = "Add the ones first, then add the tens.",
            prompts = {
                "{Hero} collects {A} on a quest and {B} on the way home. How many {items} is that in all?",
                "What is {a} + {b}?",
                "A shop in {place} has {A} on one shelf and {B} on another. How many {items} in all?",
            },
        },
        addSmall = {
            explain = "{a} + {b} = {v}.", expr = "{a} + {b}",
            hint = "Start at {a} and count up {b} more. Fingers can help!",
            prompts = {
                "{Hero} has {A}. Then {hero} finds {B}. How many {items} does {hero} have now?",
                "A basket holds {A}. The Owl Sage adds {B}. How many {items} are in the basket now?",
                "What is {a} + {b}?",
                "In {place}, {Hero} picks up {A}. Then {hero} picks up {B}. How many {items} is that?",
            },
        },
        bigMultiply = {
            explain = "{a} x {b} = {v}.", expr = "{a} x {b}",
            hint = "Multiply the ones, then the tens. Don't forget to carry!",
            prompts = {
                "A gnome workshop makes {a} gears each day. How many gears does it make in {b} days?",
                "{Hero} buys {b} stacks of arrows. Each stack has {a} arrows. How many arrows is that?",
                "What is {a} x {b}?",
            },
        },
        change = {
            explain = "{n} x {p} = {np}, and {m} - {np} = {v} copper.", expr = "{m} - {n} x {p}",
            hint = "Do it in two steps. What do you need to find out first?",
            prompts = { "{Hero} buys {n} potions for {p} copper each and pays with {m} copper. How much change does {hero} get?" },
        },
        coinsAdd = {
            explain = "{a} + {b} = {v} copper.", expr = "{a} + {b}", hint = "Add the tens, then add the ones.",
            prompts = {
                "{Hero} has {a} copper. {hero} earns {b} copper for helping a farmer. How much copper does {hero} have now?",
                "{Hero} finds {a} copper in an old boot and {b} copper under a rock. How much copper is that?",
            },
        },
        coinsChange = {
            explain = "100 - {b} = {v} copper.", expr = "{a} - {b}", hint = "What number plus {b} makes 100?",
            prompts = { "1 silver is worth 100 copper. {Hero} pays 1 silver for a pie that costs {b} copper. How much copper does {hero} get back?" },
        },
        coinsMine = {
            explain = "{a} + {b} = {v} copper.", expr = "{a} + {b}", hint = "Add the tens, then add the ones.",
            prompts = { "You have {a} copper right now! A friendly gnome gives you {b} more copper. How much copper do you have now?" },
        },
        compare = {
            explain = "{v} is the {word} number.",
            hint = "Count up from 1. The {word} number is the one you say {when}.",
            prompts = { "Four gnomes each hold up a number card.\nWhich number is the {word}?" },
        },
        count = {
            explain = "There are {counted}.", hint = "Touch each one as you count. Count each one only once!",
            prompts = { "Count the {things}:\n{row}\nHow many {things} are there?" },
        },
        decimalAdd = {
            explain = "{da} + {db} = {dv}.", expr = "{da} + {db}",
            hint = "Line up the decimal points, then add the tenths first.",
            prompts = { "{Hero} walks {da} miles to {place}, then {db} miles more. How far is that in all?" },
        },
        decimalCompare = {
            explain = "{v} is the {word}.",
            hint = "Compare the whole numbers first. If they match, compare the tenths.",
            prompts = { "Four gnomes measured their gears in inches.\nWhich number is the {word}?" },
        },
        decimalSubtract = {
            explain = "{da} - {db} = {dv}.", expr = "{da} - {db}",
            hint = "Line up the decimal points, then subtract the tenths first.",
            prompts = { "{Hero} fills a jug with {da} cups of juice and pours out {db} cups. How many cups are left?" },
        },
        divide = {
            explain = "{a} divided by {b} is {v}, because {b} x {v} = {a}.", expr = "{a} / {b}",
            hint = "Think: {b} times what number makes {a}?",
            prompts = {
                "{Hero} puts {A} into {b} bags, with the same number in each bag. How many {items} go in each bag?",
                "What is {a} divided by {b}?",
                "{A} are shared equally by {b} hunters. How many {items} does each hunter get?",
            },
        },
        fraction = {
            explain = "{t} divided by {d} is {part}. So {n}/{d} of {t} is {v}.", expr = "{t} x {n} / {d}",
            hint = "Split {t} into {d} equal parts. How many are in {n} of those parts?",
            prompts = {
                "{Hero} has {T} and gives {n}/{d} of them to a friend. How many {items} does the friend get?",
                "What is {n}/{d} of {T}?",
                "A chest in {place} holds {T}. {n}/{d} of them are sparkly. How many {items} are sparkly?",
            },
        },
        groups = {
            explain = "{a} groups of {b} is {a} x {b} = {v}.", expr = "{a} x {b}",
            hint = "There are {a} groups with {b} in each group. You can multiply!",
            prompts = {
                "There are {a} murloc huts. Each hut has {b} fish drying in the sun. How many fish are there in all?",
                "{Hero} fills {a} bags with {b} apples in each bag. How many apples is that?",
                "The gnomes line up in {a} rows with {b} gnomes in each row. How many gnomes are there?",
                "A quest giver hands out {a} rewards of {b} silver each. How much silver is that in all?",
            },
        },
        levels = {
            explain = "{a} - {b} = {v}. Keep questing!", expr = "{a} - {b}", hint = "Start at {b} and count up to {a}.",
            prompts = { "You are level {b}! How many more levels until you reach level {a}?" },
        },
        missing = {
            explain = "{a} + {v} = {c}, so the missing number is {v}.", expr = "{c} - {a}",
            hint = "Start at {a} and count up until you reach {c}.",
            prompts = {
                "{Hero} had {A}. After finding some more, {hero} has {C}. How many {items} did {hero} find?",
                "What number goes in the blank?\n{a} + __ = {c}",
                "A gnome needs {C} for a machine. The gnome has {A}. How many more {items} does the gnome need?",
            },
        },
        moneyAdd = {
            explain = "{ca} + {cb} = {cv}.", expr = "{a} + {b}",
            hint = "Add the copper first. If it reaches 100 or more, trade 100 copper for 1 silver.",
            prompts = {
                "{Hero} has {ca} and sells a wolf pelt for {cb}. How much money does {hero} have now?",
                "{Hero} has {ca} and wins {cb} at the Darkmoon Faire. How much money does {hero} have now?",
            },
        },
        moneyAddMine = {
            explain = "{ca} + {cb} = {cv}.", expr = "{a} + {b}",
            hint = "Add the copper first. If it reaches 100 or more, trade 100 copper for 1 silver.",
            prompts = { "You have {ca} right now! You sell a wolf pelt for {cb}. How much money do you have now?" },
        },
        moneyConvert = {
            explain = "{a} copper is {cv}.", expr = "{a}",
            hint = "Every 100 copper makes 1 silver. How many hundreds are in {a}?",
            prompts = { "A merchant pays {Hero} {a} copper. 100 copper = 1 silver. How much is that in silver and copper?" },
        },
        moneySubtract = {
            explain = "{ca} - {cb} = {cv}.", expr = "{a} - {b}",
            hint = "Subtract the copper first. If there isn't enough copper, trade 1 silver for 100 copper.",
            prompts = {
                "{Hero} has {ca} and buys a potion for {cb}. How much money is left?",
                "{Hero} has {ca} and pays {cb} to fix a dented shield. How much money is left?",
            },
        },
        moneySubtractMine = {
            explain = "{ca} - {cb} = {cv}.", expr = "{a} - {b}",
            hint = "Subtract the copper first. If there isn't enough copper, trade 1 silver for 100 copper.",
            prompts = { "You have {ca} right now! You buy a potion for {cb}. How much money is left?" },
        },
        multiply = {
            explain = "{a} x {b} = {v}.", expr = "{a} x {b}",
            hint = "{a} x {b} means {a} groups of {b}. Try skip counting by {b}.",
            prompts = {
                "What is {a} x {b}?",
                "Quick! A gnome needs to know:\nWhat is {a} times {b}?",
                "Solve the rune on the magic scroll:\n{a} x {b} = ?",
            },
        },
        order = {
            explain = "{text} = {v}. Parentheses first, then multiply, then add or subtract!", expr = "{text}",
            hint = "Parentheses first. Then multiply. Then add and subtract from left to right.",
            prompts = { "The Owl Sage wrote a puzzle on the scroll:\n{text} = ?", "Solve it in the right order:\n{text} = ?" },
        },
        packs = {
            explain = "{b} x {c} = {bc}, and {a} + {bc} = {v} arrows.", expr = "{a} + {b} x {c}",
            hint = "Do it in two steps. What do you need to find out first?",
            prompts = { "{Hero} has {a} arrows and buys {b} packs with {c} arrows in each pack. How many arrows does {hero} have now?" },
        },
        percentMine = {
            explain = "{p}% of {n} is {v} gold.", expr = "{n} x {p} / 100",
            hint = "{p}% means {p} out of every 100. To find 10%, divide by 10.",
            prompts = { "You have {n} gold! If you spend {p}% of it on a new saddle, how much gold do you spend?" },
        },
        percentOf = {
            explain = "{p}% of {n} is {v} gold.", expr = "{n} x {p} / 100",
            hint = "{p}% means {p} out of every 100. To find 10%, divide by 10.",
            prompts = { "What is {p}% of {n} gold?" },
        },
        percentSale = {
            explain = "{p}% of {n} is {off}, and {n} - {off} = {v} gold.", expr = "{n} - {n} x {p} / 100",
            hint = "{p}% means {p} out of every 100. Find the discount first.",
            prompts = {
                "A shiny {gear} in {place} costs {n} gold. Today it's {p}% off! What is the sale price?",
                "A merchant sells a {gear} for {n} gold. For heroes, it's {p}% off! What is the sale price?",
            },
        },
        ratio = {
            explain = "{h} / {x} = {m} groups, and {m} x {y} = {v}.", expr = "{h} / {x} x {y}",
            hint = "How many groups of {x} are in {h}? Each group needs {y}.",
            prompts = { "{sentence} If there are {have}, how many {second} are needed?" },
        },
        ratioPart = {
            explain = "{t} / {xy} = {m} groups, and {m} x {y} = {v}.", expr = "{t} / ({x} + {y}) x {y}",
            hint = "Each group has {x} + {y} = {xy}. How many groups make {t}?",
            prompts = { "At the fair, there are {x} {first} for every {y} {second}. There are {t} in all. How many are {second}?" },
        },
        remainder = {
            explain = "{b} x {v} = {bv}, and {bv} + {r} = {a}. So it's {v}, with {r} left over.",
            hint = "How many groups of {b} fit into {a}? Whatever is left is the remainder.",
            prompts = {
                "{a} arrows go into quivers that hold {b} each. How many quivers can be filled, and how many arrows are left over?",
                "{Hero} packs {a} cookies into boxes of {b}. How many boxes get filled, and how many cookies are left over?",
                "What is {a} divided by {b}? How many, and how many left over?",
            },
        },
        share = {
            explain = "{t} / {n} = {q}, and {q} + {e} = {v} gears each.", expr = "{t} / {n} + {e}",
            hint = "Do it in two steps. What do you need to find out first?",
            prompts = { "{n} gnomes share {t} gears equally. Then each gnome finds {e} more gears. How many gears does each gnome have now?" },
        },
        skip = {
            explain = "Each number is {n} more, so {v} comes next.", expr = "{start} + 4 x {n}",
            hint = "How much does each number change? Do that one more time.",
            prompts = {
                "Hop along with the frog! It jumps by {n}s:\n{shown}, __\nWhat number comes next?",
                "The gnome's gear clock clicks by {n}s:\n{shown}, __\nWhat number comes next?",
                "Count by {n}s:\n{shown}, __\nWhat number comes next?",
            },
        },
        skipBack = {
            explain = "Each number is {n} less, so {v} comes next.", expr = "{start} - 4 x {n}",
            hint = "How much does each number change? Do that one more time.",
            prompts = { "Count back by {n}s:\n{shown}, __\nWhat number comes next?" },
        },
        subtractBig = {
            explain = "{a} - {b} = {v}.", expr = "{a} - {b}",
            hint = "Subtract the ones first. If there aren't enough ones, trade a ten for ten ones.",
            prompts = {
                "{Hero} has {A}. {hero} sells {B} at the market in {place}. How many {items} are left?",
                "What is {a} - {b}?",
                "A wagon carries {A}. A bump in the road knocks off {B}. How many {items} are still on the wagon?",
            },
        },
        subtractSmall = {
            explain = "{a} - {b} = {v}.", expr = "{a} - {b}", hint = "Start at {a} and count back {b}.",
            prompts = {
                "{Hero} has {A}. {hero} gives {B} to a friend. How many {items} are left?",
                "A basket holds {A}. A grumpy murloc grabs {B} and waddles away. How many {items} are left?",
                "What is {a} - {b}?",
                "In {place}, {Hero} finds {A}. {hero} shares {B} with a hungry gnome. How many {items} are left?",
            },
        },
    },
    reading = {
        antonym = {
            explain = "\"{correct}\" is the opposite of \"{word}\".",
            hint = "Opposites are as different as can be, like up and down.",
            prompt = "Which word means the opposite of \"{word}\"?",
        },
        blank = {
            explain = "It makes sense: \"{filled}\"",
            hint = "Try each word in the blank and read the sentence out loud. Which one makes sense?",
            prompt = "Which word best fills the blank?\n{sentence}",
        },
        blend = {
            explain = "{sounds} makes \"{target}\"!", hint = "Say the sounds slowly, then say them faster and faster.",
            prompt = "Say each sound, then put them together:\n{sounds}\nWhat word do you get?",
        },
        rhyme = {
            explain = "\"{target}\" and \"{correct}\" rhyme. They end with the same sound.",
            hint = "Say \"{target}\" out loud. Listen to the sound at the end.",
            prompt = "The Owl Sage has a rhyme game!\nWhich word rhymes with \"{target}\"?",
        },
        sight = {
            explain = "\"{word}\" is spelled {spelled}.",
            hint = "Sound it out, and picture the word in a book you know.",
            prompt = "Which word fits in the sentence and is spelled right?\n\"{sentence}\"",
        },
        sound = {
            explain = "\"{target}\" and \"{correct}\" both start with the \"{letter}\" sound.",
            hint = "Say \"{target}\" slowly. Listen to the very first sound.",
            prompt = "Listen closely, young hero!\nWhich word starts with the same sound as \"{target}\"?",
        },
        spelling = {
            explain = "\"{word}\" is spelled {spelled}.",
            hint = "Look closely at every letter. Which one looks like the words in your books?",
            prompt = "Only one word is spelled right. Which one fits?\n\"{sentence}\"",
        },
        story = {
            explain = "You found it: {answer}.", hint = "Read the story again slowly. The answer is hiding in there!",
            prompt = "{story}\n{question}",
        },
        swap = {
            explain = "Swap \"{was}\" for \"{now}\" and \"{from}\" becomes \"{target}\"!",
            hint = "Say the word, swap just that one letter, then sound it out.",
            prompt = "Word magic! Change the \"{was}\" in \"{from}\" to \"{now}\".\nWhat new word do you make?",
        },
        synonym = {
            explain = "\"{correct}\" means almost the same as \"{word}\".",
            hint = "Think of a sentence with \"{word}\". Which word could take its place?",
            prompt = "Which word means almost the same as \"{word}\"?",
        },
        unscramble = {
            explain = "The letters spell {word}!", hint = "Find the word that uses every letter exactly once.",
            prompt = "A gnome mixed up the letters of a word!\n{letters}\nClue: {clue}\nWhich word is it?",
        },
        unscrambleNoClue = {
            explain = "The letters spell {word}!", hint = "Clue: {clue}",
            prompt = "A gnome mixed up the letters of a word!\n{letters}\nWhich word is it?",
        },
        vocab = {
            explain = "\"{word}\" means {meaning}.",
            hint = "Read the whole sentence again. The other words are clues to the meaning.",
            prompt = "{sentence}\nWhat does \"{word}\" mean?",
        },
    },

    -- Quest riddle text. {title} is the quest's title; the quest book holds every answer.
    quest = {
        blank = {
            explain = "The quest says: \"{filled}\"", hint = "Open the quest book and find that sentence.",
            prompt = "From the quest \"{title}\":\n\"{sentence}\"\nWhich word is missing?",
        },
        -- Objectives by kind: an item to bring, a foe to defeat, or a task to do.
        count = {
            foe = {
                explain = "It asked you to defeat {answer}: {objective}.",
                hint = "Open the quest book: it says who to defeat.",
                prompt = "The quest \"{title}\" asked you to defeat \"{objective}\". How many?",
            },
            item = {
                explain = "It asked for {answer}: {objective}.", hint = "Open the quest book: it says what to bring.",
                prompt = "The quest \"{title}\" asked you to bring \"{objective}\". How many?",
            },
            task = {
                explain = "It asked for {answer}: {objective}.", hint = "Open the quest book and read what to do.",
                prompt = "The quest \"{title}\" asked for \"{objective}\". How many?",
            },
        },
        ender = {
            explain = "You turned in \"{title}\" to {answer}.",
            hint = "Open the quest book: it says who you reported to.",
            prompt = "Who did you turn in the quest \"{title}\" to?",
        },
        endPlace = {
            explain = "You turned it in at {answer}.", hint = "Open the quest book: it says where you finished.",
            prompt = "Where did you turn in the quest \"{title}\"?",
        },
        giver = {
            explain = "{answer} gave you \"{title}\".", hint = "Open the quest book: it says who sent you.",
            prompt = "Who gave you the quest \"{title}\"?",
        },
        objective = {
            foe = {
                explain = "\"{title}\" asked you to defeat {answer}.",
                hint = "Open the quest book: it says who to defeat.",
                prompt = "Which enemy did the quest \"{title}\" ask you to defeat?",
            },
            item = {
                explain = "\"{title}\" asked you to bring {answer}.",
                hint = "Open the quest book: it says what to bring.",
                prompt = "What did the quest \"{title}\" ask you to bring?",
            },
            task = {
                explain = "\"{title}\" asked you to: {answer}.", hint = "Open the quest book and read what to do.",
                prompt = "What did the quest \"{title}\" ask you to do?",
            },
        },
        place = {
            explain = "You took \"{title}\" in {answer}.", hint = "Open the quest book: it says where it began.",
            prompt = "Where were you when you took the quest \"{title}\"?",
        },
        title = {
            explain = "{giver} gave you \"{answer}\".", hint = "Open the quest book: it names who gave you this one.",
            prompt = "{giver} gave you a quest. Which one?",
        },
    },
    -- Wrong answers for quest riddles, by the player's faction (Alliance when it's unknown): the real givers, quests
    -- (each with its real giver, so one is never offered as another quest of the riddle's own giver), places (never a
    -- whole zone, which could be true of the right place too) and objectives of the lands a new character of that
    -- faction quests in.
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
            places = {
                "Northshire Abbey", "Goldshire", "Fargodeep Mine", "Jasperlode Mine", "Eastvale Logging Camp",
                "Kharanos", "Coldridge Valley", "Shadowglen", "Dolanaar", "Sentinel Hill",
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
            places = {
                "Valley of Trials", "Razor Hill", "Sen'jin Village", "Burning Blade Coven", "Camp Narache",
                "Bloodhoof Village", "Red Cloud Mesa", "Deathknell", "Brill", "Night Web's Hollow",
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
        about = true, after = true, again = true, around = true, before = true, being = true, below = true,
        could = true, every = true, first = true, little = true, never = true, other = true, should = true,
        since = true, their = true, there = true, these = true, thing = true, those = true, through = true,
        ["until"] = true, where = true, which = true, ["while"] = true, would = true, yourself = true,
    },

    -- Reading banks for kindergarten and grade 1.

    -- Rhyme families: every word in a family rhymes, and no two families rhyme.
    rhymes = {
        { t = 1, "cat", "hat", "bat", "mat", "rat" }, { t = 1, "dog", "log", "frog", "fog" },
        { t = 1, "sun", "run", "fun", "bun" }, { t = 1, "pig", "big", "dig", "wig" },
        { t = 1, "hen", "ten", "pen", "den" }, { t = 1, "bug", "mug", "rug", "hug" },
        { t = 1, "top", "hop", "mop", "pop" }, { t = 1, "bed", "red", "fed", "sled" },
        { t = 2, "bee", "tree", "see", "three" }, { t = 2, "cake", "lake", "snake", "rake" },
        { t = 2, "king", "ring", "sing", "wing" }, { t = 2, "boat", "goat", "coat" },
        { t = 2, "star", "car", "jar", "far" }, { t = 2, "fish", "dish", "wish" },
        { t = 2, "bell", "shell", "well", "smell" }, { t = 2, "night", "light", "knight", "bright" },
        { t = 2, "snail", "tail", "mail", "sail" }, { t = 2, "moon", "spoon", "soon" },
    },
    -- First sounds: { letter, words that start with that sound }. No blends, digraphs or silent letters.
    sounds = {
        { "b", "ball", "bat", "bear", "boat", "bug", "bell" }, { "d", "dog", "duck", "dig", "door", "doll" },
        { "f", "fish", "fox", "fan", "fire", "feet" }, { "h", "hat", "hen", "horse", "hill", "hug" },
        { "l", "lamp", "leaf", "log", "lion", "lake" }, { "m", "moon", "map", "mug", "milk", "murloc" },
        { "n", "nest", "net", "nose", "nut", "nine" }, { "p", "pig", "pen", "pot", "pup", "pie" },
        { "r", "rat", "red", "ring", "rug", "rock" }, { "s", "sun", "sock", "seal", "sand", "six" },
        { "t", "top", "ten", "tent", "tiger", "toe" }, { "w", "wolf", "web", "wing", "water", "wagon" },
    },
    -- Sight words: { word, sentence, three misspellings that aren't real words }
    sight = {
        { t = 1, "the", "Look at ___ big dragon!", "teh", "hte", "tha" },
        { t = 1, "you", "Thank ___, Owl Sage!", "yuo", "yoo", "yuu" },
        { t = 1, "look", "Let's ___ at the stars.", "luk", "lok", "lookk" },
        { t = 1, "play", "Let's ___ a game.", "plai", "pley", "plae" },
        { t = 1, "help", "Can you ___ the gnome?", "halp", "hepl", "hellp" },
        { t = 1, "down", "The owl flew ___ to the tree.", "doun", "dwon", "donw" },
        { t = 1, "jump", "Frogs can ___ very high.", "jumpe", "jmup", "jupm" },
        { t = 1, "here", "Come ___, little wolf!", "heer", "hier", "heare" },
        { t = 1, "was", "The murloc ___ happy.", "wuz", "waz", "wsa" },
        { t = 1, "come", "Please ___ to my party.", "kome", "komm", "coome" },
        { t = 1, "blue", "The sky is ___.", "bloo", "bluw", "bluu" },
        { t = 2, "said", "The gnome ___ hello.", "sed", "siad", "sayd" },
        { t = 2, "they", "The gnomes said ___ were hungry.", "thay", "tehy", "thei" },
        { t = 2, "have", "I ___ a red potion.", "hav", "haev", "hafe" },
        { t = 2, "what", "Do you know ___ is in the box?", "whatt", "whut", "waht" },
        { t = 2, "where", "I know ___ the gold is.", "whare", "wher", "werre" },
        { t = 2, "little", "A ___ frog hopped by.", "littel", "litle", "lettle" },
        { t = 2, "went", "We ___ to the lake.", "whent", "wnet", "wint" },
        { t = 2, "want", "I ___ a snack.", "wunt", "whant", "wnat" },
        { t = 2, "again", "Can we play ___?", "agin", "agane", "aggain" },
        { t = 2, "many", "How ___ gems do you have?", "meny", "mony", "manny" },
        { t = 2, "were", "The fish ___ swimming.", "wer", "whre", "wre" },
        { t = 2, "from", "This is a gift ___ the owl.", "frum", "fromm", "frim" },
        { t = 2, "could", "The gnome ___ fix it.", "cood", "culd", "coud" },
        { t = 2, "friend", "The owl is my ___.", "frend", "freind", "frinde" },
        { t = 2, "there", "The dragon is over ___.", "thare", "ther", "theer" },
    },
    -- Consonant-vowel-consonant words with no repeated letters.
    cvc = {
        "cat", "hat", "bat", "mat", "rat", "sat", "map", "cap", "nap", "tap", "van", "can", "fan", "pan",
        "jam", "ham", "bag", "rag", "dog", "log", "hog", "fog", "pot", "hot", "dot", "top", "hop", "mop",
        "box", "fox", "pig", "big", "dig", "wig", "fig", "sit", "hit", "pin", "win", "fin", "tin", "six",
        "fix", "bug", "mug", "rug", "hug", "jug", "sun", "run", "fun", "bun", "cup", "hen", "ten",
        "pen", "den", "bed", "red", "fed", "net", "jet", "wet", "pet", "web", "leg", "peg",
    },

    -- Reading banks for grades 2 and 3.

    -- { WORD, clue }
    unscramble = {
        { t = 1, "OWL", "A wise bird that says hoot." }, { t = 1, "MAP", "It shows you the way." },
        { t = 1, "WOLF", "It howls at the moon." }, { t = 1, "GOLD", "Shiny yellow coins." },
        { t = 1, "BOAT", "It floats on the water." }, { t = 1, "CAVE", "A dark hole in a mountain." },
        { t = 1, "RING", "You wear it on your finger." }, { t = 1, "FROG", "It hops and says ribbit." },
        { t = 2, "SWORD", "A warrior swings this." }, { t = 2, "GNOME", "A small, clever tinkerer." },
        { t = 2, "ARROW", "A hunter shoots this from a bow." }, { t = 2, "TORCH", "It lights up dark places." },
        { t = 2, "MAGIC", "What wizards can do." }, { t = 2, "QUEST", "A job for a hero." },
        { t = 2, "HORSE", "An animal you can ride." }, { t = 2, "TOWER", "A tall, tall building." },
        { t = 3, "DRAGON", "A big lizard with wings." }, { t = 3, "POTION", "A drink that makes you feel better." },
        { t = 3, "MURLOC", "A fish-person who says mrrglglgl." }, { t = 3, "CASTLE", "Where a king and queen live." },
        { t = 3, "WIZARD", "A person who casts spells." }, { t = 3, "SCROLL", "Rolled-up paper with writing on it." },
        { t = 3, "SILVER", "Shiny gray coins." }, { t = 3, "FOREST", "Lots and lots of trees." },
        { t = 3, "CANDLE", "A small wax light." }, { t = 3, "HAMMER", "Dwarves use it to make things." },
        { t = 3, "SHIELD", "It keeps you safe from bumps." }, { t = 3, "GRYPHON", "Half eagle, half lion, and it flies." },
    },
    -- { word, same meaning, opposite (optional) }. No two entries share a meaning.
    synonyms = {
        { t = 1, "big", "large", "small" }, { t = 1, "happy", "glad", "sad" }, { t = 1, "fast", "quick", "slow" },
        { t = 1, "loud", "noisy", "quiet" }, { t = 1, "cold", "chilly", "hot" }, { t = 1, "easy", "simple", "hard" },
        { t = 1, "start", "begin", "finish" }, { t = 1, "kind", "nice", "mean" }, { t = 1, "near", "close", "far" },
        { t = 1, "under", "below", "above" }, { t = 1, "strong", "powerful", "weak" }, { t = 1, "gift", "present" },
        { t = 1, "rock", "stone" }, { t = 2, "tidy", "neat", "messy" }, { t = 2, "laugh", "giggle", "cry" },
        { t = 2, "rich", "wealthy", "poor" }, { t = 2, "brave", "bold", "afraid" }, { t = 2, "bright", "shiny", "dark" },
        { t = 2, "wet", "damp", "dry" }, { t = 2, "fix", "repair", "break" }, { t = 2, "true", "correct", "false" },
    },
    -- { word, sentence, three misspellings }
    spelling = {
        { t = 1, "because", "The gnome was late ___ he overslept.", "becuz", "becawse", "beacuse" },
        { t = 1, "people", "Many ___ came to the fair.", "peeple", "pepole", "peopel" },
        { t = 1, "every", "The owl hoots ___ night.", "evry", "evrey", "everey" },
        { t = 1, "before", "Wash your hands ___ dinner.", "befor", "bifore", "befour" },
        { t = 1, "always", "The dwarf ___ wears his helmet.", "allways", "alwayz", "awlays" },
        { t = 1, "animal", "A kodo is a big ___.", "animul", "aminal", "anamal" },
        { t = 1, "around", "The pup ran ___ the tree.", "arownd", "aroun", "arund" },
        { t = 1, "would", "I ___ like a cookie, please.", "wuld", "woud", "whould" },
        { t = 1, "laugh", "Silly jokes make me ___.", "lauhg", "lauf", "lagh" },
        { t = 1, "school", "Mages go to ___ to learn spells.", "skule", "scool", "shcool" },
        { t = 1, "water", "Murlocs love the ___.", "watter", "wauter", "woter" },
        { t = 1, "night", "Stars shine at ___.", "nihgt", "nigth", "niht" },
        { t = 2, "different", "Every snowflake is ___.", "diffrent", "diferent", "differant" },
        { t = 2, "beautiful", "The sunset was ___.", "beutiful", "beautifull", "butiful" },
        { t = 2, "favorite", "Pie is my ___ food.", "favrite", "faverite", "favorit" },
        { t = 2, "answer", "Raise your hand to ___.", "anser", "answar", "ansewr" },
        { t = 2, "believe", "I ___ in you!", "beleive", "belive", "beleve" },
        { t = 2, "library", "The Owl Sage reads in the ___.", "libary", "liberry", "librery" },
        { t = 2, "probably", "It will ___ rain today.", "probly", "probaly", "prabably" },
        { t = 2, "surprise", "The party was a big ___!", "suprise", "surprize", "serprise" },
        { t = 2, "thought", "The gnome ___ of a great idea.", "thougt", "thawt", "thougth" },
        { t = 2, "enough", "Do we have ___ apples?", "enouhg", "enogh", "enouf" },
        { t = 2, "special", "Today is a ___ day.", "speshul", "spetial", "specal" },
        { t = 2, "island", "The pirates sailed to an ___.", "iland", "ilund", "islund" },
        { t = 2, "treasure", "The map leads to hidden ___.", "tresure", "treasur", "treshure" },
    },

    -- Reading banks for grades 4 to 6.

    -- { word, sentence, meaning, three wrong meanings }
    vocab = {
        { t = 1, "brave", "Even though the cave was dark, the brave young paladin walked right in.", "not afraid to face danger", "very sleepy", "easily lost", "always hungry" },
        { t = 1, "ancient", "The ancient tree in Ashenvale had been growing for thousands of years.", "very, very old", "brand new", "very tiny", "painted blue" },
        { t = 1, "enormous", "The enormous kodo was so big that it blocked the whole road.", "very large", "very small", "very noisy", "very fast" },
        { t = 1, "cautious", "The cautious rogue tiptoed slowly and checked every step.", "careful to avoid trouble", "loud and careless", "very silly", "bored" },
        { t = 1, "exhausted", "After running all the way to Goldshire, the gnome was exhausted and fell asleep.", "very tired", "very excited", "very rich", "very angry" },
        { t = 1, "generous", "The generous innkeeper gave free soup to every traveler.", "happy to share", "unkind", "very tall", "forgetful" },
        { t = 1, "curious", "The curious murloc peeked into every crate to see what was inside.", "wanting to know more", "afraid of everything", "very sleepy", "grumpy" },
        { t = 1, "fragile", "Carry the fragile potion bottle carefully, or it might break.", "easy to break", "very heavy", "very cheap", "tasting sweet" },
        { t = 2, "treacherous", "The treacherous mountain path was icy, steep and full of loose rocks.", "very dangerous", "very pretty", "flat and easy", "brand new" },
        { t = 2, "furious", "The ogre was furious when someone ate his last cake, and he stomped around.", "very angry", "very pleased", "very sleepy", "very quiet" },
        { t = 2, "loyal", "The loyal wolf stayed by the hunter's side every single day.", "faithful and true", "mean and grumpy", "lost", "noisy" },
        { t = 2, "mysterious", "A mysterious glow came from the cave, and nobody knew what it was.", "strange and hard to explain", "easy to understand", "very loud", "freshly baked" },
        { t = 2, "nimble", "The nimble gnome climbed the tall tower quickly and easily.", "quick and light on your feet", "slow and clumsy", "very hungry", "very tall" },
        { t = 2, "reluctant", "The shy dwarf was reluctant to sing in front of the whole tavern.", "not wanting to do something", "very eager", "unable to hear", "very proud" },
        { t = 2, "gleaming", "The gleaming sword shone so brightly that it lit up the room.", "shining brightly", "rusty and old", "very heavy", "broken" },
        { t = 2, "vast", "The Barrens are so vast that it takes a long time to cross them.", "very wide and huge", "tiny", "crowded", "wet" },
        { t = 3, "abundant", "Food was abundant after the harvest, with plenty for every family.", "more than enough", "very scarce", "rotten", "expensive" },
        { t = 3, "scarce", "Water was scarce in the desert, so the travelers shared every drop.", "hard to find", "everywhere", "very cold", "free" },
        { t = 3, "peculiar", "The peculiar goblin wore a teapot as a hat.", "odd or unusual", "ordinary", "frightened", "very polite" },
        { t = 3, "triumphant", "The triumphant heroes cheered after they finally won the tournament.", "proud after winning", "sad after losing", "sleepy", "lost" },
        { t = 3, "hesitate", "Don't hesitate to ask the Owl Sage for help when you're stuck.", "to pause before acting", "to shout", "to hurry", "to forget" },
        { t = 3, "determined", "The determined druid kept practicing her spells until she got them right.", "refusing to give up", "ready to quit", "very sleepy", "confused" },
        { t = 3, "humble", "Even after saving the town, the humble knight said, \"I only helped a little.\"", "not bragging", "boastful", "very rich", "angry" },
        { t = 3, "sturdy", "The dwarves built a sturdy bridge that could hold a whole army.", "strong and solid", "weak and wobbly", "shiny", "tiny" },
        { t = 3, "serene", "The lake was serene at dawn, with no wind and no waves.", "calm and peaceful", "stormy", "crowded", "freezing" },
    },
    -- { sentence with ___, answer, three words that don't fit }
    blanks = {
        { t = 1, "The mage lit a ___ so everyone could see inside the dark cave.", "torch", "pillow", "puddle", "sandwich" },
        { t = 1, "Murlocs live near the ___ and love to splash in the waves.", "sea", "desert", "volcano", "library" },
        { t = 1, "The hunter put an ___ on the bow and aimed at the target.", "arrow", "onion", "egg", "umbrella" },
        { t = 1, "{hero} was so thirsty that {hero} drank a whole ___ of water.", "bottle", "blanket", "ladder", "hammer" },
        { t = 1, "Gnomes are famous for building clever ___ out of gears and springs.", "machines", "clouds", "puddles", "sandwiches" },
        { t = 1, "The owl opened its wings and ___ up into the night sky.", "flew", "swam", "dug", "melted" },
        { t = 1, "Please speak ___ in the library so others can read.", "quietly", "loudly", "rudely", "backwards" },
        { t = 2, "After a long quest, the tired heroes rested at the ___ in {place}.", "inn", "ocean", "volcano", "anvil" },
        { t = 2, "The dwarf used a hammer and an ___ to shape the hot metal into a sword.", "anvil", "apple", "owl", "egg" },
        { t = 2, "The goblin counted coins because he wanted to ___ enough gold for a rocket.", "save", "lose", "spill", "forget" },
        { t = 2, "The bridge was broken, so the travelers had to find a ___ way home.", "different", "noisy", "hungry", "sleepy" },
        { t = 2, "The druid turned into a bear, which made her much ___ than before.", "stronger", "smaller", "quieter", "wetter" },
        { t = 2, "{hero} studied the old map ___ so no clue would be missed.", "carefully", "carelessly", "sleepily", "angrily" },
        { t = 3, "The storm was so ___ that the ships stayed safely in the harbor.", "fierce", "gentle", "tiny", "polite" },
        { t = 3, "The two kingdoms signed a ___ and promised to be friends forever.", "treaty", "sandwich", "pebble", "mistake" },
        { t = 3, "The scout was ___ by the strange lights and went closer to look.", "intrigued", "bored", "asleep", "frozen" },
        { t = 3, "The alchemist ___ the two potions to make a brand new color.", "combined", "separated", "forgot", "painted" },
        { t = 3, "With great ___, the young paladin stepped forward to help the lost child.", "courage", "laziness", "rudeness", "boredom" },
        { t = 3, "The tauren's voice was ___, deep and loud like rolling thunder.", "booming", "squeaky", "silent", "tiny" },
    },
    -- { text, questions = { question, answer, three wrong answers }... }, with optional hero/place defaults.
    stories = {
        { "Pip the gnome built a tiny robot named Bolt. Bolt could sweep floors, but it always swept the dust under the rug! Pip laughed and gave it a dustpan.",
            { "What was silly about Bolt?", "It swept dust under the rug", "It could not move", "It was too loud", "It ate the dustpan" },
            { "How did Pip feel about the mistake?", "Pip laughed about it", "Pip was furious", "Pip cried", "Pip ran away" } },
        { "Every morning, Mira the night elf fed the owls of Teldrassil. One day a baby owl was too shy to eat. Mira sang softly until it hopped over for a berry.",
            { "Why didn't the baby owl eat at first?", "It was too shy", "It was full", "It was asleep", "It did not like berries" },
            { "What did Mira do to help?", "She sang softly", "She shouted", "She went home", "She built a nest" } },
        { "A grumpy murloc named Glub hated rain. When a storm came, the other murlocs splashed and played. Glub tried it too and found out puddles were fun.",
            { "How did Glub feel about rain at the start?", "Glub hated it", "Glub loved it", "Glub never saw rain", "Glub wanted more of it" },
            { "What did Glub find out?", "Puddles are fun", "Rain is too cold", "Storms are loud", "Fish can fly" } },
        { "Brom the dwarf lost his favorite hammer. He searched the forge, the mine and the tavern. At last he found it under his own bed, right where he left it.",
            { "Where was the hammer?", "Under Brom's bed", "In the mine", "In the tavern", "In the forge" },
            { "What does \"searched\" mean in this story?", "Looked hard for something", "Slept for a long time", "Sang a song", "Built something new" } },
        { hero = "Tamsin", "{hero} wanted to learn to fish. On the first day, {hero} caught only an old boot. The next day, {hero} caught three fish and shared them with a hungry cat.",
            { "What did {hero} catch on the first day?", "An old boot", "Three fish", "A hungry cat", "A shiny ring" },
            { "What did {hero} do with the fish?", "Shared them with a cat", "Sold them", "Threw them back", "Lost them" },
            { "What lesson does this story show?", "Keep trying", "Give up fast", "Boots are tasty", "Cats can fish" } },
        { "The goblins of Booty Bay held a boat race. Zix built the fastest boat, but it had no brakes! It zoomed past the finish line into a pile of pillows.",
            { "Why couldn't Zix stop?", "The boat had no brakes", "The water was frozen", "Zix fell asleep", "The race was canceled" },
            { "Where did the boat end up?", "In a pile of pillows", "At the bottom of the sea", "On a roof", "In a tree" } },
        { "Tavi the tauren was the tallest in her village. Some days she wished she were smaller. Then a kite got stuck high in a tree, and only Tavi could reach it.",
            { "What could only Tavi do?", "Reach the stuck kite", "Find a lost dog", "Fix a roof", "Cook dinner" },
            { "What is the main idea?", "Being different can help", "Kites are dangerous", "Trees are too tall", "Tauren can fly" } },
        { "The Owl Sage kept a library in a hollow tree. Each book glowed when someone needed it. One night, a book about stars glowed for a sleepy young gnome.",
            { "Where was the library?", "In a hollow tree", "In a castle", "Under a lake", "On a ship" },
            { "When did a book glow?", "When someone needed it", "When it rained", "Every morning", "When it was lost" } },
        { "Rook the raven loved shiny things. He collected buttons, spoons and coins. When a traveler lost her ring, Rook flew it right back to her.",
            { "What did Rook collect?", "Shiny things", "Sticks and leaves", "Old books", "Seeds" },
            { "Which word best describes Rook at the end?", "Helpful", "Greedy", "Sleepy", "Grumpy" } },
        { "In Mulgore, a young kodo named Pebble was afraid to cross the river. Her mother walked beside her, one slow step at a time, until they reached the other side.",
            { "What was Pebble afraid of?", "Crossing the river", "The dark", "Loud storms", "Other kodos" },
            { "How did Pebble's mother help?", "She walked beside her", "She carried her", "She built a bridge", "She called for help" } },
        { "Fizzle the goblin invented a hat that made tea. Sadly, it poured the tea on his head! Fizzle giggled, dried off and started drawing a better plan.",
            { "What did the hat do by mistake?", "Poured tea on his head", "Flew away", "Made ice cream", "Turned purple" },
            { "What will Fizzle probably do next?", "Try to build a better hat", "Quit inventing forever", "Sell his workshop", "Move to the moon" } },
        { hero = "Nori", place = "Elwynn Forest", "{hero} found a map with an X by a lake in {place}. After digging all day, {hero} found a box. Inside was a note: \"The real treasure is your friends!\"",
            { "What did {hero} find in the box?", "A note", "Gold coins", "A sword", "A puppy" },
            { "Where was the X on the map?", "By a lake", "On a mountain", "In a cave", "Under a bridge" } },
        { "Snowflake the wolf pup could not howl yet. She practiced every night, but only squeaks came out. On the night of the full moon, she let out a mighty howl.",
            { "What came out when Snowflake practiced?", "Only squeaks", "Loud howls", "Songs", "Nothing at all" },
            { "When did she finally howl?", "On the night of the full moon", "At lunchtime", "In the rain", "Never" } },
        { "The bakers of Stormwind had a contest. Old Mae made a cake shaped like a gryphon. It was so beautiful that the judges almost did not want to eat it.",
            { "What shape was Mae's cake?", "A gryphon", "A castle", "A dragon", "A murloc" },
            { "Why did the judges almost not eat it?", "It was so beautiful", "It tasted bad", "It was too small", "It was burned" } },
        { "Two gnomes argued over who could use the workshop. Then they had an idea: build something together! Their flying teapot won first prize.",
            { "What did the gnomes learn?", "Working together is better", "Arguing is fun", "Teapots are heavy", "Workshops are small" },
            { "What did they build?", "A flying teapot", "A robot dog", "A tiny boat", "A magic hat" } },
        { "Every autumn, the leaves in Ashenvale turned gold and red. Young Kael loved to jump in the leaf piles, then rake them up again for the next friend.",
            { "What season is it in the story?", "Autumn", "Winter", "Spring", "Summer" },
            { "What did Kael do after jumping?", "Raked the leaves up again", "Went to sleep", "Ate the leaves", "Went swimming" } },
    },
}
