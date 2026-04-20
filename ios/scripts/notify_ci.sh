#!/bin/bash
# Usage: ./notify_ci.sh <lane> <status> [message]
# Sends iMessage via BlueBubbles API
LANE="${1:-unknown}"
STATUS="${2:-unknown}"
DETAIL="${3:-}"
PHONE="+14243979689"
BB_URL="http://127.0.0.1:1234/api/v1/message/text"
# BB_PASSWORD is read from env. Set it in ~/.openclaw/dashboard-secrets.json
# (auto-loaded by the fastlane runner via the launchd env) or export it in CI.
if [ -z "${BB_PASSWORD:-}" ]; then
  echo "notify_ci: BB_PASSWORD unset; skipping iMessage send" >&2
  BB_SKIP=1
fi

if [ "$STATUS" = "success" ]; then
  TEXT="✅ RunsByIP CI — ${LANE} lane succeeded! 🚀"
  if [ -n "$DETAIL" ]; then
    TEXT="${TEXT} ${DETAIL}"
  fi
else
  TEXT="❌ RunsByIP CI — ${LANE} lane failed."
  if [ -n "$DETAIL" ]; then
    TEXT="${TEXT} Error: ${DETAIL}"
  fi
fi

LUKA_LOG="$HOME/Coding/LukaDashboard/Backend/luka-log.py"
if [ -f "$LUKA_LOG" ]; then
  /usr/bin/python3 "$LUKA_LOG" "ci" "$TEXT" || true
fi

if [ -z "${BB_SKIP:-}" ]; then
  curl -s -X POST "${BB_URL}?password=${BB_PASSWORD}" -H "Content-Type: application/json" -d "{\"chatGuid\":\"any;-;${PHONE}\",\"message\":\"${TEXT}\",\"tempGuid\":\"notify-$(date +%s)-$$\"}"
fi
