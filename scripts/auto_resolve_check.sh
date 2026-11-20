#!/usr/bin/env bash
set -euo pipefail

BASE_URL="${BASE_URL:-http://localhost:4000}"
HOST="host-$(date +%s)-$RANDOM"

sql() {
  docker compose exec -T postgres psql -q -U postgres -d minion_dev -tA -c "$1"
}

post() {
  curl -fsS -X POST "$BASE_URL/ingest/test" -H 'content-type: application/json' \
    -d "{\"type\":\"AUTO_RESOLVE_CHECK\",\"host\":\"$HOST\"}" > /dev/null
}

statuses() {
  sql "select string_agg(status, ',' order by inserted_at) from alerts where title = 'Auto-resolve check on $HOST'"
}

wait_for() {
  local expected="$1" seconds="$2"
  for _ in $(seq 1 "$seconds"); do
    if [ "$(statuses)" = "$expected" ]; then
      return 0
    fi
    sleep 1
  done
  echo "FAILED: expected alert statuses '$expected', got '$(statuses)'"
  exit 1
}

created="$(sql "insert into rules (id, name, owner_type, owner_id, enabled, severity, conditions, dedup, present, notify, inserted_at, updated_at)
  select gen_random_uuid(), 'Auto-resolve check', 'team', t.id, true, 'info',
    '{\"field\":\"payload.type\",\"op\":\"eq\",\"value\":\"AUTO_RESOLVE_CHECK\"}',
    '{\"key\":[\"payload.host\"],\"quiet_sec\":5}',
    '{\"title\":\"Auto-resolve check on {{payload.host}}\"}',
    '[]', now(), now()
  from teams t
  where t.name = 'ops' and not exists (select 1 from rules where name = 'Auto-resolve check')
  returning id")"

if [ -n "$created" ]; then
  echo "Created rule 'Auto-resolve check' (quiet_sec 5); waiting for the rules cache to load it"
  sleep 6
fi

echo "Posting an event for $HOST"
post
wait_for "open" 10
echo "Alert is open; waiting for the auto-resolve sweep (runs every 30s)"
wait_for "resolved" 45
echo "Alert was auto-resolved; posting the same event again"
post
wait_for "resolved,open" 10
echo "OK: the alert auto-resolved, and the next event opened a new alert"
