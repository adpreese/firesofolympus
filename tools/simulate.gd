extends SceneTree
## Plays all-CPU games headless and writes one JSON object per game (JSON Lines).
## Usually run through tools/simulate.sh, which splits the seeds across CPU cores and then
## runs tools/analyze_sim.py on the result.
##
##   godot --headless --script res://tools/simulate.gd -- \
##       --games 1000 --first-seed 0 --players 2,3,4 --level hard --out build/sim/part0.jsonl
##
## Options:
##   --games N         games to play (default 100)
##   --first-seed S    game i uses seed S + i (default 0), so runs are reproducible and resumable
##   --players LIST    comma-separated seat counts, cycled by seed (default 2,3,4)
##   --level NAME      easy | normal | hard (default hard), used for every seat
##   --personas MODE   none (default) or mixed: each seat gets a persona picked from the seed
##   --variant LIST    comma-separated rule variants (FoGame.VARIANTS), e.g. no_leader_reserve
##   --out PATH        output file (default build/sim/sim.jsonl); appended to, and seeds already
##                     in it are skipped, so an interrupted run picks up where it stopped
##
## The bot never draws from g.rng, so each record can be re-created exactly from its seed,
## seat count, level, personas and variants.

var data := CardData.load_default()


func _init() -> void:
	var opts := _parse(OS.get_cmdline_user_args())
	var games := int(opts.get("games", "100"))
	var first_seed := int(opts.get("first-seed", "0"))
	var counts: Array = Array(str(opts.get("players", "2,3,4")).split(",")).map(func(s): return int(s))
	var level_name := str(opts.get("level", "hard")).to_lower()
	var level := FoBot.LEVELS.map(func(s): return s.to_lower()).find(level_name)
	if level < 0:
		push_error("unknown --level %s" % level_name)
		quit(2)
		return
	var mixed := str(opts.get("personas", "none")) == "mixed"
	var variants := {}
	for v in str(opts.get("variant", "")).split(",", false):
		if not v in FoGame.VARIANTS:
			push_error("unknown --variant %s (known: %s)" % [v, ", ".join(FoGame.VARIANTS)])
			quit(2)
			return
		variants[v] = true
	var out_path := str(opts.get("out", "build/sim/sim.jsonl"))
	DirAccess.make_dir_recursive_absolute(out_path.get_base_dir())
	var done := _existing(out_path)
	var f := FileAccess.open(out_path, FileAccess.READ_WRITE if FileAccess.file_exists(out_path) else FileAccess.WRITE)
	if f == null:
		push_error("cannot open %s" % out_path)
		quit(2)
		return
	f.seek_end()
	if not done.is_empty():
		printerr("[%s] resuming: %d games already recorded" % [out_path.get_file(), done.size()])
	var started := Time.get_ticks_msec()
	for i in games:
		var s := first_seed + i
		if done.has(s):
			continue
		var n: int = counts[posmod(s, counts.size())]
		var personas := []
		for seat in n:
			personas.append(FoBot.PERSONAS[posmod(hash([s, seat, "persona"]), FoBot.PERSONAS.size())].key if mixed else "")
		var rec := play(s, n, level, personas, variants)
		rec.level = FoBot.LEVELS[level]
		rec.variants = variants.keys()
		f.store_line(JSON.stringify(rec))
		if (i + 1) % 50 == 0:
			f.flush()
			printerr("[%s] %d/%d games, %.1fs" % [out_path.get_file(), i + 1, games, (Time.get_ticks_msec() - started) / 1000.0])
	f.close()
	quit(0)


