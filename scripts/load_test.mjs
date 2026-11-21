#!/usr/bin/env node
import { execSync } from "node:child_process";
import { mkdirSync, writeFileSync } from "node:fs";

const args = Object.fromEntries(
  process.argv.slice(2).map((arg) => {
    const [key, value] = arg.replace(/^--/, "").split("=");
    return [key, value ?? "true"];
  })
);

const BASE_URL = args.url || process.env.BASE_URL || "http://localhost:4000";
const INGEST_KEY = args.key || process.env.MINION_INGEST_KEY || "minion-dev-ops-key";
const STAGES = (args.stages || "500,1000,2000,4000,8000").split(",").map(Number);
const STAGE_SECONDS = Number(args.seconds || 20);
const BATCH = Number(args.batch || 1);
const MAX_IN_FLIGHT = Number(args.inflight || 512);
const HOSTS = Number(args.hosts || 200);
const DRAIN_SECONDS = Number(args.drain || 120);
const RUN = Date.now().toString(36);

const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

let sequence = 0;
const makeEvent = () => {
  sequence += 1;
  return sequence % 10 === 0
    ? { type: "CPU_HIGH", host: `cpu-${sequence % 50}`, load: 7.5, run: RUN }
    : { type: "DISK_FULL", host: `load-${RUN}-${sequence % HOSTS}`, used: 90 + (sequence % 10), run: RUN };
};

const percentile = (sorted, p) =>
  sorted.length === 0 ? null : sorted[Math.min(sorted.length - 1, Math.ceil(sorted.length * p) - 1)];

const metrics = async (path = "", method = "GET") => (await fetch(`${BASE_URL}/metrics${path}`, { method })).json();

const consumerLag = () => {
  try {
    const out = execSync("docker compose exec -T redpanda rpk group describe minion-pipeline", {
      encoding: "utf8",
      stdio: ["ignore", "pipe", "ignore"],
    });
    const match = out.match(/TOTAL-LAG\s+(\d+)/);
    return match ? Number(match[1]) : null;
  } catch {
    return null;
  }
};

async function runStage(rate) {
  const requestsPerSecond = rate / BATCH;
  const httpLatencies = [];
  const statuses = {};
  let sentRequests = 0;
  let acceptedEvents = 0;
  let inFlight = 0;
  let saturatedTicks = 0;

  await metrics("/reset", "POST");
  const started = performance.now();
  const deadline = started + STAGE_SECONDS * 1000;

  const send = async () => {
    inFlight += 1;
    const events = Array.from({ length: BATCH }, makeEvent);
    const body = JSON.stringify(BATCH === 1 ? events[0] : events);
    const t0 = performance.now();
    try {
      const res = await fetch(`${BASE_URL}/ingest/load-test`, {
        method: "POST",
        headers: { "content-type": "application/json", authorization: `Bearer ${INGEST_KEY}` },
        body,
      });
      await res.arrayBuffer();
      statuses[res.status] = (statuses[res.status] || 0) + 1;
      if (res.status === 202) acceptedEvents += BATCH;
    } catch (error) {
      statuses[error.cause?.code || "network_error"] = (statuses[error.cause?.code || "network_error"] || 0) + 1;
    } finally {
      httpLatencies.push(performance.now() - t0);
      inFlight -= 1;
    }
  };

  while (performance.now() < deadline) {
    const due = Math.floor(((performance.now() - started) / 1000) * requestsPerSecond);
    while (sentRequests < due) {
      if (inFlight >= MAX_IN_FLIGHT) {
        saturatedTicks += 1;
        break;
      }
      sentRequests += 1;
      send();
    }
    await sleep(5);
  }

  while (inFlight > 0) await sleep(10);
  const elapsed = (performance.now() - started) / 1000;
  const server = await metrics();
  const sorted = httpLatencies.sort((a, b) => a - b);

  return {
    target_events_per_s: rate,
    accepted_events_per_s: Math.round(acceptedEvents / elapsed),
    processed_events_per_s: Math.round(server.processed / elapsed),
    http_ms: { p50: round(percentile(sorted, 0.5)), p99: round(percentile(sorted, 0.99)) },
    statuses,
    client_saturated: saturatedTicks > 0,
    pipeline_latency_ms: server.latency_ms,
    lag_at_end: consumerLag(),
    vm: server.vm,
  };
}

const round = (value) => (value == null ? null : Math.round(value * 10) / 10);

async function drain() {
  const started = performance.now();
  await metrics("/reset", "POST");
  while ((performance.now() - started) / 1000 < DRAIN_SECONDS) {
    const lag = consumerLag();
    if (lag === 0) break;
    await sleep(1000);
  }
  const server = await metrics();
  return {
    seconds: round((performance.now() - started) / 1000),
    lag: consumerLag(),
    processed_while_draining: server.processed,
    pipeline_latency_ms: server.latency_ms,
  };
}

const pad = (value, width) => String(value ?? "-").padStart(width);

console.log(`Minion load test ${RUN}: ${BASE_URL}, batch ${BATCH}, ${STAGE_SECONDS}s per stage, max ${MAX_IN_FLIGHT} requests in flight`);
console.log(" target/s  accepted/s  processed/s  http p50  http p99  e2e p50  e2e p99   e2e max      lag  procs  runq  mem MB  errors");

const stages = [];
for (const rate of STAGES) {
  const stage = await runStage(rate);
  stages.push(stage);
  const errors = Object.entries(stage.statuses).filter(([code]) => code !== "202").map(([code, n]) => `${code}:${n}`).join(" ");
  console.log(
    [
      pad(stage.target_events_per_s, 9),
      pad(stage.accepted_events_per_s, 11),
      pad(stage.processed_events_per_s, 12),
      pad(stage.http_ms.p50, 9),
      pad(stage.http_ms.p99, 9),
      pad(stage.pipeline_latency_ms.p50, 8),
      pad(stage.pipeline_latency_ms.p99, 8),
      pad(stage.pipeline_latency_ms.max, 9),
      pad(stage.lag_at_end, 8),
      pad(stage.vm.processes, 6),
      pad(stage.vm.run_queue, 5),
      pad(stage.vm.memory_mb, 7),
      " " + (errors || "none") + (stage.client_saturated ? " (generator hit its in-flight cap)" : ""),
    ].join(" ")
  );
}

console.log("Draining the backlog…");
const drained = await drain();
console.log(`Drained in ${drained.seconds}s (lag ${drained.lag}), e2e p50 ${drained.pipeline_latency_ms.p50} ms, p99 ${drained.pipeline_latency_ms.p99} ms for ${drained.processed_while_draining} events processed while draining`);

mkdirSync("load-test-results", { recursive: true });
const file = `load-test-results/${new Date().toISOString().replace(/[:.]/g, "-")}-batch${BATCH}.json`;
writeFileSync(file, JSON.stringify({ run: RUN, base_url: BASE_URL, batch: BATCH, stage_seconds: STAGE_SECONDS, max_in_flight: MAX_IN_FLIGHT, stages, drained }, null, 2));
console.log(`Results saved to ${file}`);
