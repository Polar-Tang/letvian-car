local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Roact = require(ReplicatedStorage.Shared.Roact)

local Maid = require(ReplicatedStorage.Nevermore.Quenty.maid.Shared.Maid)
local CharacterRoot = require(ReplicatedStorage.Shared.Public.CharacterRoot)
local Units = require(ReplicatedStorage.Shared.Public.Units)
local RadarConstants = require(ReplicatedStorage.Nevermore.Custom.radar.src.Shared.RadarConstants)

local useContext = require(script.Parent.Parent.Context.Utils.useContext)
local RadarContext = require(script.Parent.Parent.Context.RadarContext.RadarContext)

-- How often the readout refreshes speed/distance. Membership (which cars have
-- a tag at all) is the provider's job; these are the live numbers inside one tag.
local REFRESH_RATE = 10

local TAG_SIZE = UDim2.fromOffset(200, 150)
local SIGN_HEIGHT = 64
local DOT_SIZE = 10

local SIGN_GREEN = Color3.fromRGB(214, 234, 201)
-- Readout background while the vehicle is at or over RadarConstants.SPEED_LIMIT.
local SIGN_RED = Color3.fromRGB(230, 120, 120)
local BORDER_RED = Color3.fromRGB(255, 0, 0)
local TEXT_BLACK = Color3.fromRGB(20, 20, 20)

--[=[
	One overhead radar tag, feet to head: a red-bordered point pinned to the
	vehicle's PrimaryPart, a thin red line up, and the sign — speed column on
	the left; distance/ID row and unit/plate row on the right.
	@class SpeedTagView
]=]
local SpeedTagView = Roact.Component:extend("SpeedTagView")

function SpeedTagView:init()
	self._maid = Maid.new()
	-- Points self.root at the live HumanoidRootPart and refreshes it on respawn
	-- (the refresh connection lives on self._maid), so the distance readout is
	-- taken from the current body instead of the spot the last one died.
	CharacterRoot.bind(self)

	self:setState(self:_readVehicle())
end

-- Where the reading is taken from: the player's own body, not the camera, so a
-- panned/zoomed view doesn't change the distance. self.root is kept live by
-- CharacterRoot (refreshed on respawn), but is briefly nil around a spawn —
-- return nil then so _readVehicle's guard reports distance 0 rather than
-- measuring from the origin.
function SpeedTagView:getObserverPosition(): Vector3?
	local root = self.root
	return root and root.Position
end

function SpeedTagView:_readVehicle()
	local vehicle = self.props.vehicle
	local radarClient = self.props.radarClient
	local observerPosition = self:getObserverPosition()

	return {
		speed = radarClient and radarClient:GetSpeed(vehicle) or 0,
		distance = observerPosition and (vehicle:GetPivot().Position - observerPosition).Magnitude or 0,
	}
end

function SpeedTagView:didMount()
	local sinceLastRefresh = 0
	self._maid:GiveTask(RunService.Heartbeat:Connect(function(deltaTime)
		sinceLastRefresh += deltaTime
		if sinceLastRefresh < 1 / REFRESH_RATE then
			return
		end
		sinceLastRefresh = 0
		self:setState(self:_readVehicle())
	end))
end

function SpeedTagView:willUnmount()
	self._maid:DoCleaning()
end

-- The two info rows share one three-label layout: left text (half the row),
-- the "|" separator dead centre, right text filling the rest.
local function infoRow(position: UDim2, leftText: string, rightText: string)
	return Roact.createElement("Frame", {
		Position = position,
		Size = UDim2.new(1, 0, 0.5, 0),
		BackgroundTransparency = 1,
	}, {
		Left = Roact.createElement("TextLabel", {
			Size = UDim2.new(0.5, 0, 1, 0),
			BackgroundTransparency = 1,
			Text = leftText,
			TextColor3 = TEXT_BLACK,
			TextScaled = true,
			Font = Enum.Font.Gotham,
		}),
		Separator = Roact.createElement("TextLabel", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, 0, 0.5, 0),
			Size = UDim2.new(0.06, 0, 1, 0),
			BackgroundTransparency = 1,
			Text = "|",
			TextColor3 = TEXT_BLACK,
			TextScaled = true,
			Font = Enum.Font.Gotham,
		}),
		Right = Roact.createElement("TextLabel", {
			Position = UDim2.new(0.55, 0, 0, 0),
			Size = UDim2.new(0.45, 0, 1, 0),
			BackgroundTransparency = 1,
			Text = rightText,
			TextColor3 = TEXT_BLACK,
			TextScaled = true,
			Font = Enum.Font.Gotham,
		}),
	})
