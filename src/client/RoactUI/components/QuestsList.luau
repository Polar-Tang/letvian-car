local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Roact = require(ReplicatedStorage.Shared.Roact)

local QuestsData = require(ReplicatedStorage.Shared.Quests.QuestsData)
local questTypes = require(ReplicatedStorage.Shared.Quests.questTypes)

local QuestProgressRemote: RemoteEvent = ReplicatedStorage.Shared.RemoteEvents.QuestProgress

--[=[
	Quest tracker panel (top-right).

	Server is the single source of truth: every quest accept/progress/complete
	lands here as one `QuestProgress` payload on `QuestProgressRemote`, and the
	component just upserts it into `state.quests` keyed by questId. Titles and
	descriptions are NOT sent over the wire — they're read from the shared
	quest pool (`RS.Shared.Quests`) via the payload's questId.

	On mount it fires the same remote back at the server, which answers with a
	full resync (`PlayerQuests:Resync`) — the join-time burst usually fires
	before this component exists, and unconnected OnClientEvent fires are lost.

	@class QuestsList
]=]
local QuestsList = Roact.Component:extend("QuestsList")

function QuestsList:init()
	self._progressConn = nil

	self:setState({
		quests = {} :: { [string]: questTypes.QuestProgress },
	})
end

function QuestsList:didMount()
	self._progressConn = QuestProgressRemote.OnClientEvent:Connect(function(progress: questTypes.QuestProgress)
		-- setState merges top-level keys only, so rebuild the quests table
		-- instead of mutating the one already in state.
		local quests = table.clone(self.state.quests)
		quests[progress.questId] = progress
		self:setState({ quests = quests })
	end)

	-- Ask the server to replay everything we missed before mounting.
	QuestProgressRemote:FireServer()
end

function QuestsList:willUnmount()
	if self._progressConn then
		self._progressConn:Disconnect()
		self._progressConn = nil
	end
end

--[=[
	One row per quest: title + "n/m" counter, description, progress bar.
	Completed quests turn green and sink to the bottom of the list.
]=]
local function questEntry(progress: questTypes.QuestProgress, layoutOrder: number)
	local quest = QuestsData.FindQuest(progress.questId)
	local title = quest and quest.title or progress.questId
	local description = quest and quest.description or ""

	local ratio = if progress.requiredAmount > 0 then progress.progress / progress.requiredAmount else 1
	local accent = progress.completed and Color3.fromRGB(80, 200, 120) or Color3.fromRGB(255, 215, 50)

	return Roact.createElement("Frame", {
		Size = UDim2.new(1, 0, 0, 58),
		BackgroundColor3 = Color3.fromRGB(18, 18, 28),
		BackgroundTransparency = 0.25,
		BorderSizePixel = 0,
		LayoutOrder = layoutOrder,
	}, {
		Corner = Roact.createElement("UICorner", {
			CornerRadius = UDim.new(0, 8),
		}),

		Title = Roact.createElement("TextLabel", {
			Position = UDim2.new(0, 8, 0, 4),
			Size = UDim2.new(1, -70, 0, 18),
			BackgroundTransparency = 1,
			Text = title,
			TextColor3 = accent,
			Font = Enum.Font.GothamBold,
			TextSize = 14,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd,
		}),

		Counter = Roact.createElement("TextLabel", {
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -8, 0, 4),
			Size = UDim2.fromOffset(56, 18),
			BackgroundTransparency = 1,
			Text = progress.completed and "✓" or string.format("%d/%d", progress.progress, progress.requiredAmount),
			TextColor3 = accent,
			Font = Enum.Font.GothamBold,
			TextSize = 14,
			TextXAlignment = Enum.TextXAlignment.Right,
		}),

		Description = Roact.createElement("TextLabel", {
			Position = UDim2.new(0, 8, 0, 22),
			Size = UDim2.new(1, -16, 0, 16),
			BackgroundTransparency = 1,
			Text = description,
			TextColor3 = Color3.fromRGB(200, 200, 200),
			Font = Enum.Font.Gotham,
			TextSize = 12,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd,
		}),

		BarBack = Roact.createElement("Frame", {
			Position = UDim2.new(0, 8, 1, -12),
			Size = UDim2.new(1, -16, 0, 6),
			BackgroundColor3 = Color3.fromRGB(50, 50, 60),
			BorderSizePixel = 0,
		}, {
			Corner = Roact.createElement("UICorner", {
				CornerRadius = UDim.new(1, 0),
			}),
			Fill = Roact.createElement("Frame", {
				Size = UDim2.fromScale(math.clamp(ratio, 0, 1), 1),
				BackgroundColor3 = accent,
				BorderSizePixel = 0,
			}, {
				Corner = Roact.createElement("UICorner", {
					CornerRadius = UDim.new(1, 0),
				}),
			}),
		}),
	})
end

function QuestsList:render()
	local quests: { [string]: questTypes.QuestProgress } = self.state.quests

	-- Stable order: active quests first, then completed; alphabetical inside
	-- each group so rows don't jump around as progress events arrive.
	local sorted: { questTypes.QuestProgress } = {}
	for _, progress in pairs(quests) do
		table.insert(sorted, progress)
	end
	table.sort(sorted, function(a, b)
		if a.completed ~= b.completed then
			return not a.completed
		end
		return a.questId < b.questId
	end)

	local entries: { [string]: any } = {
		Layout = Roact.createElement("UIListLayout", {
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0, 6),
		}),
	}
	for index, progress in ipairs(sorted) do
		entries[progress.questId] = questEntry(progress, index)
	end

	return Roact.createElement("Frame", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -12, 0, 64),
		Size = UDim2.fromOffset(240, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
	}, entries)
end

return QuestsList
