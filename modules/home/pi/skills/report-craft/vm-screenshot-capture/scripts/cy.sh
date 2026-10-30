#!/usr/bin/env bash
# Выполнить команду в госте по SSH. ВМ и порт — из CYVM/CYPORT (см. vmenv.sh).
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/vmenv.sh"
exec ssh -i "$DIR/cyops_key" -p "$CYPORT" \
  -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR \
  -o ConnectTimeout=10 analyst@127.0.0.1 "$@"
