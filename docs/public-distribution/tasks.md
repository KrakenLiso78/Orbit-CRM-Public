# Public distribution tasks

## Independent installation guide

- [x] P019 Specify independent onboarding and privacy outcomes in `spec.md`, then plan documentation validation in `plan.md` before editing README (PUB-017).
- [x] P020 Update README prerequisites, own-project migrations/Auth owner, ignored frontend configuration, first sign-in, optional bridge/hosting, safe upgrades and troubleshooting; validate links, commands, public content and secret scan, publish docs only and verify anonymous readback/private-origin visibility (PUB-017). Evidence: `installation-guide-verification-2026-10-12.md`; unauthenticated README hash matched and private origin was read back as PRIVATE.

## Controlled update

- [x] P011 Specify observable update outcomes and boundaries in `spec.md` before implementation (PUB-012–016).
- [x] P012 Plan selective export, synthetic market demo, isolated validation and publication in `plan.md` after specification (PUB-012–016).
- [x] P013 Export `site/app/crm/`, `site/lib/orbit-crm.ts`, localisation, MCP cancellation metadata and six new migrations/three SQL regressions; preserve all public-only repairs and neutral configuration (PUB-012–013/PUB-015–016).
- [x] P014 Port `site/app/rank-flow.tsx`, `site/lib/rank-flow.mjs` and types; author synthetic fixtures and `/demo/market` with bilingual narrative-first layout and filterable companies (PUB-014).
- [x] P015 Run source/privacy/history/dependency/build checks and add regressions for the demo and register filters; fix candidate-only issues without touching the private checkout (PUB-012–016).
- [x] P016 Replay the complete schema into an isolated empty backend; run all synthetic SQL and actual owner/foreign/anonymous Auth/REST/Storage checks (PUB-015).
- [x] P017 Verify synthetic desktop/narrow ES/EN browser journeys, register filtering/context, priority badges and demo ordering/overflow; record bounded evidence under `docs/public-distribution/` (PUB-012–015).
- [x] P018 Update README availability statements, commit/push public source only, verify anonymous readback and unchanged private-origin visibility, then tear down identified temporary services (PUB-016). Evidence: `update-verification-2026-10-12.md`; anonymous clone installation/tests/lint/types/build passed, private origin remains PRIVATE and the temporary runtime was destroyed.

- [x] P001 Record approved outcome, boundaries and acceptance (PUB-001–007).
- [x] P002 Export allowlisted source and replace instance-specific configuration/data (PUB-001–004).
- [x] P003 Review literals, assets, metadata and run content/secret scans (PUB-002–005).
- [x] P004 Run synthetic source tests, lint, types and unconfigured build (PUB-004–005).
- [x] P005 Replay generic migrations on an isolated empty compatible database; run SQL and service-level access tests (PUB-004–005). All 40 migrations, 16 SQL regression files and 18 local Auth/REST/Storage checks passed; signed-out browser boundary observed separately.
- [x] P005a Guard optional RLS helper privilege revocation and verify absent/present environments (PUB-008).
- [x] P005b Repair repeated policy replay and recheck final owner-only predicates (PUB-009).
- [x] P005c Pin available compatible dependency fixes and assess remaining advisories before publication (PUB-009). `fflate` patched and the vulnerable glob chain replaced; complete audit reports zero vulnerabilities.
- [x] P005d Verify application/task context fields and final supported/exclusive relationships (PUB-010).
- [x] P006 Initialise independent public history with neutral identity and audit all objects (PUB-001).
- [x] P007 Create separate GitHub repository; verify anonymous clone, license, content and private origin visibility (PUB-006). Public `main` baseline matched the unauthenticated clone, AGPLv3 was detected and the existing development repository remained PRIVATE.
- [x] P008 Record public verification and future controlled export policy (PUB-007).
- [x] P009 Implement the bounded glob adapter; test compatibility and malicious-pattern rejection, regenerate the lockfile and require a zero-finding complete npm audit (PUB-011).
- [x] P010 Repeat source/privacy/history checks, build, local runtime and isolated database/API regression before publication (PUB-005/PUB-011). Clean installation, 24 Node tests, lint/types/build, 40 migrations, 16 SQL files, 18 service-level access checks and owner/logout/wrong-owner browser journeys passed.
