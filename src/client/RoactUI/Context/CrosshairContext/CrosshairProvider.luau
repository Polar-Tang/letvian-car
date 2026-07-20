local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Roact = require(ReplicatedStorage.Shared.Roact)

local CrosshairContext = require(script.Parent.CrosshairContext)
local Crosshair = require(script.Parent.Parent.Parent.components.Crosshair)

local CrosshairProvider = Roact.Component:extend("CrosshairProvider")

function CrosshairProvider:init()
	self:setState({})
end

function CrosshairProvider:render()
	return Roact.createElement(CrosshairContext.Provider, {
		value = {
			cameraMediator = self.props.cameraMediator,
		},
	}, {
		Crosshair = Roact.createElement(Crosshair),
	})
end

return CrosshairProvider