## Plays one game and summarises it.
func play(s: int, n: int, level: int, personas: Array, variants := {}) -> Dictionary:
	var names := []
	var bots := []
	for i in n:
		names.append("P%d" % i)
		bots.append(true)
	var g := FoGame.new(data)
	g.variants = variants
	var t0 := Time.get_ticks_usec()
	g.setup(names, bots, s)
	var stats := []
	for i in n:
		stats.append({"drafted": [], "sharpen": [0, 0, 0], "pass": 0, "swap": 0, "wager_yes": 0,
			"wager_no": 0, "reactions": {}, "reserved": [], "order": []})
	var orders := []
	var markets := []
	var seen_quest := -1
	var guard := 0
	while g.phase != FoGame.Phase.GAME_OVER and guard < 20000:
		if g.quest != seen_quest:
			seen_quest = g.quest
			orders.append(g.order.duplicate())
			markets.append(g.market.map(func(c): return c.name))
		var pi := g.current
		var market_ids := g.market.map(func(c): return c.id)
		var q := g.quest
		var before := g.moves.size()
		FoBot.step(g, level, personas[pi])
		guard += 1
		if g.moves.size() == before:
			continue
		var m: Array = g.moves[-1]
		var st: Dictionary = stats[pi]
		match str(m[0]):
			"draft":
				# [quest, card, from market (false = played back from the reserve)]
				st.drafted.append([q, g.card_name(int(m[1])), int(m[1]) in market_ids])
			"sharpen":
				st.sharpen[q] += 1
			"pass":
				st.pass += 1
			"swap":
				st.swap += 1
			"wager":
				st["wager_yes" if m[1] else "wager_no"] += 1
			"react":
				var card_id := int(str(m[1]).split(":")[0])
				var cname: String = g.card_name(card_id)
				st.reactions[cname] = st.reactions.get(cname, 0) + 1
			"reserve":
				st.reserved.append(g.card_name(int(m[1])))
	var winners := g.winners()
	var players := []
	for i in n:
		var p: FoGame.Player = g.players[i]
		var st: Dictionary = stats[i]
		st.seat = i
		st.persona = personas[i]
		st.total = p.total
		st.quests = p.quest_scores
		st.won = i in winners
		st.order = orders.map(func(o): return o.find(i))  # 0 = first to act in that Quest
		players.append(st)
	var quests := []
	for h in g.history:
		if h.type == "challenge":
			while quests.size() <= h.quest:
				quests.append({})
			var rows := []
			for r in h.rows:
				var row := {"player": r.player, "skipped": r.skipped}
				if r.has("successes"):
					row.successes = r.successes
				if r.has("penalty") and not r.penalty.is_empty():
					row.penalty = r.penalty
				rows.append(row)
			quests[h.quest][h.kind] = {"card": h.card.name, "rows": rows}
		elif h.type == "quest":
			quests[h.quest].wagers = h.rows.map(func(r): return r.wager)
	for q in quests.size():
		quests[q].market = markets[q] if q < markets.size() else []
	return {
		"seed": s, "players": n, "finished": g.phase == FoGame.Phase.GAME_OVER,
		"moves": g.moves.size(), "ms": (Time.get_ticks_usec() - t0) / 1000.0,
		"winners": winners, "seats": players, "quests": quests,
		"tied_on_total": _tied_on_total(g),
	}


## How many players share the top total (a tie-breaker may still have picked one winner).
func _tied_on_total(g: FoGame) -> int:
	var best := -1000000
	for p in g.players:
		best = maxi(best, p.total)
	return g.players.filter(func(p): return p.total == best).size()


## Seeds already recorded in `path`. Drops a half-written last line (from a killed run) so
## appending stays valid JSON Lines.
func _existing(path: String) -> Dictionary:
	var seeds := {}
	if not FileAccess.file_exists(path):
		return seeds
	var good := PackedStringArray()
	var dirty := false
	for line in FileAccess.get_file_as_string(path).split("\n", false):
		var j := JSON.new()  # instance parse: no error spam for a truncated line
		var rec = j.data if j.parse(line) == OK else null
		if rec is Dictionary and rec.has("seed") and rec.has("seats"):
			seeds[int(rec.seed)] = true
			good.append(line)
		else:
			dirty = true
	if dirty:
		var f := FileAccess.open(path, FileAccess.WRITE)
		for line in good:
			f.store_line(line)
		f.close()
	return seeds


func _parse(args: PackedStringArray) -> Dictionary:
	var out := {}
	var i := 0
	while i < args.size():
		var a := args[i]
		if a.begins_with("--"):
			var k := a.substr(2)
			if "=" in k:
				out[k.get_slice("=", 0)] = k.get_slice("=", 1)
			elif i + 1 < args.size() and not args[i + 1].begins_with("--"):
				out[k] = args[i + 1]
				i += 1
			else:
				out[k] = "true"
		i += 1
	return out
