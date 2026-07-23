--!strict
-- Per-client tracker of the car the LOCAL player is currently driving. A "car"
-- is a CarRegisterConstants.CAR_REGISTER_TAG model; "driving" means the local
-- character's Humanoid is seated in a VehicleSeat that belongs to such a model
-- (a passenger Seat, or standing, counts as not driving). The driven car is
-- published as an observable so RoactUI's CarProvider can show the BottomBar —
-- with the car's NumberPlate — only while the player is behind the wheel. Same
-- "inject the started service into MainApp" pattern as RadarClient.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")

local require = require(script.Parent.loader).load(script)

local Maid = require("Maid")
local ValueObject = require("ValueObject")
local CarRegisterConstants = require("CarRegisterConstants")

local CarRegisterClient = {}
CarRegisterClient.ServiceName = "CarRegisterClient"

function CarRegisterClient:Init(serviceBag)
	assert(not self._serviceBag, "Already initialized")
	self._serviceBag = assert(serviceBag, "No serviceBag")

	self._maid = Maid.new()
	-- The CarRegister-tagged Model the local player is driving, or nil. Observable
	-- so the UI gets a push the instant they sit down / stand up. Typed nil so the
	-- value type is Model? (not nil) under strict mode.
	self._drivenCar = self._maid:Add(ValueObject.new(nil :: Model?))
end

function CarRegisterClient:Start()
	local player = Players.LocalPlayer

	-- Re-hook per character: a respawn swaps the Humanoid out. A nested maid holds
	-- the current character's connections so each spawn starts clean.
	local characterMaid = self._maid:Add(Maid.new())
	local function onCharacter(character: Model)
		characterMaid:DoCleaning()
		self._drivenCar.Value = nil

		-- Runs on the CharacterAdded thread (or a spawned one for the character
		-- that already exists at Start), so this WaitForChild can't yield the
		-- ServiceBag's Start.
		local humanoid = character:WaitForChild("Humanoid", 10)
		if not (humanoid and humanoid:IsA("Humanoid")) then
			return
		end

		characterMaid:GiveTask(humanoid.Seated:Connect(function()
			self:_evaluate(humanoid)
		end))
		-- Catch a character that spawned already seated.
		self:_evaluate(humanoid)
	end

	self._maid:GiveTask(player.CharacterAdded:Connect(onCharacter))
	if player.Character then
		task.spawn(onCharacter, player.Character)
	end
end

-- Sets the driven car from the humanoid's current seat: the tagged car it belongs
-- to when seated in a VehicleSeat (the driver control seat), else nil.
function CarRegisterClient:_evaluate(humanoid: Humanoid)
	local seat = humanoid.SeatPart
	local car: Model? = nil
	if seat and seat:IsA("VehicleSeat") then
		car = self:_findTaggedCar(seat)
	end
	self._drivenCar.Value = car
end

-- Walks up from the seat to the nearest ancestor Model carrying the CarRegister
-- tag — that's the car whose NumberPlate the BottomBar shows.
function CarRegisterClient:_findTaggedCar(seat: BasePart): Model?
	local instance: Instance? = seat
	while instance do
		if instance:IsA("Model")
			and CollectionService:HasTag(instance, CarRegisterConstants.CAR_REGISTER_TAG)
		then
			return instance
		end
		instance = instance.Parent
	end
	return nil
end

-- Observable of the driven CarRegister car (or nil), for CarProvider.
function CarRegisterClient:ObserveDrivenCar()
	return self._drivenCar:Observe()
end

function CarRegisterClient:GetDrivenCar(): Model?
	return self._drivenCar.Value
end

function CarRegisterClient:Destroy()
	self._maid:DoCleaning()
end

return CarRegisterClient
