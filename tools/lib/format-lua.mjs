// The format verb's rewrites: Puck's `puck format` passes, mapped to Lua (docs/Conventions.md).
// formatLua(text) runs every pass to a fixed point and returns the canonical text.
//
//   string-merge    `"a" .. "b"` of two double-quoted literals on one line becomes one literal.
//   paren-clarity   every binary and logical expression is parenthesized, except where something
//                   already delimits it: existing parentheses, an if/elseif/while/until condition, a
//                   call's arguments, an index's brackets and a numeric for's bounds. An operand of
//                   the same `and`, `or` or `..` stays bare, so a chain stays one flat group.
//   init-order      a table constructor whose every field is `name = value` is sorted by name,
//                   when no value has a side effect. Across lines, fields that each had a line
//                   keep one; packed fields are packed again, up to 120 columns.
//   trailing-comma  a multi-line table constructor's last field ends with a comma.
//   alias-order     a file-level `local a, b = x, y` with side-effect-free values is sorted by name.
//   local-order     a file-level run of `local` statements (consecutive lines, no comment lines
//                   between, no side effects, no functions) is sorted by name, never moving a statement past one
//                   whose value reads it or one that the value read as a global before.
//   decl-spacing    one blank line between a run of `local` statements and the statement after it.
//   member-spacing  one blank line between a file-level function and its neighbors.
//   blank-lines     no run of blank lines longer than one, and none at the start of the file.
//
// Like Puck's, the reordering passes decline anything a comment could be attached to: a comment
// between table fields, or a comment line inside a run of locals. A pass that changes nothing
// returns no edits; the result must parse, and running the passes again must change nothing.
// Names sort alphabetically, ignoring case (Puck's names share one case; Lua's data keys and
// handlers don't).

import luaparse from "luaparse";
import { parse, walk } from "./lua-scope.mjs";

export const PASSES = [
    "string-merge", "paren-clarity", "init-order", "trailing-comma", "alias-order", "local-order", "decl-spacing",
    "member-spacing", "blank-lines",
];

const MaxColumns = 120;
const MaxRounds = 20;

// Every token of text, with its range (luaparse's lexer; comments are skipped).
function lexTokens(text) {
    const lexer = luaparse.parse(text, { wait: true, ranges: true, luaVersion: "5.1", encodingMode: "pseudo-latin1" });
    const tokens = [];
    for (;;) {
        const token = lexer.lex();
        if (token.type === luaparse.tokenTypes.EOF) return tokens;
        tokens.push(token);
    }
}

function lineStart(text, position) {
    return text.lastIndexOf("\n", position - 1) + 1;
}

function lineEnd(text, position) {
    const end = text.indexOf("\n", position);
    return end < 0 ? text.length : end;
}

function indentOf(text, position) {
    const start = lineStart(text, position);
    return /^ */.exec(text.slice(start))[0].length;
}

function lineOf(text, position) {
    let line = 1;
    for (let i = text.indexOf("\n"); i >= 0 && i < position; i = text.indexOf("\n", i + 1)) line++;
    return line;
}

// Alphabetical: ignoring case, then ordinal, so `label` sorts before `OnEnable`.
function compareNames(a, b) {
    const left = a.toLowerCase();
    const right = b.toLowerCase();
    if (left !== right) return left < right ? -1 : 1;
    return a < b ? -1 : a > b ? 1 : 0;
}

function commentsBetween(ast, start, end) {
    return ast.comments.filter((comment) => comment.range[0] >= start && comment.range[1] <= end);
}

// Whether evaluating node can't change anything another expression could see: no calls.
function isPure(node) {
    if (!node) return true;
    switch (node.type) {
        case "StringLiteral": case "NumericLiteral": case "BooleanLiteral": case "NilLiteral": case "VarargLiteral":
        case "Identifier": case "FunctionDeclaration":
            return true;
        case "MemberExpression":
            return isPure(node.base);
        case "IndexExpression":
            return isPure(node.base) && isPure(node.index);
        case "UnaryExpression":
            return isPure(node.argument);
        case "BinaryExpression": case "LogicalExpression":
            return isPure(node.left) && isPure(node.right);
        case "TableConstructorExpression":
            return node.fields.every((field) => isPure(field.key) && isPure(field.value));
        default:
            return false;
    }
}

