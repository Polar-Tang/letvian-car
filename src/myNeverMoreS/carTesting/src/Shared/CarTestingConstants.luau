--!strict
-- Testing-dummy car tuning. The tag key lives here so the ServiceRoot binder
-- registration and the TestingCar class agree on it (tags are constants, not
-- literals).

return {
	-- CollectionService tag that binds a model (anchored parts) to TestingCar.
	TESTING_CAR_TAG = "TestingCar",

	-- Model attribute read every update: drive speed in studs/second.
	SPEED_ATTRIBUTE = "Speed",
	DEFAULT_SPEED = 40,

	-- Seconds the car drives one way before reversing to the opposite of the
	-- primary part's look direction.
	REVERSE_AFTER = 3,
}
