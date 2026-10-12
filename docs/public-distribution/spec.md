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

1. Given private source with historical data, when a release is exported, then only allowlisted current code enters an independent public history.
2. Given no environment configuration, when the application loads, then it displays the configuration boundary and sends no request to the original instance.
3. Given private payloads, deployment identifiers, unsafe assets or personal metadata in a candidate, when the release is checked, then publication is blocked.
4. Given the public repository URL, when an anonymous community member opens it, then source and AGPL license are readable and no real installation data is present.

## Success criteria

Zero included private records or original deployment identifiers; zero unreviewed secret findings; independent history; successful source tests, lint, type checking and build; isolated database replay and access checks recorded separately from source-only checks.
