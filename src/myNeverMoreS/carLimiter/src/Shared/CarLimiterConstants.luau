--!strict
-- Config for the A-Chassis speed limiter. The caps the SpeedLimitPicker GUI
-- offers live here so the UI and CarLimiterClient agree on them (tuning values
-- are constants, not literals -- same rule as CarTestingConstants/RadarConstants).

return {
	-- Caps the GUI offers, in km/h -- written verbatim into the car's
	-- `Tune.SpeedLimit`. Shared/Public/Units.luau copies A-Chassis' scale, so
	-- these are the same km/h the radar tag, the BottomBar and the car's own
	-- speedometer all show. Both sit over RadarConstants.SPEED_LIMIT (60) on
	-- purpose: 61 is "just over", 110 "well over", so the tag's green -> red
	-- flip and the alarm can each be exercised from the driver's seat.
	PRESETS = { 61, 110 },

	-- Attribute the limiter stamps on the driven car with the active cap
	-- (cleared when uncapped). Client-local -- attributes written on a client do
	-- not replicate -- so it exists to make the cap visible in the Studio
	-- explorer during a playtest.
	LIMIT_ATTRIBUTE = "SpeedLimitKmh",
}
