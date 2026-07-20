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

----------------------------- init process -----------------------------
serviceBag:Init()

serviceBag:Start()

----------------------------- UI -----------------------------
local MainApp = require(script.RoactUI.MainApp)

-- Pass the service, not its current list: RadarProvider subscribes to
-- RadarClient's observable and updates the Roact tree on every emission.
MainApp({
	radarClient = radarClient,
})
