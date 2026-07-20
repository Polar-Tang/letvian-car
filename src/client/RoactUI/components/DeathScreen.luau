local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Roact = require(ReplicatedStorage.Shared.Roact)
local Maid = require(ReplicatedStorage.Nevermore.Quenty.maid.Shared.Maid)

local PlayerDiedRemote: RemoteEvent = ReplicatedStorage.Shared.RemoteEvents.PlayerDied
local RespawnRequestRemote: RemoteEvent = ReplicatedStorage.Shared.RemoteEvents.RespawnRequest

--[=[
	Death overlay + manual respawn gate.

	The server runs with CharacterAutoLoads = false, so a dead player stays
	dead until this component fires `RespawnRequest` (the respawn button).
	Two signals drive visibility, both idempotent because they may race:

	- `PlayerDied` remote (combat kills, fired by EffectService — the only
	  place lethal damage lands): carries the killer's character Model, which
	  is handed to `cameraMediator:EnterDeathCam` to spectate the killer.
	- local `Humanoid.Died` (covers non-combat deaths: falls, reset, debug
	  kills): shows the button with no killer cam, so the player can never
	  get stuck dead without a respawn button.

	`CharacterAdded` hides the overlay and restores the gameplay camera.

	@class DeathScreen
]=]
local DeathScreen = Roact.Component:extend("DeathScreen")

function DeathScreen:init()
	self._maid = Maid.new()

	self:setState({
		isDead = false,
		killerName = Roact.None,
	})
end

function DeathScreen._setDead(self, killerName: string?)
	-- The death screen needs a free, visible cursor (ServiceRoot hides the
	-- icon globally for gameplay; shiftlock already unlocks itself on death).
	UserInputService.MouseIconEnabled = true
	UserInputService.MouseBehavior = Enum.MouseBehavior.Default

	self:setState({
		isDead = true,
		killerName = killerName or Roact.None,
	})
end

function DeathScreen:didMount()
	local cameraMediator = self.props.cameraMediator

	self._maid:GiveTask(PlayerDiedRemote.OnClientEvent:Connect(function(data)
		local killer = data and data.killer
		cameraMediator:EnterDeathCam(killer)
		self:_setDead(killer and killer.Name)
	end))

	-- Per-character Died hook, rebuilt every spawn (the Humanoid dies with
	-- its Model). Covers deaths EffectService never sees.
	local function watchCharacter(character: Model)
		local characterMaid = Maid.new()
		self._maid._character = characterMaid

		task.spawn(function()
			local humanoid = character:WaitForChild("Humanoid")
			characterMaid:GiveTask(humanoid.Died:Connect(function()
				self:_setDead(nil)
			end))
		end)
	end

	self._maid:GiveTask(Players.LocalPlayer.CharacterAdded:Connect(function(character)
		cameraMediator:ExitDeathCam()
		UserInputService.MouseIconEnabled = false
		self:setState({
			isDead = false,
			killerName = Roact.None,
		})
		watchCharacter(character)
	end))

	if Players.LocalPlayer.Character then
		watchCharacter(Players.LocalPlayer.Character)
	end
end

function DeathScreen:willUnmount()
	self._maid:DoCleaning()
end

function DeathScreen:render()
	if not self.state.isDead then
		return nil
	end

	local killerName = self.state.killerName

	return Roact.createElement("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.fromRGB(0, 0, 0),
		BackgroundTransparency = 0.45,
		BorderSizePixel = 0,
		ZIndex = 10,
	}, {
		Title = Roact.createElement("TextLabel", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.35),
			Size = UDim2.fromOffset(400, 48),
			BackgroundTransparency = 1,
			Text = "YOU DIED",
			TextColor3 = Color3.fromRGB(230, 60, 60),
			Font = Enum.Font.GothamBold,
			TextSize = 42,
			ZIndex = 11,
		}),

		KilledBy = killerName and Roact.createElement("TextLabel", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.42),
			Size = UDim2.fromOffset(400, 24),
			BackgroundTransparency = 1,
			Text = "Eliminated by " .. killerName,
			TextColor3 = Color3.fromRGB(220, 220, 220),
			Font = Enum.Font.Gotham,
			TextSize = 18,
			ZIndex = 11,
		}),

		RespawnButton = Roact.createElement("TextButton", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.6),
			Size = UDim2.fromOffset(220, 56),
			BackgroundColor3 = Color3.fromRGB(80, 200, 120),
			BorderSizePixel = 0,
			Text = "RESPAWN",
			TextColor3 = Color3.fromRGB(18, 18, 28),
			Font = Enum.Font.GothamBold,
			TextSize = 24,
			ZIndex = 11,
			-- Modal frees the cursor even on platforms with a locked mouse.
			Modal = true,
			[Roact.Event.Activated] = function()
				-- Server-validated (only honored while dead), so spamming the
				-- button is harmless.
				RespawnRequestRemote:FireServer()
			end,
		}, {
			Corner = Roact.createElement("UICorner", {
				CornerRadius = UDim.new(0, 10),
			}),
		}),
	})
end

return DeathScreen
