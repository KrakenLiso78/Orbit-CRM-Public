# Orbit CRM Public

Orbit CRM is a private personal CRM for ongoing professional networking and career development. Companies, relationships, market signals, opportunities and applications connect to one managed record so the owner can decide and act without losing context.

This independent, AGPL-3.0-only distribution includes the bilingual dashboard, owner-scoped database schema and business operations, synthetic regression tests and an optional macOS conversational bridge.

No real contacts, applications, CVs, private reports, profiles, deployment configuration or development history are included. This project provides software for your own installation. It does not provide access to the creator's application, database or records.

Start with [Install from scratch](#install-from-scratch-your-own-database). No invitation, credential or database export from the creator is needed.

## Latest published improvements

- All-state application register with combined filters, reset and record context; employer cancellation is distinct from candidate withdrawal.
- Priority-first tasks with text/colour badges and a task-first responsive dashboard; terminal applications retain history without occupying the current lane.
- Bilingual synthetic market graphic with 25 fictional companies, explicit missing values and narrative-first responsive presentation.
- Reviewed weekly-guidance operations, source radar and application/job history, with owner-scoped readback rather than inferred outcomes.

The [update verification](docs/public-distribution/update-verification-2026-10-12.md) records the tested source baseline. Installation steps below use only your own services and data.

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

The Applications tab provides the complete owner register with combined company, state, text, channel and inclusive submission-date filters, reset and record-context opening. Application history preserves explicitly recorded submissions and outcomes independently of job-posting availability. Rejected, withdrawn and cancelled records leave the current dashboard lane but remain in the register, history and total KPI. Cancellation means the employer cancels recruitment; withdrawal means the candidate leaves the process. A disappeared or closed vacancy must not become either outcome by inference. Exact material and profile versions remain historical references even when the installer adds newer versions.

Upcoming tasks sort by numeric priority before due date and before the display limit. Text badges identify priority, including an explicit missing value; colour is supplemental. Tasks, recent interactions and completed tasks precede opportunities and applications on desktop and narrow layouts.

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

This reviewed update includes the all-state application register and combined filters, distinct employer-cancellation event, priority-first task ordering and text/colour priority badges, and revised dashboard lane arrangement. The generic company range graphic is available at `/demo/market` with 25 newly authored fictional examples, bilingual narrative-before-graphic ordering, responsive full-width narrative and a filterable company list. Missing values remain explicitly missing. The demonstration never queries a backend and is not a real market report, company selection, forecast or preconfigured careers radar.

No original quarterly analysis, personal scoring rubric, installed schedule or private execution result is supplied. Future changes still require a separate reviewed code export and validation. The public landing page remains neutral; an installer must provision their own private service and data.

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

The initial baseline passed 24 Node regressions, lint, TypeScript and production build checks, 40 migrations, 16 SQL files and 18 local service-access checks; its [verification record](docs/public-distribution/verification.md) is retained unchanged. The controlled feature update passed 32 Node regressions, lint, TypeScript, production build, 46 migrations, 19 SQL regression files, 21 actual local service-access checks and synthetic responsive browser journeys. See the [update verification](docs/public-distribution/update-verification-2026-10-12.md) for exact scope and limitations. These results do not certify a future installation or close its backup, restore and incident-response obligations.

The complete dependency audit reported zero vulnerabilities for that validated baseline; this is a dated result, not a guarantee about future advisories. A bounded local adapter backed by pinned `tinyglobby` replaces the former vulnerable `fast-glob` chain. It implements the synchronous compiler API only; future dependency updates must rerun its compatibility and adversarial-pattern tests.

## Install from scratch: your own database

This path creates an empty CRM using a new hosted Supabase project and a locally running web application. It does not install or connect to the creator's instance. A plain PostgreSQL database is insufficient: the migrations also require Supabase Auth, Storage and platform roles. Self-hosting the full Supabase stack is a separate advanced deployment option.

The commands below use a POSIX shell (macOS/Linux, or an appropriately configured Windows shell such as WSL). The web application is not macOS-specific; the optional Keychain-backed conversational bridge is. Provider accounts, availability, costs and backups are your responsibility.

### 1. Prerequisites and source

Install Git, Node.js 22.13 or later with npm, and create your own Supabase account. Python 3 is needed only for the public-content checker. The examples pin Supabase CLI 2.120.0, used for release validation; `npx` may ask permission to download it. Do not install the CLI globally with npm. See the [official CLI setup](https://supabase.com/docs/guides/local-development/cli/getting-started).

```sh
git clone https://github.com/KrakenLiso78/Orbit-CRM-Public.git
cd Orbit-CRM-Public
node --version
npm --version
npx supabase@2.120.0 --version
```

The clone has source and synthetic tests only. Do not copy a private `.env`, database backup, existing deployment binding or Keychain session into it.

### 2. Create an empty project you own

In your Supabase dashboard, create a **new project** with PostgreSQL 17 compatibility, select your region and plan, and save the database password in your password manager. Wait until the project is ready. Do not use an existing unrelated database or a project containing real records for this first setup.

Find these values in your own project's settings: project reference, project URL and publishable API key. The database password is for trusted administration only. A publishable key is a browser client identifier, not owner authentication; correct grants and Row Level Security (RLS) are still required. Secret/service-role keys must never enter frontend configuration.

### 3. Initialise, link and apply the schema

Run from the repository root. `init` creates local CLI configuration; it does not create a cloud project. Replace `YOUR_PROJECT_REF` with the reference of the new project you just created. Authenticate interactively and enter passwords only at trusted terminal prompts, never in shell arguments, chat or Git.

```sh
npx supabase@2.120.0 init
npx supabase@2.120.0 login
npx supabase@2.120.0 link --project-ref YOUR_PROJECT_REF
npx supabase@2.120.0 db push --linked --dry-run
```

Check that the linked project is yours and the preview contains this repository's 46 migrations, not an unexpected migration set. Then apply and check them:

```sh
npx supabase@2.120.0 db push --linked
npx supabase@2.120.0 migration list --linked
```

Accept the confirmation only for your new empty project. The CLI applies versioned files in order and records migration history. The migrations create the generic schema, owner-scoped operations and private `orbit-materials` bucket; they do not import any CRM records. Do not add `--include-seed`, manually paste every migration, use `db reset` against a real database, or bypass a failed migration by removing security rules. Consult the [official migration workflow](https://supabase.com/docs/guides/local-development/database-migrations) if the CLI fails.

Keep generated project links/configuration private to your installation; do not commit them or your service values back to this public repository.

### 4. Create and register your own owner

In **Authentication → Users** of your new project, create your own email/password user using the dashboard's administrative user-creation action. Ensure the user is confirmed according to your project's email settings. Save its Auth user UUID. This is not your Supabase dashboard account or project reference.

In that same project's trusted SQL editor, replace the placeholder below with **your newly created Auth user UUID** and run it once:

```sql
insert into public.crm_owner_profiles (owner_id)
values ('REPLACE_WITH_YOUR_AUTH_USER_UUID'::uuid)
on conflict (owner_id) do nothing;

select owner_id from public.crm_owner_profiles
where owner_id = 'REPLACE_WITH_YOUR_AUTH_USER_UUID'::uuid;
```

The result must contain your own UUID. This administrative bootstrap registers the account that the reviewed operations recognise as an Orbit owner; it creates no companies, contacts or applications. Do not grant unrestricted client writes to work around a missing profile.

Keep the email/password provider enabled for this browser login, disable public sign-up if your installation is owner-only, and do not enable anonymous sign-in. The application has a sign-in form, not a self-service registration flow. Review [Auth configuration](https://supabase.com/docs/guides/auth/general-configuration) and [user management](https://supabase.com/docs/guides/auth/managing-user-data) for confirmation/recovery settings.

### 5. Configure only your own browser connection

From the repository root:

```sh
cp site/.env.example site/.env.local
cd site
npm ci
```

Open `site/.env.local` in your editor and replace the empty values with **your own project URL and publishable key**. These are placeholders, not usable credentials:

```dotenv
VITE_SUPABASE_URL=YOUR_OWN_SUPABASE_PROJECT_URL
VITE_SUPABASE_PUBLISHABLE_KEY=YOUR_OWN_PUBLISHABLE_KEY
```

Do not use the database password, a personal access token, a secret key or `service_role` here. `.env.local` is ignored by Git; confirm it remains untracked. The two `VITE_` values are compiled into the browser bundle, so privileged credentials are never appropriate. Restart development after changing them and rebuild before deploying changed values.

### 6. Start and sign in

From `site/`:

```sh
npm run dev -- --host 127.0.0.1
```

Open the **Local URL printed by the server**, then visit `/crm`. Use the email and password of the Auth user created in step 4. Expected result: an empty owner dashboard, zero CRM counts and no creator records. Check ES/EN and the empty Applications register. `/demo/market` is an independent fictional demonstration, not data loaded into your database.

Sign out and reload `/crm`: only the login boundary should remain. An unconfigured build instead shows the configuration boundary. Neither state should reveal records. Stop the local server with Ctrl+C when finished. `npm run dev` is a development server, not a production hosting service.

### 7. Validate before entering personal data

Run source checks from the repository root, then web checks from `site/`:

If continuing from step 6, stop the development server with Ctrl+C and run `cd ..` once to return from `site/` to the clone root before the following block.

```sh
node --test site/lib/*.test.mjs site/vendor/safe-glob/*.test.mjs integrations/supabase/call-report-mcp/*.test.mjs
python3 scripts/check_public_content.py
cd site
npm run lint
npx tsc --noEmit --incremental false
npm run build
npm audit
```

These checks do not certify your deployed backend. Before adding real data, verify owner reads/writes, signed-out denial, another user's inability to read your synthetic records, private Storage access, and your backup/restore procedure. Keep `orbit-materials` private; do not replace its policies with public access. The browser currently has no general-purpose material upload or full CRM creation form: capture uses reviewed business operations, not arbitrary client table writes.

The 19 SQL regression files under `supabase/tests/database/` are for an isolated disposable test project, not your live installation. They contain synthetic fixtures and rollback, but this is not permission to run acceptance fixtures against personal data. The [release evidence](docs/public-distribution/update-verification-2026-10-12.md) covers an isolated local stack; no fresh hosted project was provisioned to certify this README guide.

### 8. Add your own workflows, optionally host the app

The basic browser setup is now independent. For capture, use the optional macOS bridge below or implement a separately reviewed owner-authenticated integration. There is no bundled autonomous research service: configure your own profile, rubric, companies, official sources, AI workflow and schedules through reviewed operations. Do not copy the creator's preferences or automation files.

The company registry starts with a synthetic placeholder. Until you deliberately configure your own cohort and matching source registry, the Jobs radar may report that it cannot verify a complete registry; that is not a failed CRM installation or proof of zero vacancies. Its current UI retains 25-company labels. Adapting those labels/cohort to another scope is a separate source change. The synthetic demo never registers careers sources.

For remote web access, this source targets Cloudflare Workers through Vinext/Vite; it is not a generic static-only deployment. In your own Cloudflare account, review costs and access controls, build with your own frontend configuration and optionally deploy from `site/`:

```sh
npm run build
npx wrangler login
npx wrangler deploy --config dist/server/wrangler.json
```

The generated configuration belongs to your build, not an original hosting identity. These commands publish to **your** account; do not run them unless you intend that deployment. A public login shell is not public CRM data, but both host-level access requirements and Supabase authorisation need review. Verify HTTPS, sign-out, owner/other-user access, ES/EN and narrow screens on the actual hosted URL before sharing it. See [Wrangler deployment](https://developers.cloudflare.com/workers/wrangler/commands/#deploy). No live cloud deployment is certified by the source build alone.

## Safe updates and troubleshooting

Back up your own database and private objects, then test updates in a disposable staging installation. Pull the reviewed public source, inspect new migrations, confirm the linked project and use `db push --linked --dry-run` before applying pending migrations. Initial-baseline installations need the six additive migrations dated `20261012130000` through `20261012180000`; new installations apply all 46 automatically. Never reset or import the creator's database, reapply historical migrations, or overwrite a populated schema to fix an installation error.

| Symptom | Check |
|---|---|
| Configuration pending | Both values in `site/.env.local` must be real values from your project; restart/rebuild. |
| Login fails | Auth user, confirmed email, password, enabled email provider and URL/key must belong to the same project. |
| Login succeeds but an operation is denied | Verify your Auth UUID exists in `crm_owner_profiles` and migrations/grants are complete; do not disable RLS. |
| Applications cannot load or an RPC is missing | Verify the linked project and migration list; apply the pending public migrations in order. |
| Empty CRM after first sign-in | Expected: no user records are seeded. Add your own authorised records through reviewed operations. |
| Radar cannot verify a complete registry | Own cohort/source configuration is still missing or incomplete; do not infer zero vacancies. |
| Bridge authentication fails on Windows/Linux | The shipped bridge uses macOS Keychain; browser login is independent. |

Never post `.env.local`, credentials, actual CRM payloads, CVs or full runtime logs in public issues. Describe the error with redacted diagnostics and source/migration versions instead.

## Optional conversational bridge

The macOS bridge under `integrations/supabase/call-report-mcp/` reads your own `ORBIT_SUPABASE_URL` and a separate Keychain entry, defaulting to `Orbit CRM Public Local Session`. Use `orbit-call-report-auth.mjs` to establish your own session and `orbit-call-report-mcp.mjs` as the stdio MCP server. These are macOS-specific utilities; the browser application is independent of them. Authentication and write operations require explicit user input and verified business readback.

On macOS, from the repository root, set the URL of your own HTTPS Supabase project in the terminal and run the helper:

```sh
export ORBIT_SUPABASE_URL=YOUR_OWN_HTTPS_SUPABASE_PROJECT_URL
node integrations/supabase/call-report-mcp/orbit-call-report-auth.mjs
```

Replace the placeholder first. The helper asks for your publishable key, owner email and password and stores a renewable session in macOS Keychain, not in the repository. Register `node` plus the absolute path to `orbit-call-report-mcp.mjs` in a client that supports local stdio MCP, with the same `ORBIT_SUPABASE_URL` environment value and macOS user/Keychain service. A custom `ORBIT_CALL_REPORT_KEYCHAIN_SERVICE` must be identical during authentication and server startup. Never paste refresh tokens into client configuration or chat. This optional connector does not activate a provider subscription, agent, schedule or email workflow.

## Data and updates

Each installer owns the responsibility for hosting costs, backups, access control, data processing and incidents. No creator-operated service or incident support is promised. Any selected input sent to an external model is processed by that provider. No analytics or automated public mirroring of private records is configured.

Update this public project only by reviewing explicit source exports and repeating privacy checks. Do not copy the private repository's Git history, deployment bindings or operational datasets. Keep records, credentials, exports, screenshots and operational evidence outside source control. Secret scanners supplement human source review; they cannot guarantee that arbitrary future changes contain no private information. See [the public distribution documentation](docs/public-distribution/) for the requirements and verified release baseline.

## License and language

GNU Affero General Public License v3.0 only; see [LICENSE](LICENSE). Preserve the license and make corresponding source available to users of modified network deployments. The software carries no warranty.

Open-source distribution is separate from access to anyone's application or data. Maintained documentation, code comments, identifiers and commits are written in English. The application includes English and Spanish localisation; recorded input is not automatically translated.
