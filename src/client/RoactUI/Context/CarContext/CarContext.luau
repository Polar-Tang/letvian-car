local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Roact = require(ReplicatedStorage.Shared.Roact)

local CarContext = Roact.createContext({
	-- isDriving: is the local player in a CarRegister car's seat. numberPlate: that
	-- car's plate. firstPersonActive: is first-person mode (V) on — the master
	-- switch for the whole dashboard (SpeedTags / BottomBar / RadarAlarm). It can
	-- only be true while driving (CarProvider gates the toggle and resets on exit).
	isDriving = false,
	numberPlate = "",
	firstPersonActive = false,
})

return CarContext
