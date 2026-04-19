#!/bin/bash
set -euo pipefail

SESSIONS_DIR="${CLAUDE_PROJECT_DIR:-.}/sessions"
LAST_N=""
LATEST=""

if [ -d "$SESSIONS_DIR" ]; then
  LATEST=$(ls -1 "$SESSIONS_DIR"/*.md 2>/dev/null | sort | tail -1 || true)
  if [ -n "$LATEST" ]; then
    LAST_N=$(grep -E '^last_n:' "$LATEST" | tail -1 | sed 's/^last_n:[[:space:]]*//' | tr -d '[:space:]' || true)
  fi
fi

if [ -n "$LAST_N" ] && [[ "$LAST_N" =~ ^[0-9]+$ ]]; then
  NEXT_N=$((LAST_N + 1))
  BASENAME=$(basename "$LATEST")
  MSG="Счётчик нумерации протокола: last_n=${LAST_N} (из sessions/${BASENAME}). Следующий ответ начинается с N=${NEXT_N}. Формат: **N. [YYYY-MM-DD HH:MM]**, TZ=Europe/Bratislava."
  printf '{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":%s}}\n' "$(printf '%s' "$MSG" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))')"
else
  MSG="В sessions/ не найдено last_n. Стартуй нумерацию с N=1. Формат: **N. [YYYY-MM-DD HH:MM]**, TZ=Europe/Bratislava."
  printf '{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":%s}}\n' "$(printf '%s' "$MSG" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))')"
fi
