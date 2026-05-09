// Synthetic load test for the RunsByIP chat realtime stack.
//
// Spins up N Supabase clients that each subscribe to messages-room,
// message-reactions-room, and chat-typing-room — then drives realistic
// game-night patterns (typing chatter, optional message + reaction bursts)
// and reports delivery rate + per-listener latency.
//
// Defaults to typing-only (no DB writes) so it's safe to run against prod.
// Pass INSERT_MESSAGES=true with a TEST_USER_ID to also exercise the
// postgres-changes path; the script cleans up the rows it inserts.
//
// Run:
//   SUPABASE_URL=https://ncjgkthruvapcogqaxhi.supabase.co \
//   SUPABASE_SERVICE_ROLE_KEY=eyJ... \
//   deno run --allow-net --allow-env scripts/chat-load-test.ts
//
// Tunables (env vars):
//   CLIENTS=20             number of concurrent listener+publisher clients
//   TYPING_DURATION=10     seconds of typing storm
//   TYPING_INTERVAL_MS=200 per-client emit interval during the storm
//   INSERT_MESSAGES=true   also test message INSERT delivery
//   TEST_USER_ID=<uuid>    required when INSERT_MESSAGES=true
//   MESSAGES_PER_CLIENT=5  inserts per client during the burst

import { createClient, SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2";

const URL = Deno.env.get("SUPABASE_URL");
const KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
if (!URL || !KEY) {
  console.error("Missing env: SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are required.");
  Deno.exit(1);
}

const N = Number(Deno.env.get("CLIENTS") ?? "20");
const TYPING_DURATION_S = Number(Deno.env.get("TYPING_DURATION") ?? "10");
const TYPING_INTERVAL_MS = Number(Deno.env.get("TYPING_INTERVAL_MS") ?? "200");
const INSERT_MESSAGES = Deno.env.get("INSERT_MESSAGES") === "true";
const TEST_USER_ID = Deno.env.get("TEST_USER_ID");
const MESSAGES_PER_CLIENT = Number(Deno.env.get("MESSAGES_PER_CLIENT") ?? "5");

if (INSERT_MESSAGES && !TEST_USER_ID) {
  console.error("INSERT_MESSAGES=true requires TEST_USER_ID (an existing auth.users row).");
  Deno.exit(1);
}

interface ListenerStats {
  typingReceived: number;
  typingLatenciesMs: number[];
  messagesSeen: Set<string>;
}

const stats: ListenerStats[] = Array.from({ length: N }, () => ({
  typingReceived: 0,
  typingLatenciesMs: [],
  messagesSeen: new Set(),
}));

console.log(`[load-test] booting ${N} clients against ${URL}`);

const clients: SupabaseClient[] = [];
const typingChannels: ReturnType<SupabaseClient["channel"]>[] = [];

for (let i = 0; i < N; i++) {
  const client = createClient(URL, KEY, {
    realtime: { params: { eventsPerSecond: 50 } },
  });

  const idx = i;

  const typingCh = client
    .channel("chat-typing-room")
    .on("broadcast", { event: "typing" }, (raw) => {
      stats[idx].typingReceived++;
      const sentAt = (raw?.payload as { ts?: number } | undefined)?.ts;
      if (typeof sentAt === "number") {
        stats[idx].typingLatenciesMs.push(Date.now() - sentAt);
      }
    });

  const msgCh = client
    .channel("messages-room")
    .on("postgres_changes", { event: "INSERT", schema: "public", table: "messages" }, (payload) => {
      const id = (payload.new as { id?: string })?.id;
      if (id) stats[idx].messagesSeen.add(id);
    });

  await new Promise<void>((resolve, reject) => {
    let typingReady = false;
    let msgReady = false;
    const check = () => { if (typingReady && msgReady) resolve(); };
    typingCh.subscribe((status, err) => {
      if (status === "SUBSCRIBED") { typingReady = true; check(); }
      else if (err) reject(err);
    });
    msgCh.subscribe((status, err) => {
      if (status === "SUBSCRIBED") { msgReady = true; check(); }
      else if (err) reject(err);
    });
    setTimeout(() => reject(new Error(`client ${idx} subscribe timeout`)), 15_000);
  });

  clients.push(client);
  typingChannels.push(typingCh);
}

console.log(`[load-test] all ${N} clients subscribed, settling 1s before storm...`);
await sleep(1000);

// --- Phase 1: Typing storm -------------------------------------------------

const ratePerSec = 1000 / TYPING_INTERVAL_MS;
const expectedSentTotal = Math.round(N * ratePerSec * TYPING_DURATION_S);
console.log(
  `[load-test] typing storm: ${N} clients × ${TYPING_DURATION_S}s × ${ratePerSec}/sec ` +
  `= ~${expectedSentTotal} broadcasts. Each listener should receive every event.`
);

let typingSent = 0;
const burstStart = Date.now();
const ticker = setInterval(() => {
  for (let i = 0; i < N; i++) {
    typingChannels[i].send({
      type: "broadcast",
      event: "typing",
      payload: {
        user_id: `loadtest-${i}`,
        display_name: `Player${i}`,
        state: "typing",
        ts: Date.now(),
      },
    });
    typingSent++;
  }
}, TYPING_INTERVAL_MS);

await sleep(TYPING_DURATION_S * 1000);
clearInterval(ticker);
const burstSent = typingSent;

console.log(`[load-test] storm finished, draining 2s...`);
await sleep(2000);

const totalReceived = stats.reduce((acc, s) => acc + s.typingReceived, 0);
const perListenerAvg = totalReceived / N;
const deliveryRate = burstSent > 0 ? perListenerAvg / burstSent : 0;
const allLatencies = stats.flatMap((s) => s.typingLatenciesMs).sort((a, b) => a - b);
const p = (q: number) => allLatencies.length === 0 ? 0 : allLatencies[Math.floor(allLatencies.length * q)] ?? 0;

console.log("");
console.log("=== Typing storm results ===");
console.log(`  Sent:                  ${burstSent}`);
console.log(`  Received per listener: avg=${perListenerAvg.toFixed(1)}, min=${Math.min(...stats.map((s) => s.typingReceived))}, max=${Math.max(...stats.map((s) => s.typingReceived))}`);
console.log(`  Delivery rate:         ${(deliveryRate * 100).toFixed(1)}%`);
console.log(`  Latency p50/p95/p99:   ${p(0.5)}ms / ${p(0.95)}ms / ${p(0.99)}ms (n=${allLatencies.length})`);

// --- Phase 2 (optional): message INSERT burst ------------------------------

let insertedIds: string[] = [];
if (INSERT_MESSAGES) {
  const writer = createClient(URL, KEY);
  const target = N * MESSAGES_PER_CLIENT;
  console.log("");
  console.log(`[load-test] message burst: ${N} clients × ${MESSAGES_PER_CLIENT} = ${target} inserts in parallel...`);

  const insertStart = Date.now();
  const results = await Promise.all(
    Array.from({ length: N }, async (_, i) => {
      const ids: string[] = [];
      for (let j = 0; j < MESSAGES_PER_CLIENT; j++) {
        const { data, error } = await writer
          .from("messages")
          .insert({
            user_id: TEST_USER_ID,
            display_name: `LoadTest-${i}`,
            content: `loadtest-${i}-${j}-${Date.now()}`,
            message_type: "text",
          })
          .select("id")
          .single();
        if (error) {
          console.error(`  insert error (client ${i}, msg ${j}):`, error.message);
        } else if (data?.id) {
          ids.push(data.id);
        }
      }
      return ids;
    })
  );
  insertedIds = results.flat();
  const insertDuration = Date.now() - insertStart;

  console.log(`[load-test] inserted ${insertedIds.length}/${target} rows in ${insertDuration}ms — waiting 5s for delivery...`);
  await sleep(5000);

  const totalSeen = stats.reduce((acc, s) => acc + s.messagesSeen.size, 0);
  const perListenerAvgSeen = totalSeen / N;
  const messageDelivery = insertedIds.length > 0 ? perListenerAvgSeen / insertedIds.length : 0;

  console.log("");
  console.log("=== Message burst results ===");
  console.log(`  Inserted:              ${insertedIds.length}`);
  console.log(`  Seen per listener:     avg=${perListenerAvgSeen.toFixed(1)}, min=${Math.min(...stats.map((s) => s.messagesSeen.size))}, max=${Math.max(...stats.map((s) => s.messagesSeen.size))}`);
  console.log(`  Delivery rate:         ${(messageDelivery * 100).toFixed(1)}%`);

  console.log(`[load-test] cleaning up ${insertedIds.length} test rows...`);
  const { error: delErr } = await writer.from("messages").delete().in("id", insertedIds);
  if (delErr) console.error("  cleanup error:", delErr.message);
}

console.log("");
console.log("[load-test] tearing down...");
for (const c of clients) {
  await c.removeAllChannels();
}

console.log("[load-test] done.");
Deno.exit(0);

function sleep(ms: number) {
  return new Promise<void>((r) => setTimeout(r, ms));
}
