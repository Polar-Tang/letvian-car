--!strict
-- Unit conversions between Roblox studs and real-world distance/speed. Studs
-- are the game's native unit (positions, velocities); metres, km/h and mph are
-- what the UI shows.
--
-- The scale is COPIED FROM A-CHASSIS so the dashboard and the car's own
-- speedometer can never disagree. The chassis' own units module (A-Chassis 1.7,
-- at `car["A-Chassis Tune"].README.Units`) declares:
--
--     Units.Length_mm      = 280                        -- 1 stud = 0.28 m
--     Units.Velocity_mdivs = 1/(Units.Length_mm/1000)   -- studs per m/s
--
-- and reads a velocity back as km/h with
-- `studsPerSecond / (Units.Velocity_mdivs / 3.6)` -- which is exactly what
-- studsPerSecondToKilometersPerHour works out to below (both are
-- `studsPerSecond * 1.008`). `Tune.SpeedLimit` is in these same km/h, so a cap
-- of 61 set by the SpeedLimitPicker reads 61 on the radar tag and the BottomBar
-- too.
--
-- Everything else is DERIVED from that one metres-per-stud figure, so the km/h
-- and mph readouts of the same velocity stay consistent with each other and
-- with the chassis. If the car's `Units.Length_mm` ever changes, change
-- LENGTH_MM here to match -- and nothing else.

-- A-Chassis' Units.Length_mm: millimetres of real-world length to one stud.
local LENGTH_MM = 280

local MILLIMETERS_PER_METER = 1000
local METERS_PER_STUD = LENGTH_MM / MILLIMETERS_PER_METER
-- The exact international mile, so the mph family is pinned to the same metre
-- the km/h family uses rather than a second, independent assumption.
local METERS_PER_MILE = 1609.344
local METERS_PER_KILOMETER = 1000
local HOUR_SECONDS = 3600

local Units = {}

-- Published so callers needing the raw scale (or a sanity check against the
-- chassis) don't have to re-derive it from a conversion.
Units.METERS_PER_STUD = METERS_PER_STUD
-- A-Chassis' Units.Velocity_mdivs: studs of Roblox velocity per real m/s.
Units.VELOCITY_MDIVS = 1 / METERS_PER_STUD

-- Distance: studs <-> metres
function Units.studsToMeters(studs: number): number
	return studs * METERS_PER_STUD
end

function Units.metersToStuds(meters: number): number
	return meters / METERS_PER_STUD
end

-- Distance: studs <-> miles (via metres, so one scale governs both families)
function Units.studsToMiles(studs: number): number
	return Units.studsToMeters(studs) / METERS_PER_MILE
end

function Units.milesToStuds(miles: number): number
	return Units.metersToStuds(miles * METERS_PER_MILE)
end

-- Speed: studs/second <-> kilometres/hour
function Units.studsPerSecondToKilometersPerHour(studsPerSecond: number): number
	local metersPerSecond = Units.studsToMeters(studsPerSecond)
	local metersPerHour = metersPerSecond * HOUR_SECONDS
	return metersPerHour / METERS_PER_KILOMETER
end

function Units.kilometersPerHourToStudsPerSecond(kilometersPerHour: number): number
	local metersPerHour = kilometersPerHour * METERS_PER_KILOMETER
	local metersPerSecond = metersPerHour / HOUR_SECONDS
	return Units.metersToStuds(metersPerSecond)
end

-- Speed: studs/second <-> miles/hour
function Units.studsPerSecondToMilesPerHour(studsPerSecond: number): number
	local milesPerSecond = Units.studsToMiles(studsPerSecond)
	local milesPerHour = milesPerSecond * HOUR_SECONDS
	return milesPerHour
end

function Units.milesPerHourToStudsPerSecond(milesPerHour: number): number
	local milesPerSecond = milesPerHour / HOUR_SECONDS
	return Units.milesToStuds(milesPerSecond)
end

return Units
