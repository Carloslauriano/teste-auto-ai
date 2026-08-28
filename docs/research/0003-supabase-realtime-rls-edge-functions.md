# Research: Supabase Realtime + RLS + Edge Functions patterns for authoritative multiplayer game state

GitHub issue: https://github.com/Carloslauriano/teste-auto-ai/issues/3
Map issue: https://github.com/Carloslauriano/teste-auto-ai/issues/2

Scope note: at the time of this research, `docs/adr/0001-supabase-as-backend.md`,
`docs/adr/0002-lazy-process-resolution.md`, and root `CONTEXT.md` referenced by the
issue brief did not yet exist in this worktree. This research proceeds from the
constraints restated in the issue/task brief directly: (1) authoritative game logic
must live server-side (Postgres RPC / Edge Functions), never trusted from the client;
(2) Processes resolve lazily — nothing writes to the DB in the background when a timer
expires; a Process is "done" once its recorded end time has passed, checked whenever
its state is next read; there is deliberately no cron/scheduled job.

All findings below are sourced from supabase.com/docs and supabase.com/blog (first-party)
unless explicitly marked UNVERIFIED. Quotes were retrieved via WebFetch against the live
docs pages on 2026-08-28.

---

## Question 1: Realtime vs lazy resolution

### Broadcast can be sent client-to-client, with no DB write required

Supabase Realtime Broadcast is fundamentally a WebSocket pub/sub mechanism, independent of
Postgres row changes. Per the docs:

> "Sending a message after subscribing will use WebSockets" — i.e. broadcast is dispatched
> over the socket layer, not derived from table changes.

Source: https://supabase.com/docs/guides/realtime/broadcast

This confirms: a client (or server) can call `channel.send({ type: 'broadcast', event: '...', payload: {...} })`
purely to notify other connected clients, with **no requirement that a row was written**.
This is the mechanism that can carry "you are being hacked, right now" the instant a Hack
process starts, decoupled from any DB write timing.

### Broadcast *from* Postgres (`realtime.send()` / `realtime.broadcast_changes()`)

Supabase also documents two SQL-callable functions for broadcasting from the database
itself, on the same broadcast doc page (https://supabase.com/docs/guides/realtime/broadcast):

- **`realtime.send(payload, event, topic, private)`** — general-purpose, does not require
  the payload to reflect a specific row's change:
  ```sql
  SELECT realtime.send(
    jsonb_build_object('hello', 'world'),  -- JSONB Payload
    'event',                                 -- Event name
    'topic',                                 -- Topic
    false                                     -- Public/Private flag
  );
  ```
- **`realtime.broadcast_changes(...)`** — purpose-built for emitting a table's change (via a
  trigger, `TG_OP`, `NEW`/`OLD`) into a broadcast channel instead of relying on the
  `postgres_changes` WAL-replication path:
  ```sql
  CREATE OR REPLACE FUNCTION public.your_table_changes()
  RETURNS trigger SECURITY DEFINER SET search_path = ''
  AS $$
  BEGIN
      PERFORM realtime.broadcast_changes(
        'topic:' || NEW.id::text,
        TG_OP, TG_OP, TG_TABLE_NAME,
        TG_TABLE_SCHEMA, NEW, OLD);
      RETURN NULL;
  END;
  $$ LANGUAGE plpgsql;

  CREATE TRIGGER broadcast_changes_for_your_table_trigger
  AFTER INSERT OR UPDATE OR DELETE ON public.your_table
  FOR EACH ROW EXECUTE FUNCTION your_table_changes();
  ```

Both are genuinely first-party, documented Supabase mechanisms (they live in the `realtime`
schema shipped with the platform). `realtime.broadcast_changes` still requires a trigger tied
to an actual row write (it fires `AFTER INSERT OR UPDATE OR DELETE`), so it does not, by
itself, let you broadcast something that has no underlying row event — but `realtime.send()`
can be called from *any* SQL context (including one invoked by an RPC that does other writes),
without requiring the broadcasted payload to correspond 1:1 to a row change.

### Is Postgres `NOTIFY`/`LISTEN` relevant to Supabase Realtime?

