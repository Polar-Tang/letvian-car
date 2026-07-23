--!strict
-- Read-only registry of content ids. Components read these instead of
-- hardcoding rbxassetid strings inline.

return table.freeze({
	radar = table.freeze({
		-- Looping over-limit alarm. Id pending upload — drop it in as
		-- "rbxassetid://<id>"; an empty SoundId keeps the Sound inert.
		warnSound = "",
	}),
})
