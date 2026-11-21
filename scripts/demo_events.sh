#!/usr/bin/env bash
set -euo pipefail

BASE_URL="${BASE_URL:-http://localhost:4000}"
GRU_KEY="${MINION_INGEST_KEY:-minion-dev-gru-key}"
VECTOR_KEY="${MINION_VECTOR_INGEST_KEY:-minion-dev-vector-key}"

post() {
  curl -fsS -o /dev/null -X POST "$BASE_URL/ingest/$2" -H "Authorization: Bearer $1" -H 'content-type: application/json' -d "$3"
}

kafka() {
  echo "$2" | docker compose exec -T redpanda rpk topic produce "$1" > /dev/null
}

now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

echo "Posting Gru's Squad events to $BASE_URL"
post "$GRU_KEY" lab-monitor '{"type":"DISK_FULL","host":"web-3","used":97}'
post "$GRU_KEY" lab-monitor '{"type":"DISK_FULL","host":"web-3","used":98}'
post "$GRU_KEY" lab-monitor '{"type":"DISK_FULL","host":"web-3","used":99}'
post "$GRU_KEY" lab-monitor '{"type":"DISK_FULL","host":"db-1","used":95}'
post "$GRU_KEY" prometheus '{"alertname":"HighErrorRate","labels":{"service":"payments-api","region":"eu-west"},"annotations":{"summary":"5xx responses above 5% for 5 minutes.","error_rate":"12.4%"}}'
post "$GRU_KEY" warehouse '{"type":"STOCK_LOW","item":"banana","quantity":42,"warehouse":"lair-basement"}'
post "$GRU_KEY" lab-monitor '{"type":"CPU_HIGH","host":"web-3","load":7.5}'
kafka workflow-events "{\"type\":\"WORKFLOW_FAILED\",\"workflowId\":\"WF-248358\",\"workflowName\":\"Order-settlement\",\"step\":\"validate-counterparty\",\"severity\":\"ERROR\",\"environment\":\"prod\",\"timestamp\":\"$now\",\"error\":{\"code\":\"TIMEOUT\",\"message\":\"Counterparty service did not respond in timeout\"}}"

echo "Posting Vector Industries events"
post "$VECTOR_KEY" pricing-engine-2 '{"level":"WARN","instance":"pricing-engine-2","instrument":"EURUSD","latency_ms":1840,"message":"quote took 1840 ms"}'
post "$VECTOR_KEY" prometheus '{"alertname":"TargetDown","labels":{"job":"shrink-ray","instance":"lab-2","region":"pyramid-wing"},"annotations":{"description":"Health check failed 3 times in a row."}}'
kafka trade-events "{\"meta\":{\"schema\":\"trade.rejected.v2\",\"producer\":\"rates-booking\",\"ts\":\"$now\"},\"trade\":{\"id\":\"T-90417\",\"desk\":\"rates\",\"notional\":2500000,\"currency\":\"EUR\",\"counterparty\":\"Bank of Evil\"},\"reason\":{\"code\":\"LIMIT_BREACH\",\"message\":\"Counterparty credit limit exceeded\"}}"

echo "Done: Gru's Squad gets 5 alerts (web-3 with 3 events, db-1, payments-api error rate, order settlement, Bob's bananas);"
echo "Vector Industries gets 3 (pricing latency, shrink ray, rejected trade). CPU_HIGH matches no rule and shows under Unmatched."
echo "Dashboard: $BASE_URL   Gateway: $BASE_URL/gateway   Mailpit: http://localhost:8025"