Not found in the Broadcast/Postgres-changes docs pages fetched. Supabase's own Realtime
server does not appear to be documented as consuming raw `pg_notify`/`LISTEN` as a public
integration point for client-facing Realtime — the two documented server-side mechanisms are
(a) the WAL-based `postgres_changes` publication mechanism and (b) `realtime.send` /
`realtime.broadcast_changes` calls into the `realtime` schema. **Whether Supabase Realtime's
internal Elixir/Phoenix implementation uses `LISTEN`/`NOTIFY` under the hood was not verified
against primary docs in this pass — mark as UNVERIFIED / not found in official docs** (this
would require reading the Realtime server source on GitHub, which was out of scope for this
pass given time; flagged here for a follow-up if needed).

### `postgres_changes` fires only on real row writes — confirmed

> "Use the `event` parameter to listen only to a specific database event. `event` can be
> `INSERT`, `UPDATE`, `DELETE`, or `*`"

Source: https://supabase.com/docs/guides/realtime/postgres-changes

The docs describe `postgres_changes` as built on Postgres's publication/replication
mechanism (`supabase_realtime` publication, toggled per table), which is fundamentally a WAL
(Write-Ahead Log) change-capture mechanism. There is no documented "virtual" or "computed"
event support — only genuine row mutations produce events. This directly confirms the
framing in the issue: **`postgres_changes` cannot itself notify about a Process's lazy
resolution, because nothing writes a row when a Process's timer merely elapses.**

### Reconciling "no background job" with a Target needing to learn they're being hacked, live

Based on the above, the pattern that reconciles the ADR-0002 constraint with live
notification is:

1. **Hack start = a real row write.** Starting a Hack process is a normal authoritative
   write (INSERT into a `processes`/`hacks` table via RPC or Edge Function). This is a
   genuine row event, so `postgres_changes` (or a `realtime.broadcast_changes` trigger on
   that same INSERT) fires naturally and instantly notifies the Target's client. **No
   special-casing needed for the start of a Hack** — it's an ordinary write-triggers-event
   flow.
2. **Hack end/resolution = lazy, no row write at expiry.** Per ADR-0002, nothing writes a row
   the moment the timer elapses. Consequently there is no `postgres_changes` event at the
   exact resolution instant. The client that needs to know the process finished must either:
   - **Poll on read** — re-check `ends_at <= now()` client-side or via an RPC the next time
     the relevant screen is viewed/refreshed (this is exactly the ADR-0002 model: "done" is
     a property computed from `now() > ends_at`, not a row state).
   - **Client-side timer UI** — since the client already knows `ends_at` (it was returned
     when the Hack started, via the INSERT's realtime event or the RPC's response), the
     client can render a local countdown and flip its own UI to "resolved-looking" at
     `ends_at`, without waiting for a server round-trip. The *authoritative* resolution
     (updating balances, logs, etc.) still only happens lazily, the next time any RPC
     touches that process's row (e.g., the player or the target opens a screen that reads
     it, or attempts another action gated on it) — consistent with ADR-0002's "no cron"
     rule.
   - There is no documented Supabase-specific mechanism for "notify me exactly at a future
     timestamp with no row write and no cron" — this is an application-level gap that
     Supabase Realtime does not fill, and no doc claims otherwise. This part of the
     reconciliation (client-side countdown + lazy authoritative re-check on next read) is an
     architectural inference from the ADR text combined with the documented behavior of
     `postgres_changes`/broadcast, not something asserted as a named "pattern" in Supabase's
     own docs — **flagging this synthesis as our own conclusion, not a documented Supabase
     recommendation.**

### Confirm/refute framing: "start of a Hack is an INSERT (fires postgres_changes); only the end is lazy"

