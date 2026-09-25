-- Fixture for the test runner's own tests: names with control characters survive the trip from
-- Lua to the report, and a filter can select them.
test("name with\nnewline", function() eq(1, 1) end)
test("tab\tin name", function() error("line one\nline two") end)
test("back\\slash", function() eq(1, 1) end)
