#!/usr/bin/env bash
# То же, что cy.sh, но с DISPLAY=:0 — для GUI и xdotool.
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "$DIR/cy.sh" "export DISPLAY=:0; $*"
