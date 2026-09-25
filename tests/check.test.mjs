// The check gate's own tests: run it over a fixture addon with one violation per rule and
// require exactly the expected findings, so a rule that stops firing (or starts misfiring) fails.

import { join } from "node:path";
import { repoRoot } from "../tools/lib/repo.mjs";
import { runChecks } from "../tools/verbs/check.mjs";

const EXPECTED = [
    "BadAddon/BadAddon_Camelot.toc:1: TOC ## Interface 11507 but the installed client is 16001",
    "BadAddon/BadAddon_Camelot.toc:1: TOC dependency MissingAddon is not an addon in this repository",
    "BadAddon/BadAddon_Camelot.toc:1: TOC lists Missing.lua, which does not exist",
    "BadAddon/Orphan.lua:1: TOC not listed in BadAddon_Camelot.toc",
    "BadAddon/Bad.lua:15: STYLE trailing whitespace",
    "BadAddon/Bad.lua:4: EVENT unknown event NOT_A_REAL_EVENT",
    "BadAddon/Bad.lua:5: SECRET UnitHealth can return a secret (SecretReturns); check issecretvalue or annotate \"-- secret: <why>\"",
    "BadAddon/Bad.lua:6: MEMBER C_GamePad.NotARealFunction is not in the API snapshot",
    "BadAddon/Bad.lua:7: GLOBAL read of unknown global NotARealGlobal",
    "BadAddon/Bad.lua:8: GLOBAL write to undeclared global LeakedGlobal (declare it in ## X-Globals)",
];

export const tests = [
    {
        name: "check reports exactly one finding per planted violation",
        run: async () => {
            const findings = await runChecks({ quiet: true, root: join(repoRoot, "tests", "fixtures", "check"), clientInterface: 16001 });
            const missing = EXPECTED.filter((f) => !findings.includes(f));
            const unexpected = findings.filter((f) => !EXPECTED.includes(f));
            if (missing.length || unexpected.length) {
                throw new Error(`missing: ${JSON.stringify(missing)} unexpected: ${JSON.stringify(unexpected)}`);
            }
        },
    },
];
