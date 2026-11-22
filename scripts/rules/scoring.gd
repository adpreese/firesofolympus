class_name Scoring
extends RefCounted
## Challenge card rules: Successes for Sharpness Challenges, penalties for Strength ones.
## All functions take *final* die results (after Effects, Modifiers and Reactions).

const SHARPNESS_RULES := [
	"Ice Dragon", "Razor Mantis", "Animated Flytrap", "Ancient Geometer",
	"Vampire Bat", "Ghost Knight", "Killer Bee",
]
const STRENGTH_RULES := [
	"Golem", "Phantasm", "Cockatrice", "Razorback Turtle", "Kraken", "Mimic", "Giant Crab",
]


static func knows(card_name: String) -> bool:
	return card_name in SHARPNESS_RULES or card_name in STRENGTH_RULES


static func sharpness_successes(card_name: String, vals: Array) -> int:
	match card_name:
		"Ice Dragon":  # every 10 points is a Success
			return maxi(0, floori(_sum(vals) / 10.0))
		"Razor Mantis":  # each 6 (or higher)
			return _count(vals, func(v): return v >= 6)
		"Animated Flytrap":  # each 4 or above
			return _count(vals, func(v): return v >= 4)
		"Ancient Geometer":  # each prime
			return _count(vals, func(v): return is_prime(v))
		"Vampire Bat":  # each matching pair
			var n := 0
			for c in _counts(vals).values():
				n += c / 2
			return n
		"Ghost Knight":  # each distinct value
			return _counts(vals).size()
		"Killer Bee":  # each (disjoint) pair adding to 7
			var counts := _counts(vals)
			var n := 0
			for v in counts:
				if v < 7 - v and counts.has(7 - v):
					n += mini(counts[v], counts[7 - v])
			return n
	push_error("Unknown Sharpness Challenge: " + card_name)
	return 0


## Returns {dice_loss, die_mod, opp_rerolls} and, for Razorback Turtle, cap.
static func strength_penalty(card_name: String, vals: Array) -> Dictionary:
	var out := {"dice_loss": 0, "die_mod": 0, "opp_rerolls": 0}
	var ones := _count(vals, func(v): return v == 1)
	match card_name:
		"Golem":
			out.die_mod = -ones
		"Phantasm":
			out.dice_loss = ones
		"Cockatrice":
			out.opp_rerolls = ones
		"Razorback Turtle":
			if ones > 0:
				out.cap = 6 - ones
		"Kraken":
			if _sum(vals) <= 20:
				out.dice_loss = 1
		"Mimic":
			out.dice_loss = _count(vals, func(v): return posmod(v, 2) == 1)
		"Giant Crab":
			var best := 0
			for c in _counts(vals).values():
				best = maxi(best, c)
			if best < 3:
				out.dice_loss = 2
		_:
			push_error("Unknown Strength Challenge: " + card_name)
	return out


## Rough cost of a penalty in Sharpness-dice terms (used by the bot).
static func penalty_cost(p: Dictionary) -> float:
	var cost: float = float(p.get("dice_loss", 0)) + absf(p.get("die_mod", 0)) + 0.4 * p.get("opp_rerolls", 0)
	if p.has("cap"):
		cost += 0.7 * (6 - p.cap)
	return cost


static func describe_penalty(p: Dictionary) -> String:
	var parts := PackedStringArray()
	if p.get("dice_loss", 0) > 0:
		parts.append("-%dd6 on Sharpness" % p.dice_loss)
	if p.get("die_mod", 0) != 0:
		parts.append("%d to every Sharpness die" % p.die_mod)
	if p.get("opp_rerolls", 0) > 0:
		parts.append("opponent rerolls %d Sharpness dice" % p.opp_rerolls)
	if p.has("cap"):
		parts.append("Sharpness dice capped at %d" % p.cap)
	return "no penalty" if parts.is_empty() else ", ".join(parts)


static func is_prime(n: int) -> bool:
	if n < 2:
		return false
	for d in range(2, int(sqrt(n)) + 1):
		if n % d == 0:
			return false
	return true


static func _sum(vals: Array) -> int:
	var s := 0
	for v in vals:
		s += v
	return s


static func _count(vals: Array, pred: Callable) -> int:
	var n := 0
	for v in vals:
		if pred.call(v):
			n += 1
	return n


static func _counts(vals: Array) -> Dictionary:
	var c := {}
	for v in vals:
		c[v] = c.get(v, 0) + 1
	return c
