local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Roact = require(ReplicatedStorage.Shared.Roact)
local Maid = require(ReplicatedStorage.Nevermore.Quenty.maid.Shared.Maid)

local LeaderboardConstants = require(ReplicatedStorage.Nevermore.Custom.gamemode.src.Shared.LeaderboardConstants)

local WinScreenRemote: RemoteEvent = ReplicatedStorage.Shared.RemoteEvents.WinScreen
local LeaveMatchRemote: RemoteEvent = ReplicatedStorage.Shared.RemoteEvents.LeaveMatch

--[=[
	@class WinScreen

	End-of-match results table. The server (BaseMode.BroadcastResults, fired from
	GameModeService.endMatch) sends the WinScreen remote when the match ends; this
	overlay then renders the whole leaderboard as a table: players are rows, stats
	are columns, plus a leading "player" column (avatar headshot). A centered
	footer "LEAVE" button fires the LeaveMatch remote.

	The leaderboard is NOT carried by the remote. LeaderboardService keeps a fully
	replicated `ReplicatedStorage.<FOLDER_NAME>` folder of IntValues, so this
	component is a pure observer of that folder — it re-reads on any descendant
	add/remove/change and re-renders. The remote only triggers visibility and
	carries the winner for the banner.

	ZIndex layering — the `layer` prop is the floor: the root uses `layer`, and
	each level deeper uses parent + 1 (siblings at one level share a value). So
	`layer` lets a parent slot this overlay above everything else in the tree.
]=]
local WinScreen = Roact.Component:extend("WinScreen")

-- Column order: the known base/optional stats first (so kills/deaths/damage read
-- left-to-right as authored), any future/unknown keys appended after.
local PREFERRED_STAT_ORDER = {
	LeaderboardConstants.STAT_KILLS,
	LeaderboardConstants.STAT_DEATHS,
	LeaderboardConstants.STAT_DAMAGE,
	LeaderboardConstants.STAT_FLAGS,
	LeaderboardConstants.STAT_HILL_TIME,
}

local PLAYER_COLUMN_WIDTH = 220
local STAT_COLUMN_WIDTH = 96
local ROW_HEIGHT = 40

local function headshot(userId: number): string
	return string.format("rbxthumb://type=AvatarHeadShot&id=%d&w=60&h=60", userId)
end

local function displayName(userId: number): string
	local player = Players:GetPlayerByUserId(userId)
	if player then
		return player.DisplayName
	end
	return "Player " .. tostring(userId)
end

-- Read the replicated Leaderboard folder into a sorted snapshot:
--   rows      = { { userId, stats = { [statName] = value } }, ... } (kills desc)
--   statNames = ordered column keys present across all rows
local function snapshotFolder(folder: Folder): ({ any }, { string })
	local rows = {}
	local present: { [string]: true } = {}

	for _, registry in folder:GetChildren() do
		if not registry:IsA("Folder") then
			continue
		end
		local userId = tonumber(registry.Name)
		if not userId then
			continue
		end

		local stats: { [string]: number } = {}
		for _, stat in registry:GetChildren() do
			if stat:IsA("IntValue") then
				stats[stat.Name] = stat.Value
				present[stat.Name] = true
			end
		end
		table.insert(rows, { userId = userId, stats = stats })
	end

	-- Highest kills first, damage as the tiebreak, userId for a stable order.
	table.sort(rows, function(a, b)
		local ak, bk = a.stats[LeaderboardConstants.STAT_KILLS] or 0, b.stats[LeaderboardConstants.STAT_KILLS] or 0
		if ak ~= bk then
			return ak > bk
		end
		local ad, bd = a.stats[LeaderboardConstants.STAT_DAMAGE] or 0, b.stats[LeaderboardConstants.STAT_DAMAGE] or 0
		if ad ~= bd then
			return ad > bd
		end
		return a.userId < b.userId
	end)

	local statNames = {}
	for _, name in PREFERRED_STAT_ORDER do
		if present[name] then
			table.insert(statNames, name)
			present[name] = nil -- mark consumed so the trailing sweep skips it
		end
	end
	-- Any stat key not in the preferred list (future-proofing), appended.
	for name in present do
		table.insert(statNames, name)
	end

	return rows, statNames
end

function WinScreen:init()
	self._maid = Maid.new()

	self:setState({
		visible = false,
		winner = Roact.None,
		rows = {},
		statNames = {},
	})
end

function WinScreen._refresh(self, folder: Folder)
	local rows, statNames = snapshotFolder(folder)
	self:setState({ rows = rows, statNames = statNames })
end

-- Observe the whole folder: any IntValue change / registry add / removal
-- re-snapshots. Connections live in a sub-maid so a re-observe is clean.
function WinScreen._observe(self, folder: Folder)
	local observeMaid = Maid.new()
	self._maid._observe = observeMaid

	observeMaid:GiveTask(folder.DescendantAdded:Connect(function(inst)
		if inst:IsA("IntValue") then
			observeMaid:GiveTask(inst.Changed:Connect(function()
				self:_refresh(folder)
			end))
		end
		self:_refresh(folder)
	end))
	observeMaid:GiveTask(folder.DescendantRemoving:Connect(function()
		self:_refresh(folder)
	end))

	for _, descendant in folder:GetDescendants() do
		if descendant:IsA("IntValue") then
			observeMaid:GiveTask(descendant.Changed:Connect(function()
				self:_refresh(folder)
			end))
		end
	end

	self:_refresh(folder)
