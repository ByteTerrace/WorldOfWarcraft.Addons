// The format verb's own tests (tools/lib/format-lua.mjs, tools/verbs/format.mjs): each pass's
// rewrite, what each declines, the fixed point, and the verb's --check and write modes. The
// repository's own files are held to it by check's FORMAT rule.

import { readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { FormatError, PASSES, formatLua, orderFindings } from "../tools/lib/format-lua.mjs";
import { assert, withTemp } from "../tools/lib/test-support.mjs";
import { formatRepository } from "../tools/verbs/format.mjs";

const lua = (...lines) => `${lines.join("\n")}\n`;

// Formats source with the given passes (all by default) and compares with expected.
function formats(source, expected, passes = PASSES) {
    const actual = formatLua(source, passes);
    assert(actual === expected, `expected:\n${expected}\nactual:\n${actual}`);
    assert(formatLua(actual, passes) === actual, `not a fixed point:\n${actual}`);
}

export const tests = [
    {
        name: "format parenthesizes binary and logical expressions except where something delimits them",
        run: () => {
            formats(lua(
                "local visible = UnitPowerType(\"player\") == Energy",
                "local color = PowerBarColor and PowerBarColor.ENERGY or { r = 1 }",
                "local total = a + b + c",
                "if a == nil or a == \"ENERGY\" then return a .. b .. c end",
                "while i < n and i > 0 and ok do i = i - 1 end",
                "print(a + b, t[i + 1], not (a and b), -x, #list)",
                "for i = 1, n - 1 do end",
                "local kept = (a + b) * 2",
            ), lua(
                "local visible = (UnitPowerType(\"player\") == Energy)",
                "local color = ((PowerBarColor and PowerBarColor.ENERGY) or { r = 1 })",
                "local total = ((a + b) + c)",
                "if (a == nil) or (a == \"ENERGY\") then return (a .. b .. c) end",
                "while (i < n) and (i > 0) and ok do i = (i - 1) end",
                "print(a + b, t[i + 1], not (a and b), -x, #list)",
                "for i = 1, n - 1 do end",
                "local kept = ((a + b) * 2)",
            ), ["paren-clarity"]);
        },
    },
    {
        name: "format sorts a table constructor's named fields alphabetically, ignoring case, when no value has a side effect",
        run: () => {
            formats(lua(
                "local insets = { left = 4, right = 4, top = 4, bottom = 4 }",
                "local spec = { label = \"x\", OnEnable = function() end, commands = {} }",
                "local called = { b = Next(), a = 1 }",
                "local mixed = { b = 1, \"two\", a = 3 }",
                "local twice = { b = 1, a = 2, b = 3 }",
                "local nested = { z = { y = 1, x = 2 }, a = 0 }",
            ), lua(
                "local insets = { bottom = 4, left = 4, right = 4, top = 4 }",
                "local spec = { commands = {}, label = \"x\", OnEnable = function() end }",
                "local called = { b = Next(), a = 1 }",
                "local mixed = { b = 1, \"two\", a = 3 }",
                "local twice = { b = 1, a = 2, b = 3 }",
                "local nested = { a = 0, z = { x = 2, y = 1 } }",
            ), ["init-order"]);
        },
    },
    {
        // A comment between fields would end up describing whichever field moved under it.
        name: "format moves a field's comment lines with it, and leaves a constructor with any other comment between fields as written",
        run: () => {
            formats(lua("local t = {", "    -- the second", "    b = 2,", "    a = 1,", "}"),
                lua("local t = {", "    a = 1,", "    -- the second", "    b = 2,", "}"), ["init-order"]);
            const packed = lua("local t = { b = 2, -- after b", "    a = 1 }");
            formats(packed, packed, ["init-order"]);
            formats(lua("local t = {", "    b = function()", "        -- inside a value moves with it", "    end,", "    a = 1,", "}"),
                lua("local t = {", "    a = 1,", "    b = function()", "        -- inside a value moves with it", "    end,", "}"), ["init-order"]);
        },
    },
    {
        name: "format keeps a vertical constructor one field to a line and packs a packed one up to 120 columns",
        run: () => {
            formats(lua(
                "Module(\"X\", {",
                "    label = \"X\",",
                "    OnEnable = function(module)",
                "        module:On(\"PLAYER_LOGIN\", Start)",
                "    end,",
                "    description = \"Does x.\",",
                "})",
            ), lua(
                "Module(\"X\", {",
                "    description = \"Does x.\",",
                "    label = \"X\",",
                "    OnEnable = function(module)",
                "        module:On(\"PLAYER_LOGIN\", Start)",
                "    end,",
                "})",
            ), ["init-order"]);
            formats(lua(
                "local spec = { name = \"toggle\", slash = \"fom\", label = \"Toggle the fuck-o-meter\", always = true,",
                "    run = Toggle, description = \"Shows or hides the fuck-o-meter, an obnoxiously wide bar.\" }",
            ), lua(
                "local spec = { always = true, description = \"Shows or hides the fuck-o-meter, an obnoxiously wide bar.\",",
                "    label = \"Toggle the fuck-o-meter\", name = \"toggle\", run = Toggle, slash = \"fom\" }",
            ), ["init-order"]);
        },
    },
    {
        name: "format ends a multi-line table constructor's last field with a comma",
        run: () => {
            formats(lua("local t = {", "    1,", "    2 -- the last", "}", "local u = { 1, 2 }"),
                lua("local t = {", "    1,", "    2, -- the last", "}", "local u = { 1, 2 }"), ["trailing-comma"]);
        },
    },
    {
        // A value that reads a name the run declares keeps its side of that declaration: after it
        // when it read the local, before it when it read the global of that name.
        name: "format sorts a file-level run of locals by name without changing what any value reads",
        run: () => {
            formats(lua(
                "local Height = 64",
                "local Energy = Enum.PowerType.Energy",
                "local Ease = Enum.StatusBarInterpolation.ExponentialEaseOut",
                "",
                "local Warband = ns.Warband",
                "local MyKey = Warband.MyKey",
                "local Alpha = 1",
                "",
                "local Zeta = Ceil",
                "local Ceil = 2",
                "local Beta = Rows()",
                "local Alpha2 = 1",
                "local Late = 1",
                "-- a comment line belongs to the local below it",
                "local Early = 1",
                "",
                "-- a comment of its own ends the run",
                "",
                "local Fn = function() end",
                "local Abc = 1",
            ), lua(
                "local Ease = Enum.StatusBarInterpolation.ExponentialEaseOut",
                "local Energy = Enum.PowerType.Energy",
                "local Height = 64",
                "",
                "local Alpha = 1",
                "local Warband = ns.Warband",
                "local MyKey = Warband.MyKey",
                "",
                "local Zeta = Ceil",
                "local Ceil = 2",
                "local Beta = Rows()",
                "local Alpha2 = 1",
                "-- a comment line belongs to the local below it",
                "local Early = 1",
                "local Late = 1",
                "",
                "-- a comment of its own ends the run",
                "",
                "local Fn = function() end",
                "local Abc = 1",
            ), ["local-order"]);
        },
    },
    {
        name: "format gives each name a local declares its own line, unless that would change what a value reads",
        run: () => {
            formats(lua(
                "local floor, max = math.floor, math.max",
                "local function Run()",
                "    local panel, y = Overlay.Panel, 116",
                "    local first, second",
                "end",
                "local CreateFrame, UIParent = CreateFrame, UIParent",
                "local h, addon, ns = LoadKid()",
                "local a, b = b, a",
                "local c, d = 1",
                "local e, f = 1, -- one",
                "    2",
            ), lua(
                "local floor = math.floor",
                "local max = math.max",
                "local function Run()",
                "    local panel = Overlay.Panel",
                "    local y = 116",
                "    local first",
                "    local second",
                "end",
                "local CreateFrame = CreateFrame",
                "local UIParent = UIParent",
                "local h, addon, ns = LoadKid()",
                "local a, b = b, a",
                "local c, d = 1",
                "local e, f = 1, -- one",
                "    2",
            ), ["split-locals"]);
        },
    },
    {
        name: "format puts one blank line between a run of locals and the next statement, unless a comment leads it",
        run: () => {
            formats(lua(
                "local function Run()",
                "    local a = 1",
                "    local b = 2",
                "    Use(a, b)",
                "    local c = 3",
                "",
                "",
                "    return c",
                "end",
                "local function Other()",
                "    local d = 1",
                "    -- the comment owns its placement",
                "    return d",
                "end",
                "local function Inline() local e = 1; return e end",
            ), lua(
                "local function Run()",
                "    local a = 1",
                "    local b = 2",
                "",
                "    Use(a, b)",
                "    local c = 3",
                "",
                "    return c",
                "end",
                "local function Other()",
                "    local d = 1",
                "    -- the comment owns its placement",
                "    return d",
                "end",
                "local function Inline() local e = 1; return e end",
            ), ["decl-spacing"]);
        },
    },
    {
        name: "format sets file-level functions apart with one blank line, before their leading comment",
        run: () => {
            formats(lua(
                "local Max = 1",
                "-- Says hello.",
                "local function Hello() end",
                "local function World() end",
                "",
                "",
                "",
                "Module(\"X\", {})",
            ), lua(
                "local Max = 1",
                "",
                "-- Says hello.",
                "local function Hello() end",
                "",
                "local function World() end",
                "",
                "Module(\"X\", {})",
            ), ["member-spacing"]);
        },
    },
    {
        name: "format keeps at most one blank line in a row, outside long strings",
        run: () => {
            formats(lua("", "local a = 1", "", "", "", "local b = [[", "", "", "]]"),
                lua("local a = 1", "", "local b = [[", "", "", "]]"), ["blank-lines"]);
        },
    },
    {
        name: "format merges two double-quoted literals on one line, unless that changes an escape",
        run: () => {
            formats(lua("local a = \"one \" .. \"two\"", "local b = \"\\1\" .. \"2\"", "local c = \"split \"", "    .. \"lines\""),
                lua("local a = \"one two\"", "local b = \"\\1\" .. \"2\"", "local c = \"split \"", "    .. \"lines\""), ["string-merge"]);
        },
    },
    {
        name: "format refuses source that doesn't parse",
        run: () => {
            let error;
            try {
                formatLua("local = 1\n");
            } catch (caught) {
                error = caught;
            }
            assert(error instanceof FormatError && error.message.startsWith("doesn't parse"), String(error));
        },
    },
    {
        name: "format --check names a file's first unformatted line and writes nothing; without it, the file is written byte for byte",
        run: () => withTemp((dir) => {
            const file = join(dir, "Main.lua");
            // "–" is UTF-8 in the file: it must come back as the same bytes.
            const source = lua("-- Main: a dash – here.", "", "local a = 1", "print(a == 1)");
            writeFileSync(file, source);
            const checked = formatRepository({ files: [file], check: true, root: dir });
            assert(checked.findings.length === 1 && checked.findings[0].path === "Main.lua" && checked.findings[0].line === 4,
                JSON.stringify(checked.findings));
            assert(readFileSync(file, "utf8") === source, "check wrote the file");
            const written = formatRepository({ files: [file], root: dir });
            assert(written.findings.length === 0 && written.changed.join() === "Main.lua", JSON.stringify(written));
            assert(readFileSync(file, "utf8") === lua("-- Main: a dash – here.", "", "local a = 1", "", "print(a == 1)"), readFileSync(file, "utf8"));
            assert(formatRepository({ files: [file], check: true, root: dir }).findings.length === 0, "formatted twice");
        }),
    },
    {
        name: "format moves a comment after code onto its own line above, at that line's indentation",
        run: () => {
            formats(lua("local Max = 8 -- the most at once", "local function F()", "    return 1 -- secret: widget sink", "end", "local s = [[", "a]] -- after a long string"),
                lua("-- the most at once", "local Max = 8", "local function F()", "    -- secret: widget sink", "    return 1", "end", "local s = [[",
                    "a]] -- after a long string"), ["trailing-comments"]);
        },
    },
    {
        name: "format sets blocks and multi-line statements apart with blank lines, and puts one before a return",
        run: () => {
            formats(lua(
                "local function F(a)",
                "    Prepare(a)",
                "    if a then",
                "        Use(a)",
                "        return a",
                "    end",
                "    Tidy()",
                "    -- the comment goes with what follows it",
                "    for i = 1, 2 do Use(i) end",
                "    return nil",
                "end",
            ), lua(
                "local function F(a)",
                "    Prepare(a)",
                "",
                "    if a then",
                "        Use(a)",
                "",
                "        return a",
                "    end",
                "",
                "    Tidy()",
                "",
                "    -- the comment goes with what follows it",
                "    for i = 1, 2 do Use(i) end",
                "",
                "    return nil",
                "end",
            ), ["block-spacing"]);
        },
    },
    {
        name: "format fills a prose comment paragraph up to 120 columns and leaves lists, columns and annotations alone",
        run: () => {
            const words = "word ".repeat(30).trim();
            const filled = formatLua(lua(`-- ${words}`, "-- more", "--", "--   Indented  aligned", "-- - a list item", "-- secret: why"), ["comment-fill"]);
            const lines = filled.split("\n");
            assert(lines.every((line) => line.length <= 120), filled);
            assert((lines[0].length > 110) && (lines[1] === "-- word word word word word word word more"), filled);
            assert(filled.endsWith(lua("--", "--   Indented  aligned", "-- - a list item", "-- secret: why")), filled);
            // 23 words fill 117 columns, so "10." would start the next line and read as a list item.
            const numbered = formatLua(lua(`-- ${"abcd ".repeat(23)}10. Then more.`), ["comment-fill"]);
            assert(numbered === lua(`-- ${"abcd ".repeat(22).trim()}`, "-- abcd 10. Then more."), numbered);
            const annotated = formatLua(lua(`-- ${"abcd ".repeat(21)}leaves secret: values alone.`), ["comment-fill"]);
            assert(!/\n-- secret:/.test(annotated), annotated);
        },
    },
    {
        // F reads G, so G stays before it; H read a global G2 before G2 was declared, so it stays before G2.
        name: "format sorts a file-level run of functions, locals first, never past a function whose name another reads",
        run: () => {
            formats(lua(
                "local function Zed() end",
                "",
                "--- Says hello.",
                "function M.Hello() end",
                "",
                "local function G() end",
                "",
                "local function F() return G() end",
                "",
                "local function H() return G2() end",
                "",
                "local function G2() end",
            ), lua(
                "local function G() end",
                "",
                "local function F() return G() end",
                "",
                "local function H() return G2() end",
                "",
                "local function G2() end",
                "",
                "local function Zed() end",
                "",
                "--- Says hello.",
                "function M.Hello() end",
            ), ["function-order"]);
        },
    },
    {
        name: "format sorts a run of exports by target, each statement's own pairs first",
        run: () => {
            formats(lua("Probes.Needs = Needs", "Probes.B, Probes.A = B, A", "Probes.Call = Make()", "Probes.Z = Z"),
                lua("Probes.A, Probes.B = A, B", "Probes.Needs = Needs", "Probes.Call = Make()", "Probes.Z = Z"), ["export-order"]);
        },
    },
    {
        name: "format sorts constructors whose values call something only with sortCalls, and check reports them otherwise",
        run: () => {
            const source = lua("Show({ title = Title(), body = Body() })", "-- order: the calls must run in this order", "Show({ second = Next(), first = Next() })");
            formats(source, source, ["init-order"]);
            assert(orderFindings(source).map((finding) => finding.line).join() === "1", JSON.stringify(orderFindings(source)));
            const sorted = formatLua(source, ["init-order"], { sortCalls: true });
            assert(sorted === lua("Show({ body = Body(), title = Title() })", "-- order: the calls must run in this order", "Show({ second = Next(), first = Next() })"), sorted);
            assert(orderFindings(sorted).length === 0, JSON.stringify(orderFindings(sorted)));
        },
    },
];
