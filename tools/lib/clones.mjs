// The clones verb's detector: Puck's clone analyzer (`puck scan --only clones`), mapped to Lua.
// It clusters structurally identical code, two passes deep:
//
//   unit   a function body (a declaration or a function expression).
//   block  a nested body (if, elseif, else, loops, do) of at least minStatements statements,
//          reported only when no enclosing unit or block is itself in a cluster, so a function's
//          inner blocks never count twice.
//
// The detector fingerprints each body twice over its tokens, and whitespace and comments don't
// count: a structural fingerprint with every identifier and literal replaced by a placeholder, and
// an exact one over the tokens' text. The structural one still matches a copy with renamed
// variables or changed constants. Clusters share a structural fingerprint and weigh at least
// minTokens tokens. `exact` says how many of a cluster's members are token for token the same. The
// output is ordered, so runs diff cleanly.

import luaparse from "luaparse";
import { parse, walk } from "./lua-scope.mjs";

export const DefaultMinStatements = 4;
export const DefaultMinTokens = 30;

const Types = luaparse.tokenTypes;

function lexTokens(text) {
    const lexer = luaparse.parse(text, { wait: true, ranges: true, luaVersion: "5.1", encodingMode: "pseudo-latin1" });
    const tokens = [];
    for (;;) {
        const token = lexer.lex();
        if (token.type === Types.EOF) return tokens;
        tokens.push(token);
    }
}

function placeholder(token) {
    switch (token.type) {
        case Types.Identifier: return "\u0002I";
        case Types.StringLiteral: return "\u0002S";
        case Types.NumericLiteral: return "\u0002N";
        default: return token.value;
    }
}

function lineOf(starts, position) {
    let low = 0;
    let high = starts.length - 1;
    while (low < high) {
        const middle = (low + high + 1) >> 1;
        if (starts[middle] <= position) low = middle;
        else high = middle - 1;
    }
    return low + 1;
}

// The units and blocks of one file: { kind, name, start, end, weight, structural, exact, node, owners }.
function bodiesOf(path, text, minStatements) {
    const ast = parse(text);
    const tokens = lexTokens(text);
    const starts = [0];
    for (let i = text.indexOf("\n"); i >= 0; i = text.indexOf("\n", i + 1)) starts.push(i + 1);
    const tokensIn = (start, end) => {
        let low = 0;
        let high = tokens.length;
        while (low < high) {
            const middle = (low + high) >> 1;
            if (tokens[middle].range[0] < start) low = middle + 1;
            else high = middle;
        }
        const found = [];
        for (let i = low; i < tokens.length && tokens[i].range[1] <= end; i++) found.push(tokens[i]);
        return found;
    };
    const bodies = [];
    walk(ast.body, (node, ancestors) => {
        const isUnit = node.type === "FunctionDeclaration";
        const isBlock = !isUnit && Array.isArray(node.body) && node.body.length >= minStatements;
        if ((!isUnit && !isBlock) || !node.body.length) return;
        const first = node.body[0];
        const last = node.body[node.body.length - 1];
        const body = tokensIn(first.range[0], last.range[1]);
        const name = isUnit ? nameOf(node, ancestors) : `${node.type.replace(/Statement|Clause/, "").toLowerCase()} block`;
        bodies.push({
            kind: isUnit ? "unit" : "block",
            path,
            name,
            start: lineOf(starts, node.range[0]),
            end: lineOf(starts, node.range[1]),
            weight: body.length,
            structural: body.map(placeholder).join("\u0001"),
            exact: body.map((token) => token.value).join("\u0001"),
            node,
            owners: ancestors.filter((ancestor) => ancestor.type === "FunctionDeclaration" || Array.isArray(ancestor.body)),
        });
    });
    return bodies;
}

function nameOf(node, ancestors) {
    const identifier = node.identifier;
    if (identifier?.type === "Identifier") return identifier.name;
    if (identifier?.type === "MemberExpression") return `${expressionName(identifier.base)}${identifier.indexer}${identifier.identifier.name}`;
    const parent = ancestors[ancestors.length - 1];
    if (parent?.type === "TableKeyString") return parent.key.name;
    if (parent?.type === "LocalStatement" || parent?.type === "AssignmentStatement") {
        const variable = parent.variables[parent.init.indexOf(node)];
        if (variable) return expressionName(variable);
    }
    return "function";
}

function expressionName(node) {
    if (node.type === "Identifier") return node.name;
    if (node.type === "MemberExpression") return `${expressionName(node.base)}${node.indexer}${node.identifier.name}`;
    if (node.type === "IndexExpression") return `${expressionName(node.base)}[${node.index.raw ?? expressionName(node.index)}]`;
    return "?";
}

function cluster(bodies, minTokens) {
    const groups = new Map();
    for (const body of bodies) {
        if (body.weight < minTokens) continue;
        const group = groups.get(body.structural) ?? [];
        group.push(body);
        groups.set(body.structural, group);
    }
    return [...groups.values()].filter((group) => group.length > 1);
}

/**
 * Finds the clone clusters among files ({ path, text }), heaviest first.
 * @returns {{ weight: number, exact: number, members: { kind, path, name, start, end }[] }[]}
 */
export function findClones(files, { minTokens = DefaultMinTokens, minStatements = DefaultMinStatements } = {}) {
    const bodies = files.flatMap(({ path, text }) => bodiesOf(path, text, minStatements));
    // Units come first, then blocks outside every clustered unit and block, outermost first.
    const clustered = new Set();
    const result = [];
    const take = (groups) => {
        for (const group of groups) {
            const members = group.filter((body) => !body.owners.some((owner) => clustered.has(owner)));
            if (members.length < 2) continue;
            for (const member of members) clustered.add(member.node);
            const exactCounts = new Map();
            for (const member of members) exactCounts.set(member.exact, (exactCounts.get(member.exact) ?? 0) + 1);
            const exact = Math.max(...exactCounts.values());
            result.push({ weight: members[0].weight, exact: exact > 1 ? exact : 0, members });
        }
    };
    const byDepth = (a, b) => a[0].owners.length - b[0].owners.length;
    take(cluster(bodies.filter((body) => body.kind === "unit"), minTokens).sort(byDepth));
    const blocks = cluster(bodies.filter((body) => body.kind === "block"), minTokens).sort(byDepth);
    take(blocks);
    const order = (a, b) => a.path.localeCompare(b.path) || a.start - b.start;
    return result
        .map((found) => ({ ...found, members: found.members.map(({ kind, path, name, start, end }) => ({ kind, path, name, start, end })).sort(order) }))
        .sort((a, b) => b.weight * b.members.length - a.weight * a.members.length || order(a.members[0], b.members[0]));
}
