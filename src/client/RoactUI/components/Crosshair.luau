local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Roact = require(ReplicatedStorage.Shared.Roact)
local assets = require(ReplicatedStorage.Shared.Public.assets)

local useContext = require(script.Parent.Parent.Context.Utils.useContext)
local CrosshairContext = require(script.Parent.Parent.Context.CrosshairContext.CrosshairContext)

local FIRST_PERSON_OFFSET = 12
local THIRD_PERSON_OFFSET = 28
local CORNER_SIZE = UDim2.fromOffset(16, 16)
local CENTER_SIZE = UDim2.fromOffset(32, 32)
local TWEEN_INFO = TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local function cornerPositions(offset: number)
	return {
		lSup = UDim2.new(0.5, -offset, 0.5, -offset),
		lSub = UDim2.new(0.5, -offset, 0.5, offset),
		rSup = UDim2.new(0.5, offset, 0.5, -offset),
		rSub = UDim2.new(0.5, offset, 0.5, offset),
	}
end

local CrosshairView = Roact.Component:extend("CrosshairView")

function CrosshairView:init()
    UserInputService.MouseIconEnabled = false

	self.centerRef = Roact.createRef()
	self.lSupRef = Roact.createRef()
	self.lSubRef = Roact.createRef()
	self.rSupRef = Roact.createRef()
	self.rSubRef = Roact.createRef()

	local cameraMediator = self.props.cameraMediator
	if cameraMediator then
		self._subscription = cameraMediator:ObserveIsFirstPerson():Subscribe(function(isFirstPerson)
			self:_animate(isFirstPerson)
		end)
	end
end

function CrosshairView:_animate(isFirstPerson: boolean)
	local positions = cornerPositions(isFirstPerson and FIRST_PERSON_OFFSET or THIRD_PERSON_OFFSET)

	local function tween(ref, position)
		local instance = ref:getValue()
		if instance then
			TweenService:Create(instance, TWEEN_INFO, { Position = position }):Play()
		end
	end

	tween(self.lSupRef, positions.lSup)
	tween(self.lSubRef, positions.lSub)
	tween(self.rSupRef, positions.rSup)
	tween(self.rSubRef, positions.rSub)
end

function CrosshairView:render()
	local positions = cornerPositions(THIRD_PERSON_OFFSET)
	return Roact.createElement("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(120, 120),
		BackgroundTransparency = 1,
	}, {
		Center = Roact.createElement("ImageLabel", {
			[Roact.Ref] = self.centerRef,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = CENTER_SIZE,
			BackgroundTransparency = 1,
			Image = assets.crosshair.default_croshair,
		}),
		LSup = Roact.createElement("ImageLabel", {
			[Roact.Ref] = self.lSupRef,
			AnchorPoint = Vector2.new(1, 1),
			Position = positions.lSup,
			Size = CORNER_SIZE,
			BackgroundTransparency = 1,
			Image = assets.crosshair.default_LSup,
		}),
		LSub = Roact.createElement("ImageLabel", {
			[Roact.Ref] = self.lSubRef,
			AnchorPoint = Vector2.new(1, 0),
			Position = positions.lSub,
			Size = CORNER_SIZE,
			BackgroundTransparency = 1,
			Image = assets.crosshair.default_LSub,
		}),
		RSup = Roact.createElement("ImageLabel", {
			[Roact.Ref] = self.rSupRef,
			AnchorPoint = Vector2.new(0, 1),
			Position = positions.rSup,
			Size = CORNER_SIZE,
			BackgroundTransparency = 1,
			Image = assets.crosshair.default_RSup,
		}),
		RSub = Roact.createElement("ImageLabel", {
			[Roact.Ref] = self.rSubRef,
			AnchorPoint = Vector2.new(0, 0),
			Position = positions.rSub,
			Size = CORNER_SIZE,
			BackgroundTransparency = 1,
			Image = assets.crosshair.default_RSub,
		}),
	})
end

function CrosshairView:willUnmount()
	if self._subscription then
		self._subscription:Destroy()
		self._subscription = nil
	end
end

local Crosshair = Roact.Component:extend("Crosshair")

function Crosshair:render()
	local withCtx = useContext({ CrosshairContext = CrosshairContext })

	return withCtx(function(ctx)
		local crosshairCtx = ctx.CrosshairContext

		return Roact.createElement(CrosshairView, {
			cameraMediator = crosshairCtx.cameraMediator,
		})
	end)
end

return Crosshair
