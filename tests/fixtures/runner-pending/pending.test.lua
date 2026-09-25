-- Fixture for the test runner's own tests: a pending test is reported, counted and doesn't fail.
test("passes", function()
    eq(1 + 1, 2)
end)

test("waits", function()
    pending("no observation yet")
    error("unreachable")
end)
