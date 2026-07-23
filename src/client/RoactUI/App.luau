local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Roact = require(ReplicatedStorage.Shared.Roact)

local RadarProvider = require(script.Parent.Context.RadarContext.RadarProvider)
local CarProvider = require(script.Parent.Context.CarContext.CarProvider)
local CarContext = require(script.Parent.Context.CarContext.CarContext)
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
		-- The bottom strip is the car dashboard: CarProvider tracks whether the
		-- local player is driving a CarRegister car, and the consumer mounts the
		-- BottomBar (with that car's plate) only while they are behind the wheel.
		CarProvider = Roact.createElement(CarProvider, {
			carRegisterClient = self.props.carRegisterClient,
		}, {
			BottomBar = Roact.createElement(CarContext.Consumer, {
				render = function(value)
					if not value.isDriving then
						return nil
					end
					return Roact.createElement(BottomBar, {
						numberPlate = value.numberPlate,
					})
				end,
			}),
		}),
	})
end

return App
