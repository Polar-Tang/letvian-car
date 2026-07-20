local PathfindingService = game:GetService("PathfindingService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Roact = require(ReplicatedStorage.Shared.Roact)
local Maid = require(ReplicatedStorage.Nevermore.Quenty.maid.Shared.Maid)

local GameModeConstants = require(ReplicatedStorage.Nevermore.Custom.gamemode.src.Shared.GameModeConstants)
local teamConstants = require(ReplicatedStorage.Nevermore.Custom.gamemode.src.Shared.teamConstants)

-- Recompute cadence. The component binds RenderStepped (for a smooth dt clock)
-- but only re-runs the path every REDRAW_INTERVAL seconds — ComputeAsync is the
-- expensive call, not the bind.
local REDRAW_INTERVAL = 0.1

-- Pathfinding waypoints sit right on the navmesh (floor level). A flat ground
-- arrow pivoted exactly there is coincident with the floor — it z-fights / sits
-- under the geometry and is invisible in-game (yet looks perfect in an exported
-- folder, where there's no floor to occlude it). Lift each arrow slightly so it
-- renders above the surface. Bump this if the GroundArrow model's geometry
-- extends well below its pivot.
local ARROW_GROUND_OFFSET = Vector3.new(0, 0.5, 0)

--[=[
	Headless world-space path drawer.

	Observes the server-authored CTF_carrier tag through the CarrierClient binder
	(the tag replicates for free — no remote duplicating the same fact). It only
	draws for the **local** player: when the local character becomes a carrier it
	pathfinds from `character.HumanoidRootPart` to that carrier's goal (its own
	team's CTF_home zone, resolved by the binder) and lays a trail of
	`ReplicatedStorage.VFX.GroundArrow` clones along the waypoints, refreshing
	every REDRAW_INTERVAL seconds and tearing down the previous trail before each
	redraw. The binder's class-removing signal (drop on capture / death / despawn)
	clears the trail.

	`GroundArrow` lives outside the Rojo source map, so its template is resolved
	at runtime via WaitForChild (never required / typed).

	Smart arrow facing: each arrow looks at the **next** waypoint, except the
	**last** arrow, which looks at the goal's position.

	Renders no UI (returns nil) — it is mounted purely for its lifecycle, like a
	controller. Arrows are managed imperatively in a workspace Folder owned by
	the component maid, so an unmount cleans the trail.

	@class GroundPath
]=]
local GroundPath = Roact.Component:extend("GroundPath")

function GroundPath:init()
	self._maid = Maid.new()

	self._character = nil :: Model?
	self._goal = nil :: BasePart?
	-- Arrow tint for the active local carrier (their team colour). Resolved when
	-- the carrier is set; defaults neutral until then.
	self._arrowColor = teamConstants.DEFAULT_COLOR :: Color3

	-- Drives the REDRAW_INTERVAL gate; seeded high so the first frame after a
	-- fire draws immediately instead of waiting a full interval.
	self._sinceRedraw = REDRAW_INTERVAL
	-- ComputeAsync yields, so a redraw runs in a task.spawn; this guards against
	-- stacking a second compute on top of an in-flight one.
	self._computing = false

	-- One reusable folder for the whole trail; cleared (not destroyed) per redraw.
	local folder = Instance.new("Folder")
	folder.Name = "GroundPathArrows"
	folder.Parent = Workspace
	self._arrowsFolder = folder
	self._maid:GiveTask(folder)
end

function GroundPath:didMount()
	-- The started provider — _G.BinderProvider is the registration key, not the
	-- running provider whose binders are live.
	local provider = _G.ServiceBag:GetService(_G.BinderProvider)
	local binder = provider:Get(GameModeConstants.CTF_CARRIER_TAG)
	assert(binder, `GroundPath: no binder registered for tag "{GameModeConstants.CTF_CARRIER_TAG}"`)

	-- React, don't snapshot: a carrier can bind after this mount (deferred binder
	-- instantiation), so connect the signals AND sweep GetAll. The handlers are
	-- idempotent. Signal payload is (class, instance).
	self._maid:GiveTask(binder:GetClassAddedSignal():Connect(function(class, character: Model)
		self:_onCarrier(class, character)
	end))
	self._maid:GiveTask(binder:GetClassRemovingSignal():Connect(function(_class, character: Model)
		self:_onCarrierGone(character)
	end))
	for _, carrier in binder:GetAll() do
		self:_onCarrier(carrier, carrier:GetCharacter())
	end
end

-- A character became a carrier. Only the LOCAL player needs navigation arrows,
-- so ignore every other carrier (their overhead marker is FlagBillboard's job).
function GroundPath._onCarrier(self, carrier, character: Model)
	if Players:GetPlayerFromCharacter(character) ~= Players.LocalPlayer then
		return
	end
	local goal = carrier:GetGoal()
	if not goal then
		return
	end

	-- Tint the trail with the carrier's team colour (crimson / dark blue);
	-- neutral fallback for a teamless carrier or a team with no palette entry.
	local team = carrier:GetTeam()
	self._arrowColor = (team and teamConstants.TEAM_COLORS[team.Name]) or teamConstants.DEFAULT_COLOR

	debug.profilebegin("FlagPathRender")
	self:_activate(character, goal)
	debug.profileend()
end

-- The local carrier dropped the flag (capture / death / despawn → tag removed).
function GroundPath._onCarrierGone(self, character: Model)
	if character ~= self._character then
		return
	end
	self._character = nil
	self._goal = nil
	self._maid._loop = nil
	self:_clearTrail()
end

function GroundPath:didUpdate(previousProps)
	-- The `enabled` prop can be toggled while a target is already set; restart
	-- or stop the loop to match.
	if previousProps.enabled == self.props.enabled then
		return
	end
	if self._character and self._goal then
		self:_activate(self._character, self._goal)
	end
end

function GroundPath:willUnmount()
	self._maid:DoCleaning()
end

-- (Re)arms the draw loop for a target. Idempotent: a fresh fire just retargets.
function GroundPath._activate(self, character: Model, goal: BasePart)
	self._character = character
	self._goal = goal

	-- `enabled` defaults to true when the prop is omitted.
	if self.props.enabled == false then
		self:_clearTrail()
		self._maid._loop = nil
		return
	end

	self._timer = 0
	self._lastTimer = 0

	self._maid._loop = RunService.RenderStepped:Connect(function(deltaTime: number)
		self._timer += deltaTime
		if self._timer - self._lastTimer >= REDRAW_INTERVAL then
			self._lastTimer = self._timer
			self:_redraw()
		end
	end)
end

-- Removes the previous trail's arrows without destroying the host folder.
function GroundPath._clearTrail(self)
	self._arrowsFolder:ClearAllChildren()
end

-- Resolves (and caches) the off-source-map GroundArrow template.
function GroundPath._getTemplate(self): Model?
	if self._template then
		return self._template
	end
	local vfx = ReplicatedStorage:FindFirstChild("VFX")
	local template = vfx and vfx:FindFirstChild("GroundArrow")
	if template and template:IsA("Model") then
		self._template = template
	end
	return self._template
end

-- Computes the path and re-lays the arrow trail. Runs in a task.spawn because
-- PathfindingService:ComputeAsync yields and RenderStepped must not.
function GroundPath._redraw(self)
	local character = self._character
	local goal = self._goal
	if not (character and goal and goal.Parent) then
		return
	end

	if not self.hrp then
		self.hrp = character:FindFirstChild("HumanoidRootPart")
		return
	end

	local template = self:_getTemplate()

	if not template then
		warn("GroundPath: ReplicatedStorage.VFX.GroundArrow is missing")
		return
	end

	self._computing = true
	task.spawn(function()
		local path = PathfindingService:CreatePath()
		local ok = pcall(function()
			path:ComputeAsync((self.hrp :: BasePart).Position, goal.Position)
		end)
		self._computing = false

		-- The target may have changed (new fire / disabled) while we yielded.
		if self._character ~= character or self._goal ~= goal then
			return
		end
		if not ok or path.Status ~= Enum.PathStatus.Success then
			return
		end

		self:_drawWaypoints(path:GetWaypoints(), goal)
	end)
end

-- Lays one arrow per waypoint. Each arrow looks at the next waypoint; the last
-- one looks at the goal. Always clears the prior trail first.
function GroundPath._drawWaypoints(self, waypoints: { PathWaypoint }, goal: BasePart)
	self:_clearTrail()

	local template = self._template :: Model
	for index, waypoint in waypoints do
		local position = waypoint.Position + ARROW_GROUND_OFFSET

		-- The gotcha: face the *next* waypoint, except the last arrow, which
		-- faces the goal's position instead.
		local lookTarget: Vector3
		if index < #waypoints then
			lookTarget = waypoints[index + 1].Position
		else
			lookTarget = goal.Position
		end

		-- Keep the look target on the arrow's own Y so the ground arrow stays
		-- flat (yaw only) instead of tilting up/down a step.
		lookTarget = Vector3.new(lookTarget.X, position.Y, lookTarget.Z)

		local arrow = template:Clone()
		-- Coincident points would make CFrame.lookAt throw; place axis-aligned.
		if (lookTarget - position).Magnitude > 1e-3 then
			arrow:PivotTo(CFrame.lookAt(position, lookTarget) * CFrame.Angles(math.rad(90), 0, 0))
		else
			arrow:PivotTo(CFrame.new(position) * CFrame.Angles(math.rad(90), 0, 0))
		end
		self:_tintArrow(arrow)
		arrow.Parent = self._arrowsFolder
	end
end

-- Paints every BasePart of an arrow clone with the active carrier's team colour.
function GroundPath._tintArrow(self, arrow: Model)
	for _, descendant in arrow:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Color = self._arrowColor
		end
	end
end

function GroundPath:render()
	return nil
end

return GroundPath
