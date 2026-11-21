#!/usr/bin/env bash
set -euo pipefail

BASE_URL="${BASE_URL:-http://localhost:4000}"
INGEST_KEY="${MINION_INGEST_KEY:-minion-dev-gru-key}"
RUN="$(date +%s)-$RANDOM"

sql() {
  docker compose exec -T postgres psql -q -U postgres -d minion_dev -tA -c "$1"
}

post() {
  curl -fsS -X POST "$BASE_URL/ingest/test" -H "Authorization: Bearer $INGEST_KEY" -H 'content-type: application/json' \
    -d "{\"type\":\"$1\",\"host\":\"$RUN\"}" > /dev/null
}

states() {
  sql "select coalesce(string_agg(status || case when closed_at is null then '' else '+closed' end, ',' order by inserted_at), '')
       from alerts where title = '$1 on $RUN'"
}

wait_for() {
  local title="$1" expected="$2"
  for _ in $(seq 1 45); do
    if [ "$(states "$title")" = "$expected" ]; then
      echo "  $title: $expected"
      return 0
    fi
    sleep 1
  done
  echo "FAILED: expected '$title' alerts to be '$expected', got '$(states "$title")'"
  exit 1
}

created="$(sql "
  insert into teams (id, name, auto_resolve_after, inserted_at, updated_at)
  select gen_random_uuid(), 'quiet-sweep-check', '{\"info\": 5}', now(), now()
  where not exists (select 1 from teams where name = 'quiet-sweep-check');

  insert into rules (id, name, owner_type, owner_id, enabled, severity, conditions, dedup, present, notify, inserted_at, updated_at)
  select gen_random_uuid(), v.name, 'team', t.id, true, v.severity, v.conditions::jsonb,
         '{\"key\":[\"payload.host\"],\"quiet_sec\":5}', v.present::jsonb, '[]', now(), now()
  from teams t,
       (values
         ('Quiet check (critical)', 'critical', '{\"field\":\"payload.type\",\"op\":\"eq\",\"value\":\"QUIET_CHECK_CRITICAL\"}', '{\"title\":\"Critical check on {{payload.host}}\"}'),
         ('Quiet check (info)', 'info', '{\"field\":\"payload.type\",\"op\":\"eq\",\"value\":\"QUIET_CHECK_INFO\"}', '{\"title\":\"Info check on {{payload.host}}\"}')
       ) as v(name, severity, conditions, present)
  where t.name = 'quiet-sweep-check' and not exists (select 1 from rules where name = v.name)
  returning id")"

if [ -n "$created" ]; then
  echo "Created team 'quiet-sweep-check' (info auto-resolves after 5s) and two rules (quiet_sec 5)"
  echo "Waiting for the rules cache to load them"
  sleep 6
fi

echo "1. One critical and one info event"
post QUIET_CHECK_CRITICAL
post QUIET_CHECK_INFO
wait_for "Critical check" "open"
wait_for "Info check" "open"

echo "2. After the next sweep (every 30s): critical is closed but still open, info is resolved"
wait_for "Critical check" "open+closed"
wait_for "Info check" "resolved+closed"

echo "3. The critical problem comes back: a new alert opens, the old one stays unresolved"
post QUIET_CHECK_CRITICAL
wait_for "Critical check" "open+closed,open"

echo "OK"
