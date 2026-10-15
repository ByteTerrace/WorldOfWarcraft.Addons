-- Fixture for the test runner's --coverage: loads ByteTerrace_Core's files and nothing more,
-- so its files' top levels run, and no other addon's.
test("loads the framework", function()
    local h = Harness.New()
    h:LoadFiles("ByteTerrace_Core")
end)
