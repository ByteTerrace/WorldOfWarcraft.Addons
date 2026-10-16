local addonName, ns = ...

-- The text and word banks of ScholarNumbers.lua's riddles (place value, telling time, the number line, and math from
-- the player's quests), as ns.ScholarNumberWords: ScholarNumbers.lua reads it. This file only holds data. Everything is
-- original, kid-friendly plain ASCII. The titles live with the others in ScholarWords.lua.
--
-- A text has ScholarMathWords' shape: the riddle's variables fill {name}. In word problems, a number {a} also comes
-- counted with an item as {A}, plus {Hero}, {hero}, {place}, and {items}. expr is the calculation behind the answer,
-- hint the strategy, step a worked first step (never the answer), explain the working, praise the strategy, whys what
-- mistake each named wrong answer comes from, wrong the why for any other ({choice} names it), and cases the variants a
-- generator picks by what the numbers need.
--
-- Hints and steps name only numbers the riddle shows or numbers that can't be the answer, so the giveaway check in
-- ScholarPuzzles.lua keeps them. A clock time in a text is the answer's {clock} only in an explanation.

ns.ScholarNumberWords = {
    -- Place value.
    build = {
        cases = {
            hundreds = {
                explain = "{hundredsWord} is {hv}, {tensWord} is {tv} and {onesWord} is {o}: {hv} + {tv} + {o} = {v}.",
                expr = "{hd} x 100 + {td} x 10 + {o}",
                hint = "Hundreds go on the left, then tens, then ones, whatever order they're said in.",
                step = "{hundredsWord} is {hv}, and {tensWord} is {tv}.",
            },
            zero = {
                explain = "{hundredsWord} is {hv}, there are no tens, and {onesWord} is {o}: {hv} + {o} = {v}. The 0 holds the tens place.",
                expr = "{hd} x 100 + {o}",
                praise = "Holding the empty tens place with a 0 built the number.",
                step = "{hundredsWord} is {hv}. There are no tens, so a 0 holds the tens place.",
                whys = { zero = "That leaves out the tens place. With no tens, a 0 has to hold it." },
            },
        },
        explain = "{tensWord} is {tv}, and {onesWord} is {o}: {tv} + {o} = {v}.",
        expr = "{td} x 10 + {o}",
        hint = "Tens go on the left and ones on the right, whatever order they're said in.",
        praise = "Putting each digit in its own place built the number.",
        prompts = { "What number is {said}?", "A gnome's counting machine shows {said}. What number is that?" },
        step = "{tensWord} is {tv}.",
        whys = {
            added = "That adds the digits. Each digit is worth more than that in its place.",
            said = "That writes the digits in the order they were said. Put each one in its own place instead.",
            swapped = "That puts the ones on the left. The biggest place goes on the left, and the ones on the right.",
            written = "That writes {tv} and then {o} side by side, but {tv} + {o} is a two-digit number.",
        },
        wrong = "{choice} isn't it. Put each digit in its own place: ones on the right.",
    },
    -- The number line. {t} is the number to get close to, and {listed} each choice's distance from it.
    closest = {
        explain = "From {t}: {listed}. The closest is {v}, only {gap} away.",
        expr = "{t} {sign} {gap}",
        hint = "How far is each number from {t}? Measure the distance, not the digits.",
        praise = "Measuring each distance from {t} found the closest.",
        prompts = {
            "Which number is closest to {t} on the number line?",
            "Four gnomes guessed how many gears are in a jar. There are {t}. Which guess is closest?",
            "{Hero} stops at mile {t} on the road from {place}. The camps are at these miles. Which camp is closest?",
        },
        step = "Find each number's distance from {t}: {x} is {dx} away.",
        whys = {
            digits = "{choice} starts with the same digit as {t}, but it's {dist} away. Measure the distance, not the digits.",
            far = "{choice} is {dist} away from {t}. Look for one that's closer.",
        },
    },
    digitWorth = {
        explain = "{expanded}. The {d} is in the {placeName} place, so it's worth {worth}: {v}.",
        expr = "{d} x {unit}",
        hint = "Name the places from the right: ones, tens, hundreds, thousands. Which place is the {d} in?",
        praise = "Finding the digit's place told you what it's worth.",
        prompts = {
            "What is the {d} worth in {n}?",
            "A gnome's gear counter reads {n}. What is the {d} in it worth?",
            "{Hero} counts {N} in {place}. In the number {n}, what is the {d} worth?",
        },
        step = "Count the places from the right: {walk}. The {d} is in the {placeName} place.",
        whys = {
            face = "That's the digit by itself. A digit's worth depends on its place in the number.",
            other = "That's what the {other} is worth. This riddle asks about the {d}.",
            place = "That's what a {d} would be worth one place over. Count the places from the right again.",
        },
        wrong = "{choice} isn't it. Find the {d}'s place, then think how many of that place it makes.",
    },
    -- Times-of-day riddles' places: dungeons a group runs, and rides that leave on time.
    dungeons = { "the Deadmines", "Ragefire Chasm", "Wailing Caverns", "Shadowfang Keep", "the Stockade", "Blackfathom Deeps" },
    -- A spot a fraction of the way along: {frac} names the fraction, {j} its equal parts, and {k} how many of them.
    fraction = {
        cases = {
            unit = {
                explain = "Going {frac} of the way means splitting {e} into {j} equal parts and going one part: {e} / {j} = {v}.",
                step = "Split {e} into {j} equal parts: what number times {j} makes {e}?",
            },
        },
        explain = "Going {frac} of the way means splitting {e} into {j} equal parts and going {k} of them: {e} / {j} = {s}, and {k} x {s} = {v}.",
        expr = "{e} / {j} x {k}",
        hint = "Split the line from 0 to {e} into equal parts, then count the parts.",
        praise = "Splitting the line into equal parts found the spot.",
        prompts = {
            "A flag sits {frac} of the way from 0 to {e} on the number line. What number is it on?",
            "{Hero} rides {frac} of the way along a road of {e} miles. How many miles has {hero} gone?",
        },
        step = "Split {e} into {j} equal parts: {e} / {j} = {s}.",
        whys = {
            onePart = "That's just one part. Going {frac} of the way takes {k} of those parts.",
            otherEnd = "That's {frac} of the way back from {e}, the other end. Start from 0.",
            parts = "That's how many equal parts the line is split into, not how far along the spot is.",
            top = "That's the {k} from {frac}: how many parts, not how far they reach.",
        },
        wrong = "{choice} isn't it. Split 0 to {e} into equal parts, then count the parts.",
    },
    halfway = {
        explain = "The gap from {lo} to {hi} is {gap}, and half of {gap} is {half}. {lo} + {half} = {v}, and {v} + {half} = {hi}.",
        expr = "({lo} + {hi}) / 2",
        hint = "Halfway is just as far from both ends. Find the gap, then go half of it from {lo}.",
        praise = "Halving the gap and counting on from {lo} found the middle.",
        prompts = {
            "Which number is halfway between {lo} and {hi}?",
            "{Hero} walks the road from mile {lo} to mile {hi}. At which mile is {hero} halfway?",
            "A gnome's rope stretches from {lo} to {hi} on the number line. What number is its middle?",
        },
        step = "The gap from {lo} to {hi} is {hi} - {lo} = {gap}.",
        whys = {
            gap = "That's the gap between {lo} and {hi}. Halfway is half that gap past {lo}.",
            half = "That's half the gap. Start at {lo} and go that far.",
            sum = "That's {lo} + {hi}. Halfway is half of that.",
        },
        wrong = "{choice} isn't the middle. Halfway is just as far from {lo} as from {hi}.",
    },
    -- A star on a line of equal jumps from 0 to {e}: {row} is the line as text, {j} its jumps, and {k} the star's.
    mark = {
        explain = "From 0 to {e} is {j} equal jumps, so each jump is {e} / {j} = {s}. The star is {k} jumps from 0: {k} x {s} = {v}.",
        expr = "{e} / {j} x {k}",
        hint = "Count the jumps from 0 to {e} to find how big each one is. Then count the jumps to the star.",
        praise = "Finding the size of a jump, then counting jumps, read the line.",
        prompts = {
            "The jumps on this number line are all the same size:\n{row}\nWhat number is the star on?",
            "A gnome marked a spot on the number line:\n{row}\nThe jumps are equal. What number is the star on?",
        },
        step = "There are {j} jumps from 0 to {e}, so each jump is {e} / {j} = {s}.",
        whys = {
            otherEnd = "That counts from the {e} end. Count the jumps from 0.",
            tens = "That counts by tens, but these jumps aren't tens. Find how much one jump is worth first.",
            ticks = "That counts the jumps, not what they're worth. Each jump here is worth more than 1.",
            zeroTick = "That counts the tick at 0 as a jump. Start at 0, and count the jumps after it.",
        },
        wrong = "{choice} isn't it. Find how much one jump is worth, then count the jumps to the star.",
    },
    -- Math from the player's quests. {ask}, {so}, and {list} are filled in from the quest book first: who wants how
    -- many of what. The stock cases tell the same riddles about a stock hero, giver, and item.
    questAsks = {
        foe = {
            giver = "Your quest book says {giver} wants {r} {objective} defeated",
            title = "Your quest \"{title}\" asks you to defeat {r} {objective}",
        },
        item = { giver = "Your quest book says {giver} wants {r} {objective}", title = "Your quest \"{title}\" asks for {r} {objective}" },
    },
    questBook = {
        explain = "{n} - {t} = {v}. Check: {t} + {v} = {n}.",
        expr = "{n} - {t}",
        hint = "Take the quests you turned in away from all the quests.",
        praise = "Taking away the finished quests found what's left.",
        prompt = "Your quest book holds {n} quests, and you've turned in {t} of them. How many are still to turn in?",
        step = "Think addition: {t} plus what makes {n}?",
        whys = {
            added = "That adds the two numbers. Turning in quests leaves fewer to do.",
            all = "That's all the quests, but {t} are turned in already.",
            turned = "That's how many you turned in. How many are left?",
        },
        wrong = "{choice} isn't it. Take {t} away from {n}.",
    },
    questLists = {
        foe = "Your quest book asks you to defeat {r1} {obj1} and {r2} {obj2}",
        item = "Your quest book asks for {r1} {obj1} and {r2} {obj2}",
    },
    questMore = {
        cases = {
            stock = {
                prompts = { "{Hero} has a quest: {giver} wants {r} {objective}. {hero} has {h} so far. How many more does {hero} need?" },
            },
        },
        explain = "Count up from {h} to {r}: that's {v} more. Check: {h} + {v} = {r}.",
        expr = "{r} - {h}",
        hint = "Start at {h} and count up to {r}.",
        praise = "Counting up from what's done to what the quest wants found it.",
        prompts = { "{ask}. {so}. How many more?" },
        step = "Count up from {h}: {h1} is one more. Keep going until you reach {r}.",
        whys = {
            added = "That adds {h} and {r}. With {h} done already, fewer than {r} are needed.",
            goal = "That's all {r} the quest wants. Take away the {h} done already.",
            have = "That's how many are done so far. How many more make {r}?",
        },
        wrong = "{choice} isn't it. Count up from {h} to {r}.",
    },
    questSell = {
        cases = {
            purse = {
                explain = "{r} x {p} = {np} copper from the vendor, and {mine} + {np} = {v} copper.",
                expr = "{mine} + {r} x {p}",
                praise = "Finding the vendor's copper first, then adding your own, worked.",
                prompts = {
                    "You have {mine} copper. A vendor pays {p} copper for each {objective}, and you sell {r}. How much copper do you have then?",
                },
                step = "First find what the vendor pays: one is {p} copper, two are {p2}. Keep counting by {p}s.",
                whys = {
                    allAdded = "That adds all three numbers. The vendor pays {p} for each of {r}: that's {r} groups of {p}.",
                    sales = "That's what the vendor pays. Add the {mine} copper you had.",
                },
            },
            stock = {
                prompts = { "{Hero} gathers {r} {objective} for {giver}. A vendor pays {p} copper for each one. How much copper would all {r} bring?" },
            },
        },
        explain = "{r} x {p} = {v}: {r} groups of {p} copper make {v} copper.",
        expr = "{r} x {p}",
        hint = "Each one brings {p} copper, so {r} of them make {r} groups of {p}.",
        praise = "Seeing the sale as groups of {p} found it.",
        prompts = { "Your quest asks for {r} {objective}. A vendor pays {p} copper for each one. How much copper would all {r} bring?" },
        step = "One brings {p} copper, and two bring {p2}. Keep counting by {p}s.",
        whys = {
            added = "That adds {r} and {p}. Each one brings {p}, so it's {r} groups of {p}.",
            fewer = "That's one group of {p} too few.",
            more = "That's one group of {p} too many.",
        },
        wrong = "{choice} isn't it. Count by {p}s, once for each of the {r}.",
    },
    questTotal = {
        cases = {
            carry = {
                step = "Ones first: {oa} + {ob} = {ones}. Write {od} and carry the 1 ten.",
                whys = { carry = "That's what you get without the carry. The ones make ten or more, so 1 ten moves over." },
            },
            small = { step = "Say {big}, then count on {small} more: {big1} is one more." },
            stock = {
                prompts = { "{Hero} has two quests: {g1} wants {r1} {obj1}, and {g2} wants {r2} {obj2}. How many things is that in all?" },
            },
        },
        explain = "{r1} + {r2} = {v}, so that's {v} {noun} in all.",
        expr = "{r1} + {r2}",
        hint = "In all means add the two counts together.",
        praise = "Adding both counts found the total.",
        prompts = { "{list}. How many {noun} is that in all?" },
        step = "Ones first: {oa} + {ob} = {ones}.",
        whys = {
            one = "That's only one of the two counts. In all means both of them.",
            takeAway = "That's the difference between the two counts. In all means add them.",
        },
        wrong = "{choice} isn't it. Add the two counts.",
    },
    rides = {
        "The boat from Booty Bay to Ratchet", "The boat from Menethil Harbor to Theramore",
        "The boat from Auberdine to Menethil Harbor", "The zeppelin from Orgrimmar to Undercity",
        "The zeppelin from Orgrimmar to Grom'gol", "The tram from Stormwind to Ironforge",
    },
    -- {s} is 10 or 100. {placeWord} names the digit it changes, {bigWord} the place past it, and {nextWord} the place a
    -- carry or trade reaches.
    tenMore = {
        cases = {
            less = {
                explain = "{s} less than {n} takes one from the {placeWord} digit: {n} - {s} = {v}. The other digits stay the same.",
                expr = "{n} - {s}",
                hint = "{s} less changes the {placeWord} digit by one. The other digits stay the same.",
                praise = "Taking one from the {placeWord} digit found it.",
                prompts = {
                    "What is {s} less than {n}?",
                    "{Hero} has {N} and gives {s} of them to a friend. How many {items} are left?",
                },
                step = "The {placeWord} digit of {n} is {pd}. {s} less makes it one smaller.",
                whys = {
                    big = "That changes the {bigWord} digit: it's {big} less. {s} less changes the {placeWord} digit.",
                    one = "That's one less: it changed the ones digit. {s} less changes the {placeWord} digit.",
                    opposite = "That's {s} more. The riddle asks for {s} less.",
                },
                wrong = "{choice} isn't it. Take one from the {placeWord} digit and keep the rest.",
            },
            lessCross = {
                explain = "{n} - {s} = {v}. The {placeWord} digit of {n} is 0, so one of the {nextWord} becomes ten {placeWord}, and one of those goes.",
                praise = "Trading for ten {placeWord} made room to take one away.",
                step = "The {placeWord} digit of {n} is 0, so trade one of the {nextWord} for ten {placeWord} first.",
            },
            moreCross = {
                explain = "{n} + {s} = {v}. The 9 {placeWord} and one more make ten {placeWord}, which carries 1 into the {nextWord}.",
                praise = "Carrying ten {placeWord} into the {nextWord} found it.",
                step = "The {placeWord} digit of {n} is 9. One more makes ten {placeWord}, and ten {placeWord} carry into the {nextWord}.",
            },
        },
        explain = "{s} more than {n} adds one to the {placeWord} digit: {n} + {s} = {v}. The other digits stay the same.",
        expr = "{n} + {s}",
        hint = "{s} more changes the {placeWord} digit by one. The other digits stay the same.",
        praise = "Changing just the {placeWord} digit found it.",
        prompts = { "What is {s} more than {n}?", "{Hero} has {N} and finds {s} more. How many {items} is that?" },
        step = "The {placeWord} digit of {n} is {pd}. {s} more makes it one bigger.",
        whys = {
            big = "That changes the {bigWord} digit: it's {big} more. {s} more changes the {placeWord} digit.",
            one = "That's one more: it changed the ones digit. {s} more changes the {placeWord} digit.",
            opposite = "That's {s} less. The riddle asks for {s} more.",
        },
        wrong = "{choice} isn't it. Change only the {placeWord} digit, by one.",
    },
    tensIn = {
        cases = {
            hundreds = {
                explain = "Each hundred is ten tens, so {hundredsWord} make {ht} tens. With the other {td}, that's {ht} + {td} = {v} tens, and {o} ones left over.",
                hint = "Every hundred is ten tens. Count the tens in the hundreds, then add the other tens.",
                praise = "Turning the hundreds into tens counted every ten.",
                prompts = {
                    "How many tens are in {n} in all?",
                    "{Hero} bundles {N} in tens. How many full bundles of ten can {hero} make?",
                    "A merchant stacks {n} copper in piles of 10. How many full piles are there?",
                },
                step = "Each hundred is ten tens: {hundredsWord} make {ht} tens.",
                whys = { digit = "That's just the tens digit. The hundreds are tens too: ten tens in each hundred." },
            },
        },
        explain = "{n} = {tv} + {o}: that's {tensWord} and {onesWord}. So {n} has {tensWord}.",
        expr = "({n} - {o}) / 10",
        hint = "Each ten is a bundle of 10. How many full bundles of ten fit in {n}?",
        praise = "Splitting {n} into tens and ones counted the tens.",
        prompts = {
            "How many tens are in {n}?",
            "{Hero} bundles {N} in tens. How many full bundles of ten can {hero} make?",
            "A merchant stacks {n} copper in piles of 10. How many full piles are there?",
        },
        step = "Split {n} into tens and ones: {n} = {tv} + {o}.",
        whys = {
            ones = "That's how many ones are left over after the tens.",
            value = "That's what the tens are worth all together. The riddle asks how many tens.",
            whole = "That's the whole number. How many tens make it?",
        },
        wrong = "{choice} isn't it. Split {n} into tens and ones, and count the tens.",
    },
    -- Telling time. {h} is the hour, {h1} the hour after it, and {h0} the one before. {clock} is the answer.
    timeElapsed = {
        cases = {
            cross = {
                explain = "From {start}, {up} minutes reaches {top}. {rest} more minutes is {clock}, because {up} + {rest} = {dur}.",
                hint = "Count up to the next hour first, then add the minutes that are left.",
                praise = "Counting up to the hour, then the rest, crossed the hour cleanly.",
                step = "Count up from {start} to {top}: that's {up} minutes, and {dur} - {up} = {rest} are left.",
                whys = { hour = "That forgets the new hour. Going past :00 makes it the next hour." },
            },
        },
        explain = "Add the minutes: {m1} + {dur} = {m2}. That's still before the next hour, so it's {clock}.",
        expr = "{h} x 60 + {m1} + {dur}",
        hint = "Add the minutes to the start time. If they reach 60, that's a new hour.",
        praise = "Adding the minutes and keeping the hour found the end time.",
        prompts = {
            "A flight from {place} leaves at {start} and lasts {dur} minutes. When does it land?",
            "{ride} leaves at {start}. The trip takes {dur} minutes. When does it arrive?",
            "Your group starts {dungeon} at {start}, and the run takes {dur} minutes. When does the run end?",
        },
        step = "Add the minutes first: {m1} + {dur}.",
        whys = {
            back = "That goes back {dur} minutes. The trip ends later than it starts.",
            extraHour = "That adds an hour too, but the trip is only {dur} minutes.",
        },
        wrong = "{choice} isn't it. Count {dur} minutes forward from {start}.",
    },
    timeHands = {
        cases = {
            oclock = {
                explain = "The short hand shows the hour, {h}. The long hand on the 12 means zero minutes, a new hour. So it's {clock}.",
                hint = "The short hand tells the hour. When the long hand is on the 12, it's o'clock.",
                prompts = {
                    "The short hand points at the {h}, and the long hand points at the 12. What time is it?",
                    "{ride} leaves when the short hand points at the {h} and the long hand at the 12. What time is that?",
                },
                step = "The short hand points at the {h}, so the hour is {h}.",
                whys = { face = "That reads the 12 as 12 minutes. The long hand on the 12 means a new hour: zero minutes." },
            },
        },
        explain = "The short hand is past the {h}, so the hour is {h}. The long hand on the {n} means {n} fives: {n} x 5 = {mm} minutes. So it's {clock}.",
        expr = "{h} x 60 + {mm}",
        hint = "The short hand tells the hour. The long hand counts minutes by fives, one five for each number.",
        praise = "Reading the short hand first, then counting the long hand by fives, told the time.",
        prompts = {
            "The short hand is between the {h} and the {h1}, and the long hand points at the {n}. What time is it?",
            "On the inn's clock, the short hand is between the {h} and the {h1}, and the long hand is on the {n}. What time is it?",
        },
        step = "Count by fives from the 12, one five for each number: the 1 is 5 minutes, the 2 is 10, and on to the {n}.",
        whys = {
            face = "That reads the {n} as {n} minutes. Each number on the clock is 5 minutes, so count by fives.",
            nextHour = "The short hand hasn't reached the {h1} yet, so the hour is still {h}.",
            swapped = "That reads the long hand as the hour. The short hand tells the hour, and the long hand the minutes.",
        },
        wrong = "{choice} isn't it. Read the short hand for the hour, then count the long hand by fives.",
    },
    timeHowLong = {
        cases = {
            cross = {
                explain = "From {start} to {top} is {up} minutes, and from {top} to {stop} is {rest} more: {up} + {rest} = {v} minutes.",
                hint = "Count up to the next hour first, then on to the end time.",
                praise = "Counting up to the hour, then on to the end, measured the time.",
                step = "From {start} to {top} is {up} minutes.",
                whys = {
                    hundred = "That takes away as if an hour had 100 minutes. An hour has 60: count up to {top} first.",
                    minutesOnly = "That takes away just the minutes, but the trip goes past {top}.",
                },
            },
        },
        explain = "Both times are in the {h} o'clock hour, so take away the minutes: {m2} - {m1} = {v} minutes.",
        expr = "{h2} x 60 + {m2} - ({h} x 60 + {m1})",
        hint = "Count up from the start time to the end time.",
        praise = "Counting up from the start to the end measured the time.",
        prompts = {
            "{ride} leaves at {start} and arrives at {stop}. How long is the trip?",
            "Your group starts {dungeon} at {start} and finishes at {stop}. How long was the run?",
            "A flight leaves {place} at {start} and lands at {stop}. How long is the flight?",
        },
        step = "Take away the minutes: {m2} - {m1}.",
        whys = {
            added = "That adds the minutes. How long it takes is the gap between the two times.",
            stopOnly = "That's the minutes on the end time. Take away the start's minutes too.",
        },
        wrong = "{choice} isn't it. Count up from {start} to {stop}.",
    },
    -- Times said in words: {said} is the phrase ("quarter to 5"), {m} its minutes past the hour, and {k} the minutes to
    -- the next one.
    timeWords = {
        cases = {
            half = {
                explain = "Half past {h} is half an hour after {h} o'clock, and half of 60 minutes is 30. So it's {clock}.",
                hint = "Half past means half an hour after the hour, and an hour has 60 minutes.",
                step = "Half of 60 minutes is 60 / 2 = 30, so the minutes are :30.",
                whys = {
                    decimal = "That reads half as 50, like half of 100 copper. An hour has 60 minutes, not 100.",
                    nextHour = "That's half past {h1}, an hour later.",
                    prevHour = "That's half past {h0}, an hour sooner.",
                },
            },
            past = {
                explain = "{m} minutes past {h} is {m} minutes after {h}:00, so it's {clock}.",
                hint = "Past means after the hour: the minutes count up from {h}:00.",
                step = "Start at {h}:00 and count {m} minutes forward, by fives.",
                whys = { toNotPast = "That's {m} minutes to {h}, before {h} o'clock. Past means after." },
            },
            quarterPast = {
                explain = "A quarter of an hour is 60 / 4 = 15 minutes, and past means after: 15 minutes after {h}:00 is {clock}.",
                hint = "A quarter of an hour is a quarter of 60 minutes. Past means after the hour.",
                step = "A quarter of 60 minutes: 60 / 4 = 15.",
                whys = {
                    decimal = "That reads a quarter as 25, like a quarter of 100 copper. A quarter of an hour is a quarter of 60 minutes.",
                    threeQuarters = "That's three quarters past {h}. A quarter past is just one quarter.",
                    toNotPast = "That's quarter to {h}, before {h} o'clock. Past means after.",
                },
            },
            quarterTo = {
                explain = "Quarter to {h1} is 15 minutes before {h1}:00. 60 - 15 = 45, so it's 45 minutes past {h}: {clock}.",
                hint = "Quarter to means 15 minutes before the hour, so it's still the hour before.",
                step = "Count back 15 minutes from {h1}:00. Before {h1} o'clock, it's still the {h} o'clock hour.",
                whys = {
                    keptHour = "That keeps {h1} as the hour. Quarter to {h1} comes before {h1} o'clock, so the hour is still {h}.",
                    pastNotTo = "That's quarter past {h1}, after it. Quarter to means before.",
                },
            },
            to = {
                explain = "{k} minutes to {h1} is {k} minutes before {h1}:00. 60 - {k} = {m}, so it's {m} minutes past {h}: {clock}.",
                hint = "To means before the hour, so it's still the hour before.",
                step = "Count back {k} minutes from {h1}:00: 60 - {k} = {m} minutes past the hour before.",
                whys = {
                    keptHour = "That keeps {h1} as the hour, but {k} minutes to {h1} comes before {h1} o'clock.",
                    pastNotTo = "That's {k} minutes past {h1}, after it. To means before.",
                    saidMinutes = "That puts the {k} in the minutes, but {k} to means {k} before the hour: count back from {h1}:00.",
                },
            },
        },
        expr = "{h} x 60 + {m}",
        praise = "Turning the words into an hour and minutes read the time.",
        prompts = {
            "The Owl Sage says it's {said}. What time is that on a clock?",
            "{ride} leaves at {said}. What time is that?",
            "Your group meets outside {dungeon} at {said}. What time is that?",
        },
        wrong = "{choice} isn't {said}. Find the hour first, then the minutes.",
    },
}
