--!strict
-- Unit conversions between Roblox studs and real-world distance/speed. Studs
-- are the game's native unit (positions, velocities); metres and km/h are what
-- the UI shows.
--
-- Arbitrary conversion: a stud is assumed to be one foot. That single
-- assumption ties the two families together — 5280 studs to the mile and
-- 0.3048 m to the stud are the same foot, so the mph and km/h readouts of the
-- same velocity stay consistent with each other.

local STUDS_PER_MILE = 5280
local METERS_PER_STUD = 0.3048
local METERS_PER_KILOMETER = 1000
local HOUR_SECONDS = 3600

local Units = {}

-- Distance: studs <-> miles
function Units.studsToMiles(studs: number): number
	return studs / STUDS_PER_MILE
end

function Units.milesToStuds(miles: number): number
	return miles * STUDS_PER_MILE
end

-- Distance: studs <-> metres
function Units.studsToMeters(studs: number): number
	return studs * METERS_PER_STUD
end

function Units.metersToStuds(meters: number): number
	return meters / METERS_PER_STUD
end

-- Speed: studs/second <-> miles/hour
function Units.studsPerSecondToMilesPerHour(studsPerSecond: number): number
	local milesPerSecond = Units.studsToMiles(studsPerSecond)
	local milesPerHour = milesPerSecond * HOUR_SECONDS
	return milesPerHour
end

function Units.milesPerHourToStudsPerSecond(milesPerHour: number): number
	local studsPerHour = Units.milesToStuds(milesPerHour)
	local studsPerSecond = studsPerHour / HOUR_SECONDS
	return studsPerSecond
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

return Units
