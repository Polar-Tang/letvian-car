local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Roact = require(ReplicatedStorage.Shared.Roact)
local Maid = require(ReplicatedStorage.Nevermore.Quenty.maid.Shared.Maid)

local GameModeConstants = require(ReplicatedStorage.Nevermore.Custom.gamemode.src.Shared.GameModeConstants)
local assets = require(ReplicatedStorage.Shared.Public.assets)

--[=[
	Over-head "carrying the flag" marker. The server (Flag binder) authors the
	CTF_carrier tag on whoever holds a flag; that tag replicates to every client,
	so this component observes it through the CarrierClient binder (no remote
	duplicating the same fact) and raises a BillboardGui adorned to each carrier's
	head while it carries.

	The binder's class-removing signal is the live return-to-base / death /
	despawn unmount (the tag drops in all three cases). The adornee's own
	`AncestryChanged` to a nil parent is kept as a redundant safety net so the
	marker can never linger if a teardown ever beats the binder.

	BillboardGuis are rendered through a Portal into PlayerGui (they adorn to a
	world part, so they must NOT nest inside the App ScreenGui's 2D tree).

	@class FlagBillboard
]=]
local FlagBillboard = Roact.Component:extend("FlagBillboard")

function FlagBillboard:init()
	self._maid = Maid.new()
	self._nextId = 0
	-- Model -> string id, so a repeat "carrying" for the same character reuses
	-- its billboard instead of stacking a second one.
	self._idByChar = {}

	-- state.carriers: id -> { character, image }, the live set Roact renders one
	-- billboard each. `image` is the per-team icon resolved at add time.
	self:setState({ carriers = {} })
end

-- The overhead icon for a carrier's team. Per-team art lives in `assets`
-- (keyed by team id); a teamless carrier or a team with no art falls back to
-- the roulette pointer placeholder.
local function carrierImage(carrier): string
	local team = carrier:GetTeam()
	return (team and assets.flag_carrier[team.Name]) or assets.spin_roullete.pointer
end

function FlagBillboard._addCarrier(self, carrier, character: Model)
	if self._idByChar[character] then
		return
	end

	self._nextId += 1
	local id = tostring(self._nextId)
	self._idByChar[character] = id

	local image = carrierImage(carrier)

	-- Auto-unmount when the adornee leaves the world (parent goes nil).
	self._maid[id] = character.AncestryChanged:Connect(function(_, parent: Instance?)
		if not parent then
			self:_removeCarrier(character)
		end
	end)

	self:setState(function(state)
		local carriers = table.clone(state.carriers)
		carriers[id] = { character = character, image = image }
		return { carriers = carriers }
	end)
end

function FlagBillboard._removeCarrier(self, character: Model)
	local id = self._idByChar[character]
	if not id then
		return
	end
	self._idByChar[character] = nil
	self._maid[id] = nil -- drop the AncestryChanged watch

	self:setState(function(state)
		local carriers = table.clone(state.carriers)
		carriers[id] = nil
		return { carriers = carriers }
	end)
end

function FlagBillboard:didMount()
	-- The started provider — _G.BinderProvider is the registration key, not the
	-- running provider whose binders are live.
	local provider = _G.ServiceBag:GetService(_G.BinderProvider)
	local binder = provider:Get(GameModeConstants.CTF_CARRIER_TAG)
	assert(binder, `FlagBillboard: no binder registered for tag "{GameModeConstants.CTF_CARRIER_TAG}"`)

	-- React, don't snapshot: carriers can bind after this mount (deferred binder
	-- instantiation), so connect the signals AND sweep GetAll for whoever is
	-- already bound. _addCarrier is idempotent, so the sweep and a signal reaching
	-- the same carrier is safe. The signal payload is (class, instance).
	self._maid:GiveTask(binder:GetClassAddedSignal():Connect(function(class, character: Model)
		self:_addCarrier(class, character)
	end))
	self._maid:GiveTask(binder:GetClassRemovingSignal():Connect(function(_class, character: Model)
		self:_removeCarrier(character)
	end))
	for _, carrier in binder:GetAll() do
		self:_addCarrier(carrier, carrier:GetCharacter())
	end
end

function FlagBillboard:willUnmount()
	self._maid:DoCleaning()
end

-- The adornee part: the head reads best, falling back to the root so a rig
-- without a Head still shows the marker.
local function adorneePart(character: Model): BasePart?
	return (character:FindFirstChild("Head") or character:FindFirstChild("HumanoidRootPart")) :: BasePart?
end

function FlagBillboard:render()
	local billboards: { [string]: any } = {}

	for id, entry in self.state.carriers do
		local adornee = adorneePart(entry.character)
		if not adornee then
			continue
		end

		billboards[id] = Roact.createElement("BillboardGui", {
			Adornee = adornee,
			Size = UDim2.fromOffset(48, 48),
			StudsOffsetWorldSpace = Vector3.new(0, 3, 0),
			AlwaysOnTop = true,
			MaxDistance = 250,
		}, {
			Icon = Roact.createElement("ImageLabel", {
				Size = UDim2.fromScale(1, 1),
				BackgroundTransparency = 1,
				Image = entry.image,
			}),
		})
	end

	-- Portal into PlayerGui: a BillboardGui adorns a world part and must live
	-- outside the App ScreenGui's 2D layout.
	return Roact.createElement(Roact.Portal, {
		target = Players.LocalPlayer:WaitForChild("PlayerGui"),
	}, billboards)
end

return FlagBillboard
