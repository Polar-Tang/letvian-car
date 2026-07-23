local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Roact = require(ReplicatedStorage.Shared.Roact)

local RadarProvider = require(script.Parent.Context.RadarContext.RadarProvider)
local BottomBar = require(script.Parent.components.BottomBar)
local RadarAlarm = require(script.Parent.components.RadarAlarm)
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
			-- One overhead tag per vehicle on radar; the alarm sits beside them
			-- so both read the same vehicle list from context.
			SpeedTags = Roact.createElement(SpeedTags),
			RadarAlarm = Roact.createElement(RadarAlarm),
		}),
		-- Outside the provider: the strip is status chrome, none of its fields
		-- read the radar yet.
		BottomBar = Roact.createElement(BottomBar),
	})
end

return App
