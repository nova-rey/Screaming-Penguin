#!/usr/bin/env bash
# ISO builder intentionally disabled in this repository (Ouroboros owns any future hybrid media).
set -euo pipefail
cat <<'MSG' >&2
[SP-ISO] ISO builds have been pruned from this tree. Use the canonical .img artifact and the Ouroboros side project if you need a hybrid ISO path.
MSG
exit 1
