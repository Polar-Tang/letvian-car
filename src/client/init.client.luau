--||Services||--
local RS = game:GetService("ReplicatedStorage")
----------------------------- getting servicebag and loader -----------------------------

local NeverMorePackages = RS:WaitForChild("Nevermore")
local loader = NeverMorePackages:FindFirstChild("LoaderUtils", true).Parent
local Nevermore = require(loader).bootstrapGame(NeverMorePackages)

local ServiceBag = Nevermore("ServiceBag")
local serviceBag = ServiceBag.new()

----------------------------- client services -----------------------------
-- Detection is client-side by design: each client scans its own camera cone
-- for RadarVehicle-tagged models and feeds the observable list the UI reads.
local radarClient = serviceBag:GetService(Nevermore("RadarClient"))

-- Tracks the CarRegister car the local player is driving (seated in its
-- VehicleSeat), so the BottomBar shows only while driving, with the car's plate.
local carRegisterClient = serviceBag:GetService(Nevermore("CarRegisterClient"))

----------------------------- init process -----------------------------
serviceBag:Init()

serviceBag:Start()

----------------------------- UI -----------------------------
local MainApp = require(script.RoactUI.MainApp)

-- Pass the services, not their current values: the providers subscribe to each
-- one's observable and update the Roact tree on every emission.
MainApp({
	radarClient = radarClient,
	carRegisterClient = carRegisterClient,
})