end

function WinScreen:didMount()
	self._maid:GiveTask(WinScreenRemote.OnClientEvent:Connect(function(data)
		-- The results table needs a free, visible cursor for the Leave button
		-- (ServiceRoot hides the icon globally during gameplay).
		UserInputService.MouseIconEnabled = true
		UserInputService.MouseBehavior = Enum.MouseBehavior.Default

		self:setState({
			visible = true,
			winner = (data and data.winner) or Roact.None,
		})

		-- Start observing only now (the folder is built at server Start, well
		-- before any match ends, so it exists). WaitForChild keeps it safe.
		task.spawn(function()
			local folder = ReplicatedStorage:WaitForChild(LeaderboardConstants.FOLDER_NAME, 10)
			if folder and self.state.visible then
				self:_observe(folder :: Folder)
			end
		end)
	end))
end

function WinScreen:willUnmount()
	self._maid:DoCleaning()
end

-- One fixed-width table cell. `depth` carries the ZIndex layering down.
local function cell(text: string, width: number, isHeader: boolean, layoutOrder: number, depth: number)
	return Roact.createElement("TextLabel", {
		Size = UDim2.fromOffset(width, ROW_HEIGHT),
		BackgroundTransparency = 1,
		Text = text,
		TextColor3 = if isHeader then Color3.fromRGB(170, 175, 190) else Color3.fromRGB(235, 235, 240),
		Font = if isHeader then Enum.Font.GothamBold else Enum.Font.GothamMedium,
		TextSize = if isHeader then 15 else 17,
		TextXAlignment = Enum.TextXAlignment.Center,
		LayoutOrder = layoutOrder,
		ZIndex = depth,
	})
end

-- The leading "player" column: avatar headshot + name, left-aligned.
local function playerCell(userId: number, layoutOrder: number, depth: number)
	return Roact.createElement("Frame", {
		Size = UDim2.fromOffset(PLAYER_COLUMN_WIDTH, ROW_HEIGHT),
		BackgroundTransparency = 1,
		LayoutOrder = layoutOrder,
		ZIndex = depth,
	}, {
		Layout = Roact.createElement("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0, 8),
		}),
		Padding = Roact.createElement("UIPadding", {
			PaddingLeft = UDim.new(0, 10),
		}),
		Photo = Roact.createElement("ImageLabel", {
			Size = UDim2.fromOffset(32, 32),
			BackgroundColor3 = Color3.fromRGB(40, 42, 54),
			BorderSizePixel = 0,
			Image = headshot(userId),
			LayoutOrder = 0,
			ZIndex = depth + 1,
		}, {
			Corner = Roact.createElement("UICorner", {
				CornerRadius = UDim.new(1, 0),
			}),
		}),
		Name = Roact.createElement("TextLabel", {
			Size = UDim2.fromOffset(PLAYER_COLUMN_WIDTH - 60, ROW_HEIGHT),
			BackgroundTransparency = 1,
			Text = displayName(userId),
			TextColor3 = Color3.fromRGB(235, 235, 240),
			Font = Enum.Font.GothamMedium,
			TextSize = 17,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd,
			LayoutOrder = 1,
			ZIndex = depth + 1,
		}),
	})
end

