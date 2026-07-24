local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Roact = require(ReplicatedStorage.Shared.Roact)

local assets = require(ReplicatedStorage.Shared.Public.assets)
local Units = require(ReplicatedStorage.Shared.Public.Units)
local RadarConstants = require(ReplicatedStorage.Nevermore.Custom.radar.src.Shared.RadarConstants)

local useContext = require(script.Parent.Parent.Context.Utils.useContext)
local RadarContext = require(script.Parent.Parent.Context.RadarContext.RadarContext)
local CarContext = require(script.Parent.Parent.Context.CarContext.CarContext)

-- Poll cadence for the over-limit check (matches the tags' readout refresh).
local REFRESH_RATE = 10

--[=[
	One global looping alarm, deduped across targets: it plays while ANY vehicle
	on radar is at or over RadarConstants.SPEED_LIMIT and stops once every
	target has dropped back under — stacking one Sound per speeder would chorus.
	@class RadarAlarmView
]=]
local RadarAlarmView = Roact.Component:extend("RadarAlarmView")

function RadarAlarmView:init()
	self:setState({ active = false })
end

function RadarAlarmView:_anyOverLimit(): boolean
	local radarClient = self.props.radarClient
	if not radarClient then
		return false
	end
	for _, vehicle in self.props.vehicles do
		-- GetSpeed is raw studs/second; compare in km/h so the alarm trips at the
		-- same limit the tag flips red at.
		if Units.studsPerSecondToKilometersPerHour(radarClient:GetSpeed(vehicle)) >= RadarConstants.SPEED_LIMIT then
			return true
		end
	end
	return false
end

function RadarAlarmView:didMount()
	local sinceLastCheck = 0
	self._connection = RunService.Heartbeat:Connect(function(deltaTime)
		sinceLastCheck += deltaTime
		if sinceLastCheck < 1 / REFRESH_RATE then
			return
		end
		sinceLastCheck = 0

		-- The heartbeat reads props live, so a membership change from the
		-- provider is picked up on the next tick without re-subscribing.
		local active = self:_anyOverLimit()
		if active ~= self.state.active then
			self:setState({ active = active })
		end
	end)
end

function RadarAlarmView:willUnmount()
	if self._connection then
		self._connection:Disconnect()
		self._connection = nil
	end
end

function RadarAlarmView:render()
	return Roact.createElement("Sound", {
		SoundId = assets.radar.warnSound,
		Looped = true,
		Playing = self.state.active,
	})
end

local RadarAlarm = Roact.Component:extend("RadarAlarm")

function RadarAlarm:render()
	local withCtx = useContext({ RadarContext = RadarContext, CarContext = CarContext })

	return withCtx(function(ctx)
		-- Only sound while the local player is driving a CarRegister car: the
		-- radar is the police car's, so off the wheel there's nothing to alarm on.
		if not ctx.CarContext.isDriving then
			return nil
		end
		local radarCtx = ctx.RadarContext

		return Roact.createElement(RadarAlarmView, {
			vehicles = radarCtx.vehicles,
			radarClient = radarCtx.radarClient,
		})
	end)
end

return RadarAlarm
