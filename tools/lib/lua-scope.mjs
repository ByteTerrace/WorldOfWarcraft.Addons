// Lua 5.1 AST helpers for the static gate: parsing, lexical scope resolution and static naming.
//
// analyze(ast) binds every Identifier to the local that declares it (or to nothing: a global),
// following Lua's scoping (a local is visible after its statement; `local function f` sees
// itself; parameters and loop variables are scoped to their body; `repeat ... until cond` sees
// the body's locals). A binding records whether it's ever reassigned, so aliases are trusted only
// when they can't change: conservative about shadowing and reassignment. It also records what the
// HYGIENE rule reads: each binding's declaring node, the local its declaration hides, and which
// references write rather than read.

import luaparse from "luaparse";

export function parse(text) {
    return luaparse.parse(text, {
        luaVersion: "5.1", locations: true, ranges: true, comments: true, encodingMode: "pseudo-latin1",
    });
}

export function stringValue(node) {
    return node && node.type === "StringLiteral" ? (node.value ?? node.raw.slice(1, -1)) : null;
}

// Walks an AST, calling visit(node, ancestors) for every node (ancestors: root first).
export function walk(node, visit, ancestors = []) {
    if (!node || typeof node !== "object") return;
    if (Array.isArray(node)) {
        for (const child of node) walk(child, visit, ancestors);
        return;
    }
    if (typeof node.type !== "string") return;
    visit(node, ancestors);
    ancestors.push(node);
    for (const [key, value] of Object.entries(node)) {
        if (key !== "loc" && key !== "range" && key !== "comments") walk(value, visit, ancestors);
    }
    ancestors.pop();
}

export function isFunction(node) {
    return node.type === "FunctionDeclaration";
}

// Returns { bindingOf(identifier) -> binding | undefined, fileLevel(binding) -> boolean,
// references(binding) -> the Identifiers that read or assign it (not its declaration),
// reads(binding) -> the references that read it, all() -> every binding in declaration order }.
// binding = { name, kind: "local" | "function" | "param" | "for", init, depth, reassigned,
//   identifier (the declaring Identifier; null for a method's implicit self), statement (the
//   LocalStatement, loop or FunctionDeclaration that declares it), shadows (the visible local it
//   hides, or undefined), redefines (whether that local is in the same scope) }
export function analyze(ast) {
    const bindings = new Map();
    const references = new Map();
    const writes = new Set();
    const declared = [];
    const refer = (identifier, binding) => {
        bindings.set(identifier, binding);
        const list = references.get(binding) ?? [];
        list.push(identifier);
        references.set(binding, list);
    };
    const scopes = [];
    let functionDepth = 0;

    const lookup = (name) => {
        for (let i = scopes.length - 1; i >= 0; i--) {
            const binding = scopes[i].get(name);
            if (binding) return binding;
        }
        return undefined;
    };
    const declare = (identifier, kind, init = null, statement = null) => {
        const binding = {
            name: identifier.name, kind, init, depth: functionDepth, reassigned: false,
            identifier: identifier.type === "Identifier" ? identifier : null, statement, shadows: lookup(identifier.name),
            redefines: scopes[scopes.length - 1].has(identifier.name),
        };
        scopes[scopes.length - 1].set(identifier.name, binding);
        bindings.set(identifier, binding);
        declared.push(binding);
        return binding;
    };
    const block = (fn) => {
        scopes.push(new Map());
        fn();
        scopes.pop();
    };

    function expression(node) {
        if (!node || typeof node !== "object") return;
        switch (node.type) {
            case "Identifier": {
                const binding = lookup(node.name);
                if (binding) refer(node, binding);
                return;
            }
            case "FunctionDeclaration":
                return functionBody(node);
            case "MemberExpression":
                return expression(node.base); // node.identifier is a name, not a reference
            case "IndexExpression":
                expression(node.base);
                return expression(node.index);
            case "CallExpression":
                expression(node.base);
                return node.arguments.forEach(expression);
            case "StringCallExpression":
                expression(node.base);
                return expression(node.argument);
            case "TableCallExpression":
                expression(node.base);
                return expression(node.arguments);
            case "TableConstructorExpression":
                for (const field of node.fields) {
                    if (field.type === "TableKey") expression(field.key);
                    expression(field.value);
                }
                return;
            case "BinaryExpression":
            case "LogicalExpression":
                expression(node.left);
                return expression(node.right);
            case "UnaryExpression":
                return expression(node.argument);
            default:
                return;
        }
    }

    function functionBody(node) {
        functionDepth++;
        block(() => {
            const identifier = node.identifier;
            if (identifier && identifier.type === "MemberExpression" && identifier.indexer === ":") {
                declare({ name: "self" }, "param", null, node);
            }
            for (const parameter of node.parameters) {
                if (parameter.type === "Identifier") declare(parameter, "param", null, node);
            }
            statements(node.body);
        });
        functionDepth--;
    }

    function assignTarget(target) {
        if (target.type === "Identifier") {
            const binding = lookup(target.name);
            if (binding) {
                binding.reassigned = true;
                refer(target, binding);
                writes.add(target);
            }
        } else {
            expression(target);
        }
    }

    function statement(node) {
        switch (node.type) {
            case "LocalStatement":
                node.init.forEach(expression);
                node.variables.forEach((variable, i) => declare(variable, "local", node.init[i] ?? null, node));
                return;
            case "AssignmentStatement":
                node.init.forEach(expression);
                return node.variables.forEach(assignTarget);
            case "CallStatement":
                return expression(node.expression);
            case "FunctionDeclaration":
                if (node.isLocal && node.identifier) {
                    declare(node.identifier, "function", node, node);
                } else if (node.identifier) {
                    assignTarget(node.identifier);
                }
                return functionBody(node);
            case "ReturnStatement":
                return node.arguments.forEach(expression);
            case "IfStatement":
                for (const clause of node.clauses) {
                    if (clause.condition) expression(clause.condition);
                    block(() => statements(clause.body));
                }
                return;
            case "WhileStatement":
                expression(node.condition);
                return block(() => statements(node.body));
            case "RepeatStatement":
                return block(() => {
                    statements(node.body);
                    expression(node.condition);
                });
            case "DoStatement":
                return block(() => statements(node.body));
            case "ForNumericStatement":
                expression(node.start);
                expression(node.end);
                expression(node.step);
                return block(() => {
                    declare(node.variable, "for", null, node);
                    statements(node.body);
                });
            case "ForGenericStatement":
                node.iterators.forEach(expression);
                return block(() => {
                    node.variables.forEach((variable) => declare(variable, "for", null, node));
                    statements(node.body);
                });
            default:
                return;
        }
    }

    function statements(list) {
        for (const node of list) statement(node);
    }

    block(() => statements(ast.body));
    return {
        bindingOf: (identifier) => bindings.get(identifier),
        fileLevel: (binding) => binding.depth === 0,
        references: (binding) => references.get(binding) ?? [],
        reads: (binding) => (references.get(binding) ?? []).filter((identifier) => !writes.has(identifier)),
        all: () => declared,
    };
}

