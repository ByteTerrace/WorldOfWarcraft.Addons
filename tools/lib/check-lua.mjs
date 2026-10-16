// The per-file Lua rules of the check verb: GLOBAL, MEMBER, EVENT, SECRET, PROTECTED, FRAMEWORK, and ARGS.
// See tools/verbs/check.mjs for what each rule enforces and what it can't see.

import { NOT_LOCKDOWN, flow } from "./lua-flow.mjs";
import { analyze, globalPath, parse, staticPath, stringValue, walk } from "./lua-scope.mjs";

const EVENT_METHODS = new Set(["On", "RegisterEvent", "RegisterUnitEvent", "UnregisterEvent", "Fire", "IsEventRegistered"]);
const REGISTERING_METHODS = new Set(["On", "RegisterEvent", "RegisterUnitEvent"]);
// Client tables that exist for addons to add entries to.
const REGISTRIES = new Set(["SlashCmdList", "StaticPopupDialogs"]);
// Functions that compile or re-scope code the gate can't follow.
const OPAQUE_ENVIRONMENT = {
    setfenv: "setfenv changes a function's environment",
    loadstring: "loadstring compiles code the gate can't see",
    load: "load compiles code the gate can't see",
};
const REGION_FACTORIES = new Set(["CreateFontString", "CreateTexture", "CreateMaskTexture", "CreateLine", "CreateAnimationGroup"]);
const UNIT_TYPES = new Set(["UnitToken", "UnitTokenVariant", "UnitTokenNamePlate", "UnitTokenPvPRestrictedForAddOns", "UnitTokenRestrictedForAddOns"]);
const SECRET_CALL = "check issecretvalue on each result before any use or annotate \"-- secret: <why>\"";
// Client APIs and events ByteTerrace_Core owns, with what an addon built on it uses instead.
const TIMERS = "a module timer (module:After, module:Every), which runs as a batch and stops with its module";
const COMMS = "a module's comms (comms = { prefix }), which keeps Blizzard's addon message rules";
const SETTINGS = "declared rows: the framework generates the settings panel";
const FRAMEWORK_CALLS = {
    "C_Timer.After": TIMERS,
    "C_Timer.NewTimer": TIMERS,
    "C_Timer.NewTicker": TIMERS,
    "C_ChatInfo.SendAddonMessage": COMMS,
    "C_ChatInfo.SendAddonMessageLogged": COMMS,
    "C_ChatInfo.RegisterAddonMessagePrefix": COMMS,
    PlaySoundFile: "a sound bank (ByteTerrace.NewSoundBank)",
    "Settings.RegisterProxySetting": SETTINGS,
    "Settings.RegisterAddOnSetting": SETTINGS,
    "Settings.RegisterAddOnCategory": SETTINGS,
    "Settings.RegisterVerticalLayoutCategory": SETTINGS,
    "Settings.RegisterCanvasLayoutCategory": SETTINGS,
};
const FRAMEWORK_EVENTS = { CHAT_MSG_ADDON: COMMS, CHAT_MSG_ADDON_LOGGED: COMMS };
// Script handlers that receive an event payload.
const EVENT_SCRIPTS = new Set(["SetScript", "HookScript"]);

export const callBase = (node) => (node?.type === "CallExpression" || node?.type === "StringCallExpression" || node?.type === "TableCallExpression") ? node.base : null;
export const callArgs = (node) => node.type === "CallExpression" ? node.arguments : node.type === "StringCallExpression" ? [node.argument] : [node.arguments];

