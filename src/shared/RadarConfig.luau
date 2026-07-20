--!strict
-- Tuning for the police radar. All distances are in studs.

return {
	-- CollectionService tag that marks a car as radar-equipped.
	-- Tag your police car model with this and the radar starts scanning from it.
	PoliceCarTag = "PoliceCar",

	-- Optional tag to explicitly mark a model as radar-detectable.
	-- Models that contain a VehicleSeat are detected automatically without it.
	VehicleTag = "RadarVehicle",

	-- How far ahead of the police car the radar beam reaches.
	Range = 300,

	-- Cross-section (width, height) of the radar beam. A thick beam is more
	-- forgiving than a thin ray when the target is slightly off-center.
	BeamSize = Vector2.new(8, 5),

	-- Beam origin relative to the police car's pivot (X right, Y up, Z back).
	OriginOffset = Vector3.new(0, 2, 0),

	-- How many obstructions (walls, pedestrians) a scan may skip past while
	-- searching for a vehicle before giving up.
	MaxCastHops = 4,

	-- Scans per second.
	ScanRate = 10,

	-- Multiplier from studs/second to the displayed speed.
	-- 1 stud = 0.28 m, so studs/s * 1.008 = km/h; use 0.63 for mph.
	SpeedFactor = 1,
	SpeedUnit = "km/h",

	-- Speed at which the readout flips red and the alarm starts.
	SpeedLimit = 60,

	-- Prints radar readings to the output for testing.
	Debug = true,
}
