#!/bin/sh
# Screaming Penguin audio helper skeleton (Phase 2).
# Will manage audio cues (beep/espeak-ng) in later phases.
# Currently logs only.

set -eu

# shellcheck disable=SC1091
. "$(dirname "$0")/lib/logging.sh"

sp_audio_ready() {
    log_info "Phase 2: audio-ready placeholder called."
    log_info "TODO: implement startup audio cue in a later phase."
    return 0
}

sp_audio_complete() {
    log_info "Phase 2: audio-complete placeholder called."
    log_info "TODO: implement completion audio cue in a later phase."
    return 0
}
