#!/usr/bin/env bash
set -euo pipefail

BASE_URL="${BASE_URL:-http://localhost:4000}"
INGEST_KEY="${MINION_INGEST_KEY:-minion-dev-ops-key}"

sql() {
  docker compose exec -T postgres psql -q -U postgres -d minion_dev -tA -c "$1"
}

post() {
  curl -fsS -o /dev/null -X POST "$BASE_URL/ingest/$1" -H "Authorization: Bearer $INGEST_KEY" -H 'content-type: application/json' -d "$2"
}

created="$(sql "
  insert into rules (id, name, owner_type, owner_id, enabled, severity, conditions, dedup, present, notify, inserted_at, updated_at)
  select gen_random_uuid(), v.name, 'team', t.id, true, v.severity, v.conditions::jsonb, v.dedup::jsonb, v.present::jsonb,
         jsonb_build_array(jsonb_build_object('type', 'team', 'id', t.id)), now(), now()
  from teams t,
       (values
         ('High error rate', 'critical',
          '{\"all\": [{\"field\": \"payload.alertname\", \"op\": \"eq\", \"value\": \"HighErrorRate\"},
                      {\"field\": \"payload.labels.service\", \"op\": \"matches\", \"value\": \"payments-*\"}]}',
          '{\"key\": [\"payload.labels.service\", \"payload.labels.region\"], \"quiet_sec\": 300}',
          '{\"title\": \"High error rate on {{payload.labels.service}} ({{payload.labels.region}})\",
            \"fields\": [\"payload.labels.service\", \"payload.labels.region\"], \"color\": \"red\"}'),
         ('Payments down', 'critical',
          '{\"field\": \"payload.type\", \"op\": \"eq\", \"value\": \"PAYMENTS_DOWN\"}',
          '{\"key\": [\"payload.region\"], \"quiet_sec\": 300}',
          '{\"title\": \"Payments down in {{payload.region}}\", \"body\": \"{{payload.reason}}\", \"color\": \"red\"}')
       ) as v(name, severity, conditions, dedup, present)
  where t.name = 'ops' and not exists (select 1 from rules where name = v.name)
  returning name")"

if [ -n "$created" ]; then
  echo "Created demo rules: $(echo "$created" | tr '\n' ' ')"
  echo "Waiting for the rules cache to load them"
  sleep 6
fi

echo "Posting demo events to $BASE_URL"
post ops-monitor '{"type":"DISK_FULL","host":"web-3","used":97}'
post ops-monitor '{"type":"DISK_FULL","host":"web-3","used":98}'
post ops-monitor '{"type":"DISK_FULL","host":"web-3","used":99}'
post ops-monitor '{"type":"DISK_FULL","host":"db-1","used":95}'
post prometheus '{"alertname":"HighErrorRate","labels":{"service":"payments-api","region":"eu-west"}}'
post payments '{"type":"PAYMENTS_DOWN","region":"us-east","reason":"Card processor timeouts"}'
post ops-monitor '{"type":"CPU_HIGH","host":"web-3"}'

echo "Done: 4 alerts (web-3 with 3 events, db-1, payments-api error rate, payments in us-east); CPU_HIGH matches no rule."
echo "Dashboard: $BASE_URL   Gateway: $BASE_URL/gateway   Mailpit: http://localhost:8025"
