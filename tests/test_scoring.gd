extends "res://tests/test_case.gd"


func test_sharpness_rules() -> void:
	eq(Scoring.sharpness_successes("Vampire Bat", [2, 2, 6]), 1, "rules example: 2,2,6 vs Vampire Bat")
	eq(Scoring.sharpness_successes("Vampire Bat", [3, 3, 3, 3, 3]), 2, "bat four of a kind = 2 pairs")
	eq(Scoring.sharpness_successes("Ice Dragon", [6, 6, 6, 6, 5]), 2, "ice dragon 29")
	eq(Scoring.sharpness_successes("Ice Dragon", [-3, 1]), 0, "ice dragon negative")
	eq(Scoring.sharpness_successes("Razor Mantis", [6, 7, 5]), 2, "mantis")
	eq(Scoring.sharpness_successes("Animated Flytrap", [4, 3, 9, 0]), 2, "flytrap")
	eq(Scoring.sharpness_successes("Ancient Geometer", [2, 3, 4, 5, 7, 1, 9]), 4, "geometer primes")
	eq(Scoring.sharpness_successes("Ghost Knight", [1, 1, 2, 6]), 3, "ghost knight distinct")
	eq(Scoring.sharpness_successes("Killer Bee", [1, 6, 6, 3, 4, 4]), 2, "killer bee disjoint pairs")
	eq(Scoring.sharpness_successes("Killer Bee", [8, -1]), 1, "killer bee off-range values")


func test_strength_rules() -> void:
	eq(Scoring.strength_penalty("Kraken", [3, 5, 5, 6]).dice_loss, 1, "rules example: 19 vs Kraken")
	eq(Scoring.strength_penalty("Kraken", [3, 5, 6, 7]).dice_loss, 0, "21 vs Kraken")
	eq(Scoring.strength_penalty("Mimic", [1, 3, 4, -1]).dice_loss, 3, "mimic odd count")
	eq(Scoring.strength_penalty("Giant Crab", [2, 2, 2, 5]).dice_loss, 0, "crab three of a kind")
	eq(Scoring.strength_penalty("Giant Crab", [1, 2, 3]).dice_loss, 2, "crab miss")
	eq(Scoring.strength_penalty("Golem", [1, 1, 4]).die_mod, -2, "golem")
	eq(Scoring.strength_penalty("Phantasm", [1, 1, 4]).dice_loss, 2, "phantasm")
	eq(Scoring.strength_penalty("Cockatrice", [1, 5]).opp_rerolls, 1, "cockatrice")
	eq(Scoring.strength_penalty("Razorback Turtle", [1, 1, 3]).cap, 4, "turtle cap")
	ok(not Scoring.strength_penalty("Razorback Turtle", [2, 3]).has("cap"), "turtle no ones")


func test_die_marks() -> void:
	eq(Scoring.die_marks("Vampire Bat", [3, 3, 3, 5, 5]), [1, 1, 0, 1, 1] as Array[int], "pairs")
	eq(Scoring.die_marks("Ghost Knight", [2, 2, 4]), [1, 0, 1] as Array[int], "distinct")
	eq(Scoring.die_marks("Killer Bee", [1, 6, 6, 3]), [1, 1, 0, 0] as Array[int], "sevens")
	eq(Scoring.die_marks("Razor Mantis", [6, 7, 5]), [1, 1, 0] as Array[int], "6 or more")
	eq(Scoring.die_marks("Mimic", [1, 2, 3]), [-1, 0, -1] as Array[int], "odd triggers")
	eq(Scoring.die_marks("Giant Crab", [4, 4, 4, 4, 2]), [1, 1, 1, 0, 0] as Array[int], "set of 3 protects")
	eq(Scoring.die_marks("Ice Dragon", [6, 6]), [0, 0] as Array[int], "sum-based")
	# Marked dice must agree with the count for count-based cards.
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	for card in ["Razor Mantis", "Animated Flytrap", "Ancient Geometer", "Vampire Bat", "Ghost Knight", "Killer Bee"]:
		for t in 200:
			var vals := []
			for i in rng.randi_range(0, 10):
				vals.append(rng.randi_range(-1, 9))
			var marked := Scoring.die_marks(card, vals).count(1)
			var n := Scoring.sharpness_successes(card, vals)
			if card in ["Vampire Bat", "Killer Bee"]:
				n *= 2
			eq(marked, n, "%s %s" % [card, str(vals)])
