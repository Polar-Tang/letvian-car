local ReplicatedStorage = game:GetService("ReplicatedStorage")
local repStore = game:getService("ReplicatedStorage")

local Maid = require(ReplicatedStorage.Nevermore.Quenty.maid.Shared.Maid)
local Roact = require(repStore.Roact)

local PromptContext = require(script.Parent.PromptContext)

local PromptProvider = Roact.Component:extend("PromptProvider")

local PromptController = require(script.Parent.PromptController)

local Events = repStore.RemoteEvents
local NPCs = Events.NPCs

function PromptProvider:init()
	self.distanceCheckConnections = {}
	self.__prompts = {}
	self._maid = Maid.new()

	self:setState({
		isPromptShown = false,
		prompts = {},
	})
end

function PromptProvider:render()
	return Roact.createElement(PromptContext.Provider, {
		value = {

			prompt = self.state.prompt,
			callClose = function(prompty)
				self:DisconnectPrompt(prompty)
			end,
			prompts = self.state.prompts,
		},
	}, self.props[Roact.Children])
end

function PromptProvider:DisconnectPrompt(prompty)
	if not prompty then
		warn("noPrompty")
		return
	end
	local promptId = prompty.ObjectText

	self.__prompts[promptId] = nil
	local clone = table.clone(self.state.prompts)
	clone[promptId] = nil
	self:setState({
		prompts = clone,
	})
end

function PromptProvider:didMount()
	local promptCon = game:GetService("ProximityPromptService").PromptShown:Connect(function(prompty: ProximityPrompt)
		local promptParent = prompty.Parent

		if promptParent then
			NPCs:FireServer(prompty)
		end
	end)

	-- Here we can blindly trust
	local promptCreator = NPCs.OnClientEvent:Connect(function(data)
		local npc = data.npc
		local id = data.id
		local prompty = data.prompt

		-- __prompts is the roact component's currently active prompts controllers
		if self.__prompts[id] then
			return
		end

		-- the prompt controller check player distance and if it is too far, disconnects the prompt controller
		local PromptController = PromptController.new(prompty, function(p)
			self:DisconnectPrompt(p)
		end)

		if npc:HasTag("NPC") then
			PromptController = PromptController.new(prompty, function(p)
				self:DisconnectPrompt(p)
				NPCs:FireServer(prompty, true)
			end)
		end

		self.__prompts[id] = PromptController
		PromptController:StartCheckDistance()
		-- then it set the prompt instance which is rendering in the client
		local clone = table.clone(self.state.prompts)
		clone[id] = prompty

		self:setState({
			prompts = clone,
		})
	end)
	self._maid:GiveTask(promptCon)
	self._maid:GiveTask(promptCreator)
end

function PromptProvider:unMount()
	self.promptCon:Disconnect()
end

return PromptProvider
