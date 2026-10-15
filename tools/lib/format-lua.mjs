// The format verb's rewrites: Puck's `puck format` passes, mapped to Lua, plus the habits Puck's own
// code keeps that its formatter doesn't write (docs/Conventions.md#formatting). formatLua(text) runs
// every pass to a fixed point and returns the canonical text.
//
//   trailing-comments  a comment after code moves onto its own line above it.
//   string-merge       `"a" .. "b"` of two double-quoted literals on one line becomes one literal.
//   paren-clarity      every binary and logical expression is parenthesized, except where something
//                      already delimits it: existing parentheses, an if/elseif/while/until condition,
//                      a call's arguments, an index's brackets and a numeric for's bounds. An operand
//                      of the same `and`, `or` or `..` stays bare, so a chain stays one flat group.
//   init-order         a table constructor whose every field is `name = value` is sorted by name,
//                      when no value calls anything (or with options.sortCalls); a field's own comment
//                      lines move with it. Across lines, fields that each had a line keep one; packed
//                      fields are packed again, up to 120 columns.
//   trailing-comma     a multi-line table constructor's last field ends with a comma.
//   alias-order        a file-level `local a, b = x, y` with values that call nothing is sorted by name.
//   export-order       a file-level run of `Table.member = value` lines is sorted by target.
//   local-order        a file-level run of `local` statements (consecutive lines, values that call
//                      nothing and hold no function) is sorted by name, with each one's comment lines.
//   function-order     a file-level run of functions is sorted, local ones first, with each one's
//                      comment lines.
//   decl-spacing       one blank line between a run of `local` statements and the statement after it.
//   block-spacing      one blank line around blocks and statements spanning lines, and before a return.
//   member-spacing     one blank line between a file-level function and its neighbors.
//   comment-fill       a prose paragraph of full-line comments fills its lines up to 120 columns.
//   blank-lines        no run of blank lines longer than one, and none at the start of the file.
//
// A sort never moves a unit past one whose values read a name it declares (or whose name it read as
// a global before). The comment lines directly above a statement are its own; any other comment
// where a sort would move things keeps the order as written. A pass that changes nothing returns no
// edits; the result must parse, and running the passes again must change nothing. Names sort
// alphabetically, ignoring case (Puck's names share one case; Lua's data keys and handlers don't).

import luaparse from "luaparse";
import { parse, walk } from "./lua-scope.mjs";

