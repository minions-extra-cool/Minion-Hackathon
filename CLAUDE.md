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
  "notify": [{"type": "team|person|oncall", "id": "uuid", "channels": ["sms", "phone"]}]
}
```

- `conditions` nodes (named this way because `when` is a reserved word in Elixir and SQL): `{"all": [...]}`, `{"any": [...]}`, or `{"field", "op", "value"}`. Fields are dot paths into the envelope.
- `notify[].channels` is optional: when set, those recipients get exactly these channels (`email`, `sms`, `phone`); when absent, each person's preferences decide. A person reached by several entries gets the union. The editor's "Send by" sets the same channels on every entry.
- Operators: `eq`, `neq`, `gt`, `gte`, `lt`, `lte`, `in`, `contains`, `matches` (`*` wildcard), `exists`.
- Matching semantics (`Minion.Rules.Matcher`): text comparisons ignore case; numbers compare by value even when either side is a string (`"500"` equals `500`); a missing field makes the condition false, including `neq`; an unknown operator or malformed node is false, never an error. Paths can index lists (`payload.errors.0.code`).
- Templates (`Minion.Rules.Template`): `{{payload.host}}` is replaced by the value at that path; missing values render as empty text, objects as JSON.
- Fingerprint: hash of the rule id plus the values at `dedup.key`.
- Fingerprint uniqueness: at most one *active* alert per fingerprint, i.e. not resolved and not closed (`alerts_active_fingerprint_index`).
- `quiet_sec`: an active alert with no events for this long is **closed**: `closed_at` is set, its status is unchanged, and it stops absorbing events. The next event with that fingerprint opens a new alert and notifies again. A rule without a numeric `quiet_sec` never closes its alerts.
- Auto-resolve is a **team** setting, `teams.auto_resolve_after`, e.g. `{"info": 3600, "warning": 14400}`: an unresolved alert of that severity with no events for that many seconds is resolved. Critical alerts never auto-resolve; a person must resolve them. Alerts owned by a person use that person's team setting.
- `Minion.Alerts.QuietSweepWorker` runs both checks every 30 seconds.

**Alert** (`alerts` table): `rule_id`, `owner_type`, `owner_id`, `fingerprint`, `status` (`open|acked|resolved`), `severity`, `count`, `first_seen`, `last_seen`, `closed_at`, `title`, `body`, `sample_event`.

**Delivery** (`deliveries` table): `alert_id`, `person_id`, `channel` (`email|sms|phone`), `status` (`pending|delivered|failed`), `attempts`, `last_error`.

**Preferences** (`people.preferences`, jsonb). For each severity, the first entry whose `hours` contain the current hour wins; an entry without `hours` always applies. The UI feed always shows the alert, so an empty list means "UI only". `hours: [from, to]` are whole UTC hours, `from` included and `to` excluded (`[8, 20]` is 08:00–19:59 UTC); a window with `from > to`, like `[22, 6]`, wraps past midnight.

```json
{"critical": [{"channels": ["sms"], "hours": [8, 20]}, {"channels": ["email"]}],
 "warning": [{"channels": ["email"]}],
 "info": []}