// The static path an expression names, seeing through locals that alias a global or a member
// and are never reassigned (`local UnitPower = UnitPower`, `local E = Enum.PowerType`):
// "UnitHealth", "Enum.PowerType.Energy", "_G". String-literal indexes count (`C_Spell["X"]`), and
// `getfenv()` / `getfenv(0|1)` name "_G", and `getglobal("X")` names "X". Returns null for
// anything dynamic.
export function staticPath(node, scope, seen = new Set()) {
    if (!node) return null;
    if (node.type === "Identifier") {
        const binding = scope.bindingOf(node);
        if (!binding) return node.name;
        if (binding.kind !== "local" || binding.reassigned || !binding.init || seen.has(binding)) return null;
        seen.add(binding);
        return staticPath(binding.init, scope, seen);
    }
    if (node.type === "MemberExpression" && node.indexer === ".") {
        const base = staticPath(node.base, scope, seen);
        return base ? `${base}.${node.identifier.name}` : null;
    }
    if (node.type === "IndexExpression") {
        const key = stringValue(node.index);
        const base = key !== null && staticPath(node.base, scope, seen);
        return base ? `${base}.${key}` : null;
    }
    if (node.type === "CallExpression" && node.base.type === "Identifier" && !scope.bindingOf(node.base)
        && node.base.name === "getfenv") {
        const [level] = node.arguments;
        if (!level || (level.type === "NumericLiteral" && (level.value === 0 || level.value === 1))) return "_G";
    }
    if (node.type === "CallExpression" && node.base.type === "Identifier" && !scope.bindingOf(node.base)
        && node.base.name === "getglobal" && node.arguments.length === 1) {
        return stringValue(node.arguments[0]);
    }
    return null;
}

// "_G.X" and "_G" paths name the global X; everything else is unchanged.
export function globalPath(path) {
    if (path === null) return null;
    return path.startsWith("_G.") ? path.slice(3) : path;
}
