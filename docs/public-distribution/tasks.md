# Public distribution tasks

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
