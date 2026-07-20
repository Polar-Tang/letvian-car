local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local assets = require(ReplicatedStorage.Shared.Public.assets)
local Roact = require(ReplicatedStorage.Shared.Roact)

--[=[
	Spin-roulette overlay.

	Layout: square wheel ImageLabel (rotated via a Binding for zero-cost
	per-frame updates) + a fixed pointer arrow at the top + a Spin button.

	Flow:
	  1. Player clicks Spin → fires `RouletteSpinRemote` to the server.
	  2. Server picks a reward (weighted) and fires back `{angle, reward}`.
	  3. Component animates the wheel with constant angular deceleration
	     (Newton 2nd law) until it lands exactly on the server angle.

	@class SpinRoulette
]=]
local SpinRoulette = Roact.Component:extend("SpinRoulette")

function SpinRoulette:init()
	-- Binding lets us push new rotation values straight into the ImageLabel
	-- every RenderStepped frame without triggering Roact reconciliation.
	self._rotation, self._setRotation = Roact.createBinding(0)

	self._spinning = false
	self._spinConn = nil
	self._resultConn = nil

	self:setState({
		spinning = false,
		result = nil :: string?,
	})
end

function SpinRoulette:didMount()
	self._resultConn = ReplicatedStorage.Shared.RemoteEvents.RouletteSpinRemote.OnClientEvent:Connect(
		function(data: { angle: number, reward: string })
			self:_startSpin(data.angle, data.reward)
		end
	)
end

function SpinRoulette:willUnmount()
	if self._resultConn then
		self._resultConn:Disconnect()
		self._resultConn = nil
	end
	if self._spinConn then
		self._spinConn:Disconnect()
		self._spinConn = nil
	end
end

--[=[
	Animates the wheel to `targetAngle` (radians, clockwise from top).

	Physics derivation (2nd law, constant torque → constant α):
	  ω(t)  = ω₀ + α·t
	  θ(t)  = ω₀·t + ½·α·t²
	  Final: ω=0 at θ=totalRotation  →  α = -ω₀² / (2·θ)
]=]
function SpinRoulette:_startSpin(targetAngle: number, rewardName: string)
	if self._spinning then
		return
	end
	self._spinning = true
	self:setState({ spinning = true, result = nil })

	-- To land sector `targetAngle` under the top pointer the wheel must rotate
	-- clockwise by (360·N − targetDeg).  N full rotations build up the spin feel.
	local targetDeg = math.deg(targetAngle)
	local N = 5
	local totalRotation = 360 * N - targetDeg -- degrees, clockwise

	local omega0 = 1440 -- deg/s  (4 full rotations per second at launch)
	local alpha = -(omega0 * omega0) / (2 * totalRotation)

	local omega = omega0
	local startRotation = self._rotation:getValue()
	local accumulated = 0

	self._spinConn = RunService.RenderStepped:Connect(function(dt: number)
		local newOmega = omega + alpha * dt
		if newOmega <= 0 then
			self._spinConn:Disconnect()
			self._spinConn = nil
			self._spinning = false
			-- Snap exactly to target so floating-point drift doesn't matter.
			self._setRotation(startRotation + totalRotation)
			self:setState({ spinning = false, result = rewardName })
			return
		end

		-- Euler integration of θ under constant α.
		accumulated += omega * dt + 0.5 * alpha * dt * dt
		omega = newOmega
		self._setRotation(startRotation + accumulated)
	end)
end

function SpinRoulette:render()
	local spinning: boolean = self.state.spinning
	local result: string? = self.state.result
	return Roact.createElement("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(320, 400),
		BackgroundColor3 = Color3.fromRGB(18, 18, 28),
		BackgroundTransparency = 0.1,
		BorderSizePixel = 0,
	}, {
		Corner = Roact.createElement("UICorner", {
			CornerRadius = UDim.new(0, 14),
		}),

		-- Fixed pointer arrow (top-centre, outside the wheel frame).
		Pointer = Roact.createElement("ImageLabel", {
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0, 10),
			Size = UDim2.fromOffset(18, 26),
			BackgroundTransparency = 1,
			-- Built-in Roblox down-arrow decal; swap for a custom pointer asset.
			Image = "rbxassetid://6034287551",
			ImageColor3 = Color3.fromRGB(255, 215, 50),
			ZIndex = 3,
		}),

		-- Square wheel image; Rotation is driven by the Binding.
		Wheel = Roact.createElement("ImageLabel", {
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0, 44),
			Size = UDim2.fromOffset(260, 260),
			BackgroundTransparency = 1,
			Image = assets.spin_roullete.wheel,
			ScaleType = Enum.ScaleType.Fit,
			Rotation = self._rotation,
			ZIndex = 2,
		}),

		-- Result text (visible after the wheel stops).
		ResultLabel = result and Roact.createElement("TextLabel", {
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0, 316),
			Size = UDim2.new(0.9, 0, 0, 28),
			BackgroundTransparency = 1,
			Text = "You got: " .. result,
			TextColor3 = Color3.fromRGB(255, 215, 50),
			Font = Enum.Font.GothamBold,
			TextScaled = true,
			ZIndex = 2,
		}),

		-- Spin button.
		SpinButton = Roact.createElement("TextButton", {
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -14),
			Size = UDim2.new(0.6, 0, 0, 46),
			BackgroundColor3 = spinning
				and Color3.fromRGB(70, 70, 70)
				or Color3.fromRGB(210, 40, 40),
			BorderSizePixel = 0,
			Text = spinning and "Spinning…" or "SPIN",
			TextColor3 = Color3.fromRGB(255, 255, 255),
			Font = Enum.Font.GothamBold,
			TextSize = 20,
			AutoButtonColor = not spinning,
			ZIndex = 2,
			[Roact.Event.Activated] = function()
				if not spinning then
					ReplicatedStorage.Shared.RemoteEvents.RouletteSpinRemote:FireServer()
				end
			end,
		}, {
			ButtonCorner = Roact.createElement("UICorner", {
				CornerRadius = UDim.new(0, 10),
			}),
		}),
	})
end

return SpinRoulette
