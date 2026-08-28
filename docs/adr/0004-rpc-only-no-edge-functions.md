# Authoritative logic lives only in Postgres RPC, not Edge Functions

ADR-0001 named both Postgres functions/RPC and Edge Functions as valid homes for authoritative logic. For this map's core loop, every authoritative action (starting or resolving a Process, currency transfers, Hack resolution, Log deletion) is a Postgres `SECURITY DEFINER` RPC function, called directly from the client via `supabase-js .rpc()`. We rejected routing these through Edge Functions: none of this logic needs Edge Functions' strength (low-latency, globally-distributed, non-database work like calling a third-party API) — it's all atomic multi-table reads/writes, which a Postgres RPC already handles as a single transaction. An Edge Function in front of an RPC would just add a network hop and a second codebase with no benefit.

## Consequences

If a future need arises for external HTTP calls or genuinely low-latency non-DB work, that's the point to introduce an Edge Function — not before.
