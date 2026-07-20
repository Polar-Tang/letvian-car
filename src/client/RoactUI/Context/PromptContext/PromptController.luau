local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local Maid = require(ReplicatedStorage.Nevermore.Quenty.maid.Shared.Maid)

local PromptController = {}
-- PlayerQuestHandler.lua
PromptController.__index = PromptController

function PromptController.new(prompt: ProximityPrompt, disconnectPrompt)
	local self = setmetatable({}, PromptController)
	self.prompt = prompt
	self.promptId = prompt.ObjectText
	self.hiddePrompt = disconnectPrompt

	self._maid = Maid.new()
	self.distanceCheckConnection = nil
	self.timer = 0
	self.lastTime = 0

	return self
end

function PromptController:StartCheckDistance()
	local distanceCheckConnection = RunService.Heartbeat:Connect(function(deltaTime)
		local timer = self.timer
		local lastTime = self.lastTime
		self.timer = timer + deltaTime
		if timer - lastTime >= 1 then
			self.lastTime = timer
			local hrp = player.Character and player.Character.PrimaryPart
			--print("hrp prompty", hrp)
			--print("prompy parent ", prompty.Parent)
			local prompty = self.prompt
			if not hrp or not prompty.Parent or not prompty.Parent:IsA("BasePart") then
				return
			end

			local distance = (prompty.Parent.Position - hrp.Position).Magnitude
			if distance > 25 then
				print("disconnect con")
				self:DisconnectPrompt(prompty)
			end
		end
	end)
	self._maid:GiveTask(distanceCheckConnection)
end

function PromptController:DisconnectPrompt()
	self.hiddePrompt(self.prompt)
	self._maid:DoCleaning()
end

return PromptController
