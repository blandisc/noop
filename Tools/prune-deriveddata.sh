#!/bin/bash
# Prune DerivedData folders left behind by deleted worktrees.
#
# Every Claude session builds from its own git worktree, and Xcode/xcodebuild
# mint a fresh DerivedData folder per project path (Cenit-<hash>). When the
# worktree is pruned, its ~1 GB DerivedData folder stays behind forever —
# they accumulate into tens of GB and the disk pressure slows every build.
#
# This deletes only Cenit-* folders whose WorkspacePath no longer exists on
# disk. Live checkouts (canonical ~/code/noop and active worktrees) are kept.
# Safe to run any time, even with Xcode open.

set -euo pipefail

DD=~/Library/Developer/Xcode/DerivedData
freed=0
count=0

for d in "$DD"/Cenit-*; do
  [ -d "$d" ] || continue
  wp=$(defaults read "$d/info.plist" WorkspacePath 2>/dev/null || true)
  if [ -n "$wp" ] && [ ! -e "$wp" ]; then
    sz=$(du -sm "$d" | cut -f1)
    rm -rf "$d"
    freed=$((freed + sz))
    count=$((count + 1))
    echo "pruned: $(basename "$d") ($wp, ${sz} MB)"
  fi
done

echo "pruned $count folder(s), freed ${freed} MB"
du -sh "$DD" 2>/dev/null || true
