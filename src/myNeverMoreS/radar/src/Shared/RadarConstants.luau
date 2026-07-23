--!strict
-- Shared radar tuning. Tag keys live here so the client scanner, the UI and
-- any later server-side validation all agree on them.

return {
	-- CollectionService tag that marks a model as radar-detectable.
	VEHICLE_TAG = "RadarVehicle",
	-- Tag for the police car itself (reserved for later server-side work).
	POLICE_CAR_TAG = "PoliceCar",

	-- Detection cone around the camera's look vector.
	RANGE = 300, -- studs
	FOV_DEGREES = 35, -- max angle off-centre before a vehicle drops off radar

	-- Scans per second.
	SCAN_RATE = 10,

	-- Display unit for speed. GetSpeed returns raw studs/second; the UI converts
	-- to this unit with Units.studsPerSecondToKilometersPerHour.
	SPEED_UNIT = "km/h",

	-- Speed at which the readout flips red and the alarm starts, in SPEED_UNIT
	-- (km/h) — compared against the converted speed, not raw studs/second.
	SPEED_LIMIT = 60,
}