-- A table row (header or a player's stats). `depth` is this row's ZIndex; its
-- cells render one above it.
local function row(props: {
	userId: number?,
	stats: { [string]: number }?,
	statNames: { string },
	isHeader: boolean,
	layoutOrder: number,
	depth: number,
})
	local children: { [string]: any } = {
		Layout = Roact.createElement("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	}

	-- Leading player column.
	if props.isHeader then
		children.PlayerHeader = cell("PLAYER", PLAYER_COLUMN_WIDTH, true, 0, props.depth + 1)
	else
		children.Player = playerCell(props.userId :: number, 0, props.depth + 1)
	end

	-- One cell per stat column.
	for index, statName in props.statNames do
		local text = if props.isHeader
			then string.upper(statName)
			else tostring((props.stats and props.stats[statName]) or 0)
		children["col_" .. statName] = cell(text, STAT_COLUMN_WIDTH, props.isHeader, index, props.depth + 1)
	end

	return Roact.createElement("Frame", {
		Size = UDim2.fromOffset(PLAYER_COLUMN_WIDTH + #props.statNames * STAT_COLUMN_WIDTH, ROW_HEIGHT),
		BackgroundColor3 = Color3.fromRGB(255, 255, 255),
		BackgroundTransparency = if props.isHeader then 1 else 0.94,
		BorderSizePixel = 0,
		LayoutOrder = props.layoutOrder,
		ZIndex = props.depth,
	}, children)
end

function WinScreen:render()
	if not self.state.visible then
		return nil
	end

	local layer = self.props.layer or 1
	local statNames = self.state.statNames

	-- Header + one row per player, stacked vertically.
	local rowChildren: { [string]: any } = {
		Layout = Roact.createElement("UIListLayout", {
			FillDirection = Enum.FillDirection.Vertical,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0, 2),
		}),
		Header = row({
			statNames = statNames,
			isHeader = true,
			layoutOrder = 0,
			depth = layer + 2,
		}),
	}

	for index, entry in self.state.rows do
		rowChildren["row_" .. tostring(entry.userId)] = row({
			userId = entry.userId,
			stats = entry.stats,
			statNames = statNames,
			isHeader = false,
			layoutOrder = index,
			depth = layer + 2,
		})
	end

	local winner = self.state.winner
	local winnerText = if winner and winner ~= "draw" then `{winner} wins!` else "Draw!"

	return Roact.createElement("Frame", {
		-- Full-screen, centered scrim: the Panel centers against the real
		-- viewport (a partial-height band would push it into the upper screen
		-- and run its bottom — the Leave button — off a phone).
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.fromRGB(0, 0, 0),
		BackgroundTransparency = 0.35,
		BorderSizePixel = 0,
		ZIndex = layer,
	}, {
		Panel = Roact.createElement("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			-- Height is viewport-relative (90%) so the whole card — Leave button
			-- included — always fits on a short mobile screen; the constraint
			-- caps it on a tall desktop so it doesn't balloon. The Table flexes,
			-- the fixed footer stays pinned at the bottom.
			Size = UDim2.new(0, PLAYER_COLUMN_WIDTH + math.max(#statNames, 1) * STAT_COLUMN_WIDTH + 48, 0.9, 0),
			BackgroundColor3 = Color3.fromRGB(20, 21, 30),
			BackgroundTransparency = 0.05,
			BorderSizePixel = 0,
			ZIndex = layer + 1,
		}, {
			Corner = Roact.createElement("UICorner", {
				CornerRadius = UDim.new(0, 14),
			}),
			SizeConstraint = Roact.createElement("UISizeConstraint", {
				MaxSize = Vector2.new(math.huge, 520),
			}),
			Padding = Roact.createElement("UIPadding", {
				PaddingTop = UDim.new(0, 20),
				PaddingBottom = UDim.new(0, 20),
				PaddingLeft = UDim.new(0, 24),
				PaddingRight = UDim.new(0, 24),
			}),
			Layout = Roact.createElement("UIListLayout", {
				FillDirection = Enum.FillDirection.Vertical,
				HorizontalAlignment = Enum.HorizontalAlignment.Center,
				SortOrder = Enum.SortOrder.LayoutOrder,
				Padding = UDim.new(0, 14),
			}),

			Title = Roact.createElement("TextLabel", {
				Size = UDim2.new(1, 0, 0, 30),
				BackgroundTransparency = 1,
				Text = "MATCH RESULTS",
				TextColor3 = Color3.fromRGB(235, 235, 240),
				Font = Enum.Font.GothamBold,
				TextSize = 24,
				LayoutOrder = 0,
				ZIndex = layer + 2,
			}),
			Winner = Roact.createElement("TextLabel", {
				Size = UDim2.new(1, 0, 0, 26),
				BackgroundTransparency = 1,
				Text = winnerText,
				TextColor3 = Color3.fromRGB(255, 210, 90),
				Font = Enum.Font.GothamBold,
				TextSize = 20,
				LayoutOrder = 1,
				ZIndex = layer + 2,
			}),

			Table = Roact.createElement("ScrollingFrame", {
				-- Reserve room for the fixed siblings (Title + Winner + Leave +
				-- the 14px UIListLayout gaps) so the footer never gets clipped
				-- when the panel shrinks on mobile.
				Size = UDim2.new(1, 0, 1, -160),
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				CanvasSize = UDim2.fromScale(0, 0),
				AutomaticCanvasSize = Enum.AutomaticSize.Y,
				ScrollBarThickness = 4,
				LayoutOrder = 2,
				ZIndex = layer + 2,
			}, rowChildren),

			Leave = Roact.createElement("TextButton", {
				Size = UDim2.fromOffset(200, 48),
				BackgroundColor3 = Color3.fromRGB(210, 70, 70),
				BorderSizePixel = 0,
				Text = "LEAVE",
				TextColor3 = Color3.fromRGB(245, 245, 245),
				Font = Enum.Font.GothamBold,
				TextSize = 20,
				LayoutOrder = 3,
				ZIndex = layer + 2,
				-- Modal frees the cursor even where the mouse is otherwise locked.
				Modal = true,
				[Roact.Event.Activated] = function()
					LeaveMatchRemote:FireServer()
				end,
			}, {
				Corner = Roact.createElement("UICorner", {
					CornerRadius = UDim.new(0, 10),
				}),
			}),
		}),
	})
end

return WinScreen
