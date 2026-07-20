local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Roact = require(ReplicatedStorage.Shared.Roact)

local CrosshairContext = Roact.createContext({
	cameraMediator = nil,
})

return CrosshairContext
