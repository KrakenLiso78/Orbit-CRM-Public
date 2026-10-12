#!/usr/bin/env node
/**
 * Narrow stdio MCP bridge for Orbit Call Report.
 * It exposes only reviewed database RPCs and never accepts SQL or table names.
 */
import { execFileSync } from "node:child_process";
import { createInterface } from "node:readline";
import { createCredentialCache } from "./orbit-credential-cache.mjs";
import { createFileLock, defaultRefreshLockPath } from "./orbit-refresh-lock.mjs";

const serverInfo = { name: "orbit-call-report", version: "1.0.0" };
const supabaseUrl = process.env.ORBIT_SUPABASE_URL;
const keychainService = process.env.ORBIT_CALL_REPORT_KEYCHAIN_SERVICE ?? "Orbit CRM Public Local Session";
const keychainAccount = process.env.USER ?? process.env.LOGNAME;
const refreshLockPath = process.env.ORBIT_CALL_REPORT_REFRESH_LOCK_PATH
  ?? defaultRefreshLockPath({ service: keychainService, account: keychainAccount });

if (!supabaseUrl?.startsWith("https://")) {
  throw new Error("ORBIT_SUPABASE_URL must be an https URL");
}

const object = { type: "object", additionalProperties: false };
const tools = [
  ["resolve_company", "Resolve exact owner-scoped company candidates. Does not create records.", { ...object, properties: { p_name: { type: ["string", "null"] }, p_website_url: { type: ["string", "null"] }, p_linkedin_url: { type: ["string", "null"] }, p_limit: { type: "integer", minimum: 1, maximum: 20 } } }, { readOnlyHint: true }],
  ["create_independent_company", "Create exactly one owner company with source provenance. Creates no contact, opportunity, interaction, or task. Retries require the exact payload and operation key.", { ...object, required: ["p_company", "p_operation_key"], properties: { p_company: { type: "object" }, p_operation_key: { type: "string", minLength: 1 } } }, { readOnlyHint: false, destructiveHint: false, idempotentHint: true }],
  ["read_back_independent_company", "Read authoritative independent company, provenance, and receipt by operation key.", { ...object, required: ["p_operation_key"], properties: { p_operation_key: { type: "string", minLength: 1 } } }, { readOnlyHint: true }],
  ["resolve_contact", "Resolve exact owner-scoped contact candidates. Does not create records.", { ...object, properties: { p_name: { type: ["string", "null"] }, p_email: { type: ["string", "null"] }, p_linkedin_url: { type: ["string", "null"] }, p_limit: { type: "integer", minimum: 1, maximum: 20 } } }, { readOnlyHint: true }],
  ["create_independent_contact", "Create exactly one owner contact with email or LinkedIn identity and source provenance. Creates no company affiliation, opportunity, interaction, or task. Retries require the exact payload and operation key.", { ...object, required: ["p_contact", "p_operation_key"], properties: { p_contact: { type: "object" }, p_operation_key: { type: "string", minLength: 1 } } }, { readOnlyHint: false, destructiveHint: false, idempotentHint: true }],
  ["read_back_independent_contact", "Read authoritative independent contact, provenance, and receipt by operation key.", { ...object, required: ["p_operation_key"], properties: { p_operation_key: { type: "string", minLength: 1 } } }, { readOnlyHint: true }],
  ["capture_call_report_with_entities", "Atomically create or reuse the explicitly supplied Call Report company, contact, vacancy, and interaction.", { ...object, required: ["p_capture", "p_operation_key"], properties: { p_capture: { type: "object" }, p_operation_key: { type: "string", minLength: 1 } } }, { readOnlyHint: false, destructiveHint: false, idempotentHint: true }],
  ["prepare_interaction_capture", "Validate an owner-scoped Call Report capture without saving it. A successful result is not saved.", { ...object, required: ["p_capture"], properties: { p_capture: { type: "object" } } }, { readOnlyHint: true }],
  ["record_interaction_capture", "Atomically save a prepared interaction and optional follow-up. Retries must reuse the exact payload and operation key.", { ...object, required: ["p_capture", "p_operation_key"], properties: { p_capture: { type: "object" }, p_operation_key: { type: "string", minLength: 1 } } }, { readOnlyHint: false, destructiveHint: false, idempotentHint: true }],
  ["read_back_interaction_capture", "Read the authoritative result for a saved interaction capture by operation key.", { ...object, required: ["p_operation_key"], properties: { p_operation_key: { type: "string", minLength: 1 } } }, { readOnlyHint: true }],
  ["capture_interaction_and_verify", "Atomically save an approved interaction and return its authoritative readback in one verified MCP operation. Retries must reuse the exact payload and operation key.", { ...object, required: ["p_capture", "p_operation_key"], properties: { p_capture: { type: "object" }, p_operation_key: { type: "string", minLength: 1 } } }, { readOnlyHint: false, destructiveHint: false, idempotentHint: true }],
  ["correct_call_report_record", "Correct fixed descriptive fields of one existing owner record. Requires current lock_version, correction reason, source, and stable operation key. Never accepts table names or SQL.", { ...object, required: ["p_target_type", "p_target_id", "p_expected_lock_version", "p_changes", "p_reason", "p_source", "p_operation_key"], properties: { p_target_type: { type: "string", enum: ["company", "contact", "opportunity", "interaction", "task"] }, p_target_id: { type: "string", format: "uuid" }, p_expected_lock_version: { type: "integer", minimum: 1 }, p_changes: { type: "object", minProperties: 1 }, p_reason: { type: "string", minLength: 1 }, p_source: { type: "object" }, p_operation_key: { type: "string", minLength: 1 } } }, { readOnlyHint: false, destructiveHint: false, idempotentHint: true }],
  ["read_back_call_report_correction", "Read authoritative correction history, receipt, and current record by operation key.", { ...object, required: ["p_operation_key"], properties: { p_operation_key: { type: "string", minLength: 1 } } }, { readOnlyHint: true }],
  ["complete_task", "Complete one owner commitment exactly once. Requires a stable operation key and is idempotent on exact replay.", { ...object, required: ["p_task_id", "p_completed_at", "p_operation_key"], properties: { p_task_id: { type: "string", format: "uuid" }, p_completed_at: { type: "string", format: "date-time" }, p_note: { type: ["string", "null"] }, p_operation_key: { type: "string", minLength: 1 } } }, { readOnlyHint: false, destructiveHint: false, idempotentHint: true }],
  ["read_back_task_completion", "Read the authoritative result for a saved task completion by operation key.", { ...object, required: ["p_operation_key"], properties: { p_operation_key: { type: "string", minLength: 1 } } }, { readOnlyHint: true }],
  ["resolve_application", "Find exact owner application candidates by application ID, company, role, or source identity. Never select the newest of multiple matches. Returns latest_event_id for concurrency.", { ...object, properties: { p_application_id: { type: ["string", "null"], format: "uuid" }, p_company_name: { type: ["string", "null"] }, p_role_title: { type: ["string", "null"] }, p_source_identifier: { type: ["string", "null"] }, p_limit: { type: "integer", minimum: 1, maximum: 20 } } }, { readOnlyHint: true }],
  ["record_application_event", "Record one explicitly reported event on an identified owner application and return authoritative readback. Resolve ambiguity first. Reuse exact payload and operation key on retries. Follow-ups and notes preserve the current outcome.", { ...object, required: ["p_event", "p_operation_key"], properties: { p_event: { ...object, required: ["application_id", "expected_latest_event_id", "event_type", "occurred_at", "note"], properties: { application_id: { type: "string", format: "uuid" }, expected_latest_event_id: { type: ["string", "null"], format: "uuid" }, event_type: { type: "string", enum: ["follow_up", "interview", "withdrawn", "rejected", "offer", "accepted", "reopened", "correction", "other"] }, occurred_at: { type: "string", format: "date-time" }, note: { type: "string", minLength: 1 }, evidence_url: { type: ["string", "null"] } } }, p_operation_key: { type: "string", minLength: 1 } } }, { readOnlyHint: false, destructiveHint: false, idempotentHint: true }],
  ["read_back_application_event", "Recover the saved application event, receipt, application and current state by operation key after an uncertain response.", { ...object, required: ["p_operation_key"], properties: { p_operation_key: { type: "string", minLength: 1 } } }, { readOnlyHint: true }],
  ["prepare_application_capture", "Validate an owner-scoped application capture without saving it. A successful result is not saved.", { ...object, required: ["p_capture"], properties: { p_capture: { type: "object" } } }, { readOnlyHint: true }],
  ["record_application_capture", "Atomically save a submitted application and linked material versions. Retries must reuse the exact payload and operation key.", { ...object, required: ["p_capture", "p_operation_key"], properties: { p_capture: { type: "object" }, p_operation_key: { type: "string", minLength: 1 } } }, { readOnlyHint: false, destructiveHint: false, idempotentHint: true }],
  ["read_back_application_capture", "Read the authoritative result for a saved application capture by operation key.", { ...object, required: ["p_operation_key"], properties: { p_operation_key: { type: "string", minLength: 1 } } }, { readOnlyHint: true }],
  ["configure_job_monitor", "Save the approved owner profile, scoring rubric, and official source registry through one idempotent operation.", { ...object, required: ["p_profile", "p_profile_label", "p_rubric", "p_rubric_label", "p_sources", "p_operation_key"], properties: { p_profile: { type: "object" }, p_profile_label: { type: "string", minLength: 1 }, p_rubric: { type: "object" }, p_rubric_label: { type: "string", minLength: 1 }, p_sources: { type: "array", minItems: 1, items: { type: "object" } }, p_operation_key: { type: "string", minLength: 1 } } }, { readOnlyHint: false, destructiveHint: false, idempotentHint: true }],
  ["read_back_job_monitor_configuration", "Read the authoritative job-monitor profile, rubric, source registry, and receipt by operation key.", { ...object, required: ["p_operation_key"], properties: { p_operation_key: { type: "string", minLength: 1 } } }, { readOnlyHint: true }],
  ["record_job_monitor_run", "Save one validated owner-scoped discovery and fit-scoring run. This never creates an application.", { ...object, required: ["p_run", "p_operation_key"], properties: { p_run: { type: "object" }, p_operation_key: { type: "string", minLength: 1 } } }, { readOnlyHint: false, destructiveHint: false, idempotentHint: true }],
  ["read_back_job_monitor_run", "Read an authoritative job-monitor execution and its saved role assessments by operation key.", { ...object, required: ["p_operation_key"], properties: { p_operation_key: { type: "string", minLength: 1 } } }, { readOnlyHint: true }],
  ["list_open_job_postings_for_reassessment", "List owner-scoped open, non-dismissed postings with their latest assessment and retained evidence snapshot.", { ...object, properties: { p_limit: { type: "integer", minimum: 1, maximum: 1000 } } }, { readOnlyHint: true }],
  ["record_job_reassessment_run", "Save versioned fit assessments for existing open postings while reusing retained description snapshots. This never creates a posting, opportunity, application, task, or notification.", { ...object, required: ["p_run", "p_operation_key"], properties: { p_run: { type: "object" }, p_operation_key: { type: "string", minLength: 1 } } }, { readOnlyHint: false, destructiveHint: false, idempotentHint: true }],
  ["read_back_job_reassessment_run", "Read an authoritative existing-posting reassessment and receipt by operation key.", { ...object, required: ["p_operation_key"], properties: { p_operation_key: { type: "string", minLength: 1 } } }, { readOnlyHint: true }],
  ["list_open_job_postings_for_monitor", "List owner-scoped open official postings that the monitor must recheck for continued availability.", { ...object, properties: { p_limit: { type: "integer", minimum: 1, maximum: 1000 } } }, { readOnlyHint: true }],
  ["record_job_posting_status_checks", "Mark verified postings closed or unavailable without changing application state. Retries require the exact payload and operation key.", { ...object, required: ["p_checks", "p_operation_key"], properties: { p_checks: { type: "array", minItems: 1, items: { type: "object" } }, p_operation_key: { type: "string", minLength: 1 } } }, { readOnlyHint: false, destructiveHint: false, idempotentHint: true }],
  ["read_back_job_posting_status_checks", "Read authoritative posting lifecycle changes and official-source evidence by operation key.", { ...object, required: ["p_operation_key"], properties: { p_operation_key: { type: "string", minLength: 1 } } }, { readOnlyHint: true }],
  ["promote_job_posting_to_opportunity", "Promote one explicitly selected open monitored posting into a linked CRM opportunity. Never creates an application.", { ...object, required: ["p_job_id", "p_operation_key"], properties: { p_job_id: { type: "string", format: "uuid" }, p_operation_key: { type: "string", minLength: 1 } } }, { readOnlyHint: false, destructiveHint: false, idempotentHint: true }],
  ["read_back_job_posting_promotion", "Read the authoritative linked opportunity and receipt for a posting promotion.", { ...object, required: ["p_operation_key"], properties: { p_operation_key: { type: "string", minLength: 1 } } }, { readOnlyHint: true }],
  ["record_market_review_run", "Save one validated owner-scoped market review with sourced signals and a private notification.", { ...object, required: ["p_run", "p_operation_key"], properties: { p_run: { type: "object" }, p_operation_key: { type: "string", minLength: 1 } } }, { readOnlyHint: false, destructiveHint: false, idempotentHint: true }],
  ["read_back_market_review_run", "Read an authoritative market-review execution and its saved signals by operation key.", { ...object, required: ["p_operation_key"], properties: { p_operation_key: { type: "string", minLength: 1 } } }, { readOnlyHint: true }],
  ["record_career_source_checks", "Update only the reviewed owner career-source freshness and outcome fields with idempotency.", { ...object, required: ["p_checks", "p_operation_key"], properties: { p_checks: { type: "array", minItems: 1, items: { type: "object" } }, p_operation_key: { type: "string", minLength: 1 } } }, { readOnlyHint: false, destructiveHint: false, idempotentHint: true }],
  ["read_back_career_source_checks", "Read authoritative source-check outcomes and their receipt by operation key.", { ...object, required: ["p_operation_key"], properties: { p_operation_key: { type: "string", minLength: 1 } } }, { readOnlyHint: true }],
  ["get_weekly_career_guidance_context", "Read bounded owner contacts, interactions, commitments, opportunities, applications, and approved profile evidence for one weekly career review. Writes nothing.", { ...object, properties: { p_limit: { type: "integer", minimum: 1, maximum: 100 } } }, { readOnlyHint: true }],
  ["record_weekly_career_guidance", "Atomically save exactly three ranked Spanish career-guidance actions and only their reviewed task/opportunity effects. Never sends messages or changes applications.", { ...object, required: ["p_review", "p_operation_key"], properties: { p_review: { type: "object" }, p_operation_key: { type: "string", minLength: 1 } } }, { readOnlyHint: false, destructiveHint: false, idempotentHint: true }],
  ["read_back_weekly_career_guidance", "Read the authoritative weekly review, exactly three actions, receipt, and affected tasks/opportunities by operation key.", { ...object, required: ["p_operation_key"], properties: { p_operation_key: { type: "string", minLength: 1 } } }, { readOnlyHint: true }],
  ["get_orbit_mvp_snapshot", "Read the bounded owner-scoped CRM monitoring snapshot used by the private portal.", { ...object, properties: { p_limit: { type: "integer", minimum: 1, maximum: 50 } } }, { readOnlyHint: true }],
].map(([name, description, inputSchema, annotations]) => ({ name, description, inputSchema, annotations }));

