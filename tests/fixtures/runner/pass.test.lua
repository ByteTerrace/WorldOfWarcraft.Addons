-- Fixture for the test runner's own tests: runs alongside a hanging file and still reports.
test("passes", function()
    eq(1 + 1, 2)
end)
