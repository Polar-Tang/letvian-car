--!strict
-- Reads the NumberPlate attribute a CarRegister car carries (written server-side
-- by the CarRegister binder) and returns it as a plain string. Returns "" when
-- the instance is nil or has no plate yet, so UI consumers (SpeedTags, BottomBar)
-- can drop the result straight into a TextLabel without nil-guarding.
--
-- Requires by absolute path (not the package loader) so any consumer — including
-- the RoactUI components under StarterPlayerScripts — can require it directly.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CarRegisterConstants =
	require(ReplicatedStorage.Nevermore.Custom.carRegister.src.Shared.CarRegisterConstants)

return function(instance: Instance?): string
	if not instance then
		return ""
	end
	local plate = instance:GetAttribute(CarRegisterConstants.NUMBER_PLATE_ATTRIBUTE)
	return if typeof(plate) == "string" then plate else ""
end
