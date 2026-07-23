--!strict
-- Config for the CarRegister binder: sits on top of an A-Chassis car Model and
-- gives it a generated Latvian-style number plate (the "patente"), rendered on
-- the front and rear plate parts. The tag key lives here so the ServiceRoot
-- binder registration and the CarRegister class agree on it (tags are
-- constants, not literals — same rule as CarTestingConstants).

return {
	-- CollectionService tag that binds a car Model to the CarRegister class.
	CAR_REGISTER_TAG = "CarRegister",

	-- Names of the ObjectValue children on the tagged Model. Each ObjectValue's
	-- .Value points DIRECTLY at the BasePart that should carry the plate GUI.
	-- (Verified on Workspace."Skoda Octavia A7": both ObjectValues exist and
	-- point at the thin MeshPart frames "…NomerF/NomerB…bump_front_ok.002".)
	REAR_PLATE_VALUE = "NumberPlateRear",
	FRONT_PLATE_VALUE = "NumberPlateFront",

	-- Attribute written on the Model once the plate is generated, so radar / UI
	-- / any later system can read the car's plate without re-deriving it. Read
	-- via the GetCartNumberPlate utility (Shared) rather than hard-coding the key.
	NUMBER_PLATE_ATTRIBUTE = "NumberPlate",

	-- Plate string format, mirroring Workspace.LVCarPlate's LicensePlateGenerator
	-- pattern "BB - CCCC": two letters, " - ", four digits (e.g. "AB - 1234").
	PLATE_LETTERS = 2,
	PLATE_DIGITS = 4,
	PLATE_SEPARATOR = " - ",

	-- SurfaceGui face selection. The plate parts are thin MeshParts whose visible
	-- surface is NOT necessarily the +Z (Front) face — on the Skoda the Front
	-- normal points INTO the bodywork, so a Front-faced SurfaceGui renders inside
	-- the bumper and is invisible (this is exactly why a naive clone "doesn't
	-- work"). When AUTO_DETECT_FACE is true, CarRegister picks the face whose
	-- world normal points away from the car's center. DEFAULT_FACE is the
	-- fallback if detection is degenerate; a plate part may also override with a
	-- "PlateFace" string attribute (e.g. "Back").
	AUTO_DETECT_FACE = true,
	DEFAULT_FACE = "Back",

	-- Optional: clone an existing template SurfaceGui instead of building one.
	-- Searched by name in ReplicatedStorage then ServerStorage. Leave the asset
	-- absent and CarRegister reproduces the LVCarPlate look from scratch (below).
	TEMPLATE_SURFACE_GUI = "LVCarPlateGui",

	-- The TextLabel that holds the plate number — matches LVCarPlate's "CarNr"
	-- so a cloned template and the built-from-scratch gui are handled the same.
	PLATE_LABEL_NAME = "CarNr",

	-- Values copied from Workspace.LVCarPlate.Plates.*.SGUI so the from-scratch
	-- build matches the reference plate.
	CANVAS_SIZE = Vector2.new(250, 50), -- SGUI CanvasSize, FixedSize sizing
	PLATE_TEXT_COLOR = Color3.fromRGB(0, 0, 0), -- CarNr
	LV_STRIP_COLOR = Color3.fromRGB(0, 0, 127), -- blue EU strip (Lv background)
	LV_STRIP_WIDTH = 30, -- px, Lv label X offset width
	EMBLEM_IMAGE = "rbxassetid://10560294754", -- Enblem ImageLabel
	EMBLEM_SIZE = 30, -- px square
}