// Annotation comments by kind. Only `--` line comments count. One on the line of the construct
// always counts. One on the line above counts only when it's alone on its line.
function collectAnnotations(comments, lines) {
    const annotations = { secret: { on: new Set(), above: new Set() }, protected: { on: new Set(), above: new Set() }, global: { on: new Set(), above: new Set() } };
    for (const comment of comments ?? []) {
        if (!comment.raw.startsWith("--") || /^--\[=*\[/.test(comment.raw)) continue;
        const match = /^\s*(secret|protected|global):\s*\S/.exec(comment.value);
        if (!match) continue;
        const line = comment.loc.start.line;
        annotations[match[1]].on.add(line);
        if (lines[line - 1].slice(0, comment.loc.start.column).trim() === "") annotations[match[1]].above.add(line);
    }
    return annotations;
}

export function checkLua(file, text, context, report) {
    const { api, known, clientGlobal, writes, framework } = context;
    let ast;
    try {
        ast = parse(text);
    } catch (error) {
        report(file, error.line ?? 1, "PARSE", error.message);
        return;
    }
    const scope = analyze(ast);
    const annotations = collectAnnotations(ast.comments, text.split("\n"));
    const annotated = (kind, line) => annotations[kind].on.has(line) || annotations[kind].above.has(line - 1);
    const path = (node) => globalPath(staticPath(node, scope));
    const line = (node) => node.loc.start.line;
    const isClient = (name) => clientGlobal(name.split(".")[0]);
    const hasCanAccess = api.globals.has("canaccessvalue");

    // The binding a guard call tests: issecretvalue(x) / canaccessvalue(x), x a never-reassigned local.
    const testedBinding = (call, fn) => {
        const base = callBase(call);
        if (!base || path(base) !== fn) return null;
        const [argument] = callArgs(call);
        const binding = argument?.type === "Identifier" && scope.bindingOf(argument);
        return binding && !binding.reassigned ? binding : null;
    };
    const facts = flow(ast, {
        secretCheck: (call) => testedBinding(call, "issecretvalue"),
        accessCheck: (call) => (hasCanAccess ? testedBinding(call, "canaccessvalue") : null),
        lockdownCheck: (call) => path(callBase(call)) === "InCombatLockdown",
        stableBinding: (identifier) => {
            const binding = identifier?.type === "Identifier" && scope.bindingOf(identifier);
            return binding && !binding.reassigned ? binding : null;
        },
        exits: (call) => path(callBase(call)) === "error",
    });

    // The member a call base names (`obj:M`, `obj.M`, or `obj["M"]`), or null when it names none.
    const memberName = (base) => {
        if (base?.type === "MemberExpression") return base.identifier.name;
        if (base?.type === "IndexExpression") return stringValue(base.index);
        return null;
    };
    // A method call's name, for `obj:M()`, and for `obj.M(...)` and `obj["M"](...)` when that isn't a
    // client API path.
    const methodName = (base) => {
        const member = memberName(base);
        if (member === null) return null;
        if (base.indexer === ":") return member;
        const name = path(base);
        return name && (api.functions[name] || isClient(name)) ? null : member;
    };
    // The event argument of an event method call: the first, or the second when a `.` or `[]` call
    // passes its receiver first (frame.RegisterEvent(frame, "EVENT")).
    const eventArgument = (base, args) => (base.indexer !== ":" && isMethodCall(base, args) ? args[1] : args[0]);
    // A forbidden function or method a path names: "SetRaidTarget", or "SettingsPanel:Open" for the
    // path "SettingsPanel.Open". It's null when the path names neither.
    const forbiddenPath = (name) => {
        if (!name || !api.forbiddenFunctions) return null;
        if (api.forbiddenFunctions.has(name)) return name;
        const asMethod = name.replace(/\.([^.]+)$/, ":$1");
        return asMethod !== name && api.forbiddenFunctions.has(asMethod) ? asMethod : null;
    };

    // Pre-pass: guard arguments, aspects this file's setters can make secret, receivers' events,
    // Secure frame creation, and field assignments of frames.
    const guardArguments = new Set();
    const setAspects = new Set();
    const registered = new Map(); // receiver key -> Set of event names
    const secureParents = new Set();
    const fieldFrames = new Map(); // receiver key -> Set of "secure" | "insecure" | "other"
    let fileHasSecure = false;
    const ids = new Map();
    const receiverKey = (node) => {
        if (node?.type === "Identifier") {
            const binding = scope.bindingOf(node);
            if (!binding) return `global:${node.name}`;
            if (!ids.has(binding)) ids.set(binding, ids.size);
            return `local:${ids.get(binding)}`;
        }
        if (node?.type === "MemberExpression" && node.indexer === ".") {
            const base = receiverKey(node.base);
            return base && `${base}.${node.identifier.name}`;
        }
        return null;
    };
    const maySecure = (call) => {
        if (path(callBase(call)) !== "CreateFrame") return false;
        const template = callArgs(call)[3];
        return template !== undefined && (stringValue(template) === null || /Secure/.test(stringValue(template)));
    };
    const eventName = (node) => {
        const literal = stringValue(node);
        if (literal !== null) return literal;
        const binding = node?.type === "Identifier" && scope.bindingOf(node);
        if (binding && binding.kind === "local" && scope.fileLevel(binding) && !binding.reassigned) return stringValue(binding.init);
        return null;
    };
    const parents = new Map(); // node -> the node it's a child of
    walk(ast.body, (node, ancestors) => {
        const parent = ancestors[ancestors.length - 1];
        parents.set(node, parent);
        const base = callBase(node);
        if (base) {
            const args = callArgs(node);
            if ((path(base) === "issecretvalue" || (hasCanAccess && path(base) === "canaccessvalue")) && args[0]?.type === "Identifier") guardArguments.add(args[0]);
            const method = methodName(base);
            for (const aspect of (method && api.aspectSetters.get(method)) ?? []) setAspects.add(aspect);
            if (method === "RegisterEvent" || method === "RegisterUnitEvent") {
                const key = receiverKey(base.base);
                const event = eventName(eventArgument(base, args));
                if (key && event) (registered.get(key) ?? registered.set(key, new Set()).get(key)).add(event);
            }
            if (maySecure(node)) {
                fileHasSecure = true;
                const key = receiverKey(args[2]);
                if (key) secureParents.add(key);
            }
        }
        if (node.type === "AssignmentStatement") {
            node.variables.forEach((target, i) => {
                if (target.type !== "MemberExpression") return;
                const key = receiverKey(target);
                const init = node.init[i];
                const kind = path(callBase(init)) === "CreateFrame" ? (maySecure(init) ? "secure" : "insecure") : "other";
                if (key) (fieldFrames.get(key) ?? fieldFrames.set(key, new Set()).get(key)).add(kind);
            });
        }
    });

    // Secret payload parameters of event handlers passed as function literals:
    //   X:On("EVENT", function(payload...))                 (ByteTerrace modules and events)
    //   X:RegisterEvent("EVENT", function(event, payload...)) (callback-style event registries)
    //   frame:SetScript("OnEvent", function(self, event, payload...)) for the events this file
    //   registers on that frame.
    // A vararg handler's payload is read from `...`: `local a, b = ...` at the top of its body binds
    // a and b to the payload fields `...` starts at.
    const payloadParams = new Map(); // binding -> { event, flags }
    const markParameter = (identifier, index, events) => {
        for (const event of events) {
            const entry = api.eventEntries[event];
            if (!entry?.secret?.length) continue;
            const types = entry.Payload ?? [];
            const kind = types[index] ?? types[types.length - 1];
            if (!kind || UNIT_TYPES.has(kind)) continue;
            payloadParams.set(scope.bindingOf(identifier), { event, flags: entry.secret });
            return;
        }
    };
    const markPayload = (fn, events, offset) => {
        fn.parameters.forEach((parameter, i) => {
            if (i < offset) return;
            if (parameter.type === "Identifier") {
                markParameter(parameter, i - offset, events);
            } else if (parameter.type === "VarargLiteral") {
                for (const statement of fn.body) {
                    if (statement.type !== "LocalStatement" || statement.init.length !== 1 || statement.init[0].type !== "VarargLiteral") continue;
                    statement.variables.forEach((variable, k) => markParameter(variable, i - offset + k, events));
                }
            }
        });
    };
    walk(ast.body, (node) => {
        const base = callBase(node);
        const method = memberName(base);
        if (!method) return;
        const args = callArgs(node);
        const receiverFirst = base.indexer !== ":" && isMethodCall(base, args) ? 1 : 0;
        const fn = args[1 + receiverFirst]?.type === "FunctionDeclaration" ? args[1 + receiverFirst] : null;
        if (!fn) return;
        if (method === "On" || method === "RegisterEvent") {
            const event = eventName(args[receiverFirst]);
            if (event) markPayload(fn, [event], method === "On" ? 0 : 1);
        } else if (EVENT_SCRIPTS.has(method) && stringValue(args[receiverFirst]) === "OnEvent") {
            markPayload(fn, [...(registered.get(receiverKey(base.base)) ?? [])], 2);
        }
    });

    // Aspect-derived and anchoring secrets count only where this file's setters can create them.
    const methodReasons = (method) => {
        const info = method && api.methodSecrets.get(method);
        if (!info) return null;
        const reasons = [...info.flags];
        if (info.anchoring && setAspects.size) reasons.push("SecretWhenAnchoringSecret");
        for (const aspect of info.aspects) if (setAspects.has(aspect)) reasons.push(`${aspect} aspect`);
        return reasons.length ? reasons : null;
    };

    // A global write to `name` (null = dynamic key), from a statement at node.
    const globalWrite = (name, node, dynamicKey) => {
        if (name !== null) {
            writes.push({ name, file, line: line(node) });
        } else if (!annotated("global", line(node)) && !isSlashKey(dynamicKey)) {
            report(file, line(node), "GLOBAL", "global write with a dynamic key; annotate \"-- global: <why>\"");
        }
    };
    // An assignment into table[key] (key null = dynamic) where table may be a client global.
    const memberWrite = (table, key, node) => {
        const base = path(table);
        if (!base || !isClient(base) || REGISTRIES.has(base.split(".")[0]) || annotated("global", line(node))) return;
        report(file, line(node), "GLOBAL", `assignment into client global ${base}.${key ?? "[?]"}; annotate "-- global: <why>" if intended`);
    };
    // Assignment targets: X, _G.X / _G["X"] / _G[k], getfenv().X, and client.member.
    const assignTo = (target, node) => {
        if (target.type === "Identifier") {
            if (!scope.bindingOf(target)) globalWrite(target.name, node);
            return;
        }
        const basePath = path(target.base);
        if (basePath === "_G") {
            const key = target.type === "MemberExpression" ? target.identifier.name : stringValue(target.index);
            globalWrite(key, node, target.index);
        } else if (target.type === "MemberExpression" || target.type === "IndexExpression") {
            memberWrite(target.base, target.type === "MemberExpression" ? target.identifier.name : stringValue(target.index), node);
        }
    };

    const secretCalls = new Set(); // call bases already judged, so they aren't judged as values
    const reportedPayload = new Set();
    walk(ast.body, (node, ancestors) => {
        const parent = ancestors[ancestors.length - 1];

        if (node.type === "AssignmentStatement") node.variables.forEach((target) => assignTo(target, node));
        if (node.type === "FunctionDeclaration" && node.identifier && !node.isLocal) assignTo(node.identifier, node);

        // Framework-owned functions taken as values (an alias, a callback) reach past it too. Calls
        // are reported below.
        const isMemberName = parent?.type === "MemberExpression" && parent.identifier === node;
        const isChainBase = parent?.type === "MemberExpression" && parent.base === node;
        const isLocal = node.type === "Identifier" && scope.bindingOf(node); // the alias was reported where it was made
        if (framework && (node.type === "MemberExpression" || node.type === "Identifier") && !isMemberName
            && !isChainBase && !isLocal && callBase(parent) !== node) {
            const owned = path(node);
            if (owned && FRAMEWORK_CALLS[owned]) {
                report(file, line(node), "FRAMEWORK", `${owned} belongs to the framework; use ${FRAMEWORK_CALLS[owned]}`);
            }
        }

        // Global reads.
        if (node.type === "Identifier" && !scope.bindingOf(node)) {
            const isWriteTarget = (parent?.type === "AssignmentStatement" && parent.variables.includes(node))
                || (parent?.type === "FunctionDeclaration" && parent.identifier === node);
            const isName = (parent?.type === "MemberExpression" && parent.identifier === node)
                || (parent?.type === "TableKeyString" && parent.key === node)
                || (parent?.type === "FunctionDeclaration" && parent.parameters.includes(node));
            if (!isWriteTarget && !isName && !known.has(node.name)) {
                report(file, line(node), "GLOBAL", `read of unknown global ${node.name}`);
            }
        }

        // Secret event payload parameters compared, computed with or branched on.
        const payload = node.type === "Identifier" && payloadParams.get(scope.bindingOf(node));
        if (payload && !reportedPayload.has(scope.bindingOf(node)) && decides(node, parent)
            && !facts.factsAt(node).has(scope.bindingOf(node)) && !annotated("secret", line(node))) {
            reportedPayload.add(scope.bindingOf(node));
            report(file, line(node), "SECRET", `${payload.event} payload parameter ${node.name} can be secret (${payload.flags.join(", ")}); `
                + "check issecretvalue before comparing, computing or branching on it, or annotate \"-- secret: <why>\"");
        }

        // Member chains, at the outermost static node of each chain. Assignment targets are GLOBAL's.
        if ((node.type === "MemberExpression" && node.indexer === ".") || (node.type === "IndexExpression" && stringValue(node.index) !== null)) {
            const partOfChain = (parent?.type === "MemberExpression" && parent.base === node && parent.indexer === ".")
                || (parent?.type === "IndexExpression" && parent.base === node && stringValue(parent.index) !== null);
            const isTarget = (parent?.type === "AssignmentStatement" && parent.variables.includes(node))
                || (parent?.type === "FunctionDeclaration" && parent.identifier === node);
            const full = path(node);
            if (!partOfChain && !isTarget && full) {
                const raw = staticPath(node, scope);
                if (raw.startsWith("_G.") && !full.includes(".") && !known.has(full)) {
                    report(file, line(node), "GLOBAL", `read of unknown global ${full}`);
                } else if (isClient(full)) {
                    const missing = unknownMember(api, full);
                    if (missing) report(file, line(node), "MEMBER", `${missing} is not in the API snapshot`);
                }
            }
        }

        const base = callBase(node);
        if (base) {
            const args = callArgs(node);
            const name = path(base);
            const method = methodName(base);

            // A client table's method called with `:` exists in the snapshot (C_GamePad:Nope()).
            if (base.type === "MemberExpression" && base.indexer === ":") {
                const table = path(base.base);
                const missing = table && isClient(table) && unknownMember(api, `${table}.${base.identifier.name}`);
                if (missing) report(file, line(node), "MEMBER", `${missing} is not in the API snapshot`);
            }

            // Events.
            if (EVENT_METHODS.has(memberName(base))) {
                const event = eventName(eventArgument(base, args));
                if (event && /^[A-Z][A-Z0-9_]+$/.test(event) && !api.events.has(event)) {
                    report(file, line(node), "EVENT", `unknown event ${event}`);
                } else if (event && REGISTERING_METHODS.has(memberName(base)) && api.eventEntries[event]?.HasRestrictions) {
                    report(file, line(node), "EVENT", `${event} is restricted to Blizzard's code; registering it is refused (ADDON_ACTION_FORBIDDEN)`);
                }
                if (framework && FRAMEWORK_EVENTS[event]) {
                    report(file, line(node), "FRAMEWORK", `${event} belongs to the framework; use ${FRAMEWORK_EVENTS[event]}`);
                }
            }

            // Argument counts of documented client functions. A `:` call passes a receiver the docs
            // don't count, so it's skipped.
            const documented = name && base.indexer !== ":" && isClient(name) && Object.hasOwn(api.functions, name) ? api.functions[name] : null;
            const mismatch = documented && argumentMismatch(documented, args);
            if (mismatch) report(file, line(node), "ARGS", `${name} ${mismatch}`);

            // Client APIs the framework owns.
            if (framework && name && FRAMEWORK_CALLS[name]) {
                report(file, line(node), "FRAMEWORK", `${name} belongs to the framework; use ${FRAMEWORK_CALLS[name]}`);
            }

            // Global access through functions, and frame names.
            const key = stringValue(args[1]);
            if (name === "rawset" && args[0] && path(args[0]) === "_G") globalWrite(stringValue(args[1]), node, args[1]);
            else if (name === "rawset" && args[0]) memberWrite(args[0], stringValue(args[1]), node);
            if (name === "setglobal") globalWrite(stringValue(args[0]), node, args[0]);
            if (name === "getglobal" && stringValue(args[0]) !== null && !known.has(stringValue(args[0]))) {
                report(file, line(node), "GLOBAL", `read of unknown global ${stringValue(args[0])}`);
            }
            if (name === "CreateFrame" && key !== null && clientGlobal(key)) {
                report(file, line(node), "GLOBAL", `frame name ${key} collides with a client global`);
            }
            const level = args[0];
            if (name === "getfenv" && level && !(level.type === "NumericLiteral" && (level.value === 0 || level.value === 1))
                && !annotated("global", line(node))) {
                report(file, line(node), "GLOBAL", "getfenv with a level other than 0 or 1 reaches another function's environment; annotate \"-- global: <why>\"");
            }
            if (OPAQUE_ENVIRONMENT[name] && !annotated("global", line(node))) {
                report(file, line(node), "GLOBAL", `${OPAQUE_ENVIRONMENT[name]}; annotate "-- global: <why>"`);
            }

            // Secrets.
            const flags = name ? api.functions[name]?.secret : null;
            const reasons = flags?.length ? null : methodReasons(method);
            if (flags?.length || reasons) {
                secretCalls.add(base);
                const label = flags?.length ? name : `:${method}()`;
                if (!secretGuarded(node, parent)) {
                    report(file, line(node), "SECRET", `${label} can return a secret (${(flags?.length ? flags : reasons).join(", ")}); ${SECRET_CALL}`);
                } else if (annotated("secret", line(node))) {
                    annotatedMisuse(node, parent, label);
                }
            }

            // Protected calls: a forbidden function fails at any time, and the rest need a combat guard.
            // A forbidden method is recorded as "Global:Method" (SettingsPanel:OpenToCategory), and
            // counts called with `:`, or with `.` or `[]` passing its receiver first.
            const member = memberName(base);
            const methodPath = member && isMethodCall(base, args) && path(base.base) ? `${path(base.base)}:${member}` : null;
            const forbiddenName = api.forbiddenFunctions?.has(name) ? name : api.forbiddenFunctions?.has(methodPath) ? methodPath : null;
            const forbiddenReason = forbiddenName ? api.forbiddenFunctions.get(forbiddenName) : null;
            if (forbiddenReason && !annotated("protected", line(node))) {
                report(file, line(node), "PROTECTED", `${forbiddenName} is forbidden to addon code at any time (${forbiddenReason}); `
                    + "no combat guard helps, so don't call it");
            }
            const protectedReason = forbiddenReason ? null : protectedCall(name, method, base, args);
            if (protectedReason && !annotated("protected", line(node)) && !facts.factsAt(node).has(NOT_LOCKDOWN)) {
                report(file, line(node), "PROTECTED", `${name ?? `:${method}()`} can be blocked during combat lockdown (${protectedReason}); `
                    + "guard it with an InCombatLockdown() test that returns early (or a `not InCombatLockdown()` branch), or annotate \"-- protected: <why>\"");
            }
        }

        // A secret-returning function used as a value escapes the call-site checks.
        if ((node.type === "Identifier" || node.type === "MemberExpression" || node.type === "IndexExpression") && !secretCalls.has(node)) {
            const isCallBase = parent && callBase(parent) === node;
            const partOfChain = (parent?.type === "MemberExpression" || parent?.type === "IndexExpression") && parent.base === node;
            const isName = (parent?.type === "MemberExpression" && parent.identifier === node)
                || (parent?.type === "TableKeyString" && parent.key === node);
            const isDeclaration = (parent?.type === "LocalStatement" && parent.variables.includes(node))
                || (parent?.type === "FunctionDeclaration" && (parent.identifier === node || parent.parameters.includes(node)))
                || ((parent?.type === "ForGenericStatement" || parent?.type === "ForNumericStatement")
                    && (parent.variables?.includes(node) || parent.variable === node));
            const isTest = (parent?.type === "IfClause" || parent?.type === "ElseifClause") && parent.condition === node
                || (parent?.type === "UnaryExpression" && parent.operator === "not");
            const isTarget = parent?.type === "AssignmentStatement" && parent.variables.includes(node);
            if (!isCallBase && !partOfChain && !isName && !isDeclaration && !isTest && !isTarget) {
                const name = path(node);
                // A forbidden or protected function taken as a value (an alias, pcall's argument)
                // is called where no gate looks.
                // A local alias was reported where it was made. A name the client lacks is MEMBER's.
                const viaAlias = (node.type === "Identifier" && scope.bindingOf(node)) || (name && isClient(name) && unknownMember(api, name));
                const forbiddenValue = !viaAlias && forbiddenPath(name);
                const protectedValue = !viaAlias && !forbiddenValue && name && api.protectedFunctions.has(name) ? name : null;
                if ((forbiddenValue || protectedValue) && !annotated("protected", line(node))) {
                    report(file, line(node), "PROTECTED", forbiddenValue
                        ? `${forbiddenValue} is forbidden to addon code at any time (${api.forbiddenFunctions.get(forbiddenValue)}); don't take it as a value`
                        : `${protectedValue} can be blocked during combat lockdown (${api.protectedFunctions.get(protectedValue)}) and is passed as a value, so its calls skip the combat guard; annotate "-- protected: <why>"`);
                }
                const flags = name ? api.functions[name]?.secret : null;
                // A never-reassigned local alias of a function is followed to its calls.
                const aliasIndex = parent?.type === "LocalStatement" ? parent.init.indexOf(node) : -1;
                const alias = aliasIndex >= 0 && parent.variables[aliasIndex] && !scope.bindingOf(parent.variables[aliasIndex]).reassigned;
                const method = !flags?.length && node.type === "MemberExpression" && node.indexer === "." ? methodName(node) : null;
                const reasons = method ? methodReasons(method) : null;
                if (((flags?.length && !alias) || reasons) && !annotated("secret", line(node))) {
                    report(file, line(node), "SECRET", `${name ?? `.${method}`} can return a secret (${(flags?.length ? flags : reasons).join(", ")}) and is passed as a value, `
                        + "so its results skip the call-site check; annotate \"-- secret: <why>\"");
                }
            }
        }
    });

    function isSlashKey(keyNode) {
        // _G["SLASH_" .. key .. i] declares a slash command alias.
        let node = keyNode;
        while (node?.type === "BinaryExpression" && node.operator === "..") node = node.left;
        return stringValue(node)?.startsWith("SLASH_") ?? false;
    }

    // An annotated secret call (`-- secret: <why>`) assigned to locals: the annotation vouches for
    // the call, not for every later use. A use that compares or computes with the value, tests it,
    // or keys a table with it is reported unless a guard dominates it or it carries its own
    // annotation. Passing it on, storing it, and indexing it (a structure's fields) are left to the
    // harness, whose secrets throw on indexing.
    // Assigned to an existing local, the uses that count are those after the assignment.
    function annotatedMisuse(call, parent, label) {
        if (parent?.type !== "LocalStatement" && parent?.type !== "AssignmentStatement") return;
        const index = parent.init.indexOf(call);
        if (index < 0) return;
        const targets = index === parent.init.length - 1 ? parent.variables.slice(index) : [parent.variables[index]];
        const after = parent.type === "AssignmentStatement" ? line(call) : 0;
        for (const target of targets) {
            const binding = target?.type === "Identifier" && scope.bindingOf(target);
            if (!binding) continue;
            for (const ref of scope.references(binding)) {
                if (line(ref) <= after || (parents.get(ref)?.type === "AssignmentStatement" && parents.get(ref).variables.includes(ref))) continue;
                const refParent = parents.get(ref);
                const passed = refParent && callBase(refParent) && callBase(refParent) !== ref && callArgs(refParent).includes(ref);
                if (passed || guardArguments.has(ref) || facts.factsAt(ref).has(binding) || annotated("secret", line(ref))) continue;
                if (operates(ref, refParent)) {
                    report(file, line(ref), "SECRET", `${ref.name} holds ${label}'s result; the annotation on line ${line(call)} covers the call, `
                        + "not this use, which errors on a secret: check issecretvalue before it, or annotate \"-- secret: <why>\"");
                }
            }
        }
    }

    // Whether a use operates on the value itself: compared or computed with (not `..`, which the
    // client allows), tested, or used as a table key.
    function operates(node, parent) {
        if (!parent) return false;
        if (parent.type === "BinaryExpression") return parent.operator !== "..";
        if (parent.type === "UnaryExpression") return true;
        if (parent.type === "LogicalExpression") return parent.left === node || operates(parent, parents.get(parent));
        if (parent.type === "IfClause" || parent.type === "ElseifClause" || parent.type === "WhileStatement" || parent.type === "RepeatStatement") {
            return parent.condition === node;
        }
        if (parent.type === "TableKey") return parent.key === node;
        return parent.type === "IndexExpression" && parent.index === node;
    }

    // Whether an identifier's value decides something, or is kept where later code could do those
    // things unchecked. It decides something when it's compared, computed with, tested, indexed,
    // called, or used as a key. It's kept when it's assigned (to a local, a field, or a global), put
    // in a table, or carried out of an and/or into one of those.
    function decides(node, parent) {
        if (!parent) return false;
        if (parent.type === "AssignmentStatement" || parent.type === "LocalStatement") return parent.init.includes(node);
        if (parent.type === "TableValue" || parent.type === "TableKeyString") return parent.value === node;
        if (parent.type === "TableKey") return parent.value === node || parent.key === node;
        if (parent.type === "IndexExpression" && parent.index === node) return true;
        if (parent.type === "BinaryExpression" || parent.type === "UnaryExpression") return true;
        if (parent.type === "LogicalExpression") return parent.left === node || decides(parent, parents.get(parent));
        if (parent.type === "IfClause" || parent.type === "ElseifClause" || parent.type === "WhileStatement" || parent.type === "RepeatStatement") {
            return parent.condition === node;
        }
        if ((parent.type === "MemberExpression" || parent.type === "IndexExpression") && parent.base === node) return true;
        return callBase(parent) === node;
    }

    // "secure" | "insecure" | "unknown": whether a receiver is (or may be) a frame from a Secure
    // template, or the parent of one.
    function frameKind(receiver, depth = 0) {
        if (depth > 10) return "unknown";
        const key = receiverKey(receiver);
        if (key && secureParents.has(key)) return "secure";
        if (receiver?.type === "Identifier") {
            const binding = scope.bindingOf(receiver);
            if (!binding || binding.kind !== "local" || binding.reassigned || !binding.init) return "unknown";
            const init = binding.init;
            if (path(callBase(init)) === "CreateFrame") return maySecure(init) ? "secure" : "insecure";
            if (REGION_FACTORIES.has(methodName(callBase(init)))) return "insecure";
            if (init.type === "Identifier" || init.type === "MemberExpression") return frameKind(init, depth + 1);
            return "unknown";
        }
        if (key && fieldFrames.has(key)) {
            const kinds = fieldFrames.get(key);
            if (kinds.has("secure")) return "secure";
            if (kinds.size === 1 && kinds.has("insecure")) return "insecure";
        }
        return "unknown";
    }

    // A `.` or `[]` call is a method call only when it passes its receiver first
    // (frame.Show(frame), frame["Show"](frame)). Probes.Show(value) is a plain function that happens
    // to share a method's name.
    function isMethodCall(base, args) {
        if (base.indexer === ":") return true;
        const receiver = base.base, first = args[0];
        return Boolean(first) && receiver?.type === "Identifier" && first.type === "Identifier" && first.name === receiver.name;
    }

    function protectedCall(name, method, base, args) {
        if (name && api.protectedFunctions.has(name)) return api.protectedFunctions.get(name);
        if (!method || !isMethodCall(base, args)) return null;
        if (api.restrictedMethods.has(method)) return "HasRestrictions";
        if (!api.protectedMethods.has(method)) return null;
        const kind = frameKind(base.base);
        if (kind === "secure") return "protected method on a Secure frame";
        if (kind === "unknown" && fileHasSecure) return "protected method on a frame not proven non-Secure, in a file that creates Secure frames";
        return null;
    }

    // Guarded: annotated, directly inside issecretvalue(...), or assigned to fresh locals (each
    // never reassigned) whose every use an issecretvalue test dominates.
    function secretGuarded(call, parent) {
        if (annotated("secret", line(call))) return true;
        if (parent && callBase(parent) && ["issecretvalue", hasCanAccess && "canaccessvalue"].includes(path(callBase(parent)))
            && callArgs(parent)[0] === call) return true;
        if (parent?.type !== "LocalStatement") return false;
        const index = parent.init.indexOf(call);
        if (index < 0) return false;
        const targets = index === parent.init.length - 1 ? parent.variables.slice(index) : [parent.variables[index]];
        // `_` discards a result only when nothing reads it.
        const discarded = (t) => t.name === "_" && scope.references(scope.bindingOf(t)).length === 0;
        return targets.filter((t) => t && !discarded(t)).every((target) => {
            const binding = scope.bindingOf(target);
            if (!binding || binding.reassigned) return false;
            return scope.references(binding).every((ref) => guardArguments.has(ref) || facts.factsAt(ref).has(binding));
        });
    }
}

// How a call's argument count disagrees with a documented function's Arguments, or null. A call
// whose last argument is a call or `...` passes an unknown count, so it's never judged. Required
// positions are those the docs don't mark Nilable or give a Default, and that aren't a
// LuaValueReference (which takes nil, as the harness's fakes do). The snapshot doesn't record the
// docs' StrideIndex (an argument that repeats), and every documented function with one ends in a
// LuaValueReference or LuaValueVariant (Mixin, scrub, securecallmethod), so a function ending in
// either is judged only for the arguments before it.
function argumentMismatch(entry, args) {
    const last = args[args.length - 1];
    if (last && (callBase(last) || last.type === "VarargLiteral")) return null;
    const types = entry.Arguments ?? [];
    const repeats = /^LuaValue(Reference|Variant)$/.test(types[types.length - 1] ?? "");
    const nilable = new Set(entry.ArgumentsNilable ?? []);
    const plural = (n) => `${n} argument${n === 1 ? "" : "s"}`;
    if (!repeats && args.length > types.length) return `passes ${plural(args.length)} but its documentation declares ${types.length}`;
    let required = 0;
    types.forEach((type, i) => {
        if (!nilable.has(i + 1) && type !== "LuaValueReference" && !(repeats && i === types.length - 1)) required = i + 1;
    });
    if (args.length < required) {
        return `passes ${plural(args.length)} but argument #${required} (${types[required - 1]}) isn't nilable in its documentation`;
    }
    return null;
}

// The first segment of a static path that the snapshot says doesn't exist ("Enum.PowerType.Nope"),
// or null when every checkable segment exists. A table with no recorded members isn't checked.
function unknownMember(api, path) {
    const parts = path.split(".");
    for (let i = 1; i < parts.length; i++) {
        const table = parts.slice(0, i).join(".");
        const keys = api.members.get(table);
        if (!keys || keys.size === 0) return null;
        if (!keys.has(parts[i])) return parts.slice(0, i + 1).join(".");
    }
    return null;
}
