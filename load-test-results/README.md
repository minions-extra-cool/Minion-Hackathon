# Load test results

Measured with `scripts/load_test.mjs` against the app in production mode (`MIX_ENV=prod`) on one
12-core MacBook that also ran Postgres, Redpanda (both in Docker Desktop) and the load generator.
Each HTTP request carries one event: 90% `DISK_FULL` repeats across 200 hosts (dedup into at most
200 alerts that email two people), 10% events that match no rule. Each stage lasts 20 seconds.

"End to end" is ingest (HTTP request accepted, `received_at`) to the alert stored in Postgres,
recorded by the pipeline for every event (`GET /metrics`). "Delivered" is ingest to the email
accepted by the SMTP server, from the database after the run.

## Throughput ceiling by number of pipeline processors

| Processors / DB pool | Comfortable at | Ceiling (processed/s) | e2e p50 / p99 at 4,000/s | Backlog drain rate |
|---|---|---|---|---|
| 12 / 30 (default: one per core) | 2,000/s (p99 71 ms) | ~3,700–4,000 | 171 / 740 ms | ~5,000/s |
| 48 / 60 | 4,000/s (p99 44 ms) | ~5,000–5,600 | 23 / 44 ms | ~6,700/s |
| 96 / 85 | 4,000/s (p99 48 ms) | ~4,900–5,400 | 24 / 48 ms | ~6,200/s |

- Ingest kept up in every run: up to ~10,000 requests/s accepted, zero errors, HTTP p99 under
  62 ms. Above ~8,000 requests/s the generator itself hit its in-flight cap.
- Overload never failed: events waited in Kafka, memory stayed under 240 MB, process count stayed
  flat (~800–1,300), nothing crashed, and the backlog drained on its own.
- Ingest to delivered (email): p50 1.7–3.9 s, p99 3.1–6.8 s, measured under these loads.
- Idle end-to-end latency: 15–35 ms per event (mostly Kafka polling at 10 ms).

## Why it plateaus

At 48+ processors Postgres connections spend their time in `LWLock:WALWrite` / `IO:WalSync`: every
event is its own transaction, so every event costs one WAL flush, and Docker Desktop's virtual disk
caps flushes at roughly 5,000/s. CPU is not the limit (app ~3.2 of 12 cores, Postgres ~1.2).
Row-lock contention on the shared alert rows was negligible. The fix is fewer commits per event:
process events in batches (one transaction and one multi-row upsert per batch, repeats folded
together first).

## Files

| File | Run |
|---|---|
| `…03-16-11…` | first run, 12 processors (email misconfigured in production at the time) |
| `…03-17-03…` | single 6,000/s stage, 12 processors (CPU sampling run) |
| `…03-26-23…` | 12 processors, after the delivery-worker fix (SMTP credentials bug still present) |
| `…03-39-39…` | 12 processors, all fixes |
| `…03-42-36…` | 48 processors |
| `…03-45-16…` | 96 processors |
| `…03-46-08…` | single 7,000/s stage, 96 processors (Postgres wait-event sampling run) |

A run at 03:32 was discarded: the Kafka data from earlier runs filled Docker's 18 GB disk mid-run.
The events topic now has a retention limit (`EVENTS_RETENTION_HOURS`, default 6).

## Reproduce

```
PIPELINE_PROCESSORS=48 POOL_SIZE=60 MIX_ENV=prod DATABASE_URL=… SECRET_KEY_BASE=… \
  SMTP_RELAY=localhost SMTP_PORT=1025 mix phx.server
node scripts/load_test.mjs --stages=2000,4000,6000,8000,10000 --seconds=20 --batch=1
```
