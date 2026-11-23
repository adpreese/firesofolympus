#!/usr/bin/env python3
"""Analyse JSON Lines written by tools/simulate.gd and print a Markdown report.

    python3 tools/analyze_sim.py build/sim/hard-100000/part*.jsonl -o report.md

Win rates split a shared win between the tied players (a 2-way tie is half a win each), so
each game hands out exactly one win. "Lift" compares a group's win
rate with the 1/players baseline for its seat count, so 1.00 = average, 1.20 = 20% more wins.
Intervals are 95% Wilson intervals.
"""
import argparse
import json
import math
import statistics as st
import sys
from collections import Counter, defaultdict

# cap_loss is derived: Razorback Turtle records {cap: N} (the highest a Sharpness die can count);
# 6 - N is how far the cap comes down.
STRENGTH_KEYS = ("dice_loss", "die_mod", "opp_rerolls", "cap_loss")


def wilson(k, n, z=1.96):
    if n == 0:
        return (0.0, 0.0)
    p = k / n
    d = 1 + z * z / n
    c = p + z * z / (2 * n)
    r = z * math.sqrt(p * (1 - p) / n + z * z / (4 * n * n))
    return ((c - r) / d, (c + r) / d)


def share(g, s):
    """This seat's share of the game's win: 1, 1/k for a k-way tie, or 0."""
    return 1 / len(g["winners"]) if s["won"] else 0.0


def pct(x):
    return f"{100 * x:.1f}%"


def rate(k, n):
    if n == 0:
        return "–"
    lo, hi = wilson(k, n)
    return f"{pct(k / n)} ({pct(lo)}–{pct(hi)})"


def mean(xs):
    return st.fmean(xs) if xs else float("nan")


def table(head, rows, align=None):
    align = align or ["l"] + ["r"] * (len(head) - 1)
    sep = ["---:" if a == "r" else ":---" for a in align]
    out = ["| " + " | ".join(head) + " |", "| " + " | ".join(sep) + " |"]
    for r in rows:
        out.append("| " + " | ".join(str(c) for c in r) + " |")
    return "\n".join(out)


class Lift:
    """Wins vs expected wins (sum of 1/players) for a group of player-games."""

    def __init__(self):
        self.n = 0
        self.wins = 0
        self.expected = 0.0

    def add(self, won, players):
        self.n += 1
        self.wins += won
        self.expected += 1 / players

    def lift(self):
        return self.wins / self.expected if self.expected else float("nan")


def load(paths):
    games, bad = [], 0
    for p in paths:
        with open(p) as f:
            for line in f:
                line = line.strip()
                if not line:
                    continue
                try:
                    g = json.loads(line)
                    ok = all(k in g for k in ("seed", "players", "finished", "seats", "quests", "ms", "moves", "winners"))
                    ok = ok and len(g["seats"]) == g["players"] and all(
                        all(k in s for k in ("order", "quests", "drafted", "won", "total")) for s in g["seats"])
                except (json.JSONDecodeError, TypeError):
                    ok = False
                if ok:
                    games.append(g)
                else:
                    bad += 1
    seen, uniq = set(), []
    for g in games:
        key = (g["seed"], g["players"], g.get("level"), tuple(s.get("persona", "") for s in g["seats"]),
               tuple(sorted(g.get("variants", []))))
        if key not in seen:
            seen.add(key)
            uniq.append(g)
    return uniq, bad, len(games) - len(uniq)


