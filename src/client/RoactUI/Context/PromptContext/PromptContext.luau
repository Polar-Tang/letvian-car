local RS = game:GetService("ReplicatedStorage")
local Roact = require(RS.Shared.Roact)

local PromptContext = Roact.createContext({
	distanceCheckConnections = {},
	isPromptShown = false,
	prompt = {},
})

return PromptContext
