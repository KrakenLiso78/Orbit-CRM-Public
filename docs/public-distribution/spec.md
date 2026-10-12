# Public source distribution specification

Status: preparation authorised; publication requires passing the release checks.

## Outcome

Publish Orbit CRM software as a separate AGPL-3.0-only repository named Orbit CRM Public. The existing development repository, managed application, database, credentials and real records remain private.

## Requirements

- PUB-001: The public repository has independent history and contains no private development commits, tags, branches, remotes or author email addresses.
- PUB-002: Distribute only reviewed software, generic schema/migrations, synthetic tests, neutral assets and public installation documentation through an explicit allowlist.
- PUB-003: Exclude all real records, applications, CVs, contacts, company selections, scores, preferences, exports, reports, execution evidence, backups, screenshots and deployment identifiers.
- PUB-004: Default configuration is empty and cannot connect to the original owner's instance. Each installer supplies their own service configuration and authenticated owner.
- PUB-005: Every release passes content/secret scanning, dependency and build checks. Installation acceptance additionally requires clean isolated migration replay and owner/anonymous/wrong-owner access checks.
- PUB-006: The private repository visibility and production access controls remain unchanged. No production database query, export, mutation or deployment is part of distribution preparation.
- PUB-007: A future update uses an explicit reviewed export; automatic mirroring from the private repository is prohibited.
- PUB-008: Generic migrations install on a clean Supabase project even when an optional platform helper is absent; if that helper exists, its unnecessary public execute permission is revoked.
- PUB-009: Repeated migration definitions retain their owner-only policies without failing on an already-created policy. Dependency audit findings are reviewed before publication, and resolvable vulnerable dependencies receive compatible pinned fixes.
- PUB-010: Context readback uses fields that exist on each event type. Task-state transitions must not require equivalent columns on application events; supported company/opportunity contexts remain compatible with the final schema.
- PUB-011: Replace the vulnerable glob dependency while preserving dynamic-import file matching needed by the compiler. Excessively long, numerous or deeply nested patterns fail with a bounded error before traversal. The complete dependency audit must pass before publication.

## Acceptance

## Controlled feature update

- PUB-012: The owner can browse all recorded applications with combined company, state, text, channel and inclusive date filters, reset them and open recorded context. Rejected, withdrawn and employer-cancelled records remain in history and the total KPI but are excluded from the current dashboard lane. Cancellation and withdrawal are distinct; vacancy closure never infers either.
- PUB-013: Upcoming tasks appear in numeric priority order before due date and before limiting results. Text badges expose priority including an explicit missing value. Desktop and narrow layouts prioritise tasks, interactions and completed tasks before opportunities and applications without changing owner access or actions.
- PUB-014: Distribute the generic company rank/range graphic and narrative-first full-width presentation using only newly authored synthetic companies, ranks and ranges. A clearly labelled demonstration has no real analytical report, cohort, forecast, source or installation data and does not query a backend.
- PUB-015: Preserve prior public portability/security fixes, neutral configuration and patched dependency adapter. New migration and UI validation uses an isolated empty backend and synthetic fixtures only. Test all-state completeness, cancellation lifecycle/replay/history, priority selection, owner/foreign/anonymous reads and bilingual responsive rendering before publication.
- PUB-016: Export only selected committed software from a fixed private revision; exclude in-progress research, operational records and private history. Explain the current source capabilities without importing original schedules, personal rubrics, provider keys or deployment state.

Acceptance: Given synthetic applications across all lifecycle states, combined filters return exactly the matching records and reset restores all owner rows; foreign and anonymous access reveal no owner records. Given rejected/withdrawn/cancelled applications, the current lane excludes them while the register and total retain them. Given P0/P1/P2/missing tasks, priority ordering and badges preserve recorded values. Given the synthetic market demonstration, both languages retain narrative → graphic → company-list order and narrow viewports have no page-level overflow. Given a publication candidate containing private records or an unpassed validation gate, publication is blocked.

Success: zero private content or original installation identifiers; all selected regression, audit, migration, access and browser gates pass, with independent anonymous publication readback and private-origin visibility unchanged.

1. Given private source with historical data, when a release is exported, then only allowlisted current code enters an independent public history.
2. Given no environment configuration, when the application loads, then it displays the configuration boundary and sends no request to the original instance.
3. Given private payloads, deployment identifiers, unsafe assets or personal metadata in a candidate, when the release is checked, then publication is blocked.
4. Given the public repository URL, when an anonymous community member opens it, then source and AGPL license are readable and no real installation data is present.

## Success criteria

## Independent installation documentation

- PUB-017: A new installer can identify prerequisites, create their own empty Supabase project and Auth owner, apply the distributed migrations, register that owner, configure only their own frontend URL/publishable key and reach an empty private dashboard. Documentation distinguishes browser setup from optional conversational/research/scheduling services, warns against destructive resets and private-instance configuration reuse, and names security/backup checks before real data.

Acceptance: given no access to the creator's infrastructure or files, the README provides a complete ordered path using only public source and the installer's own services, states honest validation bounds and explains common missing-configuration/owner/migration errors without proposing weaker authorisation.

Zero included private records or original deployment identifiers; zero unreviewed secret findings; independent history; successful source tests, lint, type checking and build; isolated database replay and access checks recorded separately from source-only checks.
