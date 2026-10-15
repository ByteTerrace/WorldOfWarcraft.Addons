// The clones verb's own tests (tools/lib/clones.mjs): renamed and verbatim copies cluster, a
// cloned function's inner blocks don't count again, blocks copied between different functions do,
// light bodies don't, and the output is ordered.

import { findClones } from "../tools/lib/clones.mjs";
import { assert, tlk } from "../tools/lib/test-support.mjs";

const lua = (...lines) => `${lines.join("\n")}\n`;

const Body = (name, item, count) => lua(
    `local function ${name}(list)`,
    "    local total = 0",
    "    for _, entry in ipairs(list) do",
    `        if entry.kind == "${item}" then total = total + entry.count * ${count} end`,
    "    end",
    "    return total",
    "end",
);

export const tests = [
    {
        name: "clones cluster copies with renamed names and changed constants, and count the verbatim ones",
        run: () => {
            const clusters = findClones([
                { path: "b.lua", text: Body("Weigh", "ore", 2) + Body("Count", "herb", 3) },
                { path: "a.lua", text: Body("Weigh", "ore", 2) },
            ], { minTokens: 10 });
            assert(clusters.length === 1, JSON.stringify(clusters));
            const [found] = clusters;
            assert(found.members.map((member) => `${member.path}:${member.start} ${member.name}`).join(", ") === "a.lua:1 Weigh, b.lua:1 Weigh, b.lua:8 Count",
                JSON.stringify(found.members));
            assert(found.exact === 2, `exact ${found.exact}`);
        },
    },
    {
        name: "clones report a block copied between different functions, but not the inner blocks of a cloned function",
        run: () => {
            const block = ["    if ready then", "        Open(frame)", "        Fill(frame, rows)", "        Place(frame)", "        frame:Show()", "    end"];
            const clusters = findClones([{
                path: "a.lua",
                text: lua("local function First(frame, rows)", "    Prepare()", ...block, "end", "", "local function Second(frame, rows)", "    Tidy(1, 2, 3)", ...block, "end"),
            }], { minTokens: 10, minStatements: 4 });
            assert(clusters.length === 1 && clusters[0].members.every((member) => member.kind === "block"), JSON.stringify(clusters));
            const units = findClones([{ path: "a.lua", text: Body("A", "x", 1) + Body("B", "y", 2) }], { minTokens: 10, minStatements: 1 });
            assert(units.length === 1 && units[0].members.every((member) => member.kind === "unit"), JSON.stringify(units));
        },
    },
    {
        name: "clones ignore bodies lighter than min-tokens",
        run: () => {
            const clusters = findClones([{ path: "a.lua", text: Body("A", "x", 1) + Body("B", "y", 2) }], { minTokens: 500 });
            assert(clusters.length === 0, JSON.stringify(clusters));
        },
    },
    {
        name: "the clones verb refuses a threshold that isn't a whole number",
        run: () => {
            const result = tlk(["clones", "--min-tokens", "lots"]);
            assert(result.status === 2 && result.stderr.includes("whole number"), `${result.status} ${result.stderr}`);
        },
    },
];
