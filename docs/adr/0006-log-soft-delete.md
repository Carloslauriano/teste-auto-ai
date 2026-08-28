# Log deletion is soft-delete

A Log entry, once removed by the Player who caused it (while still connected, per the domain rule), is soft-deleted via a `deleted_at` timestamp rather than a hard `DELETE`. Every read path filters `deleted_at IS NULL`, so a deleted Log is invisible to everyone — including the Target — exactly as if it had been hard-deleted. We kept the row rather than physically removing it so a deleted Log isn't unrecoverable at the storage layer, leaving room for future forensic or anti-cheat tooling without committing to what that tooling looks like now.
