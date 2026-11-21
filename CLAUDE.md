# Minion

Alert routing service: ingests events from many sources, matches them against team rules, deduplicates them into alerts, and delivers each alert on the recipient's preferred channel. The task statement is in `task.txt`.

Phoenix and Elixir usage rules are in @AGENTS.md. Follow them.

## Working rules

- **No comments.** Write code that explains itself through names. Add a comment only when the code cannot say why it does something, which should be about 1% of the time. No `@moduledoc` or `@doc` boilerplate.
- **Feature branches, frequent local commits.** Never work on `main`. Commit each small working step with a message that says what changed, so a teammate can read the branch history and follow what was built.
- **No mistakes.** Run `mix precommit` (compile with warnings as errors, format, tests) before every commit, and do not commit if it fails. Never say something works unless you ran it and saw it work.
- **Schema changes are announced.** Tell the other pair before adding or changing a migration.
- **Explain what you wrote.** The team is new to Elixir. After each change, summarise it in plain words.

## Pipeline

```
source adapters ─► Kafka topic "events" ─► pipeline: match rules ─► fingerprint ─► create/update alert
                                                                                        │ new alert only
                                                                                        ▼
                                                    Minion.Delivery.dispatch(alert) ─► deliveries + Oban jobs ─► channel adapters
```

- An adapter never interprets the payload. It wraps the original message in an envelope and publishes it.
- Rules are data in Postgres, not code. An unseen schema must need a new rule and nothing else.
- A notification is sent on the first event of an alert. Repeats only increment the counter.
- The alert, its delivery rows and their Oban jobs are written in one transaction.

## Contracts

**Event envelope** (the message on the `events` topic):

```json
{"id": "uuid", "source": "payments-api", "source_type": "http|kafka|log",
 "received_at": "ISO-8601", "payload": {}}
```

**Rule** (`rules` table; `conditions`, `dedup`, `present`, `notify` are jsonb):

```json
{
  "name": "Disk full",
  "owner_type": "team", "owner_id": "uuid",
  "severity": "info|warning|critical",
  "conditions": {"all": [{"field": "payload.type", "op": "eq", "value": "DISK_FULL"}]},
  "dedup": {"key": ["payload.host"], "quiet_sec": 600},
  "present": {"title": "Disk full on {{payload.host}}", "body": "", "fields": [], "color": "amber"},
  "notify": [{"type": "team|person|oncall", "id": "uuid"}]
}
```

- `conditions` nodes (named this way because `when` is a reserved word in Elixir and SQL): `{"all": [...]}`, `{"any": [...]}`, or `{"field", "op", "value"}`. Fields are dot paths into the envelope.
- Operators: `eq`, `neq`, `gt`, `gte`, `lt`, `lte`, `in`, `contains`, `matches` (`*` wildcard), `exists`.
- Fingerprint: hash of the rule id plus the values at `dedup.key`. At most one unresolved alert per fingerprint (enforced by a unique index).
- `quiet_sec`: an unresolved alert with no events for this long is auto-resolved.

**Alert** (`alerts` table): `rule_id`, `owner_type`, `owner_id`, `fingerprint`, `status` (`open|acked|resolved`), `severity`, `count`, `first_seen`, `last_seen`, `title`, `body`, `sample_event`.

**Delivery** (`deliveries` table): `alert_id`, `person_id`, `channel` (`email|sms|phone`), `status` (`pending|delivered|failed`), `attempts`, `last_error`.

**Preferences** (`people.preferences`, jsonb). For each severity, the first entry whose `hours` contain the current hour wins; an entry without `hours` always applies. The UI feed always shows the alert, so an empty list means "UI only". `hours: [from, to]` are whole UTC hours, `from` included and `to` excluded (`[8, 20]` is 08:00–19:59 UTC); a window with `from > to`, like `[22, 6]`, wraps past midnight.

```json
{"critical": [{"channels": ["sms"], "hours": [8, 20]}, {"channels": ["email"]}],
 "warning": [{"channels": ["email"]}],
 "info": []}
```

**PubSub topic:** `alerts:<owner_type>:<owner_id>`.

**Channel adapter:** a module implementing `Minion.Channel` with `deliver(alert, person) :: :ok | {:error, term}`.

**Delivery retries:** `Minion.Delivery.Worker` makes up to 4 attempts, 5s, 15s and 60s apart, keeping the delivery `pending` with `attempts` and `last_error` updated. After the last attempt, or at once for `:no_email_address` / `:no_phone_number`, the delivery is `failed`; a failed SMS or phone delivery falls back to one email delivery for that person. Every change is broadcast on the alert's topic as `{:delivery, %Delivery{}}`.

**Fake SMS/phone gateway:** `Minion.FakeGateway`, shown at `/gateway`. The SMS and phone channels post to `POST /fake-gateway/messages` (URL in `config :minion, Minion.Channels.Gateway`); `PUT /fake-gateway/status {"down": true}` makes it answer 503. A real provider replaces `Minion.Channels.Gateway`.

## Code layout

| Directory | Owner | Holds |
|---|---|---|
| `lib/minion/accounts/` | shared | `Team`, `Person` |
| `lib/minion/ingest/` | Pair A | source adapters, `Minion.Ingest.publish/1` |
| `lib/minion/rules/` | Pair A | `Rule`, the matcher, the rules cache |
| `lib/minion/alerts/` | Pair A | `Alert`, the pipeline consumer, auto-resolve |
| `lib/minion/delivery/` | Pair B | `Delivery`, `Minion.Delivery.dispatch/1`, workers |
| `lib/minion/channels/` | Pair B | `Minion.Channel` and one module per channel |

The seam between the pairs is `Minion.Delivery.dispatch(alert)`. Pair A calls it for every new alert; Pair B implements it.

## Running locally

```
docker compose up -d     # Postgres :5433, Redpanda :19092 (console :8080), Mailpit :8025
mix setup                # deps, database, migrations, seeds
mix phx.server           # http://localhost:4000
```
