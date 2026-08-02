local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Roact = require(ReplicatedStorage.Shared.Roact)

local Units = require(ReplicatedStorage.Shared.Public.Units)
local RadarConstants = require(ReplicatedStorage.Nevermore.Custom.radar.src.Shared.RadarConstants)

local useContext = require(script.Parent.Parent.Context.Utils.useContext)
local RadarContext = require(script.Parent.Parent.Context.RadarContext.RadarContext)
local CarContext = require(script.Parent.Parent.Context.CarContext.CarContext)

-- Poll cadence for the over-limit check (matches the tags' readout refresh).
local REFRESH_RATE = 10

-- The RemoteEvent we fire so the SERVER plays/stops the alarm Sound on the driven
-- car (RadarAlarmService owns it). Resolved lazily and memoised — waiting here
-- rather than at module load keeps a slow-to-replicate remote from stalling the
-- whole App tree's mount, and the first fire only happens once a target speeds.
local alarmRemote: RemoteEvent? = nil
local function getAlarmRemote(): RemoteEvent
	if not alarmRemote then
		local folder = ReplicatedStorage:WaitForChild("RemoteEvents")
		alarmRemote = folder:WaitForChild(RadarConstants.ALARM_REMOTE) :: RemoteEvent
	end
	return alarmRemote :: RemoteEvent
end

--[=[
	The over-limit alarm — now server-driven. This client owns only the DECISION:
	it polls the radar list and, on each on/off edge, fires the alarm RemoteEvent
	with a boolean. The server plays a single looping Sound parented to the police
	car (positional, replicated to everyone) and destroys it on `false`. One fire
	when any target crosses the limit, one when the last drops back under — or when
	this unmounts (we stop driving), so the car's alarm never outlives the loop.
	@class RadarAlarmView
]=]
local RadarAlarmView = Roact.Component:extend("RadarAlarmView")

function RadarAlarmView:init()
	-- Plain field, not state: the alarm renders nothing now, so this only exists to
	-- detect the on/off edge and fire the remote once per change.
	self._active = false
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

-- Tell the server only on a change, so it gets one "play" then one "stop".
function RadarAlarmView:_setActive(active: boolean)
	if active == self._active then
		return
	end
	self._active = active
	getAlarmRemote():FireServer(active)
end

function RadarAlarmView:didMount()
	local sinceLastCheck = 0
	self._connection = RunService.Heartbeat:Connect(function(deltaTime)
		sinceLastCheck += deltaTime
		if sinceLastCheck < 1 / REFRESH_RATE then
			return
		end
		sinceLastCheck = 0

		-- The heartbeat reads props live, so a membership change from the provider
		-- is picked up on the next tick without re-subscribing.
		self:_setActive(self:_anyOverLimit())
	end)
end

function RadarAlarmView:willUnmount()
	if self._connection then
		self._connection:Disconnect()
		self._connection = nil
	end
	-- Leaving mid-blare (stopped driving, list gone): silence the car so the
	-- server's Sound doesn't outlive our decision loop.
	self:_setActive(false)
end

function RadarAlarmView:render()
	-- Nothing on the client anymore — the Sound lives on the car (server-side).
	return nil
end

local RadarAlarm = Roact.Component:extend("RadarAlarm")

function RadarAlarm:render()
	local withCtx = useContext({ RadarContext = RadarContext, CarContext = CarContext })

	return withCtx(function(ctx)
		-- First-person mode (V) is the master switch: run the decision loop — and let
		-- the server sound the alarm — only while it's active. When V turns off this
		-- returns nil, RadarAlarmView unmounts, and its willUnmount fires the "stop",
		-- silencing the car's alarm. firstPersonActive implies driving.
		if not ctx.CarContext.firstPersonActive then
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
