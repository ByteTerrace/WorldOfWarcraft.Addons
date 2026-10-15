// Guard facts for the static gate: which checks dominate each point of a Lua 5.1 chunk.
//
// flow(ast, tests) walks every function in statement order and records, for each Identifier and
// call node, the set of facts that hold there. A fact is a binding known not to be secret (after
// an `issecretvalue(x)` test was false, or `canaccessvalue(x)` true) or NOT_LOCKDOWN (after an
// `InCombatLockdown()` test was false). Facts come only from tests that decide control flow:
//
//   if issecretvalue(x) or ... then return end   x is safe after the if (the branch exits)
//   if not issecretvalue(x) then <here> end      x is safe in the branch
//   issecretvalue(x) or x > 1                    x is safe in the right operand (and/or short-circuit)
//   if InCombatLockdown() then ... return end    not in lockdown after the if
//   local inCombat = InCombatLockdown()           the same, tested through a never-reassigned local
//   if inCombat then return end                   of the same function (its value is this run's)
//
// A test whose result is discarded (`local _ = InCombatLockdown()`) decides nothing. After an
// if, a fact holds only if it holds at the end of every branch that falls through. Loop bodies
// don't export facts. A nested function inherits the binding facts at its definition (a binding
// the tests accept is never reassigned, so it stays non-secret) but not NOT_LOCKDOWN (it runs
// later, when lockdown may have changed).
//
// tests = {
//   secretCheck(call)   -> binding | null   issecretvalue(<binding>): true means secret
//   accessCheck(call)   -> binding | null   canaccessvalue(<binding>): true means not secret
//   lockdownCheck(call) -> boolean          InCombatLockdown()
//   stableBinding(id)   -> binding | null   the never-reassigned local an identifier names
//   exits(call)         -> boolean          a call that never returns (error(...))
// }

export const NOT_LOCKDOWN = "not in combat lockdown";

const EMPTY = new Set();
const isCall = (node) => node?.type === "CallExpression" || node?.type === "StringCallExpression" || node?.type === "TableCallExpression";

function union(a, b) {
    if (!b.size) return a;
    if (!a.size) return b;
    const out = new Set(a);
    for (const key of b) out.add(key);
    return out;
}

function intersect(a, b) {
    return new Set([...a].filter((key) => b.has(key)));
}