**Confirmed**, based on the docs above. `postgres_changes` requires and only fires on actual
INSERT/UPDATE/DELETE (https://supabase.com/docs/guides/realtime/postgres-changes). If the
Hack's start is implemented as an INSERT row (e.g., a new `processes` row with
`kind = 'hack'`, `starts_at`, `ends_at`), that INSERT is a real write and will fire
`postgres_changes` (and/or a `realtime.broadcast_changes` trigger) to subscribed/authorized
clients immediately. Nothing in the docs contradicts this. The *end* of the Hack, per
ADR-0002, does not correspond to any row write at the moment of expiry — so no
`postgres_changes`/broadcast event occurs at that instant; resolution is only observed when
something later reads (and, per ADR-0002's model, writes/finalizes) that row.

---

## Question 2: RLS patterns for adversarial multiplayer data

Primary source used: https://supabase.com/docs/guides/database/postgres/row-level-security

### EXISTS subqueries referencing other tables

The docs' "Avoid recursive policies" section shows exactly the shape requested — a policy on
one table (`lists`) conditioned on rows existing in a *different* related table
(`list_members`):

```sql
create policy "members read lists" on lists for select to authenticated
using (
  exists (
    select 1 from list_members m
    where m.list_id = lists.id
    and m.user_id = (select auth.uid())
  )
);
```

This is precisely the "Player B can read a subset of Player A's row because a relationship
row exists" shape needed for "Target can see they're being hacked because an active Hack/
Connection row links Attacker to Target." Note the docs flag a **recursion hazard**: if
`list_members`'s own policy in turn queries `lists`, you get a cross-referencing policy loop;
their documented fix is to move the cross-table check into a `security definer` function
rather than a raw inline subquery, to break the recursive policy evaluation chain.

### Security definer functions to expose limited access

Docs show wrapping the cross-table check in a `SECURITY DEFINER` function to avoid the
recursion issue above:

```sql
create function private.has_good_role() returns boolean
language plpgsql security definer set search_path = ''
as $$
begin
  return exists (
    select 1 from public.roles_table
    where (select auth.uid()) = user_id and role = 'good_role'
  );
end;
$$;
```

Guidance: "Set `search_path = ''` on every `security definer` function and schema-qualify
the names inside it" (to avoid search-path hijacking). Source: same RLS doc page above. This
is directly applicable to a `is_hacking(target_id)` / `has_active_hack(attacker, target)`
helper function used inside RLS policies on the `computers`/`processes` tables.

### Column-level privileges combined with RLS

Primary source: https://supabase.com/docs/guides/database/postgres/column-level-security

Column Level Security is documented as an advanced, GRANT-based mechanism layered under RLS,
explicitly **not the default recommendation** ("an advanced feature" — the docs prefer RLS +
role/relationship tables for most cases). Example:

```sql
revoke update on table public.posts from authenticated;
grant update (title, content) on table public.posts to authenticated;
```

and to narrow further:

```sql
revoke update (title) on table public.posts from authenticated;
```

Combined with a normal row policy:

```sql
create policy "Allow update for owners" on posts for update
using ((select auth.uid()) = user_id);
```

Constraint: "Restricted roles cannot use the wildcard operator (`*`) on the affected table" —
callers must select explicit columns. For a hacked Computer's limited read ("Target's public
IP/hostname visible to an active attacker, but not their bank balance"), this GRANT-based
column restriction is a real, documented Supabase-supported primitive, usable in combination
with an EXISTS-based RLS row policy.

### Views with `security_invoker`

Same RLS doc page, "Expose a view safely" section:

```sql
create view <VIEW_NAME> with(security_invoker = true) as select <QUERY>
```

Documented as a Postgres 15+ feature: a `security_invoker` view runs with the *querying
user's* privileges (and is therefore subject to the underlying tables' RLS policies), rather
than the view owner's privileges. This is the recommended way to expose a "limited public
view of a Computer" (e.g. a `public_computer_profile` view joining only non-sensitive
columns) while still deferring to the base tables' RLS for row-level gating — i.e., it can be
combined with #1 (EXISTS-based policy) and #3 (column-limited GRANT) to build the "Target
row, limited subset, visible only while an active Hack exists" access shape end-to-end.

---

## Question 3: Edge Functions vs Postgres functions/RPC

Primary source: https://supabase.com/docs/guides/database/functions

Exact quote:

> "For data-intensive operations, use Database Functions, which are executed within your
> database and can be called remotely using the REST and GraphQL API. For use-cases which
> require low-latency, use Edge Functions, which are globally-distributed and can be written
> in Typescript."

This is the primary, first-party framing: **Database Functions (Postgres, callable via
`.rpc()`) are the documented choice for data-intensive/multi-table logic**, because they
execute inside Postgres itself and can participate in a single transaction; **Edge Functions
are positioned for low-latency, globally-distributed, non-DB-heavy work** (e.g. webhooks,
third-party API integration) rather than as the place to implement atomic multi-table
game-rule enforcement.

