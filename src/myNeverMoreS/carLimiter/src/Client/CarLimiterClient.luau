--!strict
-- Drives the A-Chassis speed limiter for the car the LOCAL player is driving.
-- The SpeedLimitPicker GUI calls SetLimit with one of CarLimiterConstants.PRESETS
-- or nil to uncap; this service writes that straight into the car's
-- "A-Chassis Tune" module as `Tune.SpeedLimit`.
--
-- Why that field and not a velocity clamp of our own: this chassis (A-Chassis
-- 1.7) ships a limiter already. Its Engine(dt) step reads `_Tune.SpeedLimit`
-- EVERY frame -- `local limit = (_CGear<0 and _Tune.ReverseSpeed or
-- _Tune.SpeedLimit)` -- and, above the limit, eases the throttle down and (with
-- Tune.SLimitBrake, on by default) applies the brake. So the cap works through
-- the drivetrain rather than fighting it, and because the read is per-frame a
-- plain table write takes effect immediately, with no car reload.
--
-- Client-side on purpose, and required to be: the chassis is a LocalScript on
-- the driver's client, so `require` there and `require` here return the SAME
-- cached table for that car's Tune module. Writing to it from the server, or
-- from a different client, would land on a different copy and do nothing.
--
-- Units: Tune.SpeedLimit is in km/h, and Shared/Public/Units.luau now copies
-- A-Chassis' own scale (Units.Length_mm = 280, so 1 stud = 0.28 m) -- so a cap
-- of 61 set here reads 61 on the radar tag, on the BottomBar and on the car's
-- own speedometer alike. Presets are written through verbatim.
--
-- Which car is "ours" comes from CarRegisterClient's driven-car observable, the
-- same source the BottomBar and the radar components gate on.

local require = require(script.Parent.loader).load(script)

local Maid = require("Maid")
local ValueObject = require("ValueObject")
local CarLimiterConstants = require("CarLimiterConstants")
local CarRegisterClient = require("CarRegisterClient")

-- The config ModuleScript A-Chassis keeps as a direct child of the car model.
local TUNE_MODULE_NAME = "A-Chassis Tune"

-- What A-Chassis treats as "no limiter" (its own guard is `if limit > 0 then`).
local NO_LIMIT = 0

local CarLimiterClient = {}
CarLimiterClient.ServiceName = "CarLimiterClient"

function CarLimiterClient:Init(serviceBag)
	assert(not self._serviceBag, "Already initialized")
	self._serviceBag = assert(serviceBag, "No serviceBag")

	self._maid = Maid.new()

	-- Active cap in km/h, or nil for uncapped. Observable so the GUI's selected
	-- button reflects what is actually in the Tune rather than its own copy of
	-- the state.
	self._limitKmh = self._maid:Add(ValueObject.new(nil :: number?))

	-- Wiring only: the observable is read in Start, by which point
	-- CarRegisterClient (registered ahead of us in init.client) has started.
	self._carRegisterClient = self._serviceBag:GetService(CarRegisterClient)

	-- The driven car, its Tune table, and the SpeedLimit that car shipped with --
	-- so uncapping restores the car's own value instead of assuming 0.
	self._car = nil :: Model?
	self._tune = nil :: any
	self._shippedLimit = nil :: number?
end

function CarLimiterClient:Start()
	-- Observe() emits the current driven car immediately, then on every change.
	-- Safe to apply synchronously from here: the Tune module is a plain config
	-- table with no requires and no waits, so requiring it cannot yield Start.
	self._maid:GiveTask(self._carRegisterClient:ObserveDrivenCar():Subscribe(function(car)
		self:_bindCar(car)
	end))
end

-- nil clears the cap. The GUI is the only caller; nothing else writes the value.
function CarLimiterClient:SetLimit(limitKmh: number?)
	self._limitKmh.Value = limitKmh
	self:_apply()
end

function CarLimiterClient:GetLimit(): number?
	return self._limitKmh.Value
end

function CarLimiterClient:ObserveLimit()
	return self._limitKmh:Observe()
end

-- Re-point at the newly driven car (or nil). The cap follows the DRIVER, not the
-- car: the one we are leaving gets its shipped limit back, and the one we are
-- getting into picks the active preset up.
function CarLimiterClient:_bindCar(car: Model?)
	if self._car ~= car then
		self:_restore()
	end

	self._car = car
	self._tune = if car then self:_resolveTune(car) else nil
	self._shippedLimit = if self._tune then self._tune.SpeedLimit else nil
	self:_apply()
end

-- Hand the car we are letting go of its own SpeedLimit back, so a car we merely
-- passed through isn't left governed once we're out of it.
function CarLimiterClient:_restore()
	if self._tune and self._shippedLimit then
		self._tune.SpeedLimit = self._shippedLimit
	end
	if self._car then
		self._car:SetAttribute(CarLimiterConstants.LIMIT_ATTRIBUTE, nil)
	end
	self._tune = nil
	self._shippedLimit = nil
end

function CarLimiterClient:_apply()
	local tune = self._tune
	if not tune then
		return -- not in a car, or this one has no A-Chassis Tune to drive
	end

	local limitKmh = self._limitKmh.Value
	-- Uncapping restores the car's shipped value rather than hard-zeroing, in
	-- case this chassis was tuned with a limiter of its own.
	tune.SpeedLimit = limitKmh or self._shippedLimit or NO_LIMIT
	print(tune.SpeedLimit, "tune.SpeedLimit")
	local car = self._car
	if car then
		car:SetAttribute(CarLimiterConstants.LIMIT_ATTRIBUTE, limitKmh)
	end
end

-- The car's Tune table, or nil if this model isn't an A-Chassis car (the radar's
-- testing dummy isn't). require() is cached per client, so this hands back the
-- very table the car's own chassis LocalScript is reading each frame.
function CarLimiterClient:_resolveTune(car: Model): any
	local module = car:FindFirstChild(TUNE_MODULE_NAME)
	if not (module and module:IsA("ModuleScript")) then
		return nil
	end
	return require(module)
end

function CarLimiterClient:Destroy()
	self:_restore()
	self._maid:DoCleaning()
end

return CarLimiterClient
