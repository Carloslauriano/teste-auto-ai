# One generic Process table; Connection is its own table

Every async timed action a Computer runs (Hack, currency transfer while connected, Log deletion) is modeled as a single `processes` table with a `kind` column, rather than one table per kind. This lets the lazy-resolution logic from ADR-0002 ("is this Process done?") be written once and reused for every kind, and lets new Process kinds (later tickets) add an enum value and, if needed, a nullable target column, instead of a new table.

A Connection (the ongoing state of a successfully completed Hack, until the attacker disconnects) is its own table, not derived from the originating Hack's Process row. A Connection outlives its Hack: the Hack Process resolves once and is done, but the Connection persists and gates further Processes (stealing currency, deleting a Log) that need to check "is there an active Connection", not "did some Hack Process succeed once".

## Consequences

Adding a Process kind never requires a migration beyond an enum value and, at most, a new nullable target column on `processes`. Any logic that needs to know whether an attacker is currently connected to a Target queries `connections`, never `processes`.
