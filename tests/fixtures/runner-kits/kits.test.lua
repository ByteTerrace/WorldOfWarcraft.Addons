-- Fixture for the test runner's own tests: use(name) returns the kit beside the test folder, and
-- runs it once however many tests use it.
test("a kit's helpers", function()
    eq(use("counter").Double(4), 8)
end)

test("the same kit, run once", function()
    eq(use("counter"), use("counter"))
    eq(Loads, 1)
end)

test("a kit that isn't there", function()
    throws(function() use("missing") end, "no test kit kits/missing.lua")
end)