```

**PubSub topic:** `alerts:<owner_type>:<owner_id>`, built by `Minion.Alerts.topic(alert)`. The pipeline broadcasts `{:alert, :created | :updated, %Alert{}}` after its transaction commits; the quiet sweep broadcasts `{:alert, :closed | :resolved, %Alert{}}`; acknowledging or resolving in the UI (`Minion.Alerts.acknowledge/1`, `resolve/1`, one conditional UPDATE so the first click wins) broadcasts `{:alert, :acked | :resolved, %Alert{}}`.

**UI:** Phoenix LiveView with daisyUI. The `minion` theme in `assets/css/app.css` is the only theme: warm off-white `base-100`, off-black `base-content`, banana-yellow `primary`, sharp corners (all radii 0; only status lights are round). The font is Lato, self-hosted in `priv/static/fonts` so browsers never call a third-party CDN. The feed's search (`/?q=`) uses `Minion.Fuzzy`: each query word must appear, letters in order, inside one word of the alert's title, body, source, owner, rule, severity or status; case and accents are ignored. In the feed, one light per alert carries both dimensions (`MinionWeb.AlertComponents.status_light/1`): its colour is the severity (red critical, orange warning, grey-blue info) and its shape is the state (solid and glowing when open, a glowing ring when acknowledged, a small grey dot when resolved). Its tooltip and screen-reader label spell both out. Nothing in the rows blinks. The alert page also lists severity as text. A rule's own `present.color` is shown only as a labelled swatch on the alert page. `/` is the live feed (`MinionWeb.DashboardLive`), `/alerts/:id` the alert detail (`MinionWeb.AlertLive`).

**Unmatched events:** an event no enabled rule matches is recorded by `Minion.Unmatched.record/1` (called from the processor) as a *shape*: one `unmatched_shapes` row per source plus set of payload field paths, upserted with a counter and the latest event as sample, broadcast as `{:unmatched, shape}` on the `unmatched` topic. The quiet sweep deletes shapes not seen for 24 hours. `/unmatched` (the feed's second tab, `MinionWeb.UnmatchedLive`) lists them; "Create rule" opens `/rules/new?from_unmatched=<id>` with `Unmatched.suggested_draft/2` (conditions on the source and an identifying field such as `type` or `alertname`) and the sample in the test panel.

**Rules UI:** `/rules` lists rules with a one-line summary (`ConditionTree.describe/1`) and an on/off switch (`MinionWeb.RulesLive`). `/rules/new` and `/rules/:id` are the editor (`MinionWeb.RuleEditorLive`): a visual condition builder (one level of nested groups), severity, title/body templates, grouping and notify, plus a JSON mode for the whole rule in the contract shape above. `Minion.Rules.Draft` converts between a rule and the editor's working copy; condition inputs are named by tree path (`c[0-1][field]`, `g[root]`). A test panel evaluates a pasted or recent event with the real matcher and shows ✓/✗ per condition. `/rules/new?from_alert=<id>` preloads that alert's event ("Create a rule from this event" on the alert page). Saving validates the rule (`Rule.changeset/2`) and broadcasts `{:rules_changed, id}` on the `rules` topic, which makes `Minion.Rules.Cache` reload at once.

**Runbooks:** `runbooks` table, at most one per rule (`rule_id` unique, deleted with the rule); `body` is free text in whatever format the team uses (steps, Markdown, a wiki link). `{{payload.x}}` placeholders are filled from the alert's first event by `Minion.Runbooks.render/2`, the same templating as titles. The result is shown through `MinionWeb.Markdown.to_html/1`, a small Markdown subset: lines starting `1.`/`1)` or `-`/`*`/`+` become lists, `**bold**`, `__italic__`, `` `code` ``; other lines keep their line breaks; HTML is always escaped. The alert page shows it as "What to do" while the alert is unresolved, with its last-updated time: on wide screens it sits right of the details and is capped at their height (it is absolutely positioned in its grid cell, so only the details set the row height); when it overflows, the `.RunbookOverflow` hook sets `data-overflowing`, which shows a fade and an Expand button that opens it in a large scrollable dialog. `/rules/:id/runbook` (`MinionWeb.RunbookLive`) edits it; with `?from_alert=<id>` it previews against that alert and returns there. After "Yes, resolve" the dialog's second step asks whether to write or update the runbook. The foreign key sits on `runbooks`, so several runbooks per rule (e.g. one per condition) only need the unique index dropped.

**Dispatch contract:** `Minion.Delivery.dispatch(alert)` runs inside the pipeline's transaction. Return `:ok`, or `{:error, reason}` (or raise) to roll back the alert; the pipeline then retries the event.

**Kafka sources:** external topics are listed in `config :minion, :kafka_sources` as `%{topic: ..., source: ...}`; adding one is a config line. `Minion.Ingest.KafkaSource` wraps each message (JSON, or the raw string) in an envelope with `source_type: "kafka"` and publishes batches to `events`, retrying until the publish succeeds. A new subscription starts at the topic's latest offset, so history is not replayed. Snappy, lz4 and gzip compressed batches are supported; zstd is not.

**Pipeline failures:** Kafka acknowledges every message, so the pipeline retries inside the handler: database outages are retried until the database is back; other errors are retried 5 times and the event is then moved to the `events_dead` topic. The pipeline and rules cache do not run in tests (`config :minion, :pipeline, enabled: false`); test `Minion.Alerts.Processor` directly.

**Channel adapter:** a module implementing `Minion.Channel` with `deliver(alert, person) :: :ok | {:error, term}`.

**Delivery retries:** `Minion.Delivery.Worker` makes up to 4 attempts, 5s, 15s and 60s apart, keeping the delivery `pending` with `attempts` and `last_error` updated. After the last attempt, or at once for `:no_email_address` / `:no_phone_number`, the delivery is `failed`; a failed SMS or phone delivery falls back to one email delivery for that person. Every change is broadcast on the alert's topic as `{:delivery, %Delivery{}}`. A delivery job orphaned by a node that died mid-send is put back in the queue after 2 minutes (Oban Lifeline `rescue_after`), so it may rarely be sent twice but is never left pending.

**Fake SMS/phone gateway:** `Minion.FakeGateway`, shown at `/gateway`. The SMS and phone channels post to `POST /fake-gateway/messages` (the app's own `/fake-gateway/messages` on whatever `PORT` it runs on; `SMS_GATEWAY_URL` points it elsewhere); `PUT /fake-gateway/status {"down": true}` makes it answer 503. A real provider replaces `Minion.Channels.Gateway`.

## Code layout

| Directory | Owner | Holds |
|---|---|---|
| `lib/minion/accounts/` | shared | `Team`, `Person` |
| `lib/minion/ingest/` | Pair A | source adapters, `Minion.Ingest.publish/1` |
| `lib/minion/kafka.ex`, `lib/minion/kafka/` | Pair A | Kafka client, topic setup |
| `lib/minion/rules/` | Pair A | `Rule`, the matcher, the rules cache |
| `lib/minion/alerts/` | Pair A | `Alert`, the pipeline consumer, the quiet sweep |
| `lib/minion/delivery/` | Pair B | `Delivery`, `Minion.Delivery.dispatch/1`, workers |
| `lib/minion/channels/` | Pair B | `Minion.Channel` and one module per channel |
| `lib/minion_web/live/`, `lib/minion_web/components/` | shared | LiveView pages, layout, alert components |

The seam between the pairs is `Minion.Delivery.dispatch(alert)`. Pair A calls it for every new alert; Pair B implements it.

## Running locally

```
docker compose up -d     # Postgres :5433, Redpanda :19092 (console :8080), Mailpit :8025
mix setup                # deps, database, migrations, seeds
mix phx.server           # http://localhost:4000
```