// The names an expression reads (not member names after `.` or `:`), function bodies included.
function namesRead(node) {
    const names = new Set();
    walk(node, (child, ancestors) => {
        const parent = ancestors[ancestors.length - 1];
        if (child.type !== "Identifier") return;
        if (parent?.type === "MemberExpression" && parent.identifier === child) return;
        if (parent?.type === "TableKeyString" && parent.key === child) return;
        names.add(child.name);
    });
    return names;
}

function hasVararg(node) {
    let found = false;
    walk(node, (child) => {
        if (child.type === "VarargLiteral") found = true;
    });
    return found;
}

// The blocks of statements in an AST, each as { body, fileLevel }.
function blocksOf(ast) {
    const blocks = [{ body: ast.body, fileLevel: true }];
    walk(ast.body, (node, ancestors) => {
        const fileLevel = ancestors.every((ancestor) => ancestor.type === "DoStatement");
        if (node.type === "DoStatement") blocks.push({ body: node.body, fileLevel });
        else if (Array.isArray(node.body) && node.type !== "Chunk") blocks.push({ body: node.body, fileLevel: false });
    });
    return blocks;
}

// The end of a statement's last line when nothing but a line comment follows it there, or -1.
function ownLineEnd(text, ast, statement) {
    const start = statement.range[0];
    if (text.slice(lineStart(text, start), start).trim() !== "") return -1;
    const end = lineEnd(text, statement.range[1]);
    const rest = text.slice(statement.range[1], end).trim();
    if (rest === "") return end;
    const trailing = ast.comments.find((comment) => comment.range[0] >= statement.range[1] && comment.range[0] < end);
    return trailing && trailing.range[1] === end && rest.startsWith("--") ? end : -1;
}