export const PASSES = [
    "trailing-comments", "string-merge", "paren-clarity", "init-order", "trailing-comma", "alias-order", "export-order",
    "local-order", "function-order", "decl-spacing", "block-spacing", "member-spacing", "comment-fill", "blank-lines",
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

// A table constructor's fields when it has two or more and every one is `name = value` with its
// own name, or null: the constructors init-order sorts.
function sortableFields(node) {
    if (node.type !== "TableConstructorExpression" || node.fields.length < 2) return null;
    if (!node.fields.every((field) => field.type === "TableKeyString")) return null;
    const names = node.fields.map((field) => field.key.name);
    return new Set(names).size === names.length ? node.fields : null;
}

// Whether `-- <kind>: <why>` sits on node's first line or alone on the line above it.
function annotated(text, ast, node, kind) {
    const start = lineStart(text, node.range[0]);
    const above = lineStart(text, start - 1);
    const pattern = new RegExp(`^--\\s*${kind}:\\s*\\S`);
    return ast.comments.some((comment) => pattern.test(comment.raw)
        && ((comment.range[0] >= start && comment.range[0] <= lineEnd(text, start))
            || (comment.range[0] >= above && comment.range[1] < start && ownLines(text, comment))));
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

// Whether a comment has its lines to itself.
function ownLines(text, comment) {
    return text.slice(lineStart(text, comment.range[0]), comment.range[0]).trim() === ""
        && text.slice(comment.range[1], lineEnd(text, comment.range[1])).trim() === "";
}

// Where a statement's unit starts: the first of the comment lines directly above it (no blank
// line between, each on its own lines), which belong to it, or the statement's own line.
function unitStart(text, ast, statement) {
    let start = lineStart(text, statement.range[0]);
    for (let i = ast.comments.length - 1; i >= 0; i--) {
        const comment = ast.comments[i];
        if (comment.range[1] > start) continue;
        if (!ownLines(text, comment) || lineEnd(text, comment.range[1]) + 1 !== start) break;
        start = lineStart(text, comment.range[0]);
    }
    return start;
}

// The long strings and comments, whose text is their own: no pass edits inside one.
function fixedRanges(ast) {
    const fixed = [...ast.comments.map((comment) => comment.range)];
    walk(ast.body, (node) => {
        if (node.type === "StringLiteral" && node.raw.startsWith("[")) fixed.push(node.range);
    });
    return fixed;
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

    "init-order": ({ text, ast, options }) => {
        const edits = [];
        walk(ast.body, (node) => {
            const fields = sortableFields(node);
            if (!fields) return;
            const sorted = [...fields].sort((a, b) => compareNames(a.key.name, b.key.name));
            if (sorted.every((field, i) => field === fields[i])) return;
            if (!options.sortCalls && !fields.every((field) => isPure(field.value))) return;
            if (annotated(text, ast, node, "order")) return;
            // In a constructor with a field to a line, the comment lines directly above a field are
            // its own and move with it; any other comment between fields keeps the order as written.
            const startsLine = (field) => text.slice(lineStart(text, field.range[0]), field.range[0]).trim() === "";
            const vertical = fields.every(startsLine);
            const starts = fields.map((field) => {
                const start = vertical ? unitStart(text, ast, field) : lineStart(text, field.range[0]);
                return start < lineStart(text, field.range[0]) ? text.indexOf("--", start) : field.range[0];
            });
            const inField = (comment) => fields.some((field, i) => comment.range[0] >= starts[i] && comment.range[1] <= field.range[1]);
            if (commentsBetween(ast, node.range[0], node.range[1]).some((comment) => !inField(comment))) return;
            // A field spanning lines moves with its lines re-indented; a long string or comment
            // inside one can't be re-indented, so that constructor stays.
            const texts = fields.map((field, i) => text.slice(starts[i], field.range[1]));
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
                    const edit = orderRun(text, run, (entry) => entry.statement.variables.map((variable) => variable.name),
                        (entry) => entry.statement.init, (entry) => entry.statement.variables[0].name, "\n");
                    if (edit) edits.push(edit);
                }
                run = [];
            };
            for (const statement of body) {
                const end = statement.type === "LocalStatement" ? ownLineEnd(text, ast, statement) : -1;
                // A local holding a function is a function: function-order sorts it.
                const movable = end >= 0 && statement.init.every(isPure) && !statement.init.some(hasVararg)
                    && !statement.init.some((value) => value.type === "FunctionDeclaration")
                    && !commentsBetween(ast, statement.range[0], statement.range[1]).length;
                if (!movable) {
                    flush();
                    continue;
                }
                const start = unitStart(text, ast, statement);
                const previous = run[run.length - 1];
                if (previous && start !== previous.end + 1) flush();
                run.push({ statement, start, end });
            }
            flush();
        }
        return edits;
    },

    // A file-level run of `Table.member = value` exports (single lines; values are names, literals
    // or other plain reads' names), sorted by target, each statement's own pairs first.
    "export-order": ({ text, ast }) => {
        const edits = [];
        const targetText = (node) => text.slice(node.range[0], node.range[1]);
        const plain = (node) => ["Identifier", "StringLiteral", "NumericLiteral", "BooleanLiteral", "NilLiteral"].includes(node.type);
        for (const { body, fileLevel } of blocksOf(ast)) {
            if (!fileLevel) continue;
            let run = [];
            const flush = () => {
                const targets = run.flatMap((entry) => entry.targets);
                if (run.length > 1 && new Set(targets).size === targets.length) {
                    const sorted = [...run].sort((a, b) => compareNames(a.targets[0], b.targets[0]));
                    if (sorted.some((entry, i) => entry !== run[i])) {
                        edits.push({ start: run[0].start, end: run[run.length - 1].end, text: sorted.map((entry) => entry.text).join("\n") });
                    }
                }
                run = [];
            };
            for (const statement of body) {
                const end = statement.type === "AssignmentStatement" ? ownLineEnd(text, ast, statement) : -1;
                const exported = end >= 0 && statement.variables.length === statement.init.length
                    && statement.variables.every((variable) => variable.type === "MemberExpression")
                    && statement.init.every(plain) && !text.slice(statement.range[0], statement.range[1]).includes("\n");
                if (!exported) {
                    flush();
                    continue;
                }
                const start = unitStart(text, ast, statement);
                const previous = run[run.length - 1];
                if (previous && start !== previous.end + 1) flush();
                const pairs = statement.variables.map((variable, i) => ({ target: targetText(variable), value: targetText(statement.init[i]) }))
                    .sort((a, b) => compareNames(a.target, b.target));
                const own = `${pairs.map((pair) => pair.target).join(", ")} = ${pairs.map((pair) => pair.value).join(", ")}`;
                const leading = text.slice(start, lineStart(text, statement.range[0]));
                const indent = text.slice(lineStart(text, statement.range[0]), statement.range[0]);
                run.push({ end, start, targets: pairs.map((pair) => pair.target), text: `${leading}${indent}${own}` });
            }
            flush();
        }
        return edits;
    },

    // A file-level run of functions (local functions, locals holding a function, and functions
    // stored in tables), each with its comment lines, sorted: local ones first, then the rest, each
    // alphabetically, never moving one past a function whose name it reads (or one whose name it
    // read as a global before). A statement of any other kind, or a comment of its own, ends the run.
    "function-order": ({ text, ast }) => {
        const edits = [];
        const nameOf = (statement) => {
            const identifier = statement.type === "FunctionDeclaration" ? statement.identifier : statement.variables[0];
            return text.slice(identifier.range[0], identifier.range[1]);
        };
        const declares = (statement) => {
            if (statement.type === "FunctionDeclaration") return statement.isLocal ? [statement.identifier.name] : [];
            return statement.type === "LocalStatement" ? [statement.variables[0].name] : [];
        };
        const isFunctionUnit = (statement) => {
            if (statement.type === "FunctionDeclaration") return statement.identifier !== null;
            return statement.type === "LocalStatement" && statement.variables.length === 1 && statement.init.length === 1
                && statement.init[0].type === "FunctionDeclaration";
        };
        for (const { body, fileLevel } of blocksOf(ast)) {
            if (!fileLevel) continue;
            let run = [];
            const flush = () => {
                const names = run.map((entry) => entry.name);
                if (run.length > 1 && new Set(names).size === names.length) {
                    const edit = orderRun(text, run, (entry) => declares(entry.statement), (entry) => [entry.statement],
                        (entry) => `${entry.local ? 0 : 1}${entry.name}`, "\n\n");
                    if (edit) edits.push(edit);
                }
                run = [];
            };
            for (const statement of body) {
                const end = isFunctionUnit(statement) ? ownLineEnd(text, ast, statement) : -1;
                if (end < 0) {
                    flush();
                    continue;
                }
                const start = unitStart(text, ast, statement);
                const previous = run[run.length - 1];
                // Only blank lines may sit between two functions of a run; a comment there is its own.
                if (previous && text.slice(previous.end, start).trim() !== "") flush();
                const local = statement.type === "LocalStatement" || statement.isLocal;
                run.push({ end, local, name: nameOf(statement), start, statement });
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

    // A comment after code on its line moves onto its own line above, at that line's indentation.
    "trailing-comments": ({ text, ast }) => {
        const edits = [];
        const fixed = fixedRanges(ast);
        for (const comment of ast.comments) {
            if (comment.raw.startsWith("--[")) continue;
            const start = lineStart(text, comment.range[0]);
            const code = text.slice(start, comment.range[0]);
            if (code.trim() === "" || lineEnd(text, comment.range[1]) !== comment.range[1]) continue;
            // A line that starts inside a long string can't take a line above it.
            if (fixed.some(([from, to]) => from < start && to > start)) continue;
            const indent = /^ */.exec(code)[0];
            const codeEnd = start + code.trimEnd().length;
            edits.push({ start, end: start, text: `${indent}${comment.raw}\n` }, { start: codeEnd, end: comment.range[1], text: "" });
        }
        return edits;
    },

    // One blank line before and after a block (if, a loop, do, a function) or a statement spanning
    // lines, and before a return or break, between statements of one block. It goes above the
    // later statement's comment lines.
    "block-spacing": ({ text, ast }) => {
        const edits = [];
        const Blocks = ["IfStatement", "WhileStatement", "RepeatStatement", "ForNumericStatement", "ForGenericStatement",
            "DoStatement", "FunctionDeclaration"];
        const blockLike = (statement) => Blocks.includes(statement.type) || text.slice(statement.range[0], statement.range[1]).includes("\n");
        const exits = (statement) => statement.type === "ReturnStatement" || statement.type === "BreakStatement";
        for (const { body } of blocksOf(ast)) {
            for (let i = 1; i < body.length; i++) {
                if (!blockLike(body[i - 1]) && !blockLike(body[i]) && !exits(body[i])) continue;
                const edit = spaceBefore(text, ast, body[i - 1], body[i], true);
                if (edit) edits.push(edit);
            }
        }
        return edits;
    },

    // A paragraph of full-line comments (same indentation and prefix, plain prose: no lists, no
    // aligned columns, no annotations) fills its lines up to MaxColumns.
    "comment-fill": ({ text, ast }) => {
        const edits = [];
        const lines = text.split("\n");
        const offsets = [];
        let offset = 0;
        for (const line of lines) {
            offsets.push(offset);
            offset += line.length + 1;
        }
        const fixed = fixedRanges(ast).filter(([from, to]) => text.slice(from, to).includes("\n"));
        const prose = (i) => {
            const match = /^( *)(---?) (\S.*)$/.exec(lines[i]);
            if (!match || fixed.some(([from, to]) => from < offsets[i] && to > offsets[i])) return null;
            const words = match[3];
            if (words.startsWith("@") || /\S {2,}\S/.test(words) || /^([-*+]|\d+[.)]) /.test(words)) return null;
            if (/^(secret|protected|global|order):/.test(words)) return null;
            return { indent: match[1], prefix: match[2], words };
        };
        for (let i = 0; i < lines.length;) {
            const first = prose(i);
            if (!first) {
                i++;
                continue;
            }
            let j = i + 1;
            const words = [first.words];
            // A line starting in lower case after one that ends a sentence is a note of its own (a
            // moved trailing comment, say), not the sentence's next line.
            const joins = (next) => next && next.indent === first.indent && next.prefix === first.prefix
                && !(/[.!?]$/.test(words[words.length - 1]) && /^[a-z]/.test(next.words));
            for (let next = prose(j); joins(next); next = prose(++j)) {
                words.push(next.words);
            }
            const lead = `${first.indent}${first.prefix} `;
            const filled = [];
            let line = "";
            for (const word of words.join(" ").split(" ")) {
                if (line && lead.length + line.length + 1 + word.length > MaxColumns) {
                    // A line starting "10." or "-" would read as a list item, and one starting
                    // "secret:" as an annotation the gates read: its word moves down with the one
                    // before it.
                    const space = line.lastIndexOf(" ");
                    if (/^(?:\d+[.)]|[-*+]|(?:secret|protected|global|order):)$/.test(word) && (space > 0)) {
                        filled.push(lead + line.slice(0, space));
                        line = `${line.slice(space + 1)} ${word}`;
                        continue;
                    }
                    filled.push(lead + line);
                    line = word;
                } else {
                    line = line ? `${line} ${word}` : word;
                }
            }
            filled.push(lead + line);
            const original = lines.slice(i, j).join("\n");
            if (filled.join("\n") !== original) edits.push({ start: offsets[i], end: offsets[i] + original.length, text: filled.join("\n") });
            i = j;
        }
        return edits;
    },

    "blank-lines": ({ text, ast }) => {
        const edits = [];
        // Lines inside a long string or comment are its own text.
        const fixed = fixedRanges(ast);
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

// Sorts one run of file-level units ({ start, end }, each its own lines) by keyOf, except that a
// unit whose values (valuesOf) read a name another unit declares (declaredOf) keeps its side of
// that declaration: after it when it read it, before it when it read the global of that name.
// The units are joined by joiner.
function orderRun(text, run, declaredOf, valuesOf, keyOf, joiner) {
    const declared = run.map(declaredOf);
    const after = run.map(() => new Set());
    run.forEach((entry, i) => {
        const read = new Set(valuesOf(entry).flatMap((value) => [...namesRead(value)]));
        run.forEach((_, j) => {
            if (i === j || !declared[j].some((name) => read.has(name))) return;
            if (j < i) after[i].add(j);
            else after[j].add(i);
        });
    });
    const order = [];
    const placed = new Set();
    while (order.length < run.length) {
        let best = -1;
        run.forEach((entry, i) => {
            if (placed.has(i) || [...after[i]].some((j) => !placed.has(j))) return;
            if (best < 0 || compareNames(keyOf(entry), keyOf(run[best])) < 0) best = i;
        });
        placed.add(best);
        order.push(best);
    }
    if (order.every((value, i) => value === i)) return null;
    const units = order.map((i) => text.slice(run[i].start, run[i].end));
    return { start: run[0].start, end: run[run.length - 1].end, text: units.join(joiner) };
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
 * Formats Lua source with the given passes (all of them by default), to a fixed point. With
 * options.sortCalls, init-order also sorts constructors whose values call something: only for a
 * reviewed sweep, since a call can change what another field reads.
 * @throws {FormatError} when the source doesn't parse, a pass breaks it, or the passes don't settle.
 */
export function formatLua(text, passes = PASSES, options = {}) {
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
            const edits = Passes[pass]({ text: current, ...parsed, options });
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

/**
 * The table constructors whose named fields aren't alphabetical and that init-order won't sort (a
 * value calls something, or a comment sits between fields), unless `-- order: <why>` says why
 * their order matters: { line } each.
 */
export function orderFindings(text) {
    const ast = parse(text);
    const findings = [];
    walk(ast.body, (node) => {
        const fields = sortableFields(node);
        if (!fields || annotated(text, ast, node, "order")) return;
        const names = fields.map((field) => field.key.name);
        const sorted = [...names].sort(compareNames);
        if (names.some((name, i) => name !== sorted[i])) findings.push({ line: lineOf(text, node.range[0]) });
    });
    return findings;
}

/** The 1-based line where two texts first differ. */
export function firstDifference(a, b) {
    let i = 0;
    while (i < a.length && a[i] === b[i]) i++;
    return lineOf(a, i);
}
