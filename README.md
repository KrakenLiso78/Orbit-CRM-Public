# Orbit CRM Public

Orbit CRM is a private personal CRM for ongoing professional networking and career development. Companies, relationships, market signals, opportunities and applications connect to one managed record so the owner can decide and act without losing context.

This independent, AGPL-3.0-only distribution includes the bilingual dashboard, owner-scoped database schema and business operations, synthetic regression tests and an optional macOS conversational bridge.

No real contacts, applications, CVs, private reports, profiles, deployment configuration or development history are included. This project provides software for your own installation. It does not provide access to the creator's application, database or records.

## Product and public scope

The product model is one private web application backed by Supabase PostgreSQL. The browser is the visual interface; conversational workflows can capture and update information through narrow authorised tools. Both channels use the same CRM record. Publishing this source does not make an installed CRM public: access to records must remain limited to their authenticated owner.

The public source provides the CRM dashboard, application history, job and fit-assessment views, market-signal views, execution-history views and reviewed database operations. It is an independently validated source snapshot, not a hosted service or an automatic mirror of the original private repository. Later private changes are not included unless explicitly reviewed and exported.

Cloning the repository does not provision a backend, populate a CRM, run job discovery or quarterly research, configure an AI provider, or activate schedules. The landing page is a neutral source-distribution page, not a copy of private analytical reports. The example company universe and regression fixtures are synthetic.

## Capabilities

| Capability | Primary responsibility |
|---|---|
| Professional relationships | Manage companies, contacts, interactions and ongoing networking history. |
| Opportunities | Preserve vacancies and distinguish them from relationship-led opportunities. |
| Fit Scoring | Record role-to-profile assessments with evidence, preferences, constraints and explainable, versioned reasoning. |
| Applications and materials | Preserve candidate decisions, confirmed submissions, outcomes and references to exact material versions in the installer's private backend. |
| Actions and follow-ups | Manage commitments, due actions, assistant proposals and completion history. |
| Market Intelligence | Store and present evidence-backed sector and company context for professional decisions. |

These are product responsibilities supported by the source model and interfaces, not a promise that every research or assistant workflow runs out of the box. External discovery, assessment and conversational processing require the installer's own configuration and authorised inputs.

Orbit CRM is the source of truth. The conversational assistant and web interface are access channels, not separate databases. The operational dashboard is the initial working view, not another capability. A high fit score is neither a submitted application nor a probability of hiring. Creating an opportunity does not establish a confirmed application, and assistant proposals remain distinct from accepted commitments.

The foundational journey is **capture an interaction → recover context → review a follow-up → complete it → retain history**. The dashboard exposes upcoming tasks, recent interactions, completed tasks, opportunities and applications; additional views show assessed jobs, market signals and execution history. Recorded narrative text retains its source language while interface labels support English and Spanish.

## Workflow details in this distribution

### Context, follow-ups and application history

Record dialogs recover owner-scoped context and structure recorded notes without rewriting the original text. The task editor supports comments and controlled state changes through versioned business operations, with authoritative readback, retry keys and conflict detection. Stored priority and application totals describe recorded CRM information; they do not establish a candidate decision or an action's completion.

Application history preserves explicitly recorded submissions and outcomes independently of job-posting availability. A disappeared or closed vacancy must not become a rejection or withdrawal by inference. Exact material and profile versions remain historical references even when the installer adds newer versions.

Pursuing an eligible monitored posting creates or reuses one linked opportunity, verifies the result, refreshes the CRM and opens the recorded official source for manual submission. It does not submit or record an application on the candidate's behalf. Dismissing a role retains its history rather than deleting the underlying evidence.

### Source radar and fit assessment

The source radar exposes the configured company sources, cadence, actual check freshness and coverage state separately from shortlisted vacancies. Registering a careers source is not proof of exhaustive vacancy discovery. Blocked, unavailable or manual-review sources must retain their limitations; incomplete enumeration is not evidence of zero vacancies or complete recall.

Fit assessment uses the installer's own approved profile and versioned rubric. Geography, work arrangement, role priorities, evidence gaps and confidence should be explicit rather than inferred. Discovery and candidate decisions remain separate from scoring: a low score does not erase a discovered role, and a high score does not establish a submission. The public distribution contains no creator profile, personal location preference or installed scoring configuration.