function session() {
  try {
    const secret = execFileSync("/usr/bin/security", ["find-generic-password", "-w", "-s", keychainService, "-a", keychainAccount], { encoding: "utf8", stdio: ["ignore", "pipe", "ignore"] });
    const parsed = JSON.parse(secret);
    if (!parsed.publishable_key || !parsed.refresh_token) throw new Error("missing fields");
    return parsed;
  } catch {
    throw new Error("Orbit Call Report is not authenticated. Run orbit-call-report-auth.mjs in your terminal; do not provide credentials in chat.");
  }
}

function saveSession(saved, refreshToken) {
  const secret = JSON.stringify({ publishable_key: saved.publishable_key, refresh_token: refreshToken });
  execFileSync("/usr/bin/security", ["add-generic-password", "-U", "-s", keychainService, "-a", keychainAccount, "-w", secret], { stdio: "ignore" });
}

const credentials = createCredentialCache({
  readSession: async () => session(),
  refreshSession: async (saved) => {
    const response = await fetch(`${supabaseUrl}/auth/v1/token?grant_type=refresh_token`, {
      method: "POST",
      headers: { apikey: saved.publishable_key, "Content-Type": "application/json" },
      body: JSON.stringify({ refresh_token: saved.refresh_token }),
    });
    if (!response.ok) throw new Error("The owner session could not be refreshed. Run orbit-call-report-auth.mjs again.");
    return response.json();
  },
  saveSession: async (saved, refreshToken) => saveSession(saved, refreshToken),
  withRefreshLock: createFileLock({ lockPath: refreshLockPath }),
});