const Passes = {
    "string-merge": ({ text, ast }) => {
        const edits = [];
        walk(ast.body, (node) => {
            if (node.type !== "BinaryExpression" || node.operator !== "..") return;
            const { left, right } = node;
            if (left.type !== "StringLiteral" || right.type !== "StringLiteral") return;
            if (!left.raw.startsWith("\"") || !right.raw.startsWith("\"")) return;
            if (commentsBetween(ast, left.range[1], right.range[0]).length) return;
            // Text broken across lines stays broken: lines stay under MaxColumns.
            if (text.slice(left.range[1], right.range[0]).includes("\n")) return;
            const leftText = left.raw.slice(1, -1);
            const rightText = right.raw.slice(1, -1);
            // "\1" .. "2" isn't "\12".
            if (/\\\d{1,2}$/.test(leftText) && /^\d/.test(rightText)) return;
            edits.push({ start: left.range[0], end: right.range[1], text: `"${leftText}${rightText}"` });
        });
        return edits;
    },

    "paren-clarity": ({ text, ast, tokens }) => {
        const tokenAt = new Map();
        tokens.forEach((token, i) => tokenAt.set(token.range[0], i));
        const tokenEnding = new Map();
        tokens.forEach((token, i) => tokenEnding.set(token.range[1], i));
        const wrapped = (node) => {
            const before = tokens[tokenAt.get(node.range[0]) - 1];
            const after = tokens[tokenEnding.get(node.range[1]) + 1];
            return before?.value === "(" && after?.value === ")";
        };
        const delimited = (node, parent) => {
            if (!parent) return true;
            switch (parent.type) {
                case "IfClause": case "ElseifClause": case "WhileStatement": case "RepeatStatement":
                    return parent.condition === node;
                case "CallExpression":
                    return parent.arguments.includes(node);
                case "IndexExpression":
                    return parent.index === node;
                case "TableKey":
                    return parent.key === node;
                case "ForNumericStatement":
                    return parent.start === node || parent.end === node || parent.step === node;
                default:
                    return false;
            }
        };
        const edits = [];
        walk(ast.body, (node, ancestors) => {
            if (node.type !== "BinaryExpression" && node.type !== "LogicalExpression") return;
            const parent = ancestors[ancestors.length - 1];
            if (delimited(node, parent) || wrapped(node)) return;
            const chained = node.operator === "and" || node.operator === "or" || node.operator === "..";
            if (chained && parent.type === node.type && parent.operator === node.operator) return;
            edits.push({ start: node.range[0], end: node.range[0], text: "(" }, { start: node.range[1], end: node.range[1], text: ")" });
        });
        return edits;
    },

    "init-order": ({ text, ast }) => {
        const edits = [];
        walk(ast.body, (node) => {
            if (node.type !== "TableConstructorExpression" || node.fields.length < 2) return;
            const fields = node.fields;
            if (!fields.every((field) => field.type === "TableKeyString")) return;
            const names = fields.map((field) => field.key.name);
            if (new Set(names).size !== names.length) return;
            const sorted = [...fields].sort((a, b) => compareNames(a.key.name, b.key.name));
            if (sorted.every((field, i) => field === fields[i])) return;
            if (!fields.every((field) => isPure(field.value))) return;
            const inField = (comment) => fields.some((field) => comment.range[0] >= field.range[0] && comment.range[1] <= field.range[1]);
            if (commentsBetween(ast, node.range[0], node.range[1]).some((comment) => !inField(comment))) return;
            // A field spanning lines moves with its lines re-indented; a long string or comment
            // inside one can't be re-indented, so that constructor stays.
            const texts = fields.map((field) => text.slice(field.range[0], field.range[1]));
            if (texts.some((value) => value.includes("\n") && /\[=*\[/.test(value))) return;
            const source = text.slice(node.range[0], node.range[1]);
            if (!source.includes("\n")) {
                sorted.forEach((field, i) => edits.push({ start: fields[i].range[0], end: fields[i].range[1], text: texts[fields.indexOf(field)] }));
                return;
            }
            // Across lines, the fields go one level in from the constructor's line. When each
            // started its own line they still do; packed fields fill lines up to MaxColumns, from
            // the brace's line when the first field was there, and a field spanning lines starts a
            // line. The closing brace stays where it was: after the last field or on its own line.
            const startsLine = (field) => text.slice(lineStart(text, field.range[0]), field.range[0]).trim() === "";
            const vertical = fields.every(startsLine);
            const openInline = !text.slice(node.range[0], fields[0].range[0]).includes("\n");
            const closeInline = !text.slice(fields[fields.length - 1].range[1], node.range[1]).includes("\n");
            const indent = indentOf(text, node.range[0]) + 4;
            const reindented = sorted.map((field, i) => {
                const delta = indent - indentOf(text, field.range[0]);
                const moved = texts[fields.indexOf(field)].split("\n").map((line, j) => {
                    if (j === 0 || delta === 0 || line === "") return line;
                    return delta > 0 ? " ".repeat(delta) + line : line.slice(Math.min(-delta, /^ */.exec(line)[0].length));
                }).join("\n");
                return closeInline && i === sorted.length - 1 ? moved : `${moved},`;
            });
            let result = "{";
            let column = node.range[0] - lineStart(text, node.range[0]) + 1;
            let first = true;
            for (const field of reindented) {
                const width = field.includes("\n") ? Infinity : field.length;
                const sameLine = first ? openInline : !vertical && column + 1 + width <= MaxColumns;
                if (sameLine) {
                    result += ` ${field}`;
                } else {
                    result += `\n${" ".repeat(indent)}${field}`;
                    column = indent - 1;
                }
                const lastLine = field.slice(field.lastIndexOf("\n") + 1);
                column = field.includes("\n") ? Infinity : column + 1 + lastLine.length;
                first = false;
            }
            result += closeInline ? " }" : `\n${" ".repeat(indentOf(text, node.range[0]))}}`;
            edits.push({ start: node.range[0], end: node.range[1], text: result });
        });
        return edits;
    },

    "trailing-comma": ({ text, ast, tokens }) => {
        const edits = [];
        const tokenEnding = new Map();
        tokens.forEach((token, i) => tokenEnding.set(token.range[1], i));
        walk(ast.body, (node) => {
            if (node.type !== "TableConstructorExpression" || node.fields.length === 0) return;
            const last = node.fields[node.fields.length - 1];
            const next = tokens[tokenEnding.get(last.range[1]) + 1];
            if (next?.value !== "}") return;
            if (!text.slice(last.range[1], next.range[0]).includes("\n")) return;
            edits.push({ start: last.range[1], end: last.range[1], text: "," });
        });
        return edits;
    },

    "alias-order": ({ text, ast }) => {
        const edits = [];
        for (const { body, fileLevel } of blocksOf(ast)) {
            if (!fileLevel) continue;
            for (const statement of body) {
                if (statement.type !== "LocalStatement" || statement.variables.length < 2) continue;
                const { variables, init } = statement;
                if (init.length !== variables.length || !init.every(isPure) || init.some(hasVararg)) continue;
                if (commentsBetween(ast, statement.range[0], statement.range[1]).length) continue;
                if (text.slice(statement.range[0], statement.range[1]).includes("\n")) continue;
                const pairs = variables.map((variable, i) => ({ name: variable.name, value: text.slice(init[i].range[0], init[i].range[1]) }));
                const sorted = [...pairs].sort((a, b) => compareNames(a.name, b.name));
                if (sorted.every((pair, i) => pair === pairs[i])) continue;
                const names = sorted.map((pair) => pair.name).join(", ");
                const values = sorted.map((pair) => pair.value).join(", ");
                edits.push({ start: statement.range[0], end: statement.range[1], text: `local ${names} = ${values}` });
            }
        }
        return edits;
    },

    "local-order": ({ text, ast }) => {
        const edits = [];
        for (const { body, fileLevel } of blocksOf(ast)) {
            if (!fileLevel) continue;
            let run = [];
            const flush = () => {
                if (run.length > 1) {
                    const edit = orderRun(text, run);
                    if (edit) edits.push(edit);
                }
                run = [];
            };
            for (const statement of body) {
                const end = statement.type === "LocalStatement" ? ownLineEnd(text, ast, statement) : -1;
                // A local holding a function is a function: member-spacing sets it apart.
                const movable = end >= 0 && statement.init.every(isPure) && !statement.init.some(hasVararg)
                    && !statement.init.some((value) => value.type === "FunctionDeclaration")
                    && !commentsBetween(ast, statement.range[0], statement.range[1]).length;
                if (!movable) {
                    flush();
                    continue;
                }
                const previous = run[run.length - 1];
                if (previous && lineStart(text, statement.range[0]) !== previous.end + 1) flush();
                run.push({ statement, start: lineStart(text, statement.range[0]), end });
            }
            flush();
        }
        return edits;
    },

    "decl-spacing": ({ text, ast }) => {
        const edits = [];
        for (const { body } of blocksOf(ast)) {
            for (let i = 1; i < body.length; i++) {
                const previous = body[i - 1];
                const current = body[i];
                if (previous.type !== "LocalStatement" || current.type === "LocalStatement") continue;
                const edit = spaceBefore(text, ast, previous, current);
                if (edit) edits.push(edit);
            }
        }
        return edits;
    },

    "member-spacing": ({ text, ast }) => {
        const edits = [];
        const isFunction = (statement) => statement.type === "FunctionDeclaration"
            || ((statement.type === "LocalStatement" || statement.type === "AssignmentStatement")
                && statement.init.length === 1 && statement.init[0].type === "FunctionDeclaration");
        for (const { body, fileLevel } of blocksOf(ast)) {
            if (!fileLevel) continue;
            for (let i = 1; i < body.length; i++) {
                if (!isFunction(body[i - 1]) && !isFunction(body[i])) continue;
                const edit = spaceBefore(text, ast, body[i - 1], body[i], true);
                if (edit) edits.push(edit);
            }
        }
        return edits;
    },

    "blank-lines": ({ text, ast }) => {
        const edits = [];
        // Lines inside a long string or comment are its own text.
        const fixed = [];
        walk(ast.body, (node) => {
            if (node.type === "StringLiteral" && node.raw.startsWith("[")) fixed.push(node.range);
        });
        for (const comment of ast.comments) fixed.push(comment.range);
        const isFixed = (position) => fixed.some(([start, end]) => position > start && position < end);
        const leading = /^\n+/.exec(text);
        if (leading) edits.push({ start: 0, end: leading[0].length, text: "" });
        for (const match of text.matchAll(/\n([ ]*\n){2,}/g)) {
            if (match.index === 0 || isFixed(match.index)) continue;
            edits.push({ start: match.index, end: match.index + match[0].length, text: "\n\n" });
        }
        return edits;
    },
};

// Sorts one run of file-level local statements: by first declared name, except that a statement
// whose value reads a name the run declares keeps its side of that declaration.
function orderRun(text, run) {
    const declared = run.map((entry) => entry.statement.variables.map((variable) => variable.name));
    const after = run.map(() => new Set());
    run.forEach((entry, i) => {
        const read = new Set(entry.statement.init.flatMap((value) => [...namesRead(value)]));
        run.forEach((_, j) => {
            if (i === j || !declared[j].some((name) => read.has(name))) return;
            // Reading a later declaration read the global or outer name: it stays before it.
            if (j < i) after[i].add(j);
            else after[j].add(i);
        });
    });
    const order = [];
    const placed = new Set();
    while (order.length < run.length) {
        let best = -1;
        run.forEach((_, i) => {
            if (placed.has(i) || [...after[i]].some((j) => !placed.has(j))) return;
            if (best < 0 || compareNames(declared[i][0], declared[best][0]) < 0) best = i;
        });
        placed.add(best);
        order.push(best);
    }
    if (order.every((value, i) => value === i)) return null;
    const lines = order.map((i) => text.slice(run[i].start, run[i].end));
    return { start: run[0].start, end: run[run.length - 1].end, text: lines.join("\n") };
}

// One blank line between two statements on their own lines, unless a comment leads the second
// (the comment owns its placement) or, with commentsToo, before that comment instead.
function spaceBefore(text, ast, previous, current, commentsToo = false) {
    const end = ownLineEnd(text, ast, previous);
    if (end < 0) return null;
    const leading = commentsBetween(ast, end, current.range[0]);
    if (leading.length && !commentsToo) return null;
    const next = leading.length ? leading[0].range[0] : current.range[0];
    const start = lineStart(text, next);
    if (start <= end || text.slice(end, start).trim() !== "") return null;
    if (text.slice(end, start) === "\n\n") return null;
    return { start: end, end: start, text: "\n\n" };
}

function applyEdits(text, edits) {
    const ordered = edits.map((edit, i) => ({ ...edit, i })).sort((a, b) => a.start - b.start || a.end - b.end || a.i - b.i);
    let result = "";
    let position = 0;
    for (const edit of ordered) {
        if (edit.start < position) continue; // overlaps an earlier edit: the next round takes it
        result += text.slice(position, edit.start) + edit.text;
        position = edit.end;
    }
    return result + text.slice(position);
}

export class FormatError extends Error {}

/**
 * Formats Lua source with the given passes (all of them by default), to a fixed point.
 * @throws {FormatError} when the source doesn't parse, a pass breaks it, or the passes don't settle.
 */
export function formatLua(text, passes = PASSES) {
    let current = text;
    const read = (source, after) => {
        try {
            return { ast: parse(source), tokens: lexTokens(source) };
        } catch (error) {
            throw new FormatError(after ? `${after} left code that doesn't parse: ${error.message}` : `doesn't parse: ${error.message}`);
        }
    };
    let parsed = read(current);
    for (let round = 0; round < MaxRounds; round++) {
        let changed = false;
        for (const pass of passes) {
            const edits = Passes[pass]({ text: current, ...parsed });
            if (!edits.length) continue;
            const next = applyEdits(current, edits);
            if (next === current) continue;
            current = next;
            changed = true;
            parsed = read(current, pass);
        }
        if (!changed) return current;
    }
    throw new FormatError(`the passes didn't settle in ${MaxRounds} rounds`);
}

/** The 1-based line where two texts first differ. */
export function firstDifference(a, b) {
    let i = 0;
    while (i < a.length && a[i] === b[i]) i++;
    return lineOf(a, i);
}
