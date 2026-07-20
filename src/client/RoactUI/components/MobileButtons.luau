local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Roact = require(ReplicatedStorage.Shared.Roact)
local assets = require(ReplicatedStorage.Shared.Public.assets)

local MobileButton = require(script.Parent.MobileButton)

local BUTTONS = assets.mobile_buttons

-- Square buttons sized off the screen height so they stay round on any
-- aspect ratio (UIAspectRatioConstraint inside MobileButton forces 1:1).
local BIG = UDim2.fromScale(0.16, 0.16)
local SMALL = UDim2.fromScale(0.13, 0.13)
local TINY = UDim2.fromScale(0.106, 0.106)

-- Right-side thumb cluster, mirroring assets/mobile/WhatsApp Image 2026-06-02.
local LAYOUT = {
	crosshair = { image = BUTTONS.crosshair, position = UDim2.fromScale(0.85, 0.48), size = SMALL },
	shot      = { image = BUTTONS.shot,      position = UDim2.fromScale(0.85, 0.65), size = BIG  },
	charge    = { image = BUTTONS.charge,    position = UDim2.fromScale(0.93, 0.65), size = SMALL },
	run       = { image = BUTTONS.run,       position = UDim2.fromScale(0.856, 0.796), size = TINY },
	slide     = { image = BUTTONS.slide,     position = UDim2.fromScale(0.836, 0.919), size = TINY },
}

--[=[
	The mobile HUD action cluster. Renders one [MobileButton] per entry in
	`assets.mobile_buttons`, positioned to resemble the reference layout.

	@class MobileButtons
]=]
local MobileButtons = Roact.Component:extend("MobileButtons")

function MobileButtons:render()
	if not UserInputService.TouchEnabled then
		return
	end

	local weapon = self.props.weaponClient
	local player = Players.LocalPlayer

	local CALLBACKS = {
		slide     = function() weapon:Execute(Enum.KeyCode.LeftControl, { direction = "forward" }) end,
		run       = function() weapon:Execute(Enum.KeyCode.LeftShift) end,
		charge    = function() weapon:Execute(Enum.KeyCode.R) end,
		crosshair = function() weapon:ToggleFirstPerson() end,
	}

	local children = {}
	for name, spec in pairs(LAYOUT) do
		local buttonProps = {
			image    = spec.image,
			position = spec.position,
			size     = spec.size,
		}

		if name == "shot" then
			-- Hold-to-fire: tap fires immediately and sets m1Hold so
			-- RangeAttackClient._setupContinuousFireObservable keeps shooting.
			-- Roact event handlers receive the host Instance first, then the
			-- event's own args — so the InputObject is the SECOND parameter.
			buttonProps.onInputBegan = function(_rbx: ImageButton, input: InputObject)
				if input.UserInputType ~= Enum.UserInputType.Touch then
					return
				end
				local m1Hold = player:FindFirstChild("m1Hold")
				if m1Hold then
					m1Hold.Value = true
				end
				weapon:Execute(Enum.UserInputType.MouseButton1)
			end
			buttonProps.onInputEnded = function(_rbx: ImageButton, input: InputObject)
				if input.UserInputType ~= Enum.UserInputType.Touch then
					return
				end
				local m1Hold = player:FindFirstChild("m1Hold")
				if m1Hold then
					m1Hold.Value = false
				end
			end
		else
			buttonProps.cb = CALLBACKS[name]
		end

		children[name] = Roact.createElement(MobileButton, buttonProps)
	end

	return Roact.createElement("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
	}, children)
end

return MobileButtons
