--!strict
-- Per-client radar scanner. Every RadarConstants.VEHICLE_TAG model within range
-- of the camera with a clear line of sight is kept in a public observable list
-- (full-range — no aim cone, so a target stays tagged wherever it drives relative
-- to the camera); RoactUI's RadarProvider subscribes to it and re-renders on change.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local CarTestingConstants = require(ReplicatedStorage.Nevermore.Custom.carTesting.src.Shared.CarTestingConstants)
-- Required by absolute path (not the loader below): it lives under
-- ReplicatedStorage.Shared, outside the Nevermore package tree.
local CharacterRoot = require(ReplicatedStorage.Shared.Public.CharacterRoot)

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
	-- Keeps self.root on the live HumanoidRootPart across respawns; _scan
	-- excludes its character from the line-of-sight rays. Connection lives on
	-- self._maid (created in Init).
	CharacterRoot.bind(self)

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

-- Raw speed of a vehicle in studs/second: the dummy's Speed attribute is
-- authored in studs/s, and the fallback is the live assembly magnitude. UI
-- consumers convert to km/h (RadarConstants.SPEED_UNIT) via Units at the point
-- they display or threshold it, so the conversion lives in exactly one place.
function RadarClient:GetSpeed(vehicle: Model): number
	local basePart = vehicle.PrimaryPart or vehicle:FindFirstChildWhichIsA("BasePart")
	if not basePart then
		return 0
	end
	local speed = vehicle:GetAttribute(CarTestingConstants.SPEED_ATTRIBUTE) or basePart.AssemblyLinearVelocity.Magnitude
	return speed
end

function RadarClient:_scan(): { Model }
	local camera = workspace.CurrentCamera
	if not camera then
		return {}
	end

	local cameraPosition = camera.CFrame.Position

	-- One params object for the whole scan; the sight exclusions (our character and
	-- the car we're driving) are constant across every candidate.
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = self:_sightExclusions()

	local detected: { Model } = {}
	for _, instance in CollectionService:GetTagged(RadarConstants.VEHICLE_TAG) do
		if not instance:IsA("Model") or not instance:IsDescendantOf(workspace) then
			continue
		end

		-- Full-range radar: any tagged vehicle within range that we can see. No aim
		-- cone, so a target stays on radar wherever it moves relative to the camera.
		local distance = (instance:GetPivot().Position - cameraPosition).Magnitude
		if distance > RadarConstants.RANGE or distance <= 0 then
			continue
		end

		if not self:_hasLineOfSight(params, cameraPosition, instance) then
			continue
		end

		table.insert(detected, instance)
	end
	return detected
end

-- Raycast exclusions for the sight test: our own character and, when we're seated
-- in one, the car we're driving — so neither our body nor our own vehicle can
-- occlude the ray to a target. The own-car case matters now that detection is
-- full-range (no cone): targets can sit right beside or behind us. self.root is
-- the live HumanoidRootPart (kept fresh by CharacterRoot).
function RadarClient:_sightExclusions(): { Instance }
	local exclusions: { Instance } = {}
	local character = self.root and self.root.Parent
	if character then
		table.insert(exclusions, character)

		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if humanoid and humanoid:IsA("Humanoid") then
			local seatPart = humanoid.SeatPart
			if seatPart then
				-- The seat's nearest Model ancestor is the car (an A-Chassis
				-- DriveSeat is a direct child of the car model); excluding it drops
				-- the whole vehicle from the rays.
				local ownCar = seatPart:FindFirstAncestorWhichIsA("Model")
				if ownCar then
					table.insert(exclusions, ownCar)
				end
			end
		end
	end
	return exclusions
end

-- Line of sight is "can a thin line reach the vehicle". The bounding-box centre is
-- the cheap common case (a single cast): a ray that arrives unobstructed — or whose
-- first hit is the vehicle itself — proves sight. Only if the centre is blocked do
-- we walk the real parts (recursively — they nest under Body/Wheels sub-models), so
-- a car that's mostly visible still counts. Short-circuits on the first part in view.
function RadarClient:_hasLineOfSight(params: RaycastParams, origin: Vector3, vehicle: Model): boolean
	local centre = vehicle:GetPivot().Position
	local result = workspace:Raycast(origin, centre - origin, params)
	if not result or result.Instance:IsDescendantOf(vehicle) then
		return true
	end

	for _, part in vehicle:GetDescendants() do
		if not part:IsA("BasePart") then
			continue
		end
		local hit = workspace:Raycast(origin, part.Position - origin, params)
		if not hit or hit.Instance:IsDescendantOf(vehicle) then
			return true
		end
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
