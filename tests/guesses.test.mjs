// The guesses verb's own tests (tools/lib/guesses.mjs): what a marker claims, which client names a claim is about,
// how much depends on it, and the order the guesses print in.

import { findGuesses, rankGuesses } from "../tools/lib/guesses.mjs";
import { assert, tlk } from "../tools/lib/test-support.mjs";

const lua = (...lines) => `${lines.join("\n")}\n`;

const Fixture = lua(
    "-- Modeling decisions:",
    "--   Plates   [D] Documented. [G] The plate shows before NAME_PLATE_UNIT_ADDED, and",
    "--            hides after it. [E] Seen in game.",
    "-- Children come in creation order ([G] the order).",
    "-- An unknown GUID is restricted [C].",
    "",
    "local fakes = {",
    "    -- [G] Counts from 1.",
    "    GetPowerLevel = function() return 1 end,",
    "}",
    "",
    "-- The player dies. [G] PLAYER_DEAD comes while lockdown holds, then h:LeaveCombat runs.",
    "function Harness:Die()",
    "end",
);

export const tests = [
    {
        name: "guesses read a claim forward, or the sentence a parenthetical or trailing marker sits in, and skip [D] and [E]",
        run: () => {
            const guesses = findGuesses("tests/harness/x.lua", Fixture);
            const shown = guesses.map((guess) => `${guess.line} ${guess.marker} ${guess.claim}`);
            assert(shown.join(" | ") === [
                "2 G The plate shows before NAME_PLATE_UNIT_ADDED, and hides after it.",
                "4 G Children come in creation order (the order).",
                "5 C An unknown GUID is restricted.",
                "8 G Counts from 1.",
                "12 G PLAYER_DEAD comes while lockdown holds, then h:LeaveCombat runs.",
            ].join(" | "), shown.join("\n"));
            assert(guesses[3].follows === "GetPowerLevel", "a comment right above a fake names it");
            assert(guesses[4].follows === "Die", "and right above a Harness method");
            assert(guesses[0].follows === null, "a header block sits above nothing");
        },
    },
    {
        name: "guesses resolve the names a claim is about, count what depends on them, and rank by addons, then tests",
        run: () => {
            const guesses = findGuesses("tests/harness/x.lua", Fixture);
            const ranked = rankGuesses(guesses, {
                addons: [
                    { path: "A/Plates.lua", text: "self:On(\"NAME_PLATE_UNIT_ADDED\", Show)" },
                    { path: "A/Pad.lua", text: "local level = C_GamePad.GetPowerLevel()" },
                    { path: "A/Other.lua", text: "local count = table.count" },
                ],
                api: {
                    events: { NAME_PLATE_UNIT_ADDED: {}, PLAYER_DEAD: {} },
                    functions: { "C_GamePad.GetPowerLevel": {}, "table.count": {}, UnitGUID: {} },
                },
                methods: ["Die", "LeaveCombat"],
                probes: [
                    { name: "pad.power", text: "run = function() return C_GamePad.GetPowerLevel() end" },
                    { name: "plates.order", text: "NAME_PLATE_UNIT_ADDED" },
                ],
                tests: [
                    { path: "tests/a.test.lua", text: "h:Die()" },
                    { path: "tests/b.test.lua", text: "h:LeaveCombat() h:Die()" },
                ],
            });
            const byLine = Object.fromEntries(ranked.map((guess) => [guess.line, guess]));
            assert(byLine[8].names.join(",") === "C_GamePad.GetPowerLevel", "a member named alone is its namespace's: " + byLine[8].names);
            assert(byLine[8].addons.join(",") === "A/Pad.lua", byLine[8].addons.join(","));
            assert(byLine[8].related.join(",") === "pad.power", "a probe reading the same API is related");
            assert(byLine[12].names.join(",") === "PLAYER_DEAD,h:Die,h:LeaveCombat", byLine[12].names.join(","));
            assert(byLine[12].tests.join(",") === "tests/a.test.lua,tests/b.test.lua", byLine[12].tests.join(","));
            assert(byLine[2].addons.join(",") === "A/Plates.lua" && byLine[2].related.join(",") === "plates.order", JSON.stringify(byLine[2]));
            assert(byLine[4].names.length === 0, "prose isn't API: " + byLine[4].names);
            assert(ranked.map((guess) => guess.line).join(",") === "2,8,12,4,5", "addons first, then tests, then place: "
                + ranked.map((guess) => guess.line).join(","));
            const cited = rankGuesses(findGuesses("x.lua", "-- [G] As plates.order records it.\n"), {
                addons: [], api: { events: {}, functions: {} }, methods: [], probes: [{ name: "plates.order", text: "" }], tests: [],
            });
            assert(cited[0].cited.join(",") === "plates.order" && cited[0].related.length === 0, JSON.stringify(cited[0]));
        },
    },
    {
        name: "tlk guesses ranks the real harness's guesses and says how many there are",
        run: () => {
            const result = tlk(["guesses", "--top", "3"]);
            assert(result.status === 0, result.stderr);
            assert((result.stdout.match(/^tests\/harness\/\w+\.lua:\d+ \[[GC]\] /gm) ?? []).length === 3, result.stdout);
            assert(/^\d+ guesses \(\d+ \[G\], \d+ \[C\]\): \d+ about API the shipped addons use/m.test(result.stdout), result.stdout);
            assert(tlk(["guesses", "--top", "0"]).status === 2, "--top needs a count");
        },
    },
];
