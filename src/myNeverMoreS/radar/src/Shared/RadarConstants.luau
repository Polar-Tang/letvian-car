--!strict
-- Shared radar tuning. Tag keys live here so the client scanner, the UI and
-- any later server-side validation all agree on them.

return {
	-- CollectionService tag that marks a model as radar-detectable.
	VEHICLE_TAG = "RadarVehicle",
	-- Tag for the police car itself (reserved for later server-side work).
	POLICE_CAR_TAG = "PoliceCar",

	-- RemoteEvent (under ReplicatedStorage.RemoteEvents) the client fires so the
	-- SERVER plays/stops the over-limit alarm Sound on the driven car — so every
	-- nearby client hears it. See radar/src/Server/RadarAlarmService and
	-- RoactUI/components/RadarAlarm.
	ALARM_REMOTE = "RadarAlarm",

	-- How far the radar reaches from the camera. No aim cone — any tagged vehicle
	-- within this range with a clear line of sight is detected (see RadarClient._scan).
	RANGE = 500, -- studs

	-- Scans per second.
	SCAN_RATE = 10,

	-- Display unit for speed. GetSpeed returns raw studs/second; the UI converts
	-- to this unit with Units.studsPerSecondToKilometersPerHour.
	SPEED_UNIT = "km/h",

	-- Speed at which the readout flips red and the alarm starts, in SPEED_UNIT
	-- (km/h) — compared against the converted speed, not raw studs/second.
	SPEED_LIMIT = 60,
}
