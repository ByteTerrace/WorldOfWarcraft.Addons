-- Fixture for the check gate's own tests: this file calls no setter that can give a widget a
-- secret aspect, so getters on its frames and plain tables aren't secret: no findings.
local Frame = CreateFrame("Frame")
local Width = Frame:GetWidth()
local Id = Frame:GetID()
local Category = Settings.RegisterVerticalLayoutCategory("x")
local Plain = {}
Plain.GetValue = function() return 1 end
print(Width, Id, Category:GetID(), Plain.GetValue(Plain), Frame.GetHeight(Frame))
