local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Roact = require(ReplicatedStorage.Shared.Roact)

local RadarContext = Roact.createContext({
	-- { Model } currently on radar, plus the service so consumers can read
	-- per-vehicle speed without going back through the service root.
	vehicles = {},
	radarClient = nil,
})

return RadarContext
