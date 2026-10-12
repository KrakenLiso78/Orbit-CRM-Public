# Orbit CRM Public

AGPL-3.0-only source code for a private professional networking and career CRM. This independent distribution includes the bilingual dashboard, owner-scoped database schema and business operations, synthetic regression tests and an optional macOS conversational bridge.

No real contacts, applications, CVs, private reports, profiles, deployment configuration or development history are included. This project provides software for your own installation. It does not provide access to the creator's application, database or records.

The complete dependency audit reports zero vulnerabilities for the validated source baseline. A bounded local adapter backed by pinned `tinyglobby` replaces the former vulnerable `fast-glob` chain. The adapter implements the synchronous compiler API only; future dependency updates must rerun its compatibility and adversarial-pattern tests. See `docs/public-distribution/verification.md` for installation and access evidence.

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

Update this public project only by reviewing explicit source exports. Keep records, credentials, exports, screenshots and operational evidence outside source control. See `docs/public-distribution/` for the distribution requirements and verified release baseline.

## License

GNU Affero General Public License v3.0 only; see [LICENSE](LICENSE). Preserve the license and make corresponding source available to users of modified network deployments. The software carries no warranty.
