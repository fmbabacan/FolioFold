#!/bin/zsh
set -euo pipefail

executable=$1
baseline_dir=Tests/VisualSnapshots
mode=verify
if [[ -n "${FOLIOFOLD_SNAPSHOT_BASELINES:-}" ]]; then baseline_dir=$FOLIOFOLD_SNAPSHOT_BASELINES; fi
if [[ -n "${FOLIOFOLD_SNAPSHOT_MODE:-}" ]]; then mode=$FOLIOFOLD_SNAPSHOT_MODE; fi
run_dir=$(mktemp -d /tmp/foliofold-visual-snapshots.XXXXXX)
log_file=$run_dir/render.log

FOLIOFOLD_SNAPSHOT_OUTPUT=$run_dir $executable >$log_file 2>&1 &
pid=$!
for _ in {1..200}; do
    kill -0 $pid 2>/dev/null || break
    sleep 0.05
done
wait $pid
grep -Fq visual_snapshot_render=passed $log_file

snapshot_count=$(find $run_dir -type f -name '*.png' | wc -l | tr -d ' ')
test $snapshot_count -eq 20

if [[ $mode == record ]]; then
    mkdir -p $baseline_dir
    find $run_dir -type f -name '*.png' -exec cp {} $baseline_dir/ \;
    find $baseline_dir -type f -name '*.png' -print0 | sort -z | xargs -0 shasum -a 256 >$baseline_dir/SHA256SUMS
    print visual_snapshot_baselines=recorded
    exit 0
fi

test -f $baseline_dir/SHA256SUMS
actual_manifest=$run_dir/SHA256SUMS
find $run_dir -type f -name '*.png' -print0 | sort -z | xargs -0 shasum -a 256 | sed "s#$run_dir/#$baseline_dir/#" >$actual_manifest
cmp $baseline_dir/SHA256SUMS $actual_manifest
print visual_regression=passed
