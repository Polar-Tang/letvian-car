local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Roact = require(ReplicatedStorage.Shared.Roact)

local CarContext = Roact.createContext({
	-- Whether the local player is driving a CarRegister car right now, and that
	-- car's plate. The BottomBar consumer mounts only while isDriving is true.
	isDriving = false,
	numberPlate = "",
})

return CarContext
