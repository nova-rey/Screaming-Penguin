#!/usr/bin/env bash
# Deprecated: ISO CI orchestration removed with this milestone (Ouroboros owns future ISO builds).
set -euo pipefail
cat <<'MSG' >&2
[CI-ISO] ISO CI workflows have been pruned; run the smoke suite (`make ci-smoke`) and rely on the .img builder. The Ouroboros side project owns any future hybrid ISO pipelines.
MSG
exit 1
