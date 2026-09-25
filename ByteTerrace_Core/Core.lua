-- ByteTerrace: the shared framework behind ByteTerrace addons.
--
-- An addon builds one isolated AddOn (AddOn.lua) and declares Modules on it. Everything a module
-- does flows through four systems, modeled on Puck's command, input and state systems:
--
--   State    (State.lua)    declared, typed rows; one admission path; versioned; one publication
--                           pass per event batch that drives watchers and edge/level rules.
--   Events   (Events.lua)   one dispatcher; handlers register lazily and are isolated from each
--                           other; each dispatch is one state batch.
--   Commands (Commands.lua) named intents; slash text, key bindings, controller buttons and UI all
--                           run the same definition.
--   Input    (Input.lua)    positional controller vocabulary, per-family labels, and binding maps
--                           that route buttons to commands.
--
-- Declare once, compile once: names resolve to dense integer ids when the addon loads, and the
-- hot paths index arrays. Declaring after compile is an error.

ByteTerrace = {}

local geterrorhandler = geterrorhandler
local pairs, sort = pairs, table.sort

-- Sorted string keys of a table: the one ordering every compile step uses, so ids are the same
-- on every load regardless of declaration order.
function ByteTerrace.SortedKeys(t)
    local keys = {}
    for key in pairs(t) do
        keys[#keys + 1] = key
    end
    sort(keys)
    return keys
end

-- Hands an error to the client's error handler (script errors window, BugSack) and continues.
function ByteTerrace.Report(message)
    geterrorhandler()(message)
end

-- Raises every problem at once, so a bad declaration reports all of its mistakes in one pass.
function ByteTerrace.Refuse(owner, problems)
    if #problems > 0 then
        error(owner .. ":\n  " .. table.concat(problems, "\n  "), 0)
    end
end
