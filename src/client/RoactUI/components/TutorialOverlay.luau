local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Roact = require(ReplicatedStorage.Shared.Roact)
local Maid = require(ReplicatedStorage.Nevermore.Quenty.maid.Shared.Maid)

-- Above every gameplay ScreenGui (App mounts at the default DisplayOrder 0),
-- so the blockers actually sit between the pointer and the HUD.
local TUTORIAL_DISPLAY_ORDER = 50
local OVERLAY_TRANSPARENCY = 0.5
local OVERLAY_COLOR = Color3.fromRGB(0, 0, 0)
local BORDER_COLOR = Color3.fromRGB(255, 200, 60)
local BORDER_THICKNESS = 3
local BORDER_RADIUS = UDim.new(0, 12)
local DEFAULT_HAND_SIZE = UDim2.fromOffset(64, 64)
local DEFAULT_HAND_DURATION = 0.8

export type TutorialHighlight = {
	-- Top-left corner of the clickable window (the hole is NOT anchored to
	-- its center — pass the same position/size you would give the frame it
	-- highlights).
	position: UDim2,
	size: UDim2,
}

export type TutorialHand = {
	image: string?, -- asset id of the pointing hand
	startPosition: UDim2,
	endPosition: UDim2,
	startRotation: number?, -- degrees; rotates around the image center
	endRotation: number?,
	startSize: UDim2?,
	endSize: UDim2?, -- only tweened when provided
	duration: number?, -- seconds for one start -> end sweep (loops, reversing)
}

export type TutorialSpec = {
	highlight: TutorialHighlight?,
	hand: TutorialHand?,
}

--[=[
	Full-screen tutorial step overlay.

	A Frame can't have a hole cut into it, so the "highlight" is four
	semi-transparent blocker panels (Active = true, so they sink clicks)
	tiled around the window. The window itself is only a border frame
	(UIStroke + UICorner) with a transparent, non-Active background — input
	falls straight through it to whatever HUD element is being highlighted,
	which is the whole trick: the bordered region is the only clickable spot
	on screen.

	The hand is an ImageLabel tweened directly through TweenService (looping,
	reversing) rather than through Roact state — re-rendering per frame for a
	cosmetic loop would be waste. The tween lives in the component maid, so
	unmounting (TutorialHandler.Destroy) cancels it.

	@class TutorialOverlay
]=]
local TutorialOverlay = Roact.Component:extend("TutorialOverlay")

local function blockerPanel(position: UDim2, size: UDim2)
	return Roact.createElement("Frame", {
		Position = position,
		Size = size,
		BackgroundColor3 = OVERLAY_COLOR,
		BackgroundTransparency = OVERLAY_TRANSPARENCY,
		BorderSizePixel = 0,
		-- Active sinks mouse/touch input, so nothing behind a panel is
		-- clickable while the tutorial step is up.
		Active = true,
		ZIndex = 2,
	})
end

function TutorialOverlay:init()
	self._maid = Maid.new()
	self._handRef = Roact.createRef()
end

function TutorialOverlay:didMount()
	local hand: TutorialHand? = self.props.hand
	if not hand then
		return
	end

	local handImage = self._handRef:getValue()
	assert(handImage, "TutorialOverlay: hand ref did not resolve on mount")

	local goal: { [string]: any } = {
		Position = hand.endPosition,
	}
	if hand.endRotation then
		goal.Rotation = hand.endRotation
	end
	if hand.endSize then
		goal.Size = hand.endSize
	end

	local tweenInfo = TweenInfo.new(
		hand.duration or DEFAULT_HAND_DURATION,
		Enum.EasingStyle.Quad,
		Enum.EasingDirection.InOut,
		-1, -- loop until the step is destroyed
		true -- reverse back to the start pose each cycle
	)
	local tween = TweenService:Create(handImage, tweenInfo, goal)
	tween:Play()

	self._maid:GiveTask(function()
		tween:Cancel()
		tween:Destroy()
	end)
end

function TutorialOverlay:willUnmount()
	self._maid:DoCleaning()
end

function TutorialOverlay:render()
	local highlight: TutorialHighlight? = self.props.highlight
	local hand: TutorialHand? = self.props.hand

	local children = {}

	if highlight then
		local position = highlight.position
		local size = highlight.size
		-- The window's far edges, kept as (scale, offset) pairs so mixed
		-- UDim2s (scale position + offset size, etc.) tile correctly.
		local rightScale = position.X.Scale + size.X.Scale
		local rightOffset = position.X.Offset + size.X.Offset
		local bottomScale = position.Y.Scale + size.Y.Scale
		local bottomOffset = position.Y.Offset + size.Y.Offset

		children.TopBlocker = blockerPanel(
			UDim2.new(0, 0, 0, 0),
			UDim2.new(1, 0, position.Y.Scale, position.Y.Offset)
		)
		children.BottomBlocker = blockerPanel(
			UDim2.new(0, 0, bottomScale, bottomOffset),
			UDim2.new(1, 0, 1 - bottomScale, -bottomOffset)
		)
		children.LeftBlocker = blockerPanel(
			UDim2.new(0, 0, position.Y.Scale, position.Y.Offset),
			UDim2.new(position.X.Scale, position.X.Offset, size.Y.Scale, size.Y.Offset)
		)
		children.RightBlocker = blockerPanel(
			UDim2.new(rightScale, rightOffset, position.Y.Scale, position.Y.Offset),
			UDim2.new(1 - rightScale, -rightOffset, size.Y.Scale, size.Y.Offset)
		)

		-- The clickable window: border only, never Active, so input passes
		-- through to the highlighted HUD element underneath.
		children.HighlightWindow = Roact.createElement("Frame", {
			Position = position,
			Size = size,
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Active = false,
			ZIndex = 3,
		}, {
			Corner = Roact.createElement("UICorner", {
				CornerRadius = BORDER_RADIUS,
			}),
			Stroke = Roact.createElement("UIStroke", {
				Color = BORDER_COLOR,
				Thickness = BORDER_THICKNESS,
				ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
			}),
		})
	end

	if hand then
		children.Hand = Roact.createElement("ImageLabel", {
			[Roact.Ref] = self._handRef,
			Image = hand.image or "",
			-- Centered anchor so startRotation/endRotation pivot the hand
			-- around its own middle instead of the top-left corner.
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = hand.startPosition,
			Rotation = hand.startRotation or 0,
			Size = hand.startSize or DEFAULT_HAND_SIZE,
			BackgroundTransparency = 1,
			Active = false,
			ZIndex = 5,
		})
	end

	return Roact.createElement("ScreenGui", {
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		DisplayOrder = TUTORIAL_DISPLAY_ORDER,
	}, children)
end

return TutorialOverlay
