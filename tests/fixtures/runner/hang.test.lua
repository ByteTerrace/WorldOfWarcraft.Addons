-- Fixture for the test runner's own tests: a test that never returns must fail its file on the
-- timeout without stopping the other files.
test("never returns", function()
    while true do end
end)
