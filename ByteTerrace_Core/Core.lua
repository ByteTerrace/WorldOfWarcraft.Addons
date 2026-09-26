-- ByteTerrace: the shared framework behind ByteTerrace addons (this addon is ByteTerrace_Core;
-- its one global is `ByteTerrace`).
--
-- An addon builds one isolated AddOn (AddOn.lua) and declares Modules on it. Everything a module
-- does flows through four systems, modeled on Puck's command, input and state systems:
--
--   State    (State.lua)    declared, typed rows; one admission path; versioned; one publication
--                           pass per batch that drives watchers and edge rules.
--   Events   (Events.lua)   one dispatcher; handlers register lazily and are isolated from each
--                           other; each dispatch is one state batch.
--   Commands (Commands.lua) named intents; slash text, key bindings, controller buttons and UI all
--                           run the same definition; each run is one state batch.
--   Input    (Input.lua)    positional controller vocabulary, per-family labels, and binding maps
--                           that route buttons to commands.
--
-- Records (Records.lua) are keyed collections of typed records that persist like rows. Modules
-- (Module.lua) own their handlers, watchers, rules and timers, and can depend on demand modules.
-- Names (Names.lua) reads players' names as Forever gives them (first and surname, no realm),
-- Comms (Comms.lua) are a module's group messages, SoundBank (SoundBank.lua) plays player-supplied
-- sounds, Facts (Facts*.lua) publish shared game state, and Diagnostics (Diagnostics.lua) is the
-- built-in debug command.
--
-- Declare once, compile once: names resolve to dense integer ids when the addon loads, and the
-- hot paths index arrays. Declaring after compile is an error.
--
-- This file loads first and exports the helpers every other file uses: SortedKeys, Report,
-- SafeCall and Refuse. ByteTerrace.Errors counts the errors SafeCall has caught since load, in
-- every ByteTerrace addon (debug status shows it).

local geterrorhandler, xpcall = geterrorhandler, xpcall
local pairs, sort = pairs, table.sort

ByteTerrace = { Errors = 0 }

-- Looked up only when an error happens, so a handler installed later (BugSack) still receives
-- it. Blizzard's CallErrorHandler does the same.
local function OnError(message)
    ByteTerrace.Errors = ByteTerrace.Errors + 1
    return geterrorhandler()(message)
end

--- The sorted string keys of a table: the one ordering every compile step uses, so ids are the
--- same on every load regardless of declaration order.
---@param t table
---@return string[]
function ByteTerrace.SortedKeys(t)
    local keys = {}
    for key in pairs(t) do
        keys[#keys + 1] = key
    end
    sort(keys)
    return keys
end

--- Hands an error to the client's error handler (script errors window, BugSack) and continues.
---@param message string
function ByteTerrace.Report(message)
    geterrorhandler()(message)
end

--- Calls fn(...) so that an error reaches the client's error handler with its own stack (the
--- handler runs before the stack unwinds) and the caller continues. WoW's xpcall passes extra
--- arguments through, as Blizzard's own CallErrorHandler usage does.
---@param fn function
---@return boolean ok true when fn returned without an error
function ByteTerrace.SafeCall(fn, ...)
    return xpcall(fn, OnError, ...)
end

--- Raises every problem at once, so a bad declaration reports all of its mistakes in one pass.
--- Does nothing when problems is empty.
---@param owner string prefixes the message, e.g. "MyAddon state"
---@param problems string[]
function ByteTerrace.Refuse(owner, problems)
    if #problems > 0 then
        error(owner .. ":\n  " .. table.concat(problems, "\n  "), 0)
    end
end
