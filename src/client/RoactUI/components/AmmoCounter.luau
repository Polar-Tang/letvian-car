local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Roact = require(ReplicatedStorage.Shared.Roact)
local Maid = require(ReplicatedStorage.Nevermore.Quenty.maid.Shared.Maid)

local Constants = require(ReplicatedStorage.Nevermore.Custom.abilities.src.Shared.Constanst)
local CombatConfig = require(ReplicatedStorage.Nevermore.Custom.weapon.src.Shared.CombatConfig)

--[=[
	Magazine readout for the equipped gun.

	Renders nothing for fists / melee: visibility is keyed on the Tool
	carrying the `_ammo` attribute, which only the server RangeAttack seeds
	(guns). The attribute is the authoritative ammo store written by the
	server, so this component just mirrors it — no remotes, no polling.

	Watches the character's Tool children directly (rebuilt per spawn via
	CharacterAdded) instead of going through the WeaponClient prop: the prop
	only refreshes on an "Armed" rebind (respawn), while the Tool changes on
	every weapon swap.

	@class AmmoCounter
]=]
local AmmoCounter = Roact.Component:extend("AmmoCounter")

local function magazineSizeFor(tool: Tool): number?
	local spec = CombatConfig:getweapon(tool.Name:lower())
	local stats = spec and spec.weapon_stats
	return stats and stats.magazineSize
end

function AmmoCounter:init()
	self._maid = Maid.new()
	self._currentTool = nil

	self:setState({
		visible = false,
		ammo = 0,
		magazine = 0,
		reloading = false,
	})
end

function AmmoCounter._watchTool(self, tool: Tool)
	local toolMaid = Maid.new()
	self._maid._tool = toolMaid
	self._currentTool = tool

	local function refresh()
		local ammo = tool:GetAttribute(Constants.AMMO_ATTRIBUTE)
		self:setState({
			visible = ammo ~= nil,
			ammo = ammo or 0,
			magazine = magazineSizeFor(tool) or 0,
			reloading = tool:GetAttribute(Constants.RELOADING_ATTRIBUTE) == true,
		})
	end

	-- One coarse AttributeChanged instead of per-name signals: it also
	-- catches the seed write landing AFTER the Tool replicates (the server
	-- sets `_ammo` in RangeAttack.new, a beat after the equip).
	toolMaid:GiveTask(tool.AttributeChanged:Connect(refresh))
	refresh()
end

function AmmoCounter._watchCharacter(self, character: Model)
	-- Respawn: drop the previous character's tool watch immediately — the new
	-- character spawns bare (default fist), so without this the dead body's
	-- gun readout would linger until the next gun equip.
	self._currentTool = nil
	self._maid._tool = nil
	self:setState({ visible = false })

	local characterMaid = Maid.new()
	self._maid._character = characterMaid

	characterMaid:GiveTask(character.ChildAdded:Connect(function(child)
		if child:IsA("Tool") then
			self:_watchTool(child)
		end
	end))
	characterMaid:GiveTask(character.ChildRemoved:Connect(function(child)
		-- Only clear for the tool we're showing: on a hot swap the old
		-- Tool's removal may land after the new one's add.
		if child == self._currentTool then
			self._currentTool = nil
			self._maid._tool = nil
			self:setState({ visible = false })
		end
	end))

	local tool = character:FindFirstChildOfClass("Tool")
	if tool then
		self:_watchTool(tool)
	end
end

function AmmoCounter:didMount()
	self._maid:GiveTask(Players.LocalPlayer.CharacterAdded:Connect(function(character)
		self:_watchCharacter(character)
	end))

	if Players.LocalPlayer.Character then
		self:_watchCharacter(Players.LocalPlayer.Character)
	end
end

function AmmoCounter:willUnmount()
	self._maid:DoCleaning()
end

function AmmoCounter:render()
	if not self.state.visible then
		return nil
	end

	local text
	if self.state.reloading then
		text = "RELOADING…"
	elseif self.state.magazine > 0 then
		text = string.format("%d / %d", self.state.ammo, self.state.magazine)
	else
		text = tostring(self.state.ammo)
	end

	-- Bottom-center: clear of the mobile thumb cluster on the right and the
	-- quest list on the left.
	return Roact.createElement("TextLabel", {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromScale(0.5, 0.97),
		Size = UDim2.fromOffset(240, 36),
		BackgroundTransparency = 1,
		Text = text,
		TextColor3 = self.state.reloading and Color3.fromRGB(235, 180, 70) or Color3.fromRGB(235, 235, 235),
		Font = Enum.Font.GothamBold,
		TextSize = 28,
	}, {
		Stroke = Roact.createElement("UIStroke", {
			Color = Color3.fromRGB(15, 15, 20),
			Thickness = 1.5,
		}),
	})
end

return AmmoCounter
