--!strict
-- Per-client radar scanner. Every RadarConstants.VEHICLE_TAG model that passes
-- the camera math (range + look-vector cone + line of sight) is kept in a
-- public observable list; RoactUI's RadarProvider subscribes to it and
-- re-renders the tree whenever the list changes.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local CarTestingConstants = require(ReplicatedStorage.Nevermore.Custom.carTesting.src.Shared.CarTestingConstants)

local require = require(script.Parent.loader).load(script)

local Maid = require("Maid")
local RadarConstants = require("RadarConstants")
local ValueObject = require("ValueObject")

local RadarClient = {}
RadarClient.ServiceName = "RadarClient"

function RadarClient:Init(serviceBag)
	assert(not self._serviceBag, "Already initialized")
	self._serviceBag = assert(serviceBag, "No serviceBag")

	self._maid = Maid.new()

	-- The public list ({ Model }). ValueObject makes it observable, so the UI
	-- gets a push on every change instead of polling the scanner.
	self._vehicles = self._maid:Add(ValueObject.new({}))
end

function RadarClient:Start()
	local sinceLastScan = 0
	self._maid:GiveTask(RunService.Heartbeat:Connect(function(deltaTime)
		sinceLastScan += deltaTime
		if sinceLastScan < 1 / RadarConstants.SCAN_RATE then
			return
		end
		sinceLastScan = 0

		local detected = self:_scan()
		-- Two identical scans build two different tables; ValueObject would
		-- treat every one as a change, so only publish when membership moved.
		if not self:_sameVehicles(self._vehicles.Value, detected) then
			self._vehicles.Value = detected
		end
	end))
end

-- Observable list of the vehicles currently on radar, for RadarProvider.
function RadarClient:ObserveVehicles()
	return self._vehicles:Observe()
end

function RadarClient:GetVehicles(): { Model }
	return self._vehicles.Value
end

-- Current display speed of a vehicle, in RadarConstants.SPEED_UNIT.
function RadarClient:GetSpeed(vehicle: Model): number
	local basePart = vehicle.PrimaryPart or vehicle:FindFirstChildWhichIsA("BasePart")
	if not basePart then
		return 0
	end
	local speed = vehicle:GetAttribute(CarTestingConstants.SPEED_ATTRIBUTE) or basePart.AssemblyLinearVelocity.Magnitude * RadarConstants.SPEED_FACTOR
	return speed
end

function RadarClient:_scan(): { Model }
	local camera = workspace.CurrentCamera
	if not camera then
		return {}
	end

	local cameraCFrame = camera.CFrame
	local cameraPosition = cameraCFrame.Position
	local lookDirection = cameraCFrame.LookVector
	local cosThreshold = math.cos(math.rad(RadarConstants.FOV_DEGREES))

	-- One params object for the whole scan: the exclusions (our own character)
	-- are constant across every candidate.
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local character = Players.LocalPlayer.Character
	params.FilterDescendantsInstances = if character then { character } else {}

	local detected: { Model } = {}
	for _, instance in CollectionService:GetTagged(RadarConstants.VEHICLE_TAG) do
		if not instance:IsA("Model") or not instance:IsDescendantOf(workspace) then
			continue
		end

		local toTarget = instance:GetPivot().Position - cameraPosition
		local distance = toTarget.Magnitude
		if distance > RadarConstants.RANGE or distance <= 0 then
			continue
		end

		-- Cone test: dot of the (unit) direction with the camera look vector.
		-- Higher = more centred; below the threshold (or behind) is rejected.
		if lookDirection:Dot(toTarget / distance) < cosThreshold then
			continue
		end

		if not self:_hasLineOfSight(params, cameraPosition, instance) then
			continue
		end

		table.insert(detected, instance)
	end
	return detected
end

-- Line of sight is "can a thin line reach ANY part of the vehicle". One thin
-- ray per body part: each direction's magnitude is the exact distance to that
-- part, so a ray that arrives unobstructed — or whose first hit is the vehicle
-- itself — proves sight even when the rest of the body is behind cover.
function RadarClient:_hasLineOfSight(params: RaycastParams, origin: Vector3, vehicle: Model): boolean
	local sawAnyPart = false
	for _, part in vehicle:GetChildren() do
		if not part:IsA("BasePart") then
			continue
		end
		sawAnyPart = true

		local result = workspace:Raycast(origin, part.Position - origin, params)
		if not result or result.Instance:IsDescendantOf(vehicle) then
			return true
		end
	end

	if not sawAnyPart then
		-- Parts nested deeper than the model root: fall back to one ray at the pivot.
		local result = workspace:Raycast(origin, vehicle:GetPivot().Position - origin, params)
		return not result or result.Instance:IsDescendantOf(vehicle)
	end
	return false
end

function RadarClient:_sameVehicles(previous: { Model }, current: { Model }): boolean
	if #previous ~= #current then
		return false
	end
	-- Element-wise compare keeps this O(n); GetTagged order is stable enough
	-- that a false "changed" (same set, new order) is rare and only costs a
	-- redundant re-render.
	for index, vehicle in current do
		if previous[index] ~= vehicle then
			return false
		end
	end
	return true
end

function RadarClient:Destroy()
	self._maid:DoCleaning()
end

return RadarClient
