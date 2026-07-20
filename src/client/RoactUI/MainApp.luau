local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Roact = require(ReplicatedStorage.Shared.Roact)

local App = require(script.Parent.App)

export type MainAppDeps = {
	-- The started RadarClient service (not a snapshot of its list): the App
	-- hands it to RadarProvider, which owns the subscription to the observable
	-- vehicle list and re-renders the tree on every radar update.
	radarClient: any,
}

return function(deps: MainAppDeps)
	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui")

	return Roact.mount(
		Roact.createElement(App, {
			radarClient = deps.radarClient,
		}),
		playerGui,
		"UI"
	)
end
