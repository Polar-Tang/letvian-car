local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Roact = require(ReplicatedStorage.Shared.Roact)

local RadarProvider = require(script.Parent.Context.RadarContext.RadarProvider)
local SpeedTags = require(script.Parent.components.SpeedTags)

local App = Roact.Component:extend("App")

function App:render()
	return Roact.createElement("ScreenGui", {
		-- Roact owns this ScreenGui for the whole session; letting the engine
		-- delete it on spawn would orphan the tree.
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
	}, {
		RadarProvider = Roact.createElement(RadarProvider, {
			radarClient = self.props.radarClient,
		}, {
			-- One overhead tag per vehicle on radar. The alert readout and
			-- bottom bar mount here next.
			SpeedTags = Roact.createElement(SpeedTags),
		}),
	})
end

return App
