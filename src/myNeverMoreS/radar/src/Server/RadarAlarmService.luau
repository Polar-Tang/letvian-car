--!strict
-- Server owner of the radar over-limit alarm Sound. The client (RadarAlarmView)
-- decides WHEN the alarm should sound and fires the RadarConstants.ALARM_REMOTE
-- RemoteEvent with a boolean; this service creates a single looping Sound on the
-- police car the firing player is driving (true) or destroys it (false), so the
-- alarm is positional and replicated to every nearby client instead of being a
-- client-local 2D sound. The car is resolved server-side from the player's seat —
-- the client's boolean is the only thing trusted.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local require = require(script.Parent.loader).load(script)

local Maid = require("Maid")
local RadarConstants = require("RadarConstants")
-- assets lives under ReplicatedStorage.Shared, outside the Nevermore package tree.
local assets = require(ReplicatedStorage.Shared.Public.assets)

-- Name of the Sound instance we parent onto the car, so we can find/dedupe it.
local SOUND_NAME = "RadarOverLimitAlarm"

local RadarAlarmService = {}
RadarAlarmService.ServiceName = "RadarAlarmService"

function RadarAlarmService:Init(serviceBag)
	assert(not self._serviceBag, "Already initialized")
	self._serviceBag = assert(serviceBag, "No serviceBag")

	self._maid = Maid.new()
	-- One live Sound per player (the car they're driving). Keyed by player so a
	-- second "play" never stacks a second sound and "stop"/leaving removes exactly
	-- the one we made.
	self._sounds = {} :: { [Player]: Sound }

	-- Publish the RemoteEvent under the shared RemoteEvents folder (reuse the one
	-- the place ships, or make it), so the client can wait for and fire it.
	local folder = ReplicatedStorage:FindFirstChild("RemoteEvents")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "RemoteEvents"
		folder.Parent = ReplicatedStorage
	end
	local remote = folder:FindFirstChild(RadarConstants.ALARM_REMOTE)
	if not remote then
		remote = Instance.new("RemoteEvent")
		remote.Name = RadarConstants.ALARM_REMOTE
		remote.Parent = folder
	end
	self._remote = remote :: RemoteEvent
end

function RadarAlarmService:Start()
	self._maid:GiveTask(self._remote.OnServerEvent:Connect(function(player: Player, shouldPlay)
		self:_setAlarm(player, shouldPlay == true)
	end))
	-- A player leaving mid-blare would orphan its Sound on the car; drop it.
	self._maid:GiveTask(Players.PlayerRemoving:Connect(function(player: Player)
		self:_stop(player)
	end))
end

function RadarAlarmService:_setAlarm(player: Player, shouldPlay: boolean)
	if shouldPlay then
		self:_play(player)
	else
		self:_stop(player)
	end
end

function RadarAlarmService:_play(player: Player)
	if self._sounds[player] then
		return -- already sounding for this player; don't stack
	end
	local adornee = self:_resolveCarPart(player)
	if not adornee then
		return -- not seated in a car right now; nothing to attach to
	end

	local sound = Instance.new("Sound")
	sound.Name = SOUND_NAME
	sound.SoundId = assets.radar.warnSound
	sound.Looped = true
	sound.Parent = adornee
	sound:Play()
	self._sounds[player] = sound
end

function RadarAlarmService:_stop(player: Player)
	local sound = self._sounds[player]
	if sound then
		sound:Destroy()
		self._sounds[player] = nil
	end
end

-- The BasePart to parent the Sound to: the driven car's PrimaryPart (or any part),
-- found from the player's current VehicleSeat. nil if they aren't seated in a car.
function RadarAlarmService:_resolveCarPart(player: Player): BasePart?
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not (humanoid and humanoid:IsA("Humanoid")) then
		return nil
	end
	local seat = humanoid.SeatPart
	if not seat then
		return nil
	end
	-- The seat's nearest Model ancestor is the car (an A-Chassis DriveSeat is a
	-- direct child of the car model). Fall back to the seat itself if unmodelled.
	local car = seat:FindFirstAncestorWhichIsA("Model")
	if car and car:IsA("Model") then
		return car.PrimaryPart or car:FindFirstChildWhichIsA("BasePart", true) or seat
	end
	return seat
end

function RadarAlarmService:Destroy()
	for _, sound in self._sounds do
		sound:Destroy()
	end
	self._sounds = {}
	self._maid:DoCleaning()
end

return RadarAlarmService
