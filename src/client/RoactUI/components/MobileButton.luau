local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Roact = require(ReplicatedStorage.Shared.Roact)

export type MobileButtonProps = {
	image: string,
	position: UDim2,
	size: UDim2,
	cb: (() -> ())?,
	onInputBegan: ((InputObject) -> ())?,
	onInputEnded: ((InputObject) -> ())?,
}

--[=[
	A circular ("fully rounded") black button used by the mobile HUD.
	The frame is forced square via a 1:1 aspect ratio constraint, and the
	image fits the whole frame. Both the frame and the image render at 0.3
	transparency.

	@class MobileButton
]=]
local MobileButton = Roact.Component:extend("MobileButton")

function MobileButton:render()
	local props: MobileButtonProps = self.props
	return Roact.createElement("ImageButton", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = props.position,
		Size = props.size,
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.3,
		BorderSizePixel = 0,
		ClipsDescendants = true,
		Image = "",
		[Roact.Event.Activated] = props.cb,
		[Roact.Event.InputBegan] = props.onInputBegan,
		[Roact.Event.InputEnded] = props.onInputEnded,
	}, {
		AspectRatio = Roact.createElement("UIAspectRatioConstraint", {
			AspectRatio = 1,
		}),
		Corner = Roact.createElement("UICorner", {
			CornerRadius = UDim.new(0.5, 0),
		}),
		Icon = Roact.createElement("ImageLabel", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			Image = props.image,
			ImageTransparency = 0.3,
			ScaleType = Enum.ScaleType.Fit,
		}),
	})
end

return MobileButton
