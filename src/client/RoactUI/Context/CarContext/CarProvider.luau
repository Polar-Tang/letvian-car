local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Roact = require(ReplicatedStorage.Shared.Roact)

local Maid = require(ReplicatedStorage.Nevermore.Quenty.maid.Shared.Maid)
local GetCartNumberPlate =
	require(ReplicatedStorage.Nevermore.Custom.carRegister.src.Shared.GetCartNumberPlate)
local CarRegisterConstants =
	require(ReplicatedStorage.Nevermore.Custom.carRegister.src.Shared.CarRegisterConstants)

local CarContext = require(script.Parent.CarContext)

local CarProvider = Roact.Component:extend("CarProvider")

function CarProvider:_stateFor(car: Model?)
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

	self:setState(self:_stateFor(self.props.carRegisterClient:GetDrivenCar()))
end

-- Re-point at the newly driven car (or nil): refresh the plate now, and — since
-- the plate is stamped server-side and could arrive just after we sit down —
-- keep it live via the attribute-changed signal for as long as this car is ours.
function CarProvider:_bindCar(car: Model?)
	self._carMaid:DoCleaning()
	self:setState(self:_stateFor(car))
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
		self:_bindCar(car)
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
		},
	}, self.props[Roact.Children])
end

return CarProvider