export function flow(ast, tests) {
    const at = new Map();
    // The locals of the function being walked that hold its own InCombatLockdown() result. A
    // nested function starts with none: it runs later, when lockdown may have changed.
    let lockdownLocals = new Set();
    const keptLockdown = (node) => node?.type === "Identifier" && lockdownLocals.has(tests.stableBinding(node));

    // Facts that hold when node evaluates truthy (whenTrue) or falsy (whenFalse).
    function whenTrue(node) {
        if (!node) return EMPTY;
        if (node.type === "UnaryExpression" && node.operator === "not") return whenFalse(node.argument);
        if (node.type === "LogicalExpression") {
            return node.operator === "and" ? union(whenTrue(node.left), whenTrue(node.right)) : intersect(whenTrue(node.left), whenTrue(node.right));
        }
        if (isCall(node)) {
            const binding = tests.accessCheck(node);
            if (binding) return new Set([binding]);
        }
        return EMPTY;
    }
    function whenFalse(node) {
        if (!node) return EMPTY;
        if (node.type === "UnaryExpression" && node.operator === "not") return whenTrue(node.argument);
        if (node.type === "LogicalExpression") {
            return node.operator === "or" ? union(whenFalse(node.left), whenFalse(node.right)) : intersect(whenFalse(node.left), whenFalse(node.right));
        }
        if (isCall(node)) {
            const binding = tests.secretCheck(node);
            if (binding) return new Set([binding]);
            if (tests.lockdownCheck(node)) return new Set([NOT_LOCKDOWN]);
        }
        if (keptLockdown(node)) return new Set([NOT_LOCKDOWN]);
        return EMPTY;
    }

    function fn(node, facts) {
        if (node.identifier && node.identifier.type !== "Identifier") expr(node.identifier, facts);
        const outer = lockdownLocals;
        lockdownLocals = new Set();
        block(node.body, new Set([...facts].filter((key) => key !== NOT_LOCKDOWN)));
        lockdownLocals = outer;
    }

    function expr(node, facts) {
        if (!node || typeof node !== "object") return;
        switch (node.type) {
            case "Identifier":
                at.set(node, facts);
                return;
            case "LogicalExpression":
                expr(node.left, facts);
                expr(node.right, union(facts, node.operator === "and" ? whenTrue(node.left) : whenFalse(node.left)));
                return;
            case "FunctionDeclaration":
                return fn(node, facts);
            case "MemberExpression":
                return expr(node.base, facts);
            case "IndexExpression":
                expr(node.base, facts);
                return expr(node.index, facts);
            case "CallExpression":
                at.set(node, facts);
                expr(node.base, facts);
                return node.arguments.forEach((argument) => expr(argument, facts));
            case "StringCallExpression":
                at.set(node, facts);
                expr(node.base, facts);
                return expr(node.argument, facts);
            case "TableCallExpression":
                at.set(node, facts);
                expr(node.base, facts);
                return expr(node.arguments, facts);
            case "TableConstructorExpression":
                for (const field of node.fields) {
                    if (field.type === "TableKey") expr(field.key, facts);
                    expr(field.value, facts);
                }
                return;
            case "BinaryExpression":
                expr(node.left, facts);
                return expr(node.right, facts);
            case "UnaryExpression":
                return expr(node.argument, facts);
            default:
                return;
        }
    }

    // Returns the facts at the end of the block, or null when it can't fall through.
    function block(statements, facts) {
        let current = facts;
        let exited = false;
        for (const node of statements) {
            const out = statement(node, current);
            if (out === null) exited = true;
            else current = out;
        }
        return exited ? null : current;
    }

    function statement(node, facts) {
        switch (node.type) {
            case "LocalStatement":
                node.init.forEach((init) => expr(init, facts));
                node.variables.forEach((variable, i) => {
                    const binding = isCall(node.init[i]) && tests.lockdownCheck(node.init[i]) && tests.stableBinding(variable);
                    if (binding) lockdownLocals.add(binding);
                });
                return facts;
            case "AssignmentStatement":
                node.init.forEach((init) => expr(init, facts));
                node.variables.forEach((target) => (target.type === "Identifier" ? at.set(target, facts) : expr(target, facts)));
                return facts;
            case "CallStatement":
                expr(node.expression, facts);
                return tests.exits(node.expression) ? null : facts;
            case "ReturnStatement":
                node.arguments.forEach((argument) => expr(argument, facts));
                return null;
            case "BreakStatement":
            case "GotoStatement":
                return null;
            case "IfStatement": {
                let otherwise = facts;
                let hasElse = false;
                const outs = [];
                for (const clause of node.clauses) {
                    if (clause.type === "ElseClause") {
                        hasElse = true;
                        outs.push(block(clause.body, otherwise));
                        continue;
                    }
                    expr(clause.condition, otherwise);
                    outs.push(block(clause.body, union(otherwise, whenTrue(clause.condition))));
                    otherwise = union(otherwise, whenFalse(clause.condition));
                }
                if (!hasElse) outs.push(otherwise);
                const live = outs.filter((out) => out !== null);
                return live.length ? live.reduce(intersect) : null;
            }
            case "WhileStatement":
                expr(node.condition, facts);
                block(node.body, union(facts, whenTrue(node.condition)));
                return facts;
            case "RepeatStatement": {
                const out = block(node.body, facts);
                expr(node.condition, out ?? facts);
                return facts;
            }
            case "DoStatement":
                return block(node.body, facts);
            case "ForNumericStatement":
                expr(node.start, facts);
                expr(node.end, facts);
                expr(node.step, facts);
                block(node.body, facts);
                return facts;
            case "ForGenericStatement":
                node.iterators.forEach((iterator) => expr(iterator, facts));
                block(node.body, facts);
                return facts;
            case "FunctionDeclaration":
                fn(node, facts);
                return facts;
            default:
                return facts;
        }
    }

    block(ast.body, EMPTY);
    return { factsAt: (node) => at.get(node) ?? EMPTY };
}
