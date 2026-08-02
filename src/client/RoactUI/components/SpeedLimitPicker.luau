local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Roact = require(ReplicatedStorage.Shared.Roact)

local Maid = require(ReplicatedStorage.Nevermore.Quenty.maid.Shared.Maid)
local CarLimiterConstants =
	require(ReplicatedStorage.Nevermore.Custom.carLimiter.src.Shared.CarLimiterConstants)

local useContext = require(script.Parent.Parent.Context.Utils.useContext)
local CarContext = require(script.Parent.Parent.Context.CarContext.CarContext)

-- Panel geometry. Sits in the bottom-right corner, lifted clear of the
-- BottomBar (whose own height this mirrors) so the two never overlap.
local BAR_HEIGHT = 36
local MARGIN = 12
local PANEL_WIDTH = 140
local PANEL_PADDING = 6
local TITLE_HEIGHT = 16
local BUTTON_HEIGHT = 28
local ITEM_PADDING = 4
local MAX_TEXT_SIZE = 18

-- Same palette as the BottomBar (chrome) and the overhead tags (the green a
-- selected cap borrows), so the picker reads as part of the same dashboard.
local PANEL_COLOR = Color3.fromHex("4a5259")
local IDLE_COLOR = Color3.fromHex("343a40")
local TEXT_COLOR = Color3.fromHex("fdfdfd")
local ACTIVE_COLOR = Color3.fromRGB(214, 234, 201)
local ACTIVE_TEXT_COLOR = Color3.fromRGB(20, 20, 20)

--[=[
	The picker itself: one button per CarLimiterConstants.PRESETS cap. Clicking a
	preset caps the driven car at that speed; clicking the selected one again
	clears the cap, so the same two buttons also switch the governor off.
	@class SpeedLimitPickerView
]=]
local SpeedLimitPickerView = Roact.Component:extend("SpeedLimitPickerView")

function SpeedLimitPickerView:init()
	self._maid = Maid.new()
	self:setState({ limitKmh = self.props.carLimiterClient:GetLimit() })
end

function SpeedLimitPickerView:didMount()
	-- Subscribe rather than keep a local copy: CarLimiterClient is the single
	-- owner of the cap, so the highlighted button always shows what the governor
	-- is enforcing -- including a limit set before this mounted.
	self._maid:GiveTask(self.props.carLimiterClient:ObserveLimit():Subscribe(function(limitKmh)
		-- Roact.None, not nil: a nil in a setState table is an absent key, which
		-- would leave the old cap highlighted after uncapping.
		self:setState({ limitKmh = limitKmh or Roact.None })
	end))
end

function SpeedLimitPickerView:willUnmount()
	self._maid:DoCleaning()
	-- The cap deliberately survives an unmount (stepping out of the car): it is a
	-- driver setting, and CarLimiterClient re-applies it to the next car driven.
end

function SpeedLimitPickerView:render()
	local presets = CarLimiterConstants.PRESETS
	print()
	local children: { [string]: any } = {
		Padding = Roact.createElement("UIPadding", {
			PaddingTop = UDim.new(0, PANEL_PADDING),
			PaddingBottom = UDim.new(0, PANEL_PADDING),
			PaddingLeft = UDim.new(0, PANEL_PADDING),
			PaddingRight = UDim.new(0, PANEL_PADDING),
		}),
		Layout = Roact.createElement("UIListLayout", {
			FillDirection = Enum.FillDirection.Vertical,
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0, ITEM_PADDING),
		}),
		Title = Roact.createElement("TextLabel", {
			LayoutOrder = 0,
			Size = UDim2.new(1, 0, 0, TITLE_HEIGHT),
			BackgroundTransparency = 1,
			Text = "CHASSIS LIMIT (KM/ST)",
			TextColor3 = TEXT_COLOR,
			TextScaled = true,
			Font = Enum.Font.GothamMedium,
		}, {
			SizeConstraint = Roact.createElement("UITextSizeConstraint", {
				MaxTextSize = MAX_TEXT_SIZE,
			}),
		}),
	}

	for index, preset in presets do
		local isActive = self.state.limitKmh == preset
		children["Preset" .. tostring(preset)] = Roact.createElement("TextButton", {
			LayoutOrder = index,
			Size = UDim2.new(1, 0, 0, BUTTON_HEIGHT),
			BackgroundColor3 = if isActive then ACTIVE_COLOR else IDLE_COLOR,
			BorderSizePixel = 0,
			AutoButtonColor = true,
			Text = ("%d+"):format(preset),
			TextColor3 = if isActive then ACTIVE_TEXT_COLOR else TEXT_COLOR,
			TextScaled = true,
			Font = Enum.Font.GothamBold,
			[Roact.Event.Activated] = function()
				self.props.carLimiterClient:SetLimit(if isActive then nil else preset)
			end,
		}, {
			SizeConstraint = Roact.createElement("UITextSizeConstraint", {
				MaxTextSize = MAX_TEXT_SIZE,
			}),
		})
	end

	-- Height is derived from the preset count, so adding a third cap to
	-- CarLimiterConstants.PRESETS grows the panel instead of clipping a button.
	local rows = #presets + 1
	local height = PANEL_PADDING * 2
		+ TITLE_HEIGHT
		+ #presets * BUTTON_HEIGHT
		+ (rows - 1) * ITEM_PADDING

	return Roact.createElement("Frame", {
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -MARGIN, 1, -(BAR_HEIGHT + MARGIN)),
		Size = UDim2.fromOffset(PANEL_WIDTH, height),
		BackgroundColor3 = PANEL_COLOR,
		BorderSizePixel = 0,
	}, children)
end

local SpeedLimitPicker = Roact.Component:extend("SpeedLimitPicker")

function SpeedLimitPicker:render()
	local withCtx = useContext({ CarContext = CarContext })

	return withCtx(function(ctx)
		-- Same gate as the rest of the dashboard: the cap applies to the car being
		-- driven, so the control belongs on screen only from the seat.
		if not ctx.CarContext.isDriving then
			return nil
		end

		return Roact.createElement(SpeedLimitPickerView, {
			carLimiterClient = self.props.carLimiterClient,
		})
	end)
end

return SpeedLimitPicker
