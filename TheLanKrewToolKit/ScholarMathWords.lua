local addonName, ns = ...

-- The math riddles' text and word banks, as ns.ScholarMathWords: ScholarMath.lua reads it. This file only holds data.
-- Everything is original, kid-friendly plain ASCII. The titles live with the others in ScholarWords.lua.
--
-- The riddle's variables fill a text's {name}. In word problems a number {a} also comes counted with an item as {A} ("3
-- apples"), plus {Hero} (first mention), {hero}, {place}, and {items}. expr is the calculation behind the answer, in
-- ASCII. hint is the strategy, step a worked first step (never the answer), explain the working, and praise names the
-- strategy when the first try is right. whys says, kindly, what mistake each named wrong answer comes from.
-- wrong is the why for any other ({choice} names it). cases are variants a generator picks by what the numbers need (a
-- carry, a trade, a unit fraction): a case's fields replace the text's, and its whys add to them.
--
-- Hints and steps name only numbers the riddle shows or numbers that can't be the answer, and spell out small constants
-- ("ten", not "10"), so the giveaway check in ScholarPuzzles.lua keeps them.

-- order: the banks first, then the texts by key
ns.ScholarMathWords = {
    -- Each counting row is { symbol, one, many }.
    countables = { { "*", "star", "stars" }, { "o", "apple", "apples" }, { "@", "fish", "fish" } },
    gear = { "sword", "shield", "staff", "bow", "helmet", "cloak", "pair of boots", "wand" },
    -- Each ratio pair is { first, second, sentence }.
    ratios = {
        { { "fish", "fish" }, { "clam", "clams" }, "Murloc soup uses {X} for every {Y}." },
        { { "apple", "apples" }, { "carrot", "carrots" }, "A horse treat uses {X} for every {Y}." },
        { { "red gem", "red gems" }, { "blue gem", "blue gems" }, "A crown has {X} for every {Y}." },
        { { "cog", "cogs" }, { "spring", "springs" }, "A gnome robot needs {X} for every {Y}." },
        { { "candle", "candles" }, { "flower", "flowers" }, "The festival table has {X} for every {Y}." },
    },
    ratioGroups = { { "gnomes", "goblins" }, { "owls", "ravens" }, { "dwarves", "elves" }, { "red kites", "blue kites" } },

    addBig = {
        cases = {
            carry = {
                explain = "Ones: {oa} + {ob} = {ones}. Write {od} and carry the 1 ten. Tens: {ta} + {tb} + 1 = {tens}. So {a} + {b} = {v}.",
                hint = "Add the ones first. They make ten or more, so carry a ten over to the tens.",
                praise = "Carrying the ten over to the tens worked.",
                step = "Ones first: {oa} + {ob} = {ones}. Write {od} and carry the 1 ten.",
                whys = { carry = "That's what you get without the carry. {oa} + {ob} = {ones}, so 1 ten moves over to the tens." },
            },
        },
        explain = "Ones: {oa} + {ob} = {ones}. Tens: {ta} + {tb} = {tens}. So {a} + {b} = {v}.",
        expr = "{a} + {b}",
        hint = "Add the ones first, then add the tens.",
        praise = "Ones first, then tens: that kept it tidy.",
        prompts = {
            "{Hero} collects {A} on a quest and {B} on the way home. How many {items} is that in all?",
            "What is {a} + {b}?",
            "A shop in {place} has {A} on one shelf and {B} on another. How many {items} in all?",
        },
        step = "Ones first: {oa} + {ob} = {ones}.",
        whys = {
            digits = "That adds {ta} + {tb} as if they were ones. They're tens: {tensA} and {tensB}.",
            tens = "That adds the tens but leaves out the ones. Add {oa} + {ob} too.",
        },
        wrong = "{choice} is close. Add the ones, then the tens, and check each.",
    },
    addSmall = {
        cases = {
            ten = {
                explain = "{big} + {fill} makes 10, and {rest} more makes {v}. So {a} + {b} = {v}.",
                hint = "Make a ten first: what goes with {big} to make ten?",
                praise = "Making a ten first was quick.",
                step = "{big} needs {fill} more to make ten. Take {fill} from the {small}, which leaves {rest}.",
                whys = { ten = "That's the ten you made. Add what's left over too." },
                wrong = "{choice} is close. Make ten with {big}, then add the rest.",
            },
        },
        explain = "Start at {big} and count on {small}: {counts}. So {a} + {b} = {v}.",
        expr = "{a} + {b}",
        hint = "Start at the bigger number, {big}, and count up {small} more. Fingers can help!",
        praise = "Counting on from the bigger number was quick.",
        prompts = {
            "{Hero} has {A}. Then {hero} finds {B}. How many {items} does {hero} have now?",
            "A basket holds {A}. The Owl Sage adds {B}. How many {items} are in the basket now?",
            "What is {a} + {b}?",
            "In {place}, {Hero} picks up {A}. Then {hero} picks up {B}. How many {items} is that?",
        },
        step = "Say {big} in your head. Then hold up {small} on your fingers, and count on one number for each finger.",
        whys = {
            start = "That's what you get if you say {big} again as you start. Start at {big}, then say the next number.",
            takeAway = "That's {big} - {small}, taking away. Adding makes more.",
        },
        wrong = "{choice} is close. Start at {big} and count on {small}, one number for each finger.",
    },
    bigMultiply = {
        cases = {
            carry = {
                hint = "Split {a} into {t0} + {o}. Multiply each part by {b}, then add. The ones part makes ten or more, so it carries into the tens.",
                praise = "Splitting {a} into tens and ones, then adding the parts, took care of the carry.",
                whys = { noCarry = "That's what you get without the carry. {o} x {b} = {po}, so carry {carried} over to the tens." },
            },
        },
        explain = "{a} = {t0} + {o}. {t0} x {b} = {pt}, and {o} x {b} = {po}. {pt} + {po} = {v}.",
        expr = "{a} x {b}",
        hint = "Split {a} into {t0} + {o}. Multiply each part by {b}, then add.",
        praise = "Splitting {a} into tens and ones made it manageable.",
        prompts = {
            "A gnome workshop makes {a} gears each day. How many gears does it make in {b} days?",
            "{Hero} buys {b} stacks of arrows. Each stack has {a} arrows. How many arrows is that?",
            "What is {a} x {b}?",
        },
        step = "Ones first: {o} x {b} = {po}.",
        whys = {
            added = "That's {a} + {b}, adding. {a} x {b} means {b} groups of {a}.",
            fewer = "That's one group of {a} too few.",
            more = "That's one group of {a} too many.",
            tensAsOnes = "That multiplies the {ta} as if it were ones. It's {tensA}: {t0} x {b} = {pt}.",
        },
        wrong = "{choice} is close. Split {a} into {t0} + {o}, multiply each part by {b}, and add.",
    },
    change = {
        explain = "{n} x {p} = {np} copper for the potions, and {m} - {np} = {v} copper back.",
        expr = "{m} - {n} x {p}",
        hint = "Do it in two steps: first find what the potions cost.",
        praise = "Finding the cost first, then the change, worked.",
        prompts = { "{Hero} buys {n} potions for {p} copper each and pays with {m} copper. How much change does {hero} get?" },
        step = "First find the cost: {n} x {p} = {np} copper.",
        whys = {
            cost = "That's what the potions cost. The change is what's left of the {m} copper.",
            one = "That pays for just one potion, but {hero} buys {n}.",
        },
        wrong = "{choice} is close. Find the cost of all {n} potions, then take it from {m}.",
    },
    coinsAdd = {
        cases = {
            carry = {
                explain = "Ones: {oa} + {ob} = {ones}. Write {od} and carry the 1 ten. Tens: {ta} + {tb} + 1 = {tens}. So {a} + {b} = {v} copper.",
                hint = "Add the ones first. They make ten or more, so carry a ten over to the tens.",
                praise = "Carrying the ten over to the tens worked.",
                step = "Ones first: {oa} + {ob} = {ones}. Write {od} and carry the 1 ten.",
                whys = { carry = "That's what you get without the carry. {oa} + {ob} = {ones}, so 1 ten moves over to the tens." },
            },
            mine = {
                prompts = { "You have {a} copper right now! A friendly gnome gives you {b} more copper. How much copper do you have now?" },
            },
        },
        explain = "Ones: {oa} + {ob} = {ones}. Tens: {ta} + {tb} = {tens}. So {a} + {b} = {v} copper.",
        expr = "{a} + {b}",
        hint = "Add the ones first, then add the tens.",
        praise = "Ones first, then tens: that kept it tidy.",
        prompts = {
            "{Hero} has {a} copper. {hero} earns {b} copper for helping a farmer. How much copper does {hero} have now?",
            "{Hero} finds {a} copper in an old boot and {b} copper under a rock. How much copper is that?",
        },
        step = "Ones first: {oa} + {ob} = {ones}.",
        whys = {
            digits = "That adds {ta} + {tb} as if they were ones. They're tens: {tensA} and {tensB}.",
            tens = "That adds the tens but leaves out the ones. Add {oa} + {ob} too.",
        },
        wrong = "{choice} is close. Add the ones, then the tens, and check each.",
    },
    coinsChange = {
        cases = {
            near = {
                explain = "Count up from {b} to 100: that's {v}. {b} + {v} = 100.",
                praise = "Counting up from {b} to 100 was quick.",
                step = "Count up from {b} to 100, one at a time.",
            },
            tens = {
                explain = "Count up by tens from {b} to 100: that's {v}. {b} + {v} = 100.",
                praise = "Counting up by tens to 100 was quick.",
                step = "Count up by tens from {b}: {b10} is one ten more.",
            },
        },
        explain = "Count up from {b}: {b} + {up} = {ten}, then {ten} + {rest} = 100. {up} + {rest} = {v} copper back.",
        expr = "{a} - {b}",
        hint = "What number plus {b} makes 100? Count up to the next ten first.",
        praise = "Counting up to the next ten, then to 100, worked.",
        prompts = { "1 silver is worth 100 copper. {Hero} pays 1 silver for a pie that costs {b} copper. How much copper does {hero} get back?" },
        step = "Count up from {b} to the next ten, {ten}.",
        whys = {
            added = "That's 100 + {b}, adding. Paying makes the copper go down.",
            borrow = "That takes {ob} from ten and {tb} from ten, as if 100 had ten tens and ten ones. After trading a ten for ones, only 9 tens are left.",
            price = "That's what the pie costs. The change is what's left of the 100 copper.",
        },
        wrong = "{choice} is close. Count up from {b} to 100.",
    },
    compare = {
        explain = "In counting order: {listed}. {v} is the {word}, the one you say {when}.",
        hint = "Count up from one. The {word} number is the one you say {when}.",
        praise = "Putting the numbers in counting order made it clear.",
        prompts = { "Four gnomes each hold up a number card.\nWhich number is the {word}?" },
        step = "Compare {x} and {y} first: {out} is {other}, so it can't be the {word}.",
        whys = { opposite = "That's the {opposite} number. This riddle asks for the {word}." },
        wrong = "{choice} isn't the {word}. Count up from one, and see which you say {when}.",
    },
    count = {
        explain = "Touch and count: {counting}. The last number you say, {v}, is how many: there are {counted}.",
        hint = "Touch each one as you count. Count each one only once!",
        praise = "Touching each one once kept the count right.",
        prompts = { "Count the {things}:\n{row}\nHow many {things} are there?" },
        step = "Touch the first {thing} and say \"one\". Touch the next and say \"two\". Keep going to the end.",
        whys = {
            extra = "That's one too many: one got counted twice. Touch each one only once.",
            missed = "That's one too few: one got skipped. Touch every one.",
        },
        wrong = "{choice} isn't quite it. Touch each one as you count, and count each only once.",
    },
    decimalAdd = {
        explain = "{da} is {tenthsA} and {db} is {tenthsB}. {a} + {b} = {tenthsV}, which is {dv}.",
        expr = "{da} + {db}",
        hint = "Line up the decimal points, then add the tenths first.",
        praise = "Thinking in tenths kept the decimal points lined up.",
        prompts = { "{Hero} walks {da} miles to {place}, then {db} miles more. How far is that in all?" },
        step = "Think in tenths: {da} is {tenthsA}, and {db} is {tenthsB}.",
        whys = {
            carry = "That's what you get without the carry. The tenths make ten or more, so 1 moves over to the ones.",
            point = "That leaves out the decimal point. Add the tenths, then put the point back in.",
        },
        wrong = "{choice} is close. Add {tenthsA} and {tenthsB}, then write it as a decimal.",
    },
    decimalCompare = {
        explain = "With two decimal places each: {listed}. {v} is the {word}.",
        hint = "Compare the whole numbers first. If they match, compare the tenths.",
        praise = "Giving every number two decimal places made it a fair comparison.",
        prompts = { "Four gnomes measured their gears in inches.\nWhich number is the {word}?" },
        step = "Compare {x} and {y} first: {out} is {other}, so it can't be the {word}.",
        whys = {
            longer = "{choice} has more digits, but more digits doesn't mean bigger. Give each number two decimal places, then compare.",
        },
        wrong = "{choice} isn't the {word}. Compare the whole numbers first, then the tenths.",
    },
    decimalSubtract = {
        explain = "{da} is {tenthsA} and {db} is {tenthsB}. {a} - {b} = {tenthsV}, which is {dv}.",
        expr = "{da} - {db}",
        hint = "Line up the decimal points, then subtract the tenths first.",
        praise = "Thinking in tenths kept the decimal points lined up.",
        prompts = { "{Hero} fills a jug with {da} cups of juice and pours out {db} cups. How many cups are left?" },
        step = "Think in tenths: {da} is {tenthsA}, and {db} is {tenthsB}.",
        whys = {
            noTrade = "That takes the smaller tenths from the bigger. {da} has fewer tenths than {db}, so trade 1 for ten tenths first.",
            point = "That leaves out the decimal point. Take away the tenths, then put the point back in.",
        },
        wrong = "{choice} is close. Take {tenthsB} from {tenthsA}, then write it as a decimal.",
    },
    divide = {
        explain = "Count by {b}s up to {a}: {skips}. That's {v} jumps, so {a} divided by {b} is {v}.",
        expr = "{a} / {b}",
        hint = "Think: {b} times what number makes {a}?",
        praise = "Counting by {b}s up to {a} found it.",
        prompts = {
            "{Hero} puts {A} into {b} bags, with the same number in each bag. How many {items} go in each bag?",
            "What is {a} divided by {b}?",
            "{A} are shared equally by {b} hunters. How many {items} does each hunter get?",
        },
        step = "Count by {b}s: {b} is the first jump. Keep jumping until you land on {a}.",
        whys = {
            multiplied = "That's {a} x {b}, multiplying. Sharing {a} makes each share smaller than {a}.",
            subtracted = "That's {a} - {b}, taking away {b} just once. Keep taking groups of {b}, and count them.",
        },
        wrong = "{choice} is close. Count by {b}s up to {a}, and count the jumps.",
    },
    fraction = {
        cases = {
            unit = {
                explain = "{t} split into {d} equal parts is {part} in each part, so 1/{d} of {t} is {v}.",
                praise = "Splitting {t} into {d} equal parts found it.",
                step = "Split {t} into {d} equal parts: what number times {d} makes {t}?",
            },
        },
        explain = "{t} split into {d} equal parts is {part} in each part. {n} parts is {n} x {part} = {v}.",
        expr = "{t} x {n} / {d}",
        hint = "Split {t} into {d} equal parts. How many are in {n} of those parts?",
        praise = "Finding one part first, then {n} parts, worked.",
        prompts = {
            "{Hero} has {T} and gives {n}/{d} of them to a friend. How many {items} does the friend get?",
            "What is {n}/{d} of {T}?",
            "A chest in {place} holds {T}. {n}/{d} of them are sparkly. How many {items} are sparkly?",
        },
        step = "First find 1/{d} of {t}: {t} / {d} = {part}.",
        whys = {
            bottom = "That's the {d} from the bottom of the fraction. It says how many equal parts, not how many {items}.",
            onePart = "That's just one part, 1/{d}. {n}/{d} means {n} of those parts.",
            rest = "That's what's left after the {n}/{d}, not the {n}/{d} itself.",
            top = "That's the {n} from the top of the fraction: how many parts, not how many {items} are in them.",
        },
        wrong = "{choice} is close. Split {t} into {d} equal parts, then take {n} of them.",
    },
    groups = {
        explain = "{a} groups of {b}: {skips}. That's {a} x {b} = {v}.",
        expr = "{a} x {b}",
        hint = "There are {a} groups with {b} in each group. You can multiply!",
        praise = "Counting by {b}s, group by group, found it.",
        prompts = {
            "There are {a} murloc huts. Each hut has {b} fish drying in the sun. How many fish are there in all?",
            "{Hero} fills {a} bags with {b} apples in each bag. How many apples is that?",
            "The gnomes line up in {a} rows with {b} gnomes in each row. How many gnomes are there?",
            "A quest giver hands out {a} rewards of {b} silver each. How much silver is that in all?",
        },
        step = "The first group makes {b}. Count on by {b}s for each group after it.",
        whys = {
            added = "That's {a} + {b}, adding. {a} groups of {b} means {b}, again and again, {a} times.",
            oneGroup = "That's just one group. There are {a} groups of {b}.",
        },
        wrong = "{choice} is close. Count by {b}s, once for each of the {a} groups.",
    },
    levels = {
        explain = "Count up from level {b} to level {a}: that's {v} levels, because {b} + {v} = {a}.",
        expr = "{a} - {b}",
        hint = "Start at {b} and count up to {a}.",
        praise = "Counting up from your level found how many to go.",
        prompts = { "You are level {b}! How many more levels until you reach level {a}?" },
        step = "From level {b}, count up one level at a time: level {b1} is one more. Keep going until you reach {a}.",
        whys = {
            added = "The word more can trick you into adding: that's {a} + {b}. Count the levels from {b} up to {a} instead.",
            goal = "That's the level you're heading for. How many levels are between {b} and {a}?",
        },
        wrong = "{choice} is close. Count up from {b} to {a}, one level at a time.",
    },
    missing = {
        explain = "Count up from {a} to {c}: that's {v}. Check: {a} + {v} = {c}.",
        expr = "{c} - {a}",
        hint = "Start at {a} and count up until you reach {c}.",
        praise = "Counting up from {a} to {c} found the missing number.",
        prompts = {
            "A gnome needs {C} for a machine and has {a} of them so far. How many more {items} does the gnome need?",
            "What number goes in the blank?\n{a} + __ = {c}",
            "{Hero} finds some {items} and puts them with the {a} {hero} already had. Now there are {C}. How many did {hero} find?",
        },
        step = "Start at {a} and count up to {c}, holding up a finger for each number you say.",
        whys = {
            added = "That's {a} + {c}, adding both. The missing number plus {a} makes {c}, so it's less than {c}.",
            start = "That's what you get if you count {a} too. Start with the number just after {a}.",
        },
        wrong = "{choice} is close. Count up from {a} to {c}, one finger for each number.",
    },
    moneyAdd = {
        cases = {
            mine = { prompts = { "You have {ca} right now! You sell a wolf pelt for {cb}. How much money do you have now?" } },
            trade = {
                explain = "Copper: {pa} + {pb} = {cs}. That's 100 or more, so trade 100 copper for 1 silver and keep {cr} copper. Silver: {sa} + {sb} + 1 = {ss}. So {ca} + {cb} = {cv}.",
                praise = "Trading 100 copper for a silver kept the coins tidy.",
                step = "Copper first: {pa} + {pb} = {cs} copper. That's 100 or more, so trade 100 copper for 1 silver.",
                whys = { lost = "That trades 100 copper away but forgets the silver it buys. Add that 1 silver to the silver." },
            },
        },
        explain = "Copper: {pa} + {pb} = {cs}. Silver: {sa} + {sb} = {ss}. So {ca} + {cb} = {cv}.",
        expr = "{a} + {b}",
        hint = "Add the copper first. If it reaches 100 or more, trade 100 copper for 1 silver.",
        praise = "Copper first, then silver: that kept it tidy.",
        prompts = {
            "{Hero} has {ca} and sells a wolf pelt for {cb}. How much money does {hero} have now?",
            "{Hero} has {ca} and wins {cb} at the Darkmoon Faire. How much money does {hero} have now?",
        },
        step = "Copper first: {pa} + {pb} = {cs} copper.",
        whys = {
            extra = "That adds a silver that isn't there: {pa} + {pb} copper is less than 100.",
            silverOnly = "That's only the silver. Add the copper too: {pa} + {pb}.",
        },
        wrong = "{choice} is close. Add the copper, then the silver, and trade 100 copper for 1 silver if you can.",
    },
    moneyConvert = {
        explain = "Every 100 copper is 1 silver. {a} = {h} + {pa}, and {h} copper is {sa} silver, so {a} copper is {cv}.",
        expr = "{a}",
        hint = "Every 100 copper makes 1 silver. How many hundreds are in {a}?",
        praise = "Counting the hundreds as silver worked.",
        prompts = { "A merchant pays {Hero} {a} copper. 100 copper = 1 silver. How much is that in silver and copper?" },
        step = "Split {a} into hundreds and the rest: {a} = {h} + {pa}.",
        whys = {
            ones = "That drops the last digit. Only full hundreds become silver, and every other copper stays copper.",
            tens = "That reads {tens} as the silver, but it takes 100 copper to make 1 silver, so only the hundreds are silver.",
        },
        wrong = "{choice} is close. Every 100 copper makes 1 silver, and the rest stays copper.",
    },
    moneySubtract = {
        cases = {
            even = {
                explain = "Copper: {pa} - {pb} = {cr}. Silver: {sa} - {sb} = {ss}. So {ca} - {cb} = {cv}.",
                praise = "Copper first, then silver: that kept it tidy.",
                step = "Copper first: {pa} - {pb} = {cr} copper.",
            },
            mine = { prompts = { "You have {ca} right now! You buy a potion for {cb}. How much money is left?" } },
        },
        explain = "{pb} copper is more than {pa}, so trade 1 silver for 100 copper: {pa} + 100 = {px}. Copper: {px} - {pb} = {cr}. Silver: {sa1} - {sb} = {ss}. So {ca} - {cb} = {cv}.",
        expr = "{a} - {b}",
        hint = "Subtract the copper first. If there isn't enough copper, trade 1 silver for 100 copper.",
        praise = "Trading 1 silver for 100 copper made it work.",
        prompts = {
            "{Hero} has {ca} and buys a potion for {cb}. How much money is left?",
            "{Hero} has {ca} and pays {cb} to fix a dented shield. How much money is left?",
        },
        step = "There isn't enough copper, so trade 1 silver for 100 copper: {pa} copper becomes {px}.",
        whys = {
            added = "That's {ca} + {cb}, adding. Paying leaves less money than {ca}.",
            noTrade = "That takes {pa} from {pb}, the smaller from the bigger. There's only {pa} copper, so trade 1 silver for 100 copper first.",
        },
        wrong = "{choice} is close. Take away the copper, then the silver, trading 1 silver for 100 copper if you need to.",
    },
    multiply = {
        cases = {
            one = {
                explain = "Times 1 keeps the number: {other} x 1 = {other}, and 1 x {other} = {other}. So {a} x {b} = {v}.",
                hint = "Times 1 keeps a number the same.",
                praise = "The one rule did it: times 1 keeps the number.",
                step = "Picture bags with 1 thing in each, and count the bags.",
                whys = {
                    added = "That's {other} + 1, adding. Times 1 keeps the number the same.",
                    one = "That's just the 1. Count how many groups of 1 there are.",
                },
                wrong = "{choice} is close. Times 1 keeps a number the same.",
            },
            ten = {
                explain = "{other} x 10 is {other} tens, and {other} tens is {v}. So {a} x {b} = {v}.",
                hint = "Times 10 makes tens: put a 0 on the end of the number.",
                praise = "The ten rule did it: put a 0 on the end.",
                step = "Think of {other} tens, and count by tens {other} times.",
                whys = { added = "That's {other} + 10, adding. Times 10 makes {other} tens." },
                wrong = "{choice} is close. Count by tens, {other} times.",
            },
            zero = {
                explain = "Times 0 means no groups, or groups with nothing in them, so it's always 0. So {a} x {b} = 0.",
                hint = "Groups with nothing in them, or no groups at all: how many is that?",
                praise = "The zero rule did it: times 0 is always 0.",
                step = "Picture {other} empty bags. How many things are inside them?",
                whys = { kept = "That's what you'd get if times 0 kept the number. Groups of nothing hold nothing." },
                wrong = "{choice} is too many. Picture {other} empty bags.",
            },
        },
        explain = "Skip count by {big}, {small} times: {skips}. So {a} x {b} = {v}.",
        expr = "{a} x {b}",
        hint = "{a} x {b} means {a} groups of {b}. Try skip counting by {big}.",
        praise = "Skip counting by {big} got there.",
        prompts = {
            "What is {a} x {b}?",
            "Quick! A gnome needs to know:\nWhat is {a} times {b}?",
            "Solve the rune on the magic scroll:\n{a} x {b} = ?",
        },
        step = "Count by {big}s, one finger for each group, until {small} fingers are up.",
        whys = {
            added = "That's {a} + {b}, adding. {a} x {b} means {a} groups of {b}.",
            fewer = "That's one {big} too few, a neighbor fact.",
            more = "That's one {big} too many, a neighbor fact.",
        },
        wrong = "{choice} is a nearby fact. Skip count by {big}, {small} times.",
    },
    order = {
        cases = {
            parens = {
                hint = "Parentheses first. Then multiply. Then add and subtract from left to right.",
                praise = "Parentheses first, then the rest in order: that's the rule.",
                step = "Start with {first}, because parentheses come first.",
                wrong = "{choice} is close. Go step by step: parentheses, then multiply, then add and subtract.",
            },
        },
        explain = "In order: {work}. So {text} = {v}.",
        expr = "{text}",
        hint = "Multiply first. Then add and subtract from left to right.",
        praise = "Multiplying before adding and subtracting kept it in order.",
        prompts = { "The Owl Sage wrote a puzzle on the scroll:\n{text} = ?", "Solve it in the right order:\n{text} = ?" },
        step = "Start with {first}, because multiplying comes before adding and subtracting.",
        whys = {
            leftToRight = "That works straight from left to right. Multiply before you add or subtract.",
            parens = "That skips the parentheses. Work out what's inside them first.",
        },
        wrong = "{choice} is close. Go step by step: multiply first, then add and subtract from left to right.",
    },
    packs = {
        explain = "{b} x {c} = {bc} arrows in the packs, and {a} + {bc} = {v} arrows.",
        expr = "{a} + {b} x {c}",
        hint = "Do it in two steps: first find the arrows in the packs.",
        praise = "Finding the packs first, then adding, worked.",
        prompts = { "{Hero} has {a} arrows and buys {b} packs with {c} arrows in each pack. How many arrows does {hero} have now?" },
        step = "First find the arrows in the packs: {b} x {c} = {bc}.",
        whys = {
            allAdded = "That adds all three numbers. {b} packs of {c} means {b} x {c}.",
            leftToRight = "That adds {a} + {b} first. Find the arrows in the packs first: {b} x {c}.",
            packs = "That's only the arrows in the packs. Add the {a} {hero} already had.",
        },
        wrong = "{choice} is close. Find the arrows in the packs, then add the {a}.",
    },
    percent = {
        cases = {
            mine = { prompts = { "You have {n} gold! If you spend {p}% of it on a new saddle, how much gold do you spend?" } },
            sale = {
                explain = "{work}, so the discount is {off} gold. {n} - {off} = {v} gold.",
                expr = "{n} - {n} x {p} / 100",
                hint = "{p}% means {p} out of every hundred. Find the discount first. {way}",
                praise = "{strategy} Then taking it off {n} gave the price.",
                prompts = {
                    "A shiny {gear} in {place} costs {n} gold. Today it's {p}% off! What is the sale price?",
                    "A merchant sells a {gear} for {n} gold. For heroes, it's {p}% off! What is the sale price?",
                },
                step = "First find the discount. {how}",
                whys = {
                    discount = "That's the discount. The sale price is what's left after taking it off {n}.",
                    gold = "That takes {p} gold off, not {p}%.",
                    tenth = "That takes a tenth off, which is 10%. This sale is {p}% off.",
                },
                wrong = "{choice} is close. Find {p}% of {n}, then take it off.",
            },
        },
        explain = "{work}. So {p}% of {n} is {v} gold.",
        expr = "{n} x {p} / 100",
        hint = "{p}% means {p} out of every hundred. {way}",
        praise = "{strategy}",
        prompts = { "What is {p}% of {n} gold?" },
        step = "{how}",
        -- How to build each percent from easy parts, filled with the riddle's numbers first: way joins the hint, how is
        -- the step, work the explanation's working, and strategy the praise.
        ways = {
            [10] = {
                how = "Ten percent is a tenth of all {n} gold: split it into ten equal parts.",
                strategy = "Splitting into ten equal parts found 10%.",
                way = "A tenth: divide by ten.",
                work = "10% is a tenth: {n} / 10 = {off}",
            },
            [15] = {
                how = "A tenth of {n} is {ten}.",
                strategy = "Building 15% from 10% and 5% worked.",
                way = "It's a tenth plus half a tenth.",
                work = "10% of {n} is {ten}, 5% is half of that, {five}, and {ten} + {five} = {off}",
            },
            [20] = {
                how = "A tenth of {n} is {ten}.",
                strategy = "Finding 10% first, then doubling it, worked.",
                way = "Find a tenth by dividing by ten, then double it.",
                work = "10% of {n} is {ten}, so 20% is 2 x {ten} = {off}",
            },
            [25] = {
                how = "Half of {n} is {half}.",
                strategy = "Halving twice found the quarter.",
                way = "It's a quarter: half of a half.",
                work = "25% is a quarter: half of {n} is {half}, and half of {half} is {off}",
            },
            [30] = {
                how = "A tenth of {n} is {ten}.",
                strategy = "Finding 10% first, then taking it three times, worked.",
                way = "Find a tenth by dividing by ten, then take it three times.",
                work = "10% of {n} is {ten}, so 30% is 3 x {ten} = {off}",
            },
            [40] = {
                how = "A tenth of {n} is {ten}.",
                strategy = "Finding 10% first, then taking it four times, worked.",
                way = "Find a tenth by dividing by ten, then take it four times.",
                work = "10% of {n} is {ten}, so 40% is 4 x {ten} = {off}",
            },
            [50] = {
                how = "Fifty percent is half: split all {n} gold into two equal parts.",
                strategy = "Halving found 50%.",
                way = "It's half.",
                work = "50% is half, and half of {n} is {off}",
            },
            [60] = {
                how = "A tenth of {n} is {ten}.",
                strategy = "Finding 10% first, then taking it six times, worked.",
                way = "Find a tenth by dividing by ten, then take it six times.",
                work = "10% of {n} is {ten}, so 60% is 6 x {ten} = {off}",
            },
            [75] = {
                how = "Half of {n} is {half}.",
                strategy = "Halving to a quarter, then taking three quarters, worked.",
                way = "It's three quarters, and a quarter is half of a half.",
                work = "75% is three quarters: half of {n} is {half}, half of that is {quarter}, and 3 x {quarter} = {off}",
            },
        },
        whys = {
            percent = "That's the {p} from {p}%. {p}% of {n} is {p} out of every hundred, so it's less than {n}.",
            rest = "That's what's left after taking {p}%, not the {p}% itself.",
            tenth = "That's 10% of {n}, a tenth. {p}% is more than a tenth.",
            whole = "That's all {n} gold, which is 100%. {p}% is only part of it.",
        },
        wrong = "{choice} is close. Remember, {p}% means {p} out of every hundred.",
    },
    ratio = {
        cases = {
            one = {
                explain = "Each {firstOne} needs {y} {second}, and there are {h}. {h} x {y} = {v} {second}.",
                hint = "Each {firstOne} needs {y} {second}. How many {firstMany} are there?",
                praise = "Multiplying for each {firstOne} kept the recipe in proportion.",
                step = "Count by {y}s, once for each of the {h} {firstMany}.",
                whys = { added = "That adds {d} to {h}. Each {firstOne} needs {y} {second}, so multiply: {h} x {y}." },
                wrong = "{choice} is close. Each {firstOne} needs {y} {second}: count by {y}s, {h} times.",
            },
        },
        explain = "{have} make {m} groups of {x}. Each group needs {y} {second}, so {m} x {y} = {v}.",
        expr = "{h} / {x} x {y}",
        hint = "How many groups of {x} are in {h}? Each group needs {y} {second}.",
        praise = "Scaling up group by group kept the recipe in proportion.",
        prompts = { "{sentence} If there are {have}, how many {second} are needed?" },
        step = "{h} / {x} = {m}, so there are {m} groups of {x}.",
        whys = {
            added = "That adds {d}, the gap between {x} and {y}. A recipe grows by groups, not by adding the same amount.",
            multiplied = "That's {h} x {y}. {h} is {m} groups of {x}, so it takes {m} groups of {y}.",
        },
        wrong = "{choice} is close. Find how many groups of {x} are in {h}, then take that many groups of {y}.",
    },
    ratioPart = {
        explain = "Each group has {x} + {y} = {xy}. {t} / {xy} = {m} groups, and {m} x {y} = {v} {second}.",
        expr = "{t} / ({x} + {y}) x {y}",
        hint = "Each group has {x} {first} and {y} {second}. How many groups make {t}?",
        praise = "Finding the groups first, then the {second} in them, worked.",
        prompts = { "At the fair, there are {x} {first} for every {y} {second}. There are {t} in all. How many are {second}?" },
        step = "Each group has {x} + {y} = {xy}. {t} / {xy} = {m} groups.",
        whys = {
            groups = "That's how many groups there are. Each group has {y} {second}.",
            other = "That's how many {first} there are. The riddle asks about the {second}.",
            takeAway = "That takes {y} from {t}. Ratios work by groups: count how many groups of {xy} make {t}.",
        },
        wrong = "{choice} is close. Find how many groups of {xy} make {t}, then count the {second}.",
    },
    remainder = {
        explain = "{b} x {v} = {bv}, and {a} - {bv} = {r}. {r} is less than {b}, so no more groups fit: {v}, with {r} left over.",
        hint = "How many groups of {b} fit into {a}? Whatever is left is the remainder.",
        praise = "Finding the biggest fact that fits made it work.",
        prompts = {
            "{a} arrows go into quivers that hold {b} each. How many quivers can be filled, and how many arrows are left over?",
            "{Hero} packs {a} cookies into boxes of {b}. How many boxes get filled, and how many cookies are left over?",
            "What is {a} divided by {b}? Find how many groups of {b}, and how many are left over.",
        },
        step = "Find the biggest {b} times fact that fits in {a}: {b} x {q1} = {bq} is too many.",
        whys = {
            leftovers = "That counts what's left over as more groups. Fewer than {b} can't make a group, so they stay left over.",
            over = "That goes past {a}. Use the biggest {b} times fact that stays at or under {a}.",
            roundedUp = "That rounds up to one more full group, but the last group isn't full.",
            short = "That leaves {left}, enough for another group of {b}. What's left over has to be less than {b}.",
            shortTwo = "That leaves {left}, enough for two more groups of {b}.",
            swapped = "That swaps the two numbers. The groups come first, then what's left over.",
        },
    },
    share = {
        explain = "{t} / {n} = {q} gears each, and {q} + {e} = {v} gears each.",
        expr = "{t} / {n} + {e}",
        hint = "Do it in two steps: first share the gears equally.",
        praise = "Sharing first, then adding the extra, worked.",
        prompts = { "{n} gnomes share {t} gears equally. Then each gnome finds {e} more gears. How many gears does each gnome have now?" },
        step = "First share: {t} / {n} = {q} gears each.",
        whys = {
            notShared = "That adds {e} to all {t} gears. Share them first: {t} / {n}.",
            shareOnly = "That's each gnome's share before they find more. Add the {e} more.",
        },
        wrong = "{choice} is close. Share {t} gears among {n} gnomes, then add {e}.",
    },
    skip = {
        cases = {
            back = {
                explain = "Each number is {n} less than the one before, so {last} - {n} = {v}.",
                expr = "{start} - 4 x {n}",
                prompts = { "Count back by {n}s:\n{shown}, __\nWhat number comes next?" },
                step = "The last number is {last}. Take one more jump back, the same size as the others.",
                whys = {
                    ones = "That's {last} - 1, counting back by ones. This pattern jumps back by {n}s.",
                    twice = "That jumps back {n} two times. Only one more jump comes next.",
                },
                wrong = "{choice} is close. Find the jump back, then take it once from {last}.",
            },
        },
        explain = "Each number is {n} more than the one before, so {last} + {n} = {v}.",
        expr = "{start} + 4 x {n}",
        hint = "How much does each number change? Do that one more time.",
        praise = "Finding the jump, then taking one more, worked.",
        prompts = {
            "Hop along with the frog! It jumps by {n}s:\n{shown}, __\nWhat number comes next?",
            "The gnome's gear clock clicks by {n}s:\n{shown}, __\nWhat number comes next?",
            "Count by {n}s:\n{shown}, __\nWhat number comes next?",
        },
        step = "The last number is {last}. Jump {n} more from there.",
        whys = {
            ones = "That's {last} + 1, counting by ones. This pattern jumps by {n}s.",
            twice = "That jumps {n} two times. Only one more jump comes next.",
        },
        wrong = "{choice} is close. Find the jump, then take it once from {last}.",
    },
    subtractBig = {
        cases = {
            trade = {
                explain = "{oa} ones is less than {ob}, so trade a ten for ten ones: {oa} becomes {oa10}. Ones: {oa10} - {ob} = {od}. Tens: {ta1} - {tb} = {td}. So {a} - {b} = {v}.",
                hint = "Subtract the ones first. There aren't enough ones, so trade a ten for ten ones.",
                praise = "Trading a ten for ten ones made it work.",
                step = "There aren't enough ones, so trade a ten for ten ones: {oa} ones become {oa10}.",
                whys = {
                    noTrade = "That takes {oa} from {ob}, the smaller from the bigger. The top number has only {oa} ones, so trade a ten first.",
                },
                wrong = "{choice} is close. Trade a ten for ten ones, then take away the ones and the tens.",
            },
        },
        explain = "Ones: {oa} - {ob} = {od}. Tens: {ta} - {tb} = {td}. So {a} - {b} = {v}.",
        expr = "{a} - {b}",
        hint = "Subtract the ones first, then the tens.",
        praise = "Ones first, then tens: that kept it tidy.",
        prompts = {
            "{Hero} has {A}. {hero} sells {B} at the market in {place}. How many {items} are left?",
            "What is {a} - {b}?",
            "A wagon carries {A}. A bump in the road knocks off {B}. How many {items} are still on the wagon?",
        },
        step = "Ones first: {oa} - {ob} = {od}.",
        whys = { added = "That's {a} + {b}, adding. Taking away leaves less than {a}." },
        wrong = "{choice} is close. Take away the ones, then the tens.",
    },
    subtractSmall = {
        cases = {
            think = {
                explain = "Think addition: {b} + {v} = {a}. So {a} - {b} = {v}.",
                hint = "Think addition: {b} plus what makes {a}?",
                praise = "Turning it into addition worked.",
                step = "Start at {b} and count up to {a}. Counting up to the next ten first can help.",
                whys = { start = "That's what you get if you count {b} too. Start with the number just after {b}." },
                wrong = "{choice} is close. Think: {b} plus what makes {a}?",
            },
            up = {
                explain = "Count up from {b} to {a}: {counts}. That's {v} more, so {a} - {b} = {v}.",
                hint = "{b} and {a} are close together. Start at {b} and count up to {a}.",
                praise = "Counting up from {b} to {a} was quick.",
                step = "Start at {b} and count up to {a}, one finger for each number you say.",
                whys = { start = "That's what you get if you count {b} too. Start with the number just after {b}." },
                wrong = "{choice} is close. Count up from {b} to {a}, one finger for each number.",
            },
        },
        explain = "Start at {a} and count back {b}: {counts}. So {a} - {b} = {v}.",
        expr = "{a} - {b}",
        hint = "Start at {a} and count back {b}.",
        praise = "Counting back one at a time found it.",
        prompts = {
            "{Hero} has {A}. {hero} gives {b} of them to a friend. How many {items} are left?",
            "A basket holds {A}. A grumpy murloc grabs {b} of them and waddles away. How many {items} are left?",
            "What is {a} - {b}?",
            "In {place}, {Hero} finds {A}. {hero} shares {b} of them with a hungry gnome. How many {items} are left?",
        },
        step = "Hold up {b} on your fingers. Start at {a}, and count back one number for each finger.",
        whys = {
            added = "That's {a} + {b}, adding. Taking away leaves fewer than {a}.",
            start = "That's what you get if you say {a} as you start counting back. Start with the number just before {a}.",
        },
        wrong = "{choice} is close. Count back {b} from {a}, one number at a time.",
    },
}
