-- Helpers for the harness's own fidelity tests (tests/harness-*.test.lua). A test file gets the
-- table with use("harness").

--- Records every firing of the named events, in order, each as "EVENT:arg:arg" with its
--- arguments revealed.
---@return table seen
local function Watch(h, ...)
    local seen = {}
    local frame = h.env.CreateFrame("Frame")

    for _, event in ipairs({ ... }) do
        frame:RegisterEvent(event)
    end
    frame:SetScript("OnEvent", function(_, event, ...)
        local parts = { event }

        for i = 1, select("#", ...) do
            parts[#parts + 1] = tostring(Reveal((select(i, ...))))
        end
        seen[#seen + 1] = table.concat(parts, ":")
    end)
    return seen
end

return { Watch = Watch }
