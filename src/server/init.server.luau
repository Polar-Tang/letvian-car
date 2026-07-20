--||Services||--
local RS = game:GetService("ReplicatedStorage")
----------------------------- getting servicebag and loader -----------------------------

local NeverMorePackages = RS.Nevermore
local loader = NeverMorePackages:FindFirstChild("LoaderUtils", true).Parent
local Nevermore = require(loader).bootstrapGame(NeverMorePackages)

-- Auto-respawn is ON (engine default): the engine reloads the character on
-- death; CheckpointService then pivots the fresh rig to the player's last
-- checkpoint (no checkpoint yet -> engine default spawn). The LoadCharacter in
-- PlayerAdded below only covers a first join that arrived without a character.

local ServiceBag = Nevermore("ServiceBag")
local serviceBag = ServiceBag.new()

----------------------------- binders -----------------------------
local Binder = Nevermore("Binder")
local BinderProvider = Nevermore("BinderProvider")

local CarTestingConstants = Nevermore("CarTestingConstants")

-- tag -> constructor class. The binder calls constructor.new(taggedInstance, ...)
-- for every Instance carrying the tag.
local Binders = {
	-- Moving dummy the radar tracks; "binder" (lowercase) is the TestingCar
	-- class in myNeverMoreS/carTesting, distinct from Quenty's "Binder".
	[CarTestingConstants.TESTING_CAR_TAG] = Nevermore("binder"),
}

---------- USE BINDER PROVIDER ----------
local InitBinders
InitBinders = BinderProvider.new("InitBinders", function(self, serviceBag)
	for tag, constructor in pairs(Binders) do
		self:Add(Binder.new(tag, constructor, serviceBag, self))
	end
end)

-- _G.BinderProvider is the registration KEY (binders NOT started yet). The live
-- provider only comes back from serviceBag:GetService(...) below.
_G.BinderProvider = InitBinders

-- Register the provider with the bag BEFORE Init() so the bag drives its
-- Init/Start. GetService AFTER Start() errors ("Already started, cannot add").
-- Same object is returned here and after Start() -- it's just live by then.
local binderProvider = serviceBag:GetService(_G.BinderProvider)

----------------------------- init process -----------------------------
_G.FistBag = serviceBag


serviceBag:Init()

serviceBag:Start()

_G.FistBag = nil
_G.ServiceBag = serviceBag

