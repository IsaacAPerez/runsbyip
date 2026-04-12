#!/bin/bash
# Usage: ./notify_ci.sh <lane> <status> [message]
# Sends iMessage via BlueBubbles API
LANE="${1:-unknown}"
STATUS="${2:-unknown}"
DETAIL="${3:-}"
PHONE="+14243979689"
BB_PASSWORD="Chess2435"
BB_URL="http://127.0.0.1:1234/api/v1/message/text"

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

curl -s -X POST "${BB_URL}?password=${BB_PASSWORD}" -H "Content-Type: application/json" -d "{\"chatGuid\":\"any;-;${PHONE}\",\"message\":\"${TEXT}\",\"tempGuid\":\"notify-$(date +%s)-$$\"}"
