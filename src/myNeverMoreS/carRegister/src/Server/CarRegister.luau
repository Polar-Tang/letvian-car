-- Bound to every CarRegisterConstants.CAR_REGISTER_TAG Model (an A-Chassis car).
-- On bind it generates a Latvian-style plate string once and stamps it onto the
-- car's front and rear plate parts as a SurfaceGui + TextLabel, mirroring the
-- Workspace.LVCarPlate look. Plate generation is server-authoritative; the
-- SurfaceGui the server parents to each plate part replicates down to clients.
--
-- Why a naive "clone the SurfaceGui onto the plate" fails, and what we do about
-- it (both verified in Studio against the Skoda Octavia A7):
--   * The plate parts are thin MeshParts whose visible surface is on the BACK
--     (-Z) face — the Front (+Z) normal points INTO the bodywork. A Front-faced
--     SurfaceGui renders inside the bumper and is invisible. We pick the face
--     whose world normal points away from the car's centre (_outwardFace).
--   * A cloned template keeps its Adornee pointing at the original part, so it
--     renders there, not on the new plate. We clear Adornee and parent directly.

local RS = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local require = require(script.Parent.loader).load(script)

local CarRegisterConstants = require("CarRegisterConstants")
local Maid = require("Maid")

-- Name we give the SurfaceGui we create, so a re-tag (or a second pass) replaces
-- our own plate rather than stacking a second one on the part.
local PLATE_GUI_NAME = "CarRegisterPlate"

local FACE_NORMALS = {
	Front = Enum.NormalId.Front,
	Back = Enum.NormalId.Back,
	Top = Enum.NormalId.Top,
	Bottom = Enum.NormalId.Bottom,
	Right = Enum.NormalId.Right,
	Left = Enum.NormalId.Left,
}

local CarRegister = {}
CarRegister.ClassName = "CarRegister"
CarRegister.__index = CarRegister

function CarRegister.new(model: Model)
	local self = setmetatable({}, CarRegister)

	self._model = model
	self._maid = Maid.new()

	-- Generate the patente once; the same string goes on both plates and onto
	-- the model attribute so other systems can read it.
	self._plate = self:_generatePlate()
	model:SetAttribute(CarRegisterConstants.NUMBER_PLATE_ATTRIBUTE, self._plate)

	self:_applyToPlate(CarRegisterConstants.FRONT_PLATE_VALUE)
	self:_applyToPlate(CarRegisterConstants.REAR_PLATE_VALUE)

	return self
end

-- Two letters + separator + four digits, e.g. "AB - 1234" (LVCarPlate pattern).
function CarRegister:_generatePlate(): string
	local rng = Random.new()
	local letters = {}
	for _ = 1, CarRegisterConstants.PLATE_LETTERS do
		table.insert(letters, string.char(rng:NextInteger(65, 90))) -- A-Z
	end
	local number = rng:NextInteger(0, 10 ^ CarRegisterConstants.PLATE_DIGITS - 1)
	return string.format(
		"%s%s%0" .. CarRegisterConstants.PLATE_DIGITS .. "d",
		table.concat(letters),
		CarRegisterConstants.PLATE_SEPARATOR,
		number
	)
end

-- Resolves the ObjectValue named `valueName` on the model, reads its .Value
-- (the plate BasePart), and stamps the plate SurfaceGui onto it.
function CarRegister:_applyToPlate(valueName: string)
	local objectValue = self._model:FindFirstChild(valueName, true)
	if not (objectValue and objectValue:IsA("ObjectValue")) then
		warn(("[CarRegister] %s has no ObjectValue %q — skipping that plate")
			:format(self._model:GetFullName(), valueName))
		return
	end

	local platePart = objectValue.Value
	if not (platePart and platePart:IsA("BasePart")) then
		warn(("[CarRegister] %s.%s does not point at a BasePart — skipping")
			:format(self._model:GetFullName(), valueName))
		return
	end

	-- Idempotent: drop a plate we made earlier before adding the fresh one.
	local existing = platePart:FindFirstChild(PLATE_GUI_NAME)
	if existing then
		existing:Destroy()
	end

	local gui = self:_buildPlateGui(platePart)
	gui.Name = PLATE_GUI_NAME
	gui.Adornee = nil -- render on the parent part's own surface, not a stale ref
	gui.Face = self:_resolveFace(platePart)
	gui.Parent = platePart
	-- Tie the gui's lifetime to the tag: untagging the car removes the plate.
	self._maid:GiveTask(gui)
end

-- Picks the SurfaceGui face for a plate part: an explicit "PlateFace" attribute
-- wins; otherwise auto-detect the outward face; otherwise the constant default.
function CarRegister:_resolveFace(platePart: BasePart): Enum.NormalId
	local override = platePart:GetAttribute("PlateFace")
	if type(override) == "string" and FACE_NORMALS[override] then
		return FACE_NORMALS[override]
	end
	if CarRegisterConstants.AUTO_DETECT_FACE then
		local detected = self:_outwardFace(platePart)
		if detected then
			return detected
		end
	end
	return FACE_NORMALS[CarRegisterConstants.DEFAULT_FACE] or Enum.NormalId.Back