Market-signal views preserve source links, dates and suggested actions. Execution history distinguishes successful, partial and failed runs and their recorded outcomes. A partial research run cannot silently promote itself to a validated analytical baseline. No private quarterly report, financial dataset or historical company forecast is supplied with this source.

### Optional weekly career guidance

The shipped schema and conversational bridge provide `get_weekly_career_guidance_context`, `record_weekly_career_guidance` and `read_back_weekly_career_guidance`. A configured authorised workflow can prepare exactly three ranked, evidence-bounded actions and persist them through the reviewed atomic operation. The current payload contract requires Spanish action reasons and next steps; the surrounding application interface remains bilingual.

The operation can create, reuse or update supported tasks and existing opportunity planning fields or evidence-supported lifecycle state. It cannot change contacts, applications or application outcomes, materials, or send messages. Equivalent open tasks should be reused; uncertain or stale evidence should lead to verification or waiting rather than an unsupported closure. Exact replay returns the original result instead of duplicating the plan or its effects.

This is a business-operation foundation, not a bundled autonomous advisor or an active weekly schedule. Each installer must configure their own reasoning workflow, authorisation and optional scheduler, then verify actual execution and readback. A configured schedule or a manual run does not prove that a scheduled run completed.

### Snapshot compatibility

This README describes the reviewed public source, not every later increment in private development. The newer all-state application register and combined filters, distinct employer-cancellation event, priority-first task ordering and coloured priority badges, revised dashboard lane arrangement, and executive 25-company graphic are not included in this snapshot. The public landing page and synthetic company example must not be interpreted as a copy of an operational market review or a preconfigured 25-company radar.

Those changes would require a separate reviewed code export and validation before they could be documented as available here. Updating this README does not import private code changes, data, deployment state, scheduled-run results or acceptance evidence.

## Architecture and operating boundaries

Supabase PostgreSQL holds the CRM record, Auth establishes the user session, and private Storage protects materials. Owner-scoped database policies and business operations enforce the record boundary. A web host's audience controls do not replace database or Storage authorisation; each installation must verify both.

The browser reads and updates the installer's backend. The optional conversational bridge uses a separate authenticated owner session and narrow operations with business readback. An assistant must report an unverified or failed write as unsaved rather than treating generated text as a persisted record.

Managed hosting is an installation choice, not a service supplied by this repository. Connectivity is required for the configured backend and any external model or fresh public-source research. If an installer adds local schedules, they depend on the local machine, running software, network and renewable owner session; they are not an independent managed scheduler.

Privacy of an installed CRM also depends on its configuration and operating practices:

- Send only user-selected input and the minimum authorised context to an external model. Input entered into a conversational provider is already outside the CRM's storage boundary.
- Provider processing and retention depend on the selected service and account controls. Private application access does not establish zero external retention.
- Public research should use non-personal queries, not private CRM history, CVs, materials or personal fit rationale.
- Keep secrets, real records, materials, exports, backups, screenshots and runtime logs outside Git. Never put service-role credentials in browser bundles, prompts or assistant configuration.
- Keep historical evidence and record versions distinguishable. A partial research execution must not silently replace a validated baseline, and a proposed action must not overwrite confirmed history.

## Source structure and specification-driven development

Orbit's development approach connects product requirements to contracts and models, plans, small tasks, synthetic regressions and verification evidence. Implementation, test success and acceptance are separate checkpoints: a build alone does not establish correct access control, recovery or a working hosted deployment.

The original private planning documents, operational reports and historical inputs are not distributed because they can contain installation-specific or personal context. The public distribution has its own requirements, plan, tasks and verification record:

| Path | Responsibility |
|---|---|
| [Distribution specification](docs/public-distribution/spec.md) | Public-source scope and privacy requirements. |
| [Distribution plan](docs/public-distribution/plan.md) | Independent export, validation and release approach. |
| [Distribution tasks](docs/public-distribution/tasks.md) | Preparation and publication checkpoints. |
| [Verification record](docs/public-distribution/verification.md) | Dated source, empty-backend, access and publication evidence. |
| [site/](site/) | Bilingual application, neutral landing page and development configuration. |
| [site/lib/](site/lib/) | CRM contracts, backend access, localisation and source regressions. |
| [Conversational bridge](integrations/supabase/call-report-mcp/) | Optional macOS owner authentication and narrow conversational operations. |
| [Database migrations](supabase/migrations/) | Generic schema, owner-scoped policies and business operations; no original installation-data migrations. |
| [Database regressions](supabase/tests/database/) | Synthetic transaction-based checks for operations, history, integrity and isolation. |
| [Public-content checker](scripts/check_public_content.py) | Source allowlist and checks for unsafe content or configuration. |

## Validated release baseline

The published baseline passed 24 Node regressions, lint, TypeScript and production build checks. In an isolated empty Supabase environment, all 40 migrations and 16 SQL regression files passed, alongside 18 Auth/REST/Storage checks and synthetic owner, signed-out and wrong-owner browser journeys. See the [verification record](docs/public-distribution/verification.md) for the exact evidence and limitations. These results do not certify a future installation or close its backup, restore and incident-response obligations.

The complete dependency audit reported zero vulnerabilities for that validated baseline; this is a dated result, not a guarantee about future advisories. A bounded local adapter backed by pinned `tinyglobby` replaces the former vulnerable `fast-glob` chain. It implements the synchronous compiler API only; future dependency updates must rerun its compatibility and adversarial-pattern tests.

## Development

Use Node.js 22.13 or later. From `site/`:

```sh
npm ci
npm run lint
npx tsc --noEmit --incremental false
npm run build
npm run dev
```

Without configuration, `/crm` displays a configuration boundary. Create an ignored `site/.env.local` using `site/.env.example` only after you have provisioned your own project. Never place a service-role key in frontend configuration.

Run source regressions from the repository root:

```sh
node --test site/lib/*.test.mjs site/vendor/safe-glob/*.test.mjs integrations/supabase/call-report-mcp/*.test.mjs
python3 scripts/check_public_content.py
```

## Independent backend

The application requires Supabase PostgreSQL, Auth and private Storage. The `supabase/migrations/` directory contains generic schema and owner-scoped operations, without installation data migrations. Apply them in filename order to a new empty compatible Supabase project. The SQL regressions in `supabase/tests/database/` use synthetic fixtures and transaction rollback; run them only in an isolated disposable test project, never against a live installation.

Create your own Auth user and corresponding `crm_owner_profiles` row using trusted administrative setup. Only a profile's authenticated owner should access its records. Keep sign-ups restricted to your intended users. Configure only your own URL and publishable key in the browser. Verify anonymous, wrong-owner and Storage access before adding personal data. Source-only tests do not validate an installed database or its access controls.

The example company universe is deliberately synthetic. Replace it with your own approved company configuration in your private installation. No scheduled research or AI provider is configured or activated by cloning this repository.

## Optional conversational bridge

The macOS bridge under `integrations/supabase/call-report-mcp/` reads your own `ORBIT_SUPABASE_URL` and a separate Keychain entry, defaulting to `Orbit CRM Public Local Session`. Use `orbit-call-report-auth.mjs` to establish your own session and `orbit-call-report-mcp.mjs` as the stdio MCP server. These are macOS-specific utilities; the browser application is independent of them. Authentication and write operations require explicit user input and verified business readback.

## Data and updates

Each installer owns the responsibility for hosting costs, backups, access control, data processing and incidents. No creator-operated service or incident support is promised. Any selected input sent to an external model is processed by that provider. No analytics or automated public mirroring of private records is configured.

Update this public project only by reviewing explicit source exports and repeating privacy checks. Do not copy the private repository's Git history, deployment bindings or operational datasets. Keep records, credentials, exports, screenshots and operational evidence outside source control. Secret scanners supplement human source review; they cannot guarantee that arbitrary future changes contain no private information. See [the public distribution documentation](docs/public-distribution/) for the requirements and verified release baseline.

## License and language

GNU Affero General Public License v3.0 only; see [LICENSE](LICENSE). Preserve the license and make corresponding source available to users of modified network deployments. The software carries no warranty.

Open-source distribution is separate from access to anyone's application or data. Maintained documentation, code comments, identifiers and commits are written in English. The application includes English and Spanish localisation; recorded input is not automatically translated.
