# Lazy resolution for async Processes instead of cron

Timed Processes (cracking a password, hacking, deleting a Log) need to "complete" without a background scheduler doing the work. We considered pg_cron / a scheduled Edge Function sweeping for expired Processes, and rejected it: a Process is instead considered complete once its recorded end time has passed, computed whenever its state is next read (by the owner, or by whoever's checking it). No job ever marks it done.

## Consequences

Nothing reacts to a Process finishing unless something reads its state afterward. Any behavior that should fire automatically at completion (e.g. a Realtime notification) has to be triggered by a read that notices the Process just crossed its end time, not by a background sweep.