end

-- The plate's visible side is the face whose world normal points away from the
-- car's centre. Compare all six face normals against that outward direction and
-- take the best-aligned one — works for both plates and any mesh orientation.
function CarRegister:_outwardFace(platePart: BasePart): Enum.NormalId?
	local center = self._model:GetBoundingBox().Position
	local outward = platePart.Position - center
	if outward.Magnitude < 1e-3 then
		return nil
	end
	outward = outward.Unit

	local cf = platePart.CFrame
	local candidates = {
		{ Enum.NormalId.Front, cf.LookVector },
		{ Enum.NormalId.Back, -cf.LookVector },
		{ Enum.NormalId.Right, cf.RightVector },
		{ Enum.NormalId.Left, -cf.RightVector },
		{ Enum.NormalId.Top, cf.UpVector },
		{ Enum.NormalId.Bottom, -cf.UpVector },
	}

	local best, bestDot = nil, -math.huge
	for _, pair in candidates do
		local dot = pair[2]:Dot(outward)
		if dot > bestDot then
			bestDot, best = dot, pair[1]
		end
	end
	return best
end

-- Returns a SurfaceGui (not yet parented, Face/Adornee set by the caller)
-- carrying the plate text, either cloned from a template or built from scratch.
function CarRegister:_buildPlateGui(platePart: BasePart): SurfaceGui
	local template = self:_findTemplate()
	if template then
		local gui = template:Clone()
		local label = gui:FindFirstChild(CarRegisterConstants.PLATE_LABEL_NAME, true)
		if label and label:IsA("TextLabel") then
			label.Text = self._plate
		end
		return gui
	end
	return self:_defaultPlateGui()
end

-- Looks for the shared template SurfaceGui in replicated/server storage by name.
function CarRegister:_findTemplate(): SurfaceGui?
	local name = CarRegisterConstants.TEMPLATE_SURFACE_GUI
	for _, container in { RS, ServerStorage } do
		local found = container:FindFirstChild(name, true)
		if found and found:IsA("SurfaceGui") then
			return found
		end
	end
	return nil
end

-- Faithful reproduction of Workspace.LVCarPlate.Plates.*.SGUI: white field
-- (the plate part's own colour shows through the transparent CarNr), a blue EU
-- strip on the left with "LV" and the emblem image, and the plate number.
function CarRegister:_defaultPlateGui(): SurfaceGui
	local gui = Instance.new("SurfaceGui")
	gui.SizingMode = Enum.SurfaceGuiSizingMode.FixedSize
	gui.CanvasSize = CarRegisterConstants.CANVAS_SIZE
	gui.LightInfluence = 0

	local stripW = CarRegisterConstants.LV_STRIP_WIDTH

	-- Opaque white field behind everything, so any texture baked into the plate
	-- mesh (e.g. the Skoda's "RUS" decal) can't bleed through the transparent
	-- number label. LVCarPlate relied on a plain-white part; this makes us
	-- robust to whatever the plate part looks like.
	local field = Instance.new("Frame")
	field.Name = "Field"
	field.Size = UDim2.fromScale(1, 1)
	field.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	field.BorderSizePixel = 0
	field.ZIndex = 0
	field.Parent = gui

	local lv = Instance.new("TextLabel")
	lv.Name = "Lv"
	lv.Size = UDim2.new(0, stripW, 1, 0)
	lv.Position = UDim2.fromScale(0, 0)
	lv.BackgroundColor3 = CarRegisterConstants.LV_STRIP_COLOR
	lv.BorderSizePixel = 0
	lv.Text = "LV"
	lv.Font = Enum.Font.GothamBold
	lv.TextColor3 = Color3.fromRGB(255, 255, 255)
	lv.TextScaled = true
	lv.Parent = gui

	local emblem = Instance.new("ImageLabel")
	emblem.Name = "Enblem"
	emblem.Size = UDim2.fromOffset(CarRegisterConstants.EMBLEM_SIZE, CarRegisterConstants.EMBLEM_SIZE)
	emblem.Position = UDim2.fromScale(0, 0)
	emblem.BackgroundTransparency = 1
	emblem.Image = CarRegisterConstants.EMBLEM_IMAGE
	emblem.ZIndex = 2
	emblem.Parent = lv

	local carNr = Instance.new("TextLabel")
	carNr.Name = CarRegisterConstants.PLATE_LABEL_NAME -- "CarNr"
	carNr.Size = UDim2.new(1, -stripW, 1, 0)
	carNr.Position = UDim2.fromOffset(stripW, 0)
	carNr.BackgroundTransparency = 1
	carNr.Text = self._plate
	carNr.Font = Enum.Font.GothamBold
	carNr.TextColor3 = CarRegisterConstants.PLATE_TEXT_COLOR
	carNr.TextScaled = true
	carNr.Parent = gui

	return gui
end

function CarRegister:GetPlate(): string
	return self._plate
end

function CarRegister:Destroy()
	self._maid:Destroy()
	self._model:SetAttribute(CarRegisterConstants.NUMBER_PLATE_ATTRIBUTE, nil)
end

return CarRegister
