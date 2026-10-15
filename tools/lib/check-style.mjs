// The NAMING and COMMENT rules of the check verb: Puck's C# conventions, mapped to Lua (see
// docs/Conventions.md). Only what a parser can decide is enforced; field naming (PascalCase public
// members, m_ private fields) is a review rule.

import { analyze, parse, walk } from "./lua-scope.mjs";

const PASCAL = /^[A-Z][A-Za-z0-9]*$/;
const GLOBAL_PASCAL = /^[A-Z][A-Za-z0-9_]*$/; // client-facing globals may carry the addon prefix
const CAMEL = /^_?[a-z][A-Za-z0-9]*$|^_$/;
const SCREAMING = /^[A-Z][A-Z0-9]*_[A-Z0-9_]*$|^[A-Z]{2,}[0-9]*$/;
const BANNER = /[-=*#_~]{4,}/;
// Debt markers are the conventional capitalized words; "hack" or "revisit" in prose isn't one.
const DEBT = /\b(?:TODO|FIXME|HACK|XXX|KLUDGE|REVISIT)\b|\b[Ff]or now\b/;

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
// is file-level state; one inside a function, loop or branch is a local.
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
}
