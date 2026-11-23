#!/usr/bin/env bash
# Plays lots of all-CPU games in parallel, then writes an analysis report.
#   tools/simulate.sh [GAMES] [extra simulate.gd options...]
#   tools/simulate.sh 100000                        # 100k Hard games, 2/3/4 players cycled by seed
#   tools/simulate.sh 2000 --players 4 --personas mixed
#   tools/simulate.sh 3000 --variant no_leader_reserve   # -> build/sim/hard-no_leader_reserve-3000
# Env: JOBS (parallel workers, default = CPU cores), FIRST_SEED (default 0),
#      OUT (directory, default build/sim/<level>-<GAMES>).
# Results: $OUT/part*.jsonl (one JSON object per game), $OUT/report.md.
# Re-running the same command resumes: seeds already in the part files are skipped.
# Rough cost on Hard: ~1.6 s (2p), ~5.6 s (3p), ~8.6 s (4p) of CPU per game.
set -euo pipefail
cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"
GAMES="${1:-100000}"
shift || true
JOBS="${JOBS:-$(sysctl -n hw.ncpu 2>/dev/null || nproc)}"
FIRST_SEED="${FIRST_SEED:-0}"
LEVEL=hard
VARIANT=""
args=("$@")
for ((i = 0; i < ${#args[@]}; i++)); do
  [ "${args[$i]}" = "--level" ] && LEVEL="${args[$((i + 1))]}"
  [ "${args[$i]}" = "--variant" ] && VARIANT="-${args[$((i + 1))]//,/+}"
done
OUT="${OUT:-build/sim/${LEVEL}${VARIANT}-${GAMES}}"
mkdir -p "$OUT"
LOCK="$OUT/.running"
if [ -f "$LOCK" ] && kill -0 "$(cat "$LOCK")" 2>/dev/null; then
  echo "Another simulation (pid $(cat "$LOCK")) is writing to $OUT"; exit 1
fi
echo $$ >"$LOCK"

"$GODOT" --headless --import --quit >/dev/null 2>&1 || true

per=$(( (GAMES + JOBS - 1) / JOBS ))
pids=()
cleanup() { (( ${#pids[@]} )) && kill "${pids[@]}" 2>/dev/null || true; rm -f "$LOCK"; }
trap cleanup EXIT
trap 'exit 130' INT TERM
echo "Playing $GAMES games on $JOBS workers -> $OUT (log: $OUT/worker*.log)"
for ((w = 0; w < JOBS; w++)); do
  start=$(( FIRST_SEED + w * per ))
  n=$(( GAMES - w * per )); (( n > per )) && n=$per
  (( n <= 0 )) && break
  "$GODOT" --headless --script res://tools/simulate.gd -- \
    --games "$n" --first-seed "$start" --level "$LEVEL" --out "$OUT/part$w.jsonl" "$@" \
    >"$OUT/worker$w.log" 2>&1 &
  pids+=($!)
done

t0=$(date +%s)
while :; do
  alive=0
  for p in "${pids[@]}"; do kill -0 "$p" 2>/dev/null && alive=$((alive + 1)); done
  done_n=$( { cat "$OUT"/part*.jsonl 2>/dev/null || true; } | wc -l | tr -d ' ')
  el=$(( $(date +%s) - t0 ))
  printf '\r%s / %s games, %dm%02ds, %d workers running   ' "$done_n" "$GAMES" $((el / 60)) $((el % 60)) "$alive"
  (( alive == 0 )) && break
  sleep 10
done
echo
fail=0
for p in "${pids[@]}"; do wait "$p" || fail=1; done
if grep -l -E "SCRIPT ERROR|Parse Error" "$OUT"/worker*.log >/dev/null 2>&1; then
  echo "Script errors in worker logs:"; grep -h -A3 -E "SCRIPT ERROR|Parse Error" "$OUT"/worker*.log | head -20; fail=1
fi
python3 tools/analyze_sim.py "$OUT"/part*.jsonl -o "$OUT/report.md"
echo "Report: $OUT/report.md"
exit $fail