The docs page fetched does not contain an explicit side-by-side statement about
transactions/atomicity beyond this framing (no further comparison table was found on that
page). Supabase's own docs do **not** appear to document `supabase-js`/PostgREST as
supporting client-driven multi-statement transactions — Edge Functions calling out to
PostgREST (`.from(...).update(...)`) issue separate HTTP calls per statement with no shared
transaction; **an Edge Function that needs several table writes to be atomic must delegate
that atomicity to a single Postgres RPC call** (a `SECURITY DEFINER` function doing all the
reads/writes inside one PL/pgSQL function body, which Postgres runs as one transaction by
default). This composition (Edge Function as thin HTTP/webhook layer → calls one Postgres RPC
that does the atomic multi-table work) is consistent with, but not verbatim quoted from, the
docs — **flagging the "Edge Function calls one RPC for atomicity" composition as an inference
from the documented division of labor, not an explicit quoted recommendation** from Supabase.

**Conclusion for "Hack resolution" specifically:** given it needs to atomically read multiple
rows (attacker, target, process), validate, and write multiple rows (process state,
logs, balances) — the documented guidance points to a **Postgres `SECURITY DEFINER` RPC
function**, not an Edge Function, as the correct place for that logic.

---

## Question 4: Prior art

### Genuine, verified repos found (client-side realtime demos — NOT idle/incremental games with server-authoritative lazy resolution)

- **joshenlim/supabase-mog** — https://github.com/joshenlim/supabase-mog — confirmed to
  exist; README: "Simple HTML canvas multiplayer game, built with Vue and Supabase. Features
  basic 2D movements, jumping and collision detection with platforms." Author is a Supabase
  team member (DevRel), so this is a reasonably credible reference for Realtime patterns, but
  it is a live-action collision-detection demo, not an idle/incremental or lazy-resolution
  game.
- **Supabase's own multiplayer.dev showcase**, announced at
  https://supabase.com/blog/supabase-realtime-with-multiplayer-features — first-party
  (Supabase's own blog). Demonstrates Presence (via CRDTs, for "who's online") and Broadcast
  (for ephemeral events like cursor movement) at scale (20-node global cluster, Next.js +
  Phoenix/Elixir Realtime). The post mentions "a server clock which broadcasts a timer to
  every connected client (e.g. auction sites)" as a suggested extension — relevant as a
  primitive for a live countdown UI, but this is a suggested-use-case aside, not a worked
  example, and not a game.
- **gaborcselle/supabase-realtime-experiment** —
  https://github.com/gaborcselle/supabase-realtime-experiment — a small "claim-a-rectangle"
  realtime toy, not verified in depth beyond the search summary; adjacent but not idle-game
  prior art.
- **yallurium/supaquiz** — a multiplayer trivia game (Supabase Launch Week hackathon entry)
  using Realtime for synchronized game-start; again, not idle/incremental, not
  server-authoritative-timer prior art.

### Explicitly not found

**No genuine open-source Supabase-based idle/incremental game, and no Supabase-based clone
or reimplementation of Hacker Experience (or comparable "async timed process" hacking game),
was found.** Searches for "Hacker Experience clone Supabase" and "Supabase idle/incremental
game" returned only unrelated Hacker-News-clone tutorials (which are about the Y Combinator
news aggregator "Hacker News", not the hacking game "Hacker Experience") and generic realtime
demo games listed above. **This should be stated plainly rather than inventing a repo: there
is no verified prior-art project combining Supabase + lazy/no-cron timed process resolution +
adversarial multiplayer RLS that this research could locate.** Supabase's official
showcase/examples listing (supabase.com/docs — "Examples") was not exhaustively crawled
page-by-page in this pass; if a more targeted trawl of that list is wanted, it should be done
as a follow-up rather than asserted here.

---

## Summary of unverified / gaps

- Whether Supabase Realtime's server internals use Postgres `LISTEN`/`NOTIFY` — not
  confirmed from docs pages fetched; would need Realtime source-code inspection.
- The "Edge Function as thin layer calling one atomic Postgres RPC" composition is a
  reasonable inference from the documented division of labor, not a verbatim documented
  recommendation.
- No genuine idle-game / lazy-resolution-pattern prior art on Supabase was found; this is
  reported as a negative finding, not as "none exists" in an absolute sense (only that this
  research pass could not verify any).
