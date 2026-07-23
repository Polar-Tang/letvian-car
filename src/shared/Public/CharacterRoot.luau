--!strict
-- CharacterRoot: keeps `caller.root` pointing at the LocalPlayer's live
-- HumanoidRootPart, and keeps it fresh across respawns.
--
-- Why this exists: BottomBar, SpeedTags and RadarClient each reach for the
-- local character's root part to read position/velocity. Caching it once is a
-- bug — a respawn destroys the old character Model, so the cached part turns
-- into a "ghost" reference that freezes the readout at the spot the last body
-- died. This binds `caller.root` now and rewires it on every CharacterAdded;
-- the refresh connection is parked on the caller's Maid so it dies with the
-- caller (no dangling listener after unmount / Destroy).
--
-- Usage — the caller must already own a Maid at `caller._maid`:
--   CharacterRoot.bind(self) -- sets self.root now, refreshes it on respawn
--
-- Non-yielding by contract: safe from a Roact :init or any Heartbeat-adjacent
-- path that must not block. `caller.root` may be nil for a frame or two around
-- spawn / respawn — every reader already guards for that (returns 0 / zero).

local Players = game:GetService("Players")

local ROOT_PART_NAME = "HumanoidRootPart"

export type Rootable = {
	root: BasePart?,
	_maid: any,
}

local CharacterRoot = {}

-- Resolve a character's root part without yielding. PrimaryPart is set by the
-- engine for player rigs (the fast path); FindFirstChild covers the sliver of
-- time before that property lands. Returns nil if neither is ready yet.
local function resolveRoot(character: Model?): BasePart?
	if not character then
		return nil
	end
	local root = character.PrimaryPart or character:FindFirstChild(ROOT_PART_NAME)
	return root :: BasePart?
end

-- Write the freshly-resolved root onto the caller. In the rare case the part
-- hasn't replicated yet at CharacterAdded time (PrimaryPart unset AND the HRP
-- not yet a child), fall back to a WaitForChild off the signal thread and
-- discard the result if a newer character has spawned in the meantime.
local function assign(caller: Rootable, character: Model)
	local root = resolveRoot(character)
	if root then
		caller.root = root
		return
	end

	caller.root = nil
	task.spawn(function()
		local hrp = character:WaitForChild(ROOT_PART_NAME, 5)
		if hrp and Players.LocalPlayer.Character == character then
			caller.root = hrp :: BasePart
		end
	end)
end

--[=[
	Binds `caller.root` to the LocalPlayer's current HumanoidRootPart and keeps
	it in sync across respawns. The refresh connection is handed to caller._maid,
	so cleanup is automatic when the maid is cleaned.
	@param caller { root, _maid } -- the object to write `.root` onto
	@return RBXScriptConnection -- the respawn listener (also on caller._maid)
]=]
function CharacterRoot.bind(caller: Rootable): RBXScriptConnection
	local maid = assert(caller._maid, "[CharacterRoot.bind] caller has no _maid to own the respawn connection")

	local character = Players.LocalPlayer.Character
	if character then
		assign(caller, character)
	else
		caller.root = nil
	end

	local connection = Players.LocalPlayer.CharacterAdded:Connect(function(spawned)
		assign(caller, spawned)
	end)
	maid:GiveTask(connection)
	return connection
end

return CharacterRoot
