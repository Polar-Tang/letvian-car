local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local Roact = require(ReplicatedStorage.Shared.Roact)

local Maid = require(ReplicatedStorage.Nevermore.Quenty.maid.Shared.Maid)
local GetCartNumberPlate =
	require(ReplicatedStorage.Nevermore.Custom.carRegister.src.Shared.GetCartNumberPlate)
local CarRegisterConstants =
	require(ReplicatedStorage.Nevermore.Custom.carRegister.src.Shared.CarRegisterConstants)

local CarContext = require(script.Parent.CarContext)

-- Same key the car's A-Chassis first-person-camera plugin uses. Pressing it while
-- driving flips `firstPersonActive`, the master switch for the whole dashboard
-- (SpeedTags, BottomBar, RadarAlarm all gate on it). Kept here — not in each
-- component — so one press drives everything from one source of truth.
local FIRST_PERSON_TOGGLE_KEY = Enum.KeyCode.V

local CarProvider = Roact.Component:extend("CarProvider")

function CarProvider:_stateFor(car: Model?)
	print("car ", car)
	return {
		isDriving = car ~= nil,
		numberPlate = GetCartNumberPlate(car),
	}
end

function CarProvider:init()
	self._maid = Maid.new()
	-- Per-car maid: cleared each time the driven car changes, so a stale car's
	-- attribute listener never outlives it.
	self._carMaid = self._maid:Add(Maid.new())

	local state = self:_stateFor(self.props.carRegisterClient:GetDrivenCar())
	-- First-person mode always starts off; the driver raises the dashboard with V
	-- once seated.
	state.firstPersonActive = false
	self:setState(state)
end

-- Re-point at the newly driven car (or nil): refresh the plate now, and — since
-- the plate is stamped server-side and could arrive just after we sit down —
-- keep it live via the attribute-changed signal for as long as this car is ours.
function CarProvider:_bindCar(car: Model?)
	self._carMaid:DoCleaning()
	local state = self:_stateFor(car)
	if not car then
		-- Left the car: drop first-person mode so the dashboard/alarm can't linger,
		-- and so re-entering starts fresh (matching the car's own FP-cam reset).
		state.firstPersonActive = false
	end
	self:setState(state)
	if car then
		self._carMaid:GiveTask(
			car:GetAttributeChangedSignal(CarRegisterConstants.NUMBER_PLATE_ATTRIBUTE):Connect(function()
				self:setState({ numberPlate = GetCartNumberPlate(car) })
			end)
		)
	end
end

function CarProvider:didMount()
	-- Observe() emits the current driven car immediately, then on every change.
	self._maid:GiveTask(self.props.carRegisterClient:ObserveDrivenCar():Subscribe(function(car)
		print("bind to car")
		self:_bindCar(car)
	end))

	-- V toggles first-person mode, but only while driving (mirrors the car's FP-cam
	-- plugin, which only toggles while seated) — so `firstPersonActive` can never be
	-- true on foot. gameProcessed guards against toggling while typing in a text box.
	self._maid:GiveTask(UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed then
			return
		end
		if input.KeyCode == FIRST_PERSON_TOGGLE_KEY and self.state.isDriving then
			self:setState(function(previous)
				return { firstPersonActive = not previous.firstPersonActive }
			end)
		end
	end))
end

function CarProvider:willUnmount()
	self._maid:DoCleaning()
end

function CarProvider:render()
	return Roact.createElement(CarContext.Provider, {
		value = {
			isDriving = self.state.isDriving,
			numberPlate = self.state.numberPlate,
			firstPersonActive = self.state.firstPersonActive,
		},
	}, self.props[Roact.Children])
end

return CarProvider
