# Supabase as the game's backend

The game needs real-multiplayer persistence, auth, live push events, and server-authoritative logic (a client can't be trusted to resolve its own Hacks or currency transfers). We chose Supabase (Postgres, Auth, Realtime, Edge Functions) over a custom backend, trading some platform lock-in for not having to stand up and operate that infrastructure ourselves.

## Consequences

Authoritative game logic (Hack resolution, currency movement, Process completion) must live in Postgres functions or Edge Functions, never trusted from the client. Row-level security enforces that a Player can only read/write what their own Player account is entitled to.
