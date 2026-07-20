local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Roact = require(ReplicatedStorage.Shared.Roact)

local Maid = require(ReplicatedStorage.Nevermore.Quenty.maid.Shared.Maid)

local RadarContext = require(script.Parent.RadarContext)

local RadarProvider = Roact.Component:extend("RadarProvider")

function RadarProvider:init()
	self._maid = Maid.new()

	self:setState({
		vehicles = self.props.radarClient:GetVehicles(),
	})
end

function RadarProvider:didMount()
	-- Every emission from the RadarClient's observable list lands here: setState
	-- replaces the context value, which re-renders everything under the provider.
	self._maid:GiveTask(self.props.radarClient:ObserveVehicles():Subscribe(function(vehicles)
		self:setState({
			vehicles = vehicles,
		})
	end))
end

function RadarProvider:willUnmount()
	self._maid:DoCleaning()
end

function RadarProvider:render()
	return Roact.createElement(RadarContext.Provider, {
		value = {
			vehicles = self.state.vehicles,
			radarClient = self.props.radarClient,
		},
	}, self.props[Roact.Children])
end

return RadarProvider
