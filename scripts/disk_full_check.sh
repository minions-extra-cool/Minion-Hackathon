#!/usr/bin/env bash
set -euo pipefail

BASE_URL="${BASE_URL:-http://localhost:4000}"
INGEST_KEY="${MINION_INGEST_KEY:-minion-dev-gru-key}"
RUN="$(date +%s)-$RANDOM"

post() {
  curl -fsS -X POST "$BASE_URL/ingest/test" -H "Authorization: Bearer $INGEST_KEY" -H 'content-type: application/json' -d "$1" > /dev/null
}

echo "Posting five events for hosts web-1-$RUN and web-2-$RUN"
post "{\"type\":\"DISK_FULL\",\"host\":\"web-1-$RUN\"}"
post "{\"type\":\"DISK_FULL\",\"host\":\"web-1-$RUN\"}"
post "{\"type\":\"CPU_HIGH\",\"host\":\"web-1-$RUN\"}"
post "{\"type\":\"DISK_FULL\",\"host\":\"web-2-$RUN\"}"
post "{\"type\":\"DISK_FULL\",\"host\":\"web-1-$RUN\"}"

query="select title || ' | count ' || count from alerts where title like '%-$RUN' order by count desc"
expected=$'Disk full on web-1-'"$RUN"$' | count 3\nDisk full on web-2-'"$RUN"' | count 1'

for _ in $(seq 1 20); do
  actual="$(docker compose exec -T postgres psql -U postgres -d minion_dev -tA -c "$query")"
  if [ "$actual" = "$expected" ]; then
    echo "$actual"
    echo "OK: two alerts, counts 3 and 1"
    exit 0
  fi
  sleep 0.5
done

echo "Expected:"
echo "$expected"
echo "Got:"
echo "$actual"
exit 1
