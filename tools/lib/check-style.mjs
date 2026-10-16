// The NAMING, COMMENT, and HYGIENE rules of the check verb: Puck's C# conventions, mapped to Lua (see
// docs/Conventions.md), and luacheck's warnings. The rules enforce only what a parser can decide.
// Field naming (PascalCase public members, m_ private fields) is a review rule.

import { analyze, parse, walk } from "./lua-scope.mjs";

const PASCAL = /^[A-Z][A-Za-z0-9]*$/;
const GLOBAL_PASCAL = /^[A-Z][A-Za-z0-9_]*$/; // client-facing globals may carry the addon prefix
const CAMEL = /^_?[a-z][A-Za-z0-9]*$|^_$/;
const SCREAMING = /^[A-Z][A-Z0-9]*_[A-Z0-9_]*$|^[A-Z]{2,}[0-9]*$/;
const BANNER = /[-=*#_~]{4,}/;
// Debt markers are the conventional capitalized words, so "hack" or "revisit" in prose isn't one.
const DEBT = /\b(?:TODO|FIXME|HACK|XXX|KLUDGE|REVISIT)\b|\b[Ff]or now\b/;

// A comment paragraph's first word: anything but a lower-case word of prose. It can be a capital,
// a digit, punctuation, or code such as ns.Krew, h:Fire, powerToken, docs/Conventions.md, or
// `level`. Words such as "lower-case" and "it's" are prose.
const SENTENCE_START = /^(?:[^a-z]|[a-z]+[A-Z0-9_.:([=/])/;
// Its last line's end: a sentence's punctuation, maybe inside closing quotes or brackets.
const SENTENCE_END = /[.!?:]["')\]`]*$/;
// Comment lines kept as written: aligned columns and indented items, ---@ annotations, list items,
// and the annotations the gates read.
const VERBATIM = /^(?: {2,}|@|[-*+] |\d+[.)] |(?:secret|protected|global|order):)/;

// The paragraphs of prose comments: consecutive full-line comments with the same prefix (-- or
// ---) and indentation, ended by an empty comment line or a verbatim one. { first, last, startLine,
// endLine } each: the first line's text and the last line's.
function proseParagraphs(text, ast) {
    const lines = text.split("\n");
    const paragraphs = [];
    let current = null;
    let previousLine = -1;
    const close = () => {
        if (current) paragraphs.push(current);
        current = null;
    };
    for (const comment of ast.comments ?? []) {
        const line = comment.loc.start.line;
        const match = /^( *)(---?)(?: (.*))?$/.exec(lines[line - 1]);
        if (comment.raw.startsWith("--[") || (comment.loc.end.line !== line) || !match) {
            close();
            continue;
        }
        const [, indent, prefix, words = ""] = match;
        const key = `${indent}${prefix}`;
        if ((words.trim() === "") || VERBATIM.test(words)) {
            close();
        } else if (current && (current.key === key) && (line === previousLine + 1)) {
            current.last = words;
            current.endLine = line;
        } else {
            close();
            current = { endLine: line, first: words, key, last: words, startLine: line };
        }
        previousLine = line;
    }
    close();
    return paragraphs;
}

// `local x = x` or `local floor = math.floor`: an alias keeps the name of what it aliases.
function isAlias(name, init) {
    if (!init) return false;
    if (init.type === "Identifier") return init.name === name;
    return init.type === "MemberExpression" && init.identifier.name === name;
}

function pascalHint(name) {
    if (!name.includes("_") && name !== name.toUpperCase()) return name[0].toUpperCase() + name.slice(1);
    return name.toLowerCase().split("_").filter(Boolean).map((part) => part[0].toUpperCase() + part.slice(1)).join("");
}

// A local declared at the chunk's top level, or inside top-level `do` blocks that only scope it,
// is file-level state. One inside a function, loop, or branch is a local.
function isFileLevel(ancestors) {
    return ancestors.every((ancestor) => ancestor.type === "DoStatement");
}

// The bindings of locals that are later given a function (`local Pump` then `function Pump()`
// or `Pump = function`): functions, so PascalCase wherever they're declared.
function functionBindings(ast) {
    const scope = analyze(ast);
    const bindings = new Set();
    walk(ast.body, (node) => {
        if (node.type === "FunctionDeclaration" && !node.isLocal && node.identifier?.type === "Identifier") {
            const binding = scope.bindingOf(node.identifier);
            if (binding) bindings.add(binding);
        } else if (node.type === "AssignmentStatement") {
            node.variables.forEach((variable, i) => {
                if (variable.type === "Identifier" && node.init[i]?.type === "FunctionDeclaration") {
                    const binding = scope.bindingOf(variable);
                    if (binding) bindings.add(binding);
                }
            });
        }
    });
    return { scope, bindings };
}

// The statement lists of a chunk: its body, and every function, branch, loop, and do body in it.
function blocks(ast) {
    const lists = [ast.body];
    walk(ast.body, (node) => {
        if (node.type === "IfStatement") for (const clause of node.clauses) lists.push(clause.body);
        else if (Array.isArray(node.body)) lists.push(node.body);
    });
    return lists;
}

// Whether a statement always leaves its block: return, break, a `do` block that does, or an if
// with an else whose every branch does.
function leaves(node) {
    if (node.type === "ReturnStatement" || node.type === "BreakStatement") return true;
    if (node.type === "DoStatement") return node.body.some(leaves);
    if (node.type === "IfStatement") {
        return node.clauses.some((clause) => clause.type === "ElseClause") && node.clauses.every((clause) => clause.body.some(leaves));
    }
    return false;
}

const EMPTY_BLOCKS = {
    IfClause: "if branch", ElseifClause: "elseif branch", ElseClause: "else branch", DoStatement: "do block",
    WhileStatement: "loop body", RepeatStatement: "loop body", ForNumericStatement: "loop body", ForGenericStatement: "loop body",
};
const KINDS = { local: "local", function: "local function", param: "parameter", for: "loop variable" };
const KEEP = "rename it to _, since a later one is read and keeps its position";
const isCall = (node) => node?.type === "CallExpression" || node?.type === "StringCallExpression" || node?.type === "TableCallExpression";

// HYGIENE: luacheck's warnings, as far as a parser can decide them. Names starting with `_` are
// exempt, and so is a file's own `local addonName, ns = ...`. An empty function body is a no-op
// callback, not an empty block. A local function is used when something outside its own body
// reads it. A callback's `state` parameter may shadow an outer `state` (docs/Conventions.md).
function checkHygiene(ast, file, report) {
    const scope = analyze(ast);
    const line = (node) => node.loc.start.line;
    const exempt = (name) => name.startsWith("_");
    const within = (node, outer) => node.range[0] >= outer.range[0] && node.range[1] <= outer.range[1];

    // The innermost function around each identifier (null: the chunk), so a local a closure
    // references is left out of the overwritten-value check.
    const functionOf = new Map();
    walk(ast.body, (node, ancestors) => {
        if (node.type === "Identifier") functionOf.set(node, ancestors.findLast((ancestor) => ancestor.type === "FunctionDeclaration") ?? null);
    });
    // Whether a function's own body (not a nested function's) reads `...`.
    const readsVararg = (fn) => {
        let found = false;
        walk(fn.body, (node, ancestors) => {
            if (node.type === "VarargLiteral" && !ancestors.some((ancestor) => ancestor.type === "FunctionDeclaration")) found = true;
        });
        return found;
    };
    const isHeader = (binding) => binding.depth === 0 && binding.statement?.type === "LocalStatement"
        && binding.statement.init.length === 1 && binding.statement.init[0].type === "VarargLiteral"
        && binding.statement.variables.every((variable, i) => variable.name === ["addonName", "ns"][i]);
    const read = (identifier) => scope.reads(scope.bindingOf(identifier)).length > 0;

    for (const binding of scope.all()) {
        const { identifier, statement, name } = binding;
        if (!identifier || exempt(name) || isHeader(binding)) continue;
        // docs/Conventions.md: a callback may name its parameter `state` where an outer `state`
        // holds the same object.
        const stateCallback = binding.kind === "param" && name === "state" && !statement.identifier;
        if (binding.shadows && !exempt(binding.shadows.name) && !stateCallback) {
            const hidden = binding.shadows.identifier;
            report(file, line(identifier), "HYGIENE", hidden
                ? `${KINDS[binding.kind]} ${name} ${binding.redefines ? "redefines" : "shadows"} the ${KINDS[binding.shadows.kind]} ${name} on line ${line(hidden)}; rename one`
                : `${KINDS[binding.kind]} ${name} shadows the implicit self of the method on line ${line(binding.shadows.statement)}; rename it`);
        }
        const reads = scope.reads(binding);
        if (binding.kind === "function") {
            if (!reads.some((ref) => !within(ref, statement))) {
                report(file, line(identifier), "HYGIENE", `unused local function ${name}: ${reads.length ? "only its own body calls it" : "nothing calls or reads it"}`);
            }
            continue;
        }
        if (reads.length) continue;
        if (binding.kind === "param") {
            const later = statement.parameters.slice(statement.parameters.indexOf(identifier) + 1);
            const kept = later.some((parameter) => (parameter.type === "VarargLiteral" ? readsVararg(statement) : read(parameter)));
            report(file, line(identifier), "HYGIENE", `unused parameter ${name}: ${kept ? KEEP : "remove it"}`);
        } else if (binding.kind === "for") {
            const later = statement.type === "ForGenericStatement" ? statement.variables.slice(statement.variables.indexOf(identifier) + 1) : [];
            const kept = statement.type === "ForNumericStatement" || later.some(read);
            report(file, line(identifier), "HYGIENE", `unused loop variable ${name}: ${kept ? (later.length ? KEEP : "rename it to _") : "remove it"}`);
        } else {
            const later = statement.type === "LocalStatement" ? statement.variables.slice(statement.variables.indexOf(identifier) + 1) : [];
            report(file, line(identifier), "HYGIENE", `unused local ${name}: nothing reads it${later.some(read) ? `; ${KEEP}` : ""}`);
        }
    }

    for (const list of blocks(ast)) {
        const exit = list.findIndex(leaves);
        if (exit >= 0 && exit < list.length - 1) {
            report(file, line(list[exit + 1]), "HYGIENE", `unreachable code: the statement on line ${line(list[exit])} always leaves this block`);
        }
        list.forEach((statement, i) => overwritten(list, statement, i));
    }

    walk(ast.body, (node) => {
        const kind = EMPTY_BLOCKS[node.type];
        if (kind && node.body.length === 0) report(file, line(node), "HYGIENE", `empty ${kind}`);
    });

    // A value assigned to a local (declared with one, or assigned) that a later statement of the
    // same block overwrites before anything reads it. Only straight-line code counts, and only
    // locals no closure references, so a call in between can't read the value.
    function overwritten(list, statement, i) {
        const written = [];
        if (statement.type === "LocalStatement") {
            const last = statement.init[statement.init.length - 1];
            statement.variables.forEach((variable, k) => {
                const value = statement.init[k];
                if (value ? value.type !== "NilLiteral" : isCall(last) || last?.type === "VarargLiteral") written.push(variable);
            });
        } else if (statement.type === "AssignmentStatement") {
            for (const target of statement.variables) if (target.type === "Identifier" && scope.bindingOf(target)) written.push(target);
        }
        for (const target of written) {
            const binding = scope.bindingOf(target);
            if (!binding.identifier || exempt(binding.name)) continue;
            const home = functionOf.get(binding.identifier);
            const refs = scope.references(binding);
            if (refs.some((ref) => functionOf.get(ref) !== home)) continue;
            const next = refs.filter((ref) => ref.range[0] > statement.range[1]).sort((a, b) => a.range[0] - b.range[0])[0];
            const overwriter = next && list.slice(i + 1).find((later) => later.type === "AssignmentStatement" && later.variables.includes(next));
            if (overwriter && !scope.reads(binding).some((ref) => within(ref, overwriter))) {
                report(file, line(target), "HYGIENE", `the value assigned to ${binding.name} is overwritten on line ${line(overwriter)} before anything reads it`);
            }
        }
    }
}

export function checkStyleRules(file, text, report) {
    let ast;
    try {
        ast = parse(text);
    } catch {
        return; // PARSE already reported it
    }

    for (const comment of ast.comments ?? []) {
        const body = comment.value.replace(/^-(?=[^-]|$)/, ""); // a `---` doc comment's third dash isn't a banner
        if (BANNER.test(body)) {
            report(file, comment.loc.start.line, "COMMENT", "banner divider: let the code's structure and doc comments do that work");
        }
        const debt = DEBT.exec(comment.value);
        if (debt) {
            report(file, comment.loc.start.line, "COMMENT", `debt marker "${debt[0]}": do the work, or say what's true today`);
        }
    }
    for (const paragraph of proseParagraphs(text, ast)) {
        if (!SENTENCE_START.test(paragraph.first)) {
            report(file, paragraph.startLine, "COMMENT", "a comment is a sentence: start it with a capital letter, or with `code`");
        }
        if (!SENTENCE_END.test(paragraph.last)) {
            report(file, paragraph.endLine, "COMMENT", "a comment is a sentence: end it with a period (or ! ? :)");
        }
    }

    const naming = (node, name, rule, what) => {
        if (!rule.test(name)) {
            const pascal = pascalHint(name);
            const hint = rule === CAMEL ? pascal[0].toLowerCase() + pascal.slice(1) : pascal;
            report(file, node.loc.start.line, "NAMING", `${what} '${name}' should be ${rule === CAMEL ? "camelCase" : "PascalCase"}${hint && hint !== name ? ` (${hint})` : ""}`);
        }
    };

    const { scope, bindings } = functionBindings(ast);
    walk(ast.body, (node, ancestors) => {
        if (node.type === "LocalStatement") {
            // The file's own header, `local addonName, ns = ...`, keeps the client's names.
            const header = node.init.length === 1 && node.init[0].type === "VarargLiteral" && isFileLevel(ancestors)
                && node.variables.every((variable, i) => variable.name === ["addonName", "ns"][i]);
            node.variables.forEach((variable, i) => {
                const name = variable.name;
                if (header || isAlias(name, node.init[i])) return;
                if (node.init[i]?.type === "FunctionDeclaration" || bindings.has(scope.bindingOf(variable))) {
                    naming(variable, name, PASCAL, "function");
                } else if (!isFileLevel(ancestors)) {
                    naming(variable, name, CAMEL, "local");
                } else if (SCREAMING.test(name)) {
                    report(file, variable.loc.start.line, "NAMING", `constant '${name}' should be PascalCase (${pascalHint(name)})`);
                } else {
                    naming(variable, name, PASCAL, "file-level local");
                }
            });
        } else if (node.type === "FunctionDeclaration") {
            const id = node.identifier;
            if (id?.type === "Identifier") {
                naming(id, id.name, node.isLocal || scope.bindingOf(id) ? PASCAL : GLOBAL_PASCAL, "function");
            } else if (id?.type === "MemberExpression" && !id.identifier.name.startsWith("__")) {
                naming(id.identifier, id.identifier.name, PASCAL, "method");
            }
            for (const parameter of node.parameters) {
                if (parameter.type === "Identifier" && parameter.name !== "self") naming(parameter, parameter.name, CAMEL, "parameter");
            }
        } else if (node.type === "ForGenericStatement") {
            for (const variable of node.variables) naming(variable, variable.name, CAMEL, "loop variable");
        } else if (node.type === "ForNumericStatement") {
            naming(node.variable, node.variable.name, CAMEL, "loop variable");
        }
    });

    checkHygiene(ast, file, report);
}
