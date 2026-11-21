#!/usr/bin/env bash
set -euo pipefail

RUN="$(date +%s)-$RANDOM"

sql() {
  docker compose exec -T postgres psql -q -U postgres -d minion_dev -tA -c "$1"
}

event() {
  local workflow_id="$1" step="$2" environment="$3"
  printf '{"type":"WORKFLOW_FAILED","workflowId":"%s","workflowName":"Order-settlement","step":"%s","severity":"ERROR","environment":"%s","timestamp":"%s","error":{"code":"TIMEOUT","message":"Counterparty service did not respond in timeout"}}\n' \
    "$workflow_id" "$step" "$environment" "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}

echo "Writing four WORKFLOW_FAILED events to the external Kafka topic workflow-events"
{
  event "WF-1-$RUN" "validate-counterparty-$RUN" prod
  event "WF-2-$RUN" "validate-counterparty-$RUN" prod
  event "WF-3-$RUN" "book-trade-$RUN" prod
  event "WF-4-$RUN" "validate-counterparty-$RUN" uat
} | docker compose exec -T redpanda rpk topic produce workflow-events > /dev/null

query="select title || ' | count ' || count || ' | ' || body from alerts where title like '%-$RUN' order by count desc, title"
expected="Order-settlement failed at validate-counterparty-$RUN | count 2 | Counterparty service did not respond in timeout
Order-settlement failed at book-trade-$RUN | count 1 | Counterparty service did not respond in timeout"

for _ in $(seq 1 20); do
  actual="$(sql "$query")"
  if [ "$actual" = "$expected" ]; then
    echo "$actual"
    echo "OK: two alerts from Kafka; the uat event matched no rule"
    exit 0
  fi
  sleep 0.5
done

echo "Expected:"
echo "$expected"
echo "Got:"
echo "$actual"
exit 1