async function invoke(name, args) {
  const tool = tools.find((candidate) => candidate.name === name);
  if (!tool) throw new Error("Unsupported Call Report operation.");
  const { accessToken, publishableKey } = await credentials();
  const response = await fetch(`${supabaseUrl}/rest/v1/rpc/${name}`, {
    method: "POST",
    headers: {
      apikey: publishableKey,
      Authorization: `Bearer ${accessToken}`,
      "Content-Type": "application/json",
      Accept: "application/json",
    },
    body: JSON.stringify(args),
  });
  const body = await response.text();
  if (!response.ok) {
    let message = "The Call Report RPC rejected the request.";
    try {
      const parsed = JSON.parse(body);
      message = [parsed.message, parsed.details, parsed.hint].filter((value) => typeof value === "string" && value).join(" | ") || message;
    } catch { /* do not return non-JSON server data */ }
    throw new Error(message);
  }
  return body ? JSON.parse(body) : null;
}

function send(message) {
  process.stdout.write(`${JSON.stringify(message)}\n`);
}

async function respond(request) {
  if (request.method === "notifications/initialized") return;
  if (request.method === "initialize") {
    return { protocolVersion: request.params?.protocolVersion ?? "2025-03-26", capabilities: { tools: {} }, serverInfo };
  }
  if (request.method === "tools/list") return { tools };
  if (request.method === "tools/call") {
    if (request.params?.name === "capture_interaction_and_verify") {
      const args = request.params?.arguments ?? {};
      const saved = await invoke("record_interaction_capture", args);
      const readback = await invoke("read_back_interaction_capture", { p_operation_key: args.p_operation_key });
      return { content: [{ type: "text", text: JSON.stringify({ saved, readback, verified: true }) }] };
    }
    const result = await invoke(request.params?.name, request.params?.arguments ?? {});
    return { content: [{ type: "text", text: JSON.stringify(result) }] };
  }
  throw new Error("Unsupported MCP method.");
}

const lines = createInterface({ input: process.stdin, crlfDelay: Infinity });
for await (const line of lines) {
  if (!line.trim()) continue;
  let request;
  try {
    request = JSON.parse(line);
    const result = await respond(request);
    if (request.id !== undefined) send({ jsonrpc: "2.0", id: request.id, result });
  } catch (error) {
    if (request?.id !== undefined) send({ jsonrpc: "2.0", id: request.id, error: { code: -32000, message: error instanceof Error ? error.message : "Call Report MCP error" } });
  }
}
