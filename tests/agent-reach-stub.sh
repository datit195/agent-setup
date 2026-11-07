#!/usr/bin/env bash
# A stand-in for the agent-reach CLI, used by tests/install-test.sh:
# `agent-reach doctor` prints ~/.agent-reach-stub-doctor.json when it exists,
# else a doctor report where every default channel is fine.
set -euo pipefail
case "${1:-}" in
  doctor)
    if [ -f "$HOME/.agent-reach-stub-doctor.json" ]; then
      cat "$HOME/.agent-reach-stub-doctor.json"
    else
      printf '%s\n' '{"schema_version": 1, "ok": true, "action": "doctor", "result": {"channels": [{"channel": "github", "level": "default", "status": "unverified", "problems": []}, {"channel": "twitter", "level": "optional", "status": "not_added", "problems": []}]}, "error": null}'
    fi
    ;;
  *) echo "agent-reach stub: unsupported: $*" >&2; exit 1 ;;
esac