def report(games, bad, dupes):
    out = []
    w = out.append
    fin = [g for g in games if g["finished"]]
    levels = Counter(g.get("level", "?") for g in games)
    w("# Fires of Olympus: all-CPU simulation report\n")
    w(f"- Games: **{len(games):,}** ({', '.join(f'{k} {v:,}' for k, v in levels.items())}); "
      f"unfinished: {len(games) - len(fin)}; unreadable lines: {bad}; duplicates dropped: {dupes}")
    secs = sum(g["ms"] for g in games) / 1000
    w(f"- CPU time: {secs / 3600:.1f} h total, {mean([g['ms'] for g in games]) / 1000:.2f} s per game")
    variants = Counter(", ".join(sorted(g.get("variants", []))) or "standard rules" for g in games)
    w(f"- Rules: {'; '.join(f'{k} ({v:,})' for k, v in variants.items())}"
      + ("  **(mixed rule sets: compare runs separately)**" if len(variants) > 1 else ""))
    w(f"- Seeds {min(g['seed'] for g in games)}–{max(g['seed'] for g in games)}\n")
    if not fin:
        return "\n".join(out)
    by_n = defaultdict(list)
    for g in fin:
        by_n[g["players"]].append(g)
    counts = sorted(by_n)

    # ------------------------------------------------------------------ overview
    w("## Scores by player count\n")
    rows = []
    for n in counts:
        gs = by_n[n]
        tot = [s["total"] for g in gs for s in g["seats"]]
        win = [max(s["total"] for s in g["seats"]) for g in gs]
        margin = []
        for g in gs:
            t = sorted((s["total"] for s in g["seats"]), reverse=True)
            margin.append(t[0] - t[1])
        ties = sum(len(g["winners"]) > 1 for g in gs)
        rows.append([n, f"{len(gs):,}", f"{mean(tot):.2f}", f"{st.pstdev(tot):.2f}", f"{mean(win):.2f}",
                     f"{mean(margin):.2f}", pct(ties / len(gs)), f"{mean([g['moves'] for g in gs]):.0f}",
                     f"{mean([g['ms'] for g in gs]) / 1000:.2f}"])
    w(table(["Players", "Games", "Mean total", "SD", "Winning total", "Win margin", "Tie games", "Moves", "s/game"], rows))
    w("")
    broken = [g for g in fin if g.get("tied_on_total", len(g["winners"])) > len(g["winners"])]
    if broken:
        w(f"Ties on total broken by a tie-breaker card (Olive Bough): {len(broken):,} games "
          f"({pct(len(broken) / len(fin))}); \"Tie games\" counts only ties left standing.\n")

    w("### Distribution of final totals (all players)\n")
    hist = Counter(s["total"] for g in fin for s in g["seats"])
    whist = Counter(max(s["total"] for s in g["seats"]) for g in fin)
    allp = sum(hist.values())
    rows = []
    for v in range(min(hist), max(hist) + 1):
        bar = "█" * round(60 * hist[v] / max(hist.values()))
        rows.append([v, pct(hist[v] / allp), pct(whist[v] / len(fin)), bar])
    w(table(["Total", "All players", "Winners", ""], rows, ["r", "r", "r", "l"]))
    w("")

    w("### Mean Successes per Quest\n")
    rows = []
    for n in counts:
        gs = by_n[n]
        qs = [[s["quests"][q] for g in gs for s in g["seats"]] for q in range(3)]
        rows.append([n] + [f"{mean(x):.2f} (sd {st.pstdev(x):.2f})" for x in qs])
    w(table(["Players", "Quest 1", "Quest 2", "Quest 3"], rows))
    w("")

    # ------------------------------------------------------------------ turn order
    w("## Turn order\n")
    w("Position 1 acts first in the snake draft and in the Challenges. Quest 1 order is rolled; "
      "later Quests put the fewest Successes first.\n")
    for q, label in ((0, "Quest 1 position → game win rate"), (None, "Position → that Quest's Successes")):
        w(f"### {label}\n")
        rows = []
        for n in counts:
            gs = by_n[n]
            row = [n]
            for pos in range(n):
                if q == 0:
                    k = sum(share(g, s) for g in gs for s in g["seats"] if s["order"][0] == pos)
                    row.append(rate(k, len(gs)))
                else:
                    row.append(" / ".join(f"{mean([s['quests'][qq] for g in gs for s in g['seats'] if s['order'][qq] == pos]):.2f}"
                                          for qq in range(3)))
            rows.append(row + [""] * (max(counts) - n))
        head = ["Players"] + [f"Pos {i + 1}" for i in range(max(counts))]
        w(table(head, rows))
        w("" if q == 0 else "\n(Q1 / Q2 / Q3 mean Successes.)\n")
        if q == 0:
            w("Fair share is 1/players (50.0%, 33.3%, 25.0%); ties split the win.\n")

    w("### Leader after Quest 2 wins the game\n")
    rows = []
    for n in counts:
        gs = by_n[n]
        k = tot = 0
        for g in gs:
            after2 = [s["quests"][0] + s["quests"][1] for s in g["seats"]]
            best = max(after2)
            leaders = [i for i, v in enumerate(after2) if v == best]
            if len(leaders) == 1:
                tot += 1
                k += share(g, g["seats"][leaders[0]])
        rows.append([n, f"{tot:,}", rate(k, tot)])
    w(table(["Players", "Games with a sole leader", "Leader wins"], rows))
    w("")

    # ------------------------------------------------------------------ ingredients
    w("## Ingredients\n")
    w("Seen = copies in a Quest's market. Pick = drafted from the market / seen. "
      "Lift = game win rate of players who drafted it (in any Quest) vs the 1/players baseline. "
      "Quest Δ = mean Successes in Quests where the player held it minus Quests where they didn't.\n")
    seen = Counter()
    picked = Counter()
    from_reserve = Counter()
    holders = defaultdict(Lift)
    held_q = defaultdict(list)
    all_q = []
    reactions = Counter()
    reserved = Counter()
    for g in fin:
        n = g["players"]
        for q in g["quests"]:
            for c in q.get("market", []):
                seen[c] += 1
        for s in g["seats"]:
            cards = set()
            per_q = defaultdict(set)
            for d in s["drafted"]:
                qi, name = d[0], d[1]
                fm = d[2] if len(d) > 2 else True
                (picked if fm else from_reserve)[name] += 1
                cards.add(name)
                per_q[qi].add(name)
            for c in cards:
                holders[c].add(share(g, s), n)
            for qi in range(3):
                all_q.append(s["quests"][qi])
                for c in per_q[qi]:
                    held_q[c].append(s["quests"][qi])
            for c, k in s["reactions"].items():
                reactions[c] += k
            for c in s["reserved"]:
                reserved[c] += 1
    base_q = mean(all_q)
    names = sorted(set(seen) | set(picked), key=lambda c: -holders[c].lift())
    rows = []
    for c in names:
        h = holders[c]
        rows.append([c, f"{seen[c]:,}", pct(picked[c] / seen[c]) if seen[c] else "–", f"{h.lift():.2f}",
                     f"{mean(held_q[c]) - base_q:+.2f}" if held_q[c] else "–",
                     f"{from_reserve[c]:,}", f"{reserved[c]:,}", f"{reactions[c]:,}"])
    w(table(["Ingredient", "Seen", "Pick", "Lift", "Quest Δ", "Replayed from reserve", "Reserved", "Reactions used"], rows))
    w("\nQuest Δ is confounded with how many cards a player drafted; compare cards with each other "
      "rather than with zero.\n")

    # ------------------------------------------------------------------ challenges
    w("## Challenge cards\n")
    sharp = defaultdict(list)
    stren = defaultdict(lambda: {"n": 0, "skipped": 0, **{k: [] for k in STRENGTH_KEYS}})
    for g in fin:
        for q in g["quests"]:
            if "Sharpness" in q:
                for r in q["Sharpness"]["rows"]:
                    sharp[q["Sharpness"]["card"]].append(r.get("successes", 0))
            if "Strength" in q:
                d = stren[q["Strength"]["card"]]
                for r in q["Strength"]["rows"]:
                    d["n"] += 1
                    if r["skipped"]:
                        d["skipped"] += 1
                        continue
                    pen = dict(r.get("penalty", {}))
                    pen["cap_loss"] = 6 - pen["cap"] if "cap" in pen else 0
                    for k in STRENGTH_KEYS:
                        d[k].append(pen.get(k, 0))
    w("### Sharpness (Successes per player, before wagers)\n")
    rows = []
    for c, xs in sorted(sharp.items(), key=lambda kv: -mean(kv[1])):
        z = sum(x == 0 for x in xs)
        rows.append([c, f"{len(xs):,}", f"{mean(xs):.2f}", f"{st.pstdev(xs):.2f}", pct(z / len(xs)), max(xs)])
    w(table(["Card", "Rolls", "Mean", "SD", "Zero", "Max"], rows))
    w("\n### Strength (penalty carried into Sharpness)\n")
    rows = []
    for c, d in sorted(stren.items(), key=lambda kv: -sum(mean(kv[1][k]) for k in STRENGTH_KEYS[:3])):
        rolled = d["n"] - d["skipped"]
        any_pen = sum(1 for i in range(rolled) if any(d[k][i] for k in STRENGTH_KEYS))
        rows.append([c, f"{d['n']:,}", pct(any_pen / rolled) if rolled else "–"]
                    + [f"{mean(d[k]):.2f}" for k in STRENGTH_KEYS] + [pct(d["skipped"] / d["n"])])
    w(table(["Card", "Rolls", "Any penalty", "Dice lost", "Die mod", "Opp. rerolls", "Max value cut", "Skipped (Golden Apple)"], rows))
    w("")

    # ------------------------------------------------------------------ actions
    w("## Actions\n")
    w("### Sharpening\n")
    rows = []
    for n in counts:
        gs = by_n[n]
        seats = [s for g in gs for s in g["seats"]]
        rows.append([n] + [f"{mean([s['sharpen'][q] for s in seats]):.2f}" for q in range(3)]
                    + [f"{mean([len(s['drafted']) for s in seats]):.2f}", f"{mean([s['pass'] for s in seats]):.2f}",
                       f"{mean([s['swap'] for s in seats]):.2f}"])
    w(table(["Players", "Sharpens Q1", "Q2", "Q3", "Drafts/game", "Passes/game", "Bauble swaps/game"], rows))
    w("\n### Total sharpens in a game → win lift\n")
    groups = defaultdict(Lift)
    for g in fin:
        for s in g["seats"]:
            groups[sum(s["sharpen"])].add(share(g, s), g["players"])
    rows = [[k, f"{v.n:,}", f"{v.lift():.2f}"] for k, v in sorted(groups.items())]
    w(table(["Sharpens", "Player-games", "Lift"], rows))
    w("\n### Drafts in a game → win lift\n")
    groups = defaultdict(Lift)
    for g in fin:
        for s in g["seats"]:
            groups[len(s["drafted"])].add(share(g, s), g["players"])
    rows = [[k, f"{v.n:,}", f"{v.lift():.2f}"] for k, v in sorted(groups.items())]
    w(table(["Drafts", "Player-games", "Lift"], rows))

    w("\n### Gambler's Charm wagers\n")
    yes = no = 0
    results = Counter()
    for g in fin:
        for s in g["seats"]:
            yes += s["wager_yes"]
            no += s["wager_no"]
        for q in g["quests"]:
            for v in q.get("wagers", []):
                if v:
                    results[v] += 1
    offered = yes + no
    w(f"- Offered {offered:,} times, taken {rate(yes, offered) if offered else '–'}")
    taken = results[1] + results[-1]
    w(f"- Taken wagers won: {rate(results[1], taken) if taken else '–'} "
      f"(net {results[1] - results[-1]:+,} Successes over {taken:,} wagers)\n")

    # ------------------------------------------------------------------ personas
    personas = {s.get("persona", "") for g in fin for s in g["seats"]}
    if personas - {""}:
        w("## Personas\n")
        groups = defaultdict(Lift)
        totals = defaultdict(list)
        for g in fin:
            for s in g["seats"]:
                p = s.get("persona") or "(none)"
                groups[p].add(share(g, s), g["players"])
                totals[p].append(s["total"])
        rows = [[p, f"{v.n:,}", f"{v.lift():.2f}", f"{mean(totals[p]):.2f}"] for p, v in sorted(groups.items(), key=lambda kv: -kv[1].lift())]
        w(table(["Persona", "Player-games", "Lift", "Mean total"], rows))
        w("")
    return "\n".join(out)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("files", nargs="+")
    ap.add_argument("-o", "--out", help="write the report here as well as to stdout")
    a = ap.parse_args()
    games, bad, dupes = load(a.files)
    if not games:
        sys.exit("no games found")
    text = report(games, bad, dupes)
    print(text)
    if a.out:
        with open(a.out, "w") as f:
            f.write(text + "\n")


if __name__ == "__main__":
    main()
