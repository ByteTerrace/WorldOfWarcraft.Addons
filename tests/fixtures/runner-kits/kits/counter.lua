-- Fixture for the test runner's own tests: a kit counts how often it ran.
Loads = (Loads or 0) + 1

return {
    Double = function(value) return value * 2 end,
}
