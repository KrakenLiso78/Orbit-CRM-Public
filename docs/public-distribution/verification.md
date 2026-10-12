# Public source candidate verification

Status: published and verified at [Orbit-CRM-Public](https://github.com/KrakenLiso78/Orbit-CRM-Public) on 12 October 2026.

## Passed

- Independent Git directory and neutral contributor identity; no private repository history, remotes or tags copied.
- Reviewed text-only source allowlist; no real records or original installation datasets distributed.
- Two installation-data migrations excluded; 40 generic migrations and 16 synthetic SQL regression files retained.
- Empty environment examples and neutral hosting configuration; distinct optional Keychain service.
- Twenty source regression tests passed.
- Lint, TypeScript and unconfigured production build passed.
- Gitleaks 8.30.1 staged-source scan: approximately 837 KB scanned, no leaks found, full redaction enabled.
- Project content checker: no findings.
- Independent initial-commit full-history Gitleaks scan: no leaks found.
- Additional original installation identifier and private application identifier comparison: no overlap in included source or compiled bundles.
- Official local Supabase CLI 2.120.0 with PostgreSQL 17.11 in an independent temporary container runtime, without a cloud project link or private checkout mount.
- Empty pre-migration public schema confirmed. All 40 public migrations replayed successfully without private data migrations or seed import.
- All 16 SQL regression files passed, including 33 referential-integrity pgTAP assertions and the existing RPC, idempotency, history and wrong-owner checks.
- Optional platform helper absent/present paths verified; unnecessary public execute permission is removed when present.
- Eighteen actual local Auth/REST/Storage checks passed: owner reads, wrong-owner exclusion, anonymous denial or empty results, invalid-session denial, protected RPCs, selected context and private object access. All fixtures were newly created synthetic users, records and text objects.
- Signed-out browser on the isolated configured application shows the login boundary, without any CRM record content.
- Final source tests, lint, TypeScript and unconfigured production build passed after portability corrections and the compatible `fflate` 0.7.5 override.
- Production-only npm dependency audit reported zero advisories.
- Compiled artifacts are excluded from Git and the source archive. A separate artifact scan detected Vinext's newly generated `prerenderSecret` in its server manifest; it is a local build credential, not an imported private installation credential. The manifest and all compiled artifacts remain outside the distributable source. No original private identifier matches were found in source or the unconfigured build.

## Resolved dependency finding

The original full npm audit contained six package entries sharing the root `braces` advisory [GHSA-vfj7-8cjw-p6xm](https://github.com/advisories/GHSA-vfj7-8cjw-p6xm). The vulnerable chain was removed by overriding the compiler's `fast-glob` dependency with the local `@orbit-crm/safe-glob` adapter backed by pinned `tinyglobby` 0.2.17. The override references a direct local development dependency so `npm ci` works reproducibly from a clean checkout. No advisory is suppressed. The separate compatible `fflate` 0.7.5 override is retained.

Repeated validation passed: clean offline `npm ci`, complete npm audit with zero vulnerabilities, 24 Node tests including four new glob/compiler regressions, lint, TypeScript and the unconfigured production build. The adapter rejects excessive length/count/nesting before traversal and preserves the actual dynamic-import plugin's extension alternatives and file discovery. No framework downgrade was necessary.

The empty local Supabase replay, all 16 SQL regression files, optional-helper guard and all 18 Auth/REST/Storage checks were repeated successfully. Browser checks confirmed the owner sees its synthetic task and context, logout removes record content, and a different owner sees zero foreign companies/tasks. Local runtime credentials and fixtures are excluded from the source baseline.

## Public readback

- GitHub visibility: PUBLIC; default branch: `main`; detected license: GNU AGPLv3.
- Baseline public commit: `98ff671e85a4629f569236234c95383c37ae6373`, created from the final reviewed export with no preparation or private development history.
- Clean unauthenticated Git clone succeeded with credential helpers and prompting disabled. Its commit matched the uploaded baseline exactly.
- All 119 source files passed the content checker. The complete independent public history passed Gitleaks with no findings. Original private installation and application identifiers had zero matches.
- The anonymous clone passed clean `npm ci`, all 24 Node tests, lint and TypeScript checks.
- The existing development repository was read back as PRIVATE before and after publication. No production database, Storage object, private deployment or private Git reference was changed.
- Public data examples and tests are synthetic. No compiled artifacts, environment credentials, original deployment bindings, real records, CVs, reports, backups, screenshots or operational logs are distributed.

Every future update requires an explicit reviewed source export and fresh checks. Repository publication does not provide access to any existing installation or its records.

Build results validate the exported source, not an installed Supabase service. Secret and identifier scanners supplement source review and do not prove absolute privacy for future arbitrary changes. Every update requires a fresh reviewed export.
