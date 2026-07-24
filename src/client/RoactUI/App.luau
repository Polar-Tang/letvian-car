local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Roact = require(ReplicatedStorage.Shared.Roact)

local RadarProvider = require(script.Parent.Context.RadarContext.RadarProvider)
local CarProvider = require(script.Parent.Context.CarContext.CarProvider)
local CarContext = require(script.Parent.Context.CarContext.CarContext)
local BottomBar = require(script.Parent.components.BottomBar)
local RadarAlarm = require(script.Parent.components.RadarAlarm)
local SpeedTags = require(script.Parent.components.SpeedTags)
local useContext = require(script.Parent.Context.Utils.useContext)

local App = Roact.Component:extend("App")

function App:render()
	local withCtx = useContext({ CarContext = CarContext })

	return Roact.createElement("ScreenGui", {
		-- Roact owns this ScreenGui for the whole session; letting the engine
		-- delete it on spawn would orphan the tree.
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
	}, {
		-- CarProvider is the outermost dashboard gate: whether the local player is
		-- driving a CarRegister car decides the WHOLE readout. It wraps the radar
		-- pieces so SpeedTags/RadarAlarm can read CarContext too and hide off the
		-- wheel, and it wraps the BottomBar consumer. Nesting (not siblings) is
		-- what puts CarContext in the radar components' ancestor chain.
		CarProvider = Roact.createElement(CarProvider, {
			carRegisterClient = self.props.carRegisterClient,
		}, {
			RadarProvider = Roact.createElement(RadarProvider, {
				radarClient = self.props.radarClient,
			}, {
				-- One overhead tag per vehicle on radar; the alarm sits beside
				-- them so both read the same vehicle list from context. Each also
				-- reads CarContext and renders only while driving.
				SpeedTags = Roact.createElement(SpeedTags),
				RadarAlarm = Roact.createElement(RadarAlarm),
			}),
			BottomBar = withCtx(function(ctx)
				local value = CarContext.Consumer
				if not value.isDriving then
					return nil
				end
				return Roact.createElement(BottomBar, {
					numberPlate = value.numberPlate,
				})
			end),
		}),
	})
end

return App
