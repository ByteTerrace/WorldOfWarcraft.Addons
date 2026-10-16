// The Lua the test runner runs before each test file (tools/lib/test-worker.mjs): test, eq, truthy,
// falsy, throws, pending, and use, plus the runner's own __names and __run. check reads it too, for the
// globals it defines (tools/lib/check-tests.mjs).

export const PRELUDE = `
    local tests = {}
    function test(name, fn) tests[#tests + 1] = { name = name, fn = fn } end
    local function show(v) if type(v) == "string" then return string.format("%q", v) end return tostring(Reveal(v)) end
    function eq(actual, expected, message)
        actual = Reveal(actual)
        if actual ~= expected then
            error((message and (message .. ": ") or "") .. "expected " .. show(expected) .. ", got " .. show(actual), 2)
        end
    end
    function truthy(value, message) if not Reveal(value) then error((message or "expected truthy") .. ", got " .. show(value), 2) end end
    function falsy(value, message) if Reveal(value) then error((message or "expected falsy") .. ", got " .. show(value), 2) end end
    function throws(fn, pattern, message)
        local ok, err = pcall(fn)
        if ok then error((message or "expected an error"), 2) end
        if pattern and not tostring(err):find(pattern) then error("error " .. show(err) .. " does not match " .. show(pattern), 2) end
    end
    -- use(name) runs kits/<name>.lua (beside the test file) once and returns what it returns.
    local kits = {}
    function use(name)
        if kits[name] == nil then
            local source = __kits[name]
            if not source then error("no test kit kits/" .. tostring(name) .. ".lua", 2) end
            kits[name] = assert(loadstring(source, "@kits/" .. name .. ".lua"))()
        end
        return kits[name]
    end
    -- pending(reason) ends a test that can't decide anything yet: it neither passes nor fails.
    local PendingMeta = {}
    function pending(reason) error(setmetatable({ reason = tostring(reason) }, PendingMeta), 0) end
    -- Names and errors cross to JS one per line, tab-separated: backslash, tab, CR and LF are escaped.
    local ESCAPES = { ["\\\\"] = "\\\\\\\\", ["\\t"] = "\\\\t", ["\\r"] = "\\\\r", ["\\n"] = "\\\\n" }
    local function escape(s) return (tostring(s):gsub("[\\\\\\t\\r\\n]", ESCAPES)) end
    function __names()
        local names = {}
        for i, t in ipairs(tests) do names[i] = escape(t.name) end
        return table.concat(names, "\\n")
    end
    -- Status per test: 1 passed, 0 failed, 2 pending. With __coverageOn, the addons' files the
    -- tests load are instrumented (COVERAGE_LUA, tools/lib/coverage.mjs).
    function __run(selected)
        if __coverageOn then __coverageStart() end
        local lines = {}
        for _, t in ipairs(tests) do
            if selected[t.name] then
                Harness.created = {}
                local ok, err = pcall(t.fn)
                local status = ok and "1" or "0"
                if not ok and getmetatable(err) == PendingMeta then
                    ok, status, err = true, "2", err.reason
                end
                if ok then
                    for _, h in ipairs(Harness.created) do
                        local problem = h:UnexpectedErrors()
                        if problem then
                            ok, status, err = false, "0", problem
                            break
                        end
                    end
                end
                local detail = status == "1" and "" or escape(err)
                lines[#lines + 1] = status .. "\\t" .. escape(t.name) .. "\\t" .. detail
            end
        end
        if __coverageOn then __coverageStop() end
        return table.concat(lines, "\\n")
    end
`;
