--!strict
-- Config for the A-Chassis speed limiter. The caps the SpeedLimitPicker GUI
-- offers live here so the UI and CarLimiterClient agree on them (tuning values
-- are constants, not literals -- same rule as CarTestingConstants/RadarConstants).

return {
	-- Caps the GUI offers. Written verbatim into the car's `Tune.SpeedLimit`, so
	-- these are the CHASSIS's km/h -- see the units note in CarLimiterClient: a
	-- radar readout of the same car runs ~8.9% higher, because A-Chassis scales
	-- 1 stud = 0.28m and Shared/Public/Units.luau assumes 0.3048m. Both presets
	-- still land well over RadarConstants.SPEED_LIMIT (60) either way, which is
	-- the point: 61 is "just over", 110 "well over", so the tag's green -> red
	-- flip and the alarm can each be exercised from the driver's seat.
	PRESETS = { 61, 110 },

	-- Attribute the limiter stamps on the driven car with the active cap
	-- (cleared when uncapped). Client-local -- attributes written on a client do
	-- not replicate -- so it exists to make the cap visible in the Studio
	-- explorer during a playtest.
	LIMIT_ATTRIBUTE = "SpeedLimitKmh",
}
