#!/usr/bin/env python3
"""Compare two simulation runs game-by-game on the seeds they share.

    python3 tools/compare_sim.py build/sim/hard-10000 build/sim/hard-no_leader_reserve-2000 -o compare.md

Each argument is a run directory (its part*.jsonl files are read). Games are paired by
(seed, players), so with a variant that only changes later play, both runs are identical up to
that point and differences come from the rule rather than the dice. Ties split the win.
"""
import argparse
import glob
import json
import math
import os
import statistics as st
from collections import defaultdict


def load(d):
    out = {}
    for f in sorted(glob.glob(os.path.join(d, "part*.jsonl"))):
        for line in open(f):
            try:
                g = json.loads(line)
            except json.JSONDecodeError:
                continue
            if g.get("finished") and "seats" in g:
                out[(g["seed"], g["players"])] = g
    return out


def share(g, i):
    return 1 / len(g["winners"]) if i in g["winners"] else 0.0


def after_q2(g):
    return [s["quests"][0] + s["quests"][1] for s in g["seats"]]


def sole_leader(g, quests=2):
    a = [sum(s["quests"][:quests]) for s in g["seats"]]
    b = max(a)
    return a.index(b) if a.count(b) == 1 else None


def ci(xs):
    """Mean and 95% half-width."""
    if len(xs) < 2:
        return (st.fmean(xs) if xs else float("nan"), float("nan"))
    return (st.fmean(xs), 1.96 * st.stdev(xs) / math.sqrt(len(xs)))


def fmt_pct(m, h):
    return f"{100 * m:.1f}% ±{100 * h:.1f}"


def fmt(m, h, digits=2):
    return f"{m:.{digits}f} ±{h:.{digits}f}"


def table(head, rows):
    out = ["| " + " | ".join(head) + " |", "| :--- |" + " ---: |" * (len(head) - 1)]
    out += ["| " + " | ".join(str(c) for c in r) + " |" for r in rows]
    return "\n".join(out)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("base")
    ap.add_argument("variant")
    ap.add_argument("-o", "--out")
    a = ap.parse_args()
    A, B = load(a.base), load(a.variant)
    keys = sorted(set(A) & set(B))
    na = lambda d: ", ".join(sorted(next(iter(d.values())).get("variants", []))) or "standard rules"
    out = [f"# {na(B)} vs {na(A)}\n",
           f"- Paired games: **{len(keys):,}** (seeds shared by `{a.base}` and `{a.variant}`)",
           "- ± is a 95% interval. Δ columns are paired (variant minus base on the same seed).\n"]
    by_n = defaultdict(list)
    for k in keys:
        by_n[k[1]].append(k)
    rows = []
    for n in sorted(by_n) + ["all"]:
        ks = keys if n == "all" else by_n[n]
        lw_a, lw_b, l1_a, l1_b, d_lead, d_tie, d_margin, same_q2 = [], [], [], [], [], [], [], 0
        for k in ks:
            ga, gb = A[k], B[k]
            same_q2 += after_q2(ga) == after_q2(gb)
            # Each run's own leader (a variant that starts earlier can change who leads).
            for g, lw, l1 in ((ga, lw_a, l1_a), (gb, lw_b, l1_b)):
                if sole_leader(g) is not None:
                    lw.append(share(g, sole_leader(g)))
                if sole_leader(g, 1) is not None:
                    l1.append(share(g, sole_leader(g, 1)))
            L = sole_leader(ga)
            ties_a = len(ga["winners"]) > 1
            ties_b = len(gb["winners"]) > 1
            d_tie.append(ties_b - ties_a)
            ma = sorted((s["total"] for s in ga["seats"]), reverse=True)
            mb = sorted((s["total"] for s in gb["seats"]), reverse=True)
            d_margin.append((mb[0] - mb[1]) - (ma[0] - ma[1]))
            if L is None or sole_leader(gb) != L:
                continue
            # Leader's Q3 Successes minus the mean of the others'
            q3 = lambda g: g["seats"][L]["quests"][2] - st.fmean(s["quests"][2] for i, s in enumerate(g["seats"]) if i != L)
            d_lead.append(q3(gb) - q3(ga))
        rows.append([n, f"{len(ks):,}", f"{same_q2 / len(ks):.0%}", fmt_pct(*ci(l1_a)), fmt_pct(*ci(l1_b)),
                     fmt_pct(*ci(lw_a)), fmt_pct(*ci(lw_b)),
                     f"{100 * (st.fmean(lw_b) - st.fmean(lw_a)):+.1f} pts",
                     fmt(*ci(d_lead)), fmt_pct(*ci(d_tie)), fmt(*ci(d_margin))])
    out.append("## Does the leader win?\n")
    out.append(table(["Players", "Games", "Same Q1+Q2", "Q1 leader wins (base)", "Q1 leader wins (variant)",
                      "Q2 leader wins (base)", "Q2 leader wins (variant)", "Δ Q2 leader wins",
                      "Δ leader's Q3 edge", "Δ tie rate", "Δ win margin"], rows))
    out.append("\nLeader win rates use each run's own sole leader. \"Leader's Q3 edge\" = the Q2 leader's "
               "Quest 3 Successes minus the other players' average, paired on games where both runs have the "
               "same sole leader. \"Same Q1+Q2\" is ~100% for a variant that starts after Quest 2 and lower "
               "for one that changes Quest 2.\n")

    rows = []
    for n in sorted(by_n):
        ks = by_n[n]
        sa = [s["total"] for k in ks for s in A[k]["seats"]]
        sb = [s["total"] for k in ks for s in B[k]["seats"]]
        q3a = [s["quests"][2] for k in ks for s in A[k]["seats"]]
        q3b = [s["quests"][2] for k in ks for s in B[k]["seats"]]
        rows.append([n, f"{st.fmean(sa):.2f} → {st.fmean(sb):.2f}", f"{st.fmean(q3a):.2f} → {st.fmean(q3b):.2f}"])
    out.append("## Scores\n")
    out.append(table(["Players", "Mean total", "Mean Q3"], rows))
    text = "\n".join(out)
    print(text)
    if a.out:
        with open(a.out, "w") as f:
            f.write(text + "\n")


if __name__ == "__main__":
    main()
