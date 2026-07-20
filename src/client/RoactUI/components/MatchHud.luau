local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Teams = game:GetService("Teams")
local Workspace = game:GetService("Workspace")

local Roact = require(ReplicatedStorage.Shared.Roact)

local gameModeTypes = require(ReplicatedStorage.Nevermore.Custom.gamemode.src.Shared.gameModeTypes)
local GameModeConfig = require(ReplicatedStorage.Nevermore.Custom.gamemode.src.Shared.GameModeConfig)

local MatchStateRemote: RemoteEvent = ReplicatedStorage.Shared.RemoteEvents.MatchState

--[=[
	Match scoreboard (top-center): one tile per team score, the countdown, and
	the winner banner once the match ends. Hidden until the server reports an
	active match.

	Server is the single source of truth: GameModeService broadcasts the full
	ScoreState snapshot on every mutation and this component just replaces its
	state with it (QuestsList pattern). On mount it fires the remote back for
	a resync — the match usually started before this component existed.

	The countdown is derived locally each second from `matchEndTime -
	workspace:GetServerTimeNow()`: no per-second remote traffic.

	@class MatchHud
]=]
local MatchHud = Roact.Component:extend("MatchHud")

local function teamColor(teamId: string): Color3
	local team = Teams:FindFirstChild(teamId)
	if team then
		return team.TeamColor.Color
	end
	return Color3.fromRGB(200, 200, 200)
end

local function formatClock(seconds: number): string
	local clamped = math.max(0, math.floor(seconds))
	return string.format("%d:%02d", clamped // 60, clamped % 60)
end

function MatchHud:init()
	self._stateConn = nil
	self._clockThread = nil

	self:setState({
		match = nil :: gameModeTypes.ScoreState?,
		now = Workspace:GetServerTimeNow(),
	})
end

function MatchHud:didMount()
	self._stateConn = MatchStateRemote.OnClientEvent:Connect(function(match: gameModeTypes.ScoreState)
		self:setState({ match = match })
	end)

	-- Ask the server to replay the snapshot we missed before mounting.
	MatchStateRemote:FireServer()

	-- 1 Hz re-render so the countdown ticks without any remote traffic.
	self._clockThread = task.spawn(function()
		while true do
			task.wait(1)
			self:setState({ now = Workspace:GetServerTimeNow() })
		end
	end)
end

function MatchHud:willUnmount()
	if self._stateConn then
		self._stateConn:Disconnect()
		self._stateConn = nil
	end
	if self._clockThread then
		task.cancel(self._clockThread)
		self._clockThread = nil
	end
end

local function scoreTile(teamId: string, score: number, target: number, layoutOrder: number)
	return Roact.createElement("Frame", {
		Size = UDim2.fromOffset(110, 44),
		BackgroundColor3 = Color3.fromRGB(18, 18, 28),
		BackgroundTransparency = 0.25,
		BorderSizePixel = 0,
		LayoutOrder = layoutOrder,
	}, {
		Corner = Roact.createElement("UICorner", {
			CornerRadius = UDim.new(0, 8),
		}),
		Accent = Roact.createElement("Frame", {
			Size = UDim2.new(1, 0, 0, 4),
			BackgroundColor3 = teamColor(teamId),
			BorderSizePixel = 0,
		}),
		Score = Roact.createElement("TextLabel", {
			Position = UDim2.new(0, 0, 0, 4),
			Size = UDim2.new(1, 0, 1, -4),
			BackgroundTransparency = 1,
			Text = string.format("%s  %d/%d", teamId, score, target),
			TextColor3 = teamColor(teamId),
			Font = Enum.Font.GothamBold,
			TextSize = 16,
		}),
	})
end

function MatchHud:render()
	local match: gameModeTypes.ScoreState? = self.state.match
	if not match or match.phase == "waiting" then
		return nil
	end

	local children: { [string]: any } = {
		Layout = Roact.createElement("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0, 8),
		}),
	}

	-- Stable team order from the mode config (pairs over scores would jitter).
	local config = GameModeConfig[match.modeId]
	local order = 1
	if config and config.teams then
		for _, spec in config.teams do
			children[spec.id] = scoreTile(spec.id, match.scores[spec.id] or 0, match.targetScore, order)
			order += 1
		end
	end

	if match.matchEndTime and match.phase == "active" then
		children.Clock = Roact.createElement("TextLabel", {
			Size = UDim2.fromOffset(70, 44),
			BackgroundTransparency = 1,
			Text = formatClock(match.matchEndTime - self.state.now),
			TextColor3 = Color3.fromRGB(240, 240, 240),
			Font = Enum.Font.GothamBold,
			TextSize = 18,
			LayoutOrder = 0,
		})
	end

	local banner = nil
	if match.phase == "ended" then
		local text = if match.winner == "draw" or match.winner == nil
			then "Draw!"
			else `{match.winner} wins!`
		banner = Roact.createElement("TextLabel", {
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0, 110),
			Size = UDim2.fromOffset(420, 64),
			BackgroundColor3 = Color3.fromRGB(18, 18, 28),
			BackgroundTransparency = 0.15,
			Text = text,
			TextColor3 = if match.winner and match.winner ~= "draw"
				then teamColor(match.winner)
				else Color3.fromRGB(240, 240, 240),
			Font = Enum.Font.GothamBold,
			TextSize = 32,
		}, {
			Corner = Roact.createElement("UICorner", {
				CornerRadius = UDim.new(0, 12),
			}),
		})
	end

	return Roact.createElement("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
	}, {
		Scores = Roact.createElement("Frame", {
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0, 12),
			Size = UDim2.fromOffset(0, 44),
			AutomaticSize = Enum.AutomaticSize.X,
			BackgroundTransparency = 1,
		}, children),
		Banner = banner,
	})
end

return MatchHud
