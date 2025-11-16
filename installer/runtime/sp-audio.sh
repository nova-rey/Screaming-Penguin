#!/bin/sh
# Screaming Penguin audio helper (Phase 5).
# Provides optional audio cues for start and completion.
#
# This remains best-effort and non-fatal if audio tools are missing.

set -eu

# shellcheck disable=SC1091
. "$(dirname "$0")/lib/logging.sh"

_sp_audio_say() {
    msg="$1"

    if command -v espeak-ng >/dev/null 2>&1; then
        espeak-ng "$msg" 2>/dev/null || :
    elif command -v beep >/dev/null 2>&1; then
        beep 2>/dev/null || :
    else
        # No audio tools; silent.
        :
    fi
}

sp_audio_ready() {
    log_info "Audio: installer ready."
    _sp_audio_say "Installer ready."
    return 0
}

sp_audio_complete() {
    log_info "Audio: installation complete."
    _sp_audio_say "Installation complete."
    return 0
}
