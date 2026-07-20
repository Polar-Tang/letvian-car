-- Bound to every CarTestingConstants.TESTING_CAR_TAG model — a moving dummy
-- for the radar. The model's parts stay anchored; a Heartbeat loop pivots the
-- whole model along the primary part's look vector at the speed set by the
-- model's Speed attribute, reversing to the opposite direction every
-- REVERSE_AFTER seconds.

local RunService = game:GetService("RunService")

local require = require(script.Parent.loader).load(script)

local CarTestingConstants = require("CarTestingConstants")
local Maid = require("Maid")

local TestingCar = {}
TestingCar.ClassName = "TestingCar"
TestingCar.__index = TestingCar

function TestingCar.new(model: Model)
	local self = setmetatable({}, TestingCar)

	self._model = model
	self._maid = Maid.new()

	-- +1 = along the primary part's look vector, -1 = opposite, 0 = parked.
	self._direction = 0
	self._sinceReversed = 0

	-- Cached once: the radar reads speed off AssemblyLinearVelocity, which an
	-- anchored, hand-pivoted part reports as zero — Update writes the true
	-- velocity onto every part so the readout matches the motion.
	self._parts = {}
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			table.insert(self._parts, descendant)
		end
	end

	self:Start()

	-- Tagging alone sets the dummy moving; call Run() again to restart a leg.
	self:Run()

	return self
end

-- Drive loop. Runs for the lifetime of the tag; Update is a no-op while parked.
function TestingCar:Start()
	self._maid:GiveTask(RunService.Heartbeat:Connect(function(deltaTime)
		self:Update(deltaTime)
	end))
end

-- Starts (or restarts) the drive: forward along the primary part's current
-- look direction, flipping to the opposite direction every REVERSE_AFTER
-- seconds.
function TestingCar:Run()
	self._direction = 1
	self._sinceReversed = 0
end

function TestingCar:Update(deltaTime: number)
	if self._direction == 0 then
		return
	end

	local primaryPart = self._model.PrimaryPart
	if not primaryPart then
		return
	end

	self._sinceReversed += deltaTime
	if self._sinceReversed >= CarTestingConstants.REVERSE_AFTER then
		self._sinceReversed -= CarTestingConstants.REVERSE_AFTER
		self._direction = -self._direction
	end

	local speed = self._model:GetAttribute(CarTestingConstants.SPEED_ATTRIBUTE)
	if type(speed) ~= "number" then
		speed = CarTestingConstants.DEFAULT_SPEED
	end

	-- Flatten the look vector onto the XZ plane so a tilted primary part
	-- can't steer the car up or down — height stays wherever it spawned.
	local look = primaryPart.CFrame.LookVector
	local flat = Vector3.new(look.X, 0, look.Z)
	if flat.Magnitude < 1e-4 then
		return
	end

	local velocity = flat.Unit * (speed * self._direction)
	self._model:PivotTo(self._model:GetPivot() + velocity * deltaTime)

	for _, part in self._parts do
		part.AssemblyLinearVelocity = velocity
	end
end

function TestingCar:Destroy()
	-- Untagged mid-drive: zero the written velocity so the radar doesn't keep
	-- reading a parked car as moving.
	for _, part in self._parts do
		part.AssemblyLinearVelocity = Vector3.zero
	end
	self._maid:Destroy()
end

return TestingCar
