# Independent installation guide review — 2026-10-12

PUB-017 was specified, planned and decomposed before README changes. Documentation now describes current published improvements and an ordered independent setup: clone, prerequisites, new Supabase project, migration preview/application, Auth user/profile bootstrap, ignored frontend configuration, first sign-in, validation, optional capture/hosting, safe upgrades and troubleshooting.

## Verified

- Installation flags were checked against Supabase CLI 2.120.0 command help and official CLI/migration/Auth documentation. The pinned npm CLI returned version 2.120.0.
- `supabase init` succeeded in a separate temporary folder containing a copy of the distributed migration directory. No cloud login, project link, remote migration, account creation or production query was performed.
- The owner bootstrap was checked against the existing Auth foreign key, profile schema and owner guard. No SQL example was executed against any live project.
- Frontend variable names, build-time replacement, ignored environment file, private Storage policies and macOS bridge requirements were checked against shipped source.
- README local links, heading anchors, fenced blocks and 46-migration count passed checks. Content allowlist, original identifier exclusion and redacted staged secret scan found no issues.
- Application source, migrations, regression tests, dependency inputs and neutral configuration remain byte-identical to the previously validated public feature update. No new application/database acceptance is claimed for documentation changes.

## Limits

This is command/schema/documentation verification, not a newly completed cloud installation or hosted deployment. The earlier isolated release evidence remains the source/runtime baseline. Each installer must verify their own project, permissions, owner identity, service configuration, access controls and backups before entering personal data. The guide includes no original instance credential, private URL, owner identifier or dataset.

Published documentation commit: `58b08f8`. Unauthenticated raw README readback matched local SHA-256 `de6cb25ffe3f4f5ac577af7adc1e38749915c32fefc7be206eb0281f14fffb51`. The original development repository was read back as PRIVATE after the push. P020 records completed documentation publication; no application or database change occurred.
