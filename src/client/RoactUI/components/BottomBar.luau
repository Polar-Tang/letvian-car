local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Roact = require(ReplicatedStorage.Shared.Roact)

local Maid = require(ReplicatedStorage.Nevermore.Quenty.maid.Shared.Maid)
local CharacterRoot = require(ReplicatedStorage.Shared.Public.CharacterRoot)
local Units = require(ReplicatedStorage.Shared.Public.Units)

-- Bar geometry. IgnoreGuiInset is already set on the App ScreenGui, so anchoring
-- to the bottom edge really is the bottom of the screen.
local BAR_HEIGHT = 36
local BAR_COLOR = Color3.fromHex("4a5259")
local TEXT_COLOR = Color3.fromHex("fdfdfd")
local SEPARATOR_COLOR = Color3.fromHex("f7f7f7")
local MAX_TEXT_SIZE = 20

-- Every segment is sized by its character count (plus this breathing room), so
-- the row always spans exactly the full width and long fields like the location
-- get proportionally more of it. Change a placeholder and the layout follows.
local PADDING_CHARS = 3

-- The date, the clock and the velocity are live (velocity reads the local
-- player's assembly for now — see readVelocity's TODO). The rest are static
-- stand-ins; wire them to real data (plate, unit ID, district) later.
local LOCATION = "KVL TESTING PLACE"
local UNIT = "KVL"
local PATENT = "NR6767"
local ID = "SC850-493"
local SPEED_UNIT = "KM/ST"
local CITY_NAME = "PRIEKŠĀ"

local SEPARATOR = "|"

--[=[
	The full-width status strip along the bottom of the screen: live date and
	clock, then pipe-separated placeholder fields (location, unit, plate, ID,
	speed, city).
	@class BottomBar
]=]
local BottomBar = Roact.Component:extend("BottomBar")

-- Latvian-style stamps: dots in the date, colons in the clock.
local function readClock()
	return {
		date = os.date("%d.%m.%Y"),
		time = os.date("%H:%M:%S"),
	}
end

-- Live speed of the local player's assembly, in studs/second (rounded). Read
-- fresh every tick and never cached: a respawn swaps the character Model out
-- from under us, and FindFirstChild keeps this off the yielding path a
-- Heartbeat callback forbids. Returns 0 while there's no character/root part.
--
-- TODO(car-system task): this is a stand-in reading the player's own body.
-- Once the police car exists, read the CAR's AssemblyLinearVelocity here.
function BottomBar:readVelocity(): number
	
	if not self.root then 
		return 0
	end
	return math.round(self.root.AssemblyLinearVelocity.Magnitude)
end

function BottomBar:init()
	self._maid = Maid.new()
	-- Points self.root at the live HumanoidRootPart and refreshes it on every
	-- respawn (the refresh connection lives on self._maid). Must run before the
	-- first readVelocity so the initial state isn't a needless 0.
	CharacterRoot.bind(self)

	local clock = readClock()
	self:setState({
		date = clock.date,
		time = clock.time,
		velocity = self:readVelocity(),
	})
end

function BottomBar:didMount()
	-- Heartbeat rather than task.wait so the tick dies with the frame loop, but
	-- only push state when a displayed value actually moves: the clock on a new
	-- second, the speed on a new rounded stud/s. Everything else no-ops.
	self._maid:GiveTask(RunService.Heartbeat:Connect(function()
		local now = readClock()
		local velocity = self:readVelocity()
		if now.time ~= self.state.time or velocity ~= self.state.velocity then
			self:setState({
				date = now.date,
				time = now.time,
				velocity = velocity,
			})
		end
	end))
end

function BottomBar:willUnmount()
	self._maid:DoCleaning()
end

function BottomBar:render()
	-- name, text, colour. Separators are segments too, so they take their share
	-- of the width instead of overlapping their neighbours.
	local segments = {
		{ "Date", self.state.date, TEXT_COLOR },
		{ "Time", self.state.time, TEXT_COLOR },
		{ "Separator1", SEPARATOR, SEPARATOR_COLOR },
		{ "Location", LOCATION, TEXT_COLOR },
		{ "Separator2", SEPARATOR, SEPARATOR_COLOR },
		{ "Unit", UNIT, TEXT_COLOR },
		{ "Separator3", SEPARATOR, SEPARATOR_COLOR },
		{ "Patent", PATENT, TEXT_COLOR },
		{ "Separator4", SEPARATOR, SEPARATOR_COLOR },
		{ "Id", ID, TEXT_COLOR },
		{ "Separator5", SEPARATOR, SEPARATOR_COLOR },
		-- state.velocity is raw studs/second; convert to km/h for the KM/ST field.
		{
			"Velocity",
			("%d %s"):format(math.round(Units.studsPerSecondToKilometersPerHour(self.state.velocity)), SPEED_UNIT),
			TEXT_COLOR,
		},
		{ "Separator6", SEPARATOR, SEPARATOR_COLOR },
		{ "CityName", CITY_NAME, TEXT_COLOR },
	}

	-- utf8.len, not #: "PRIEKŠĀ" carries two-byte characters and would otherwise
	-- claim more width than it draws.
	local totalWeight = 0
	local weights = {}
	for index, segment in segments do
		local weight = (utf8.len(segment[2]) or #segment[2]) + PADDING_CHARS
		weights[index] = weight
		totalWeight += weight
	end

	local children: { [string]: any } = {
		Layout = Roact.createElement("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	}

	for index, segment in segments do
		local name, text, color = segment[1], segment[2], segment[3]
		children[name] = Roact.createElement("TextLabel", {
			LayoutOrder = index,
			Size = UDim2.new(weights[index] / totalWeight, 0, 1, 0),
			BackgroundTransparency = 1,
			Text = text,
			TextColor3 = color,
			-- Scaled so the row survives any screen size; the constraint stops
			-- it ballooning on a tall bar.
			TextScaled = true,
			Font = Enum.Font.GothamMedium,
		}, {
			SizeConstraint = Roact.createElement("UITextSizeConstraint", {
				MaxTextSize = MAX_TEXT_SIZE,
			}),
		})
	end

	return Roact.createElement("Frame", {
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 0, 1, 0),
		Size = UDim2.new(1, 0, 0, BAR_HEIGHT),
		BackgroundColor3 = BAR_COLOR,
		BorderSizePixel = 0,
	}, children)
end

return BottomBar
