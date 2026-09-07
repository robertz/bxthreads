# db/

`schema.sql` is the full MySQL DDL for the `dismal` datasource (see [`boxlang.json`](../boxlang.json)), dumped directly from a live `dismal` MySQL instance — ground truth, not inferred from application code.

It also seeds the `Achievements` and `AchievementTiers` tables with the real achievement catalog (12 achievements, 5 tiers each). Those two tables have no in-app INSERT path — `models/services/AchievementService.bx` only ever reads them — so the app expects this catalog to already exist. No other table is seeded; `Users`, `Forums`, `Posts`, etc. start empty.

## Apply to a fresh server

```bash
mysql -u root -p < db/schema.sql
```

This creates the `dismal` database (if it doesn't exist), all 19 tables, and the achievement seed data. Verified against a fresh MySQL 8 database (`mysql -u root -p < db/schema.sql` completes with no errors, all tables created, 12/60 rows in `Achievements`/`AchievementTiers`).

Requires MySQL 8.0.13+ (uses generated columns and expression column `DEFAULT`s) and 8.0.16+ (enforced `CHECK` constraints).

## Notes

- Not a migrations system — this is a point-in-time dump. If the live schema changes, this file needs to be regenerated/updated by hand alongside it.
- `id_short` on `Users`/`Forums`/`Posts`/`Comments` is a generated column (`LEFT(BIN_TO_UUID(id), 8)`), not stored independently.