end

function SpeedTagView:render()
	local vehicle: Model = self.props.vehicle
	local adornee = vehicle.PrimaryPart or vehicle:FindFirstChildWhichIsA("BasePart")
	if not adornee then
		return nil
	end

	-- state.speed / state.distance are raw studs (native unit); convert to the
	-- km/h + m the sign shows. The same km/h value decides the red flip so the
	-- colour change lines up exactly with the number on screen.
	local speedKmh = Units.studsPerSecondToKilometersPerHour(self.state.speed)
	local distanceMeters = Units.studsToMeters(self.state.distance)
	local isOverLimit = speedKmh >= RadarConstants.SPEED_LIMIT

	return Roact.createElement("BillboardGui", {
		Adornee = adornee,
		Size = TAG_SIZE,
		-- Shift up half our height so the bottom edge (the point) sits at the
		-- centre of the primary part.
		SizeOffset = Vector2.new(0, 0.45),
		AlwaysOnTop = true,
		MaxDistance = RadarConstants.RANGE,
	}, {
		Sign = Roact.createElement("Frame", {
			Size = UDim2.new(1, 0, 0, SIGN_HEIGHT),
			BackgroundColor3 = if isOverLimit then SIGN_RED else SIGN_GREEN,
			BorderSizePixel = 1,
			BorderColor3 = BORDER_RED,
		}, {
			Speed = Roact.createElement("TextLabel", {
				Size = UDim2.new(0.3, 0, 1, 0),
				BackgroundTransparency = 1,
				Text = tostring(math.round(speedKmh)),
				TextColor3 = TEXT_BLACK,
				TextScaled = true,
				Font = Enum.Font.GothamBold,
			}),
			Info = Roact.createElement("Frame", {
				Position = UDim2.new(0.3, 0, 0, 0),
				Size = UDim2.new(0.7, 0, 1, 0),
				BackgroundTransparency = 1,
			}, {
				DistanceRow = infoRow(
					UDim2.new(0, 0, 0, 0),
					("↑ %dm"):format(math.round(distanceMeters)),
					"ID: 68"
				),
				UnitRow = infoRow(UDim2.new(0, 0, 0.5, 0), "km/st", "HAT3"),
			}),
		}),
		Line = Roact.createElement("Frame", {
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0, SIGN_HEIGHT),
			Size = UDim2.new(0, 4, 1, -(SIGN_HEIGHT + DOT_SIZE)),
			BackgroundColor3 = BORDER_RED,
			BorderSizePixel = 0,
		}),
		Point = Roact.createElement("Frame", {
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, 0),
			Size = UDim2.fromOffset(DOT_SIZE, DOT_SIZE),
			BackgroundColor3 = Color3.fromRGB(255, 255, 255),
			BorderSizePixel = 2,
			BorderColor3 = BORDER_RED,
		}),
	})
end

local SpeedTags = Roact.Component:extend("SpeedTags")

function SpeedTags:render()
	local withCtx = useContext({ RadarContext = RadarContext })

	return withCtx(function(ctx)
		local radarCtx = ctx.RadarContext

		local billboards: { [string]: any } = {}
		for index, vehicle in radarCtx.vehicles do
			billboards["Tag" .. index] = Roact.createElement(SpeedTagView, {
				vehicle = vehicle,
				radarClient = radarCtx.radarClient,
			})
		end

		-- Portal into PlayerGui: billboards adorn world parts, so they must not
		-- nest inside the App ScreenGui's 2D layout (same as FlagBillboard).
		return Roact.createElement(Roact.Portal, {
			target = Players.LocalPlayer:WaitForChild("PlayerGui"),
		}, billboards)
	end)
end

return SpeedTags
