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
	"Fiery Salamander",
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


## Returns {dice_loss, die_mod, opp_rerolls}, plus cap (Razorback Turtle) or free_six
## (Fiery Salamander's boon: an extra Sharpness die showing 6).
## `extra`: penalties taken automatically (Kraken Blood). Each one counts as one more
## triggering die; pass/fail cards (Kraken, Giant Crab) give their penalty regardless.
static func strength_penalty(card_name: String, vals: Array, extra := 0) -> Dictionary:
	var out := {"dice_loss": 0, "die_mod": 0, "opp_rerolls": 0}
	var ones := _count(vals, func(v): return v == 1) + extra
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
			if _sum(vals) <= 20 or extra > 0:
				out.dice_loss = 1
		"Mimic":
			out.dice_loss = _count(vals, func(v): return posmod(v, 2) == 1) + extra
		"Giant Crab":
			var best := 0
			for c in _counts(vals).values():
				best = maxi(best, c)
			if best < 3 or extra > 0:
				out.dice_loss = 2
		"Fiery Salamander":  # a boon, not a penalty, so Kraken Blood has nothing to take
			if straight_start(vals) != null:
				out.free_six = 1
		_:
			push_error("Unknown Strength Challenge: " + card_name)
	return out


## Which dice matter for this Challenge, for highlighting: one int per die.
## Sharpness: 1 = the die scores. Strength: -1 = the die triggers the penalty,
## 1 = the die protects you (Giant Crab's set of 3). Sum-based cards (Ice Dragon, Kraken) mark nothing.
static func die_marks(card_name: String, vals: Array) -> Array[int]:
	var marks: Array[int] = []
	marks.resize(vals.size())
	match card_name:
		"Razor Mantis":
			_mark(marks, vals, func(v): return v >= 6, 1)
		"Animated Flytrap":
			_mark(marks, vals, func(v): return v >= 4, 1)
		"Ancient Geometer":
			_mark(marks, vals, func(v): return is_prime(v), 1)
		"Vampire Bat":  # both dice of each pair
			var counts := _counts(vals)
			var left := {}
			for v in counts:
				left[v] = counts[v] - counts[v] % 2
			_mark_up_to(marks, vals, left, 1)
		"Ghost Knight":  # the first die of each distinct value
			var left := {}
			for v in vals:
				left[v] = 1
			_mark_up_to(marks, vals, left, 1)
		"Killer Bee":
			var counts := _counts(vals)
			var left := {}
			for v in counts:
				if counts.has(7 - v) and v != 7 - v:
					left[v] = mini(counts[v], counts[7 - v])
			_mark_up_to(marks, vals, left, 1)
		"Golem", "Phantasm", "Cockatrice", "Razorback Turtle":
			_mark(marks, vals, func(v): return v == 1, -1)
		"Mimic":
			_mark(marks, vals, func(v): return posmod(v, 2) == 1, -1)
		"Giant Crab":
			var counts := _counts(vals)
			for v in counts:
				if counts[v] >= 3:
					_mark_up_to(marks, vals, {v: 3}, 1)
					break
		"Fiery Salamander":
			var s = straight_start(vals)
			if s != null:
				_mark_up_to(marks, vals, {s: 1, s + 1: 1, s + 2: 1}, 1)
	return marks


## Lowest v with v, v+1 and v+2 all among the results (Fiery Salamander), or null.
static func straight_start(vals: Array):
	var counts := _counts(vals)
	var keys := counts.keys()
	keys.sort()
	for v in keys:
		if counts.has(v + 1) and counts.has(v + 2):
			return v
	return null


## Extra context for sum-based Challenges, e.g. "Total 23". Empty for the rest.
static func total_note(card_name: String, vals: Array) -> String:
	match card_name:
		"Ice Dragon":
			return "Total %d (1 Success per 10)" % _sum(vals)
		"Kraken":
			return "Total %d (needs more than 20)" % _sum(vals)
	return ""


static func _mark(marks: Array[int], vals: Array, pred: Callable, m: int) -> void:
	for i in vals.size():
		if pred.call(vals[i]):
			marks[i] = m


## Marks the first left[v] dice showing each value v.
static func _mark_up_to(marks: Array[int], vals: Array, left: Dictionary, m: int) -> void:
	var left_now := left.duplicate()
	for i in vals.size():
		var v = vals[i]
		if left_now.get(v, 0) > 0:
			marks[i] = m
			left_now[v] -= 1


## Rough cost of a penalty in Sharpness-dice terms (used by the bot).
static func penalty_cost(p: Dictionary) -> float:
	var cost: float = float(p.get("dice_loss", 0)) + absf(p.get("die_mod", 0)) + 0.4 * p.get("opp_rerolls", 0)
	if p.has("cap"):
		cost += 0.7 * (6 - p.cap)
	cost -= 1.5 * p.get("free_six", 0)  # a boon: negative cost
	return cost


static func describe_penalty(p: Dictionary) -> String:
	var parts := PackedStringArray()
	if p.get("dice_loss", 0) > 0:
		parts.append("-%dd6 on Sharpness" % p.dice_loss)
	if p.get("die_mod", 0) != 0:
		parts.append("%d to every Sharpness die" % p.die_mod)
	if p.get("opp_rerolls", 0) > 0:
		parts.append("opponent rerolls %d Sharpness %s" % [p.opp_rerolls, "die" if p.opp_rerolls == 1 else "dice"])
	if p.has("cap"):
		parts.append("Sharpness dice capped at %d" % p.cap)
	if p.get("free_six", 0) > 0:
		parts.append("a free 6 on Sharpness")
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
