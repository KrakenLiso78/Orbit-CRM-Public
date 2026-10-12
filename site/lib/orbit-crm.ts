import { parseDashboardSnapshot, parseJobPostingPromotion, parseMvpSnapshot } from './orbit-crm-contract.mjs';
import { readLatestProcessExecutions, mergeExecutionHistory } from './orbit-execution-history.mjs';
import { readJobRadar } from './orbit-job-radar.mjs';
import cohort from './pharma-top25.json';

export type OrbitSession = {
  access_token: string;
  refresh_token: string;
  expires_at?: number;
  expires_in?: number;
};

export type DashboardSnapshot = {
  counts: {
    companies: number;
    contacts: number;
    opportunities: number;
    applications: number;
    open_tasks: number;
  };
  due_tasks: Array<{ id: string; title: string; state: string; priority: string | null; due_at: string | null }>;
  recent_completed_tasks: Array<{
    id: string;
    title: string;
    completed_at: string;
    source_interaction_id: string | null;
    source_interaction_title: string | null;
    events: Array<{ id: string; event_type: string; occurred_at: string; note: string | null }>;
  }>;
  recent_interactions: Array<{ id: string; title: string; interaction_type: string | null; occurred_at: string; summary: string | null }>;
  active_opportunities: Array<{ id: string; title: string; status: string | null; priority: string | null; next_step_at: string | null }>;
  recent_applications: Array<{
    id: string;
    company_name: string;
    role_title: string | null;
    submitted_at: string;
    channel: string;
    current_state: string | null;
    state_recorded_at: string | null;
    latest_event_type: string | null;
    latest_event_at: string | null;
    latest_event_note: string | null;
  }>;
};

export type MvpSnapshot = {
  generated_at: string;
  job_roles: Array<{
    id: string; title: string; company_name: string; location: string | null; work_arrangement: string | null;
    source_url: string; status: string; first_seen_at: string; last_seen_at: string | null; posted_at: string | null;
    closing_at: string | null; score: number | null; confidence: number | null; rationale: string | null;
    strengths: string[]; gaps: string[]; constraints: string[]; assessed_at: string;
  }>;
  dismissed_jobs: Array<{ id: string; title: string; company_name: string; reason: string; dismissed_at: string; assessment_id: string | null }>;
  market_signals: Array<{
    id: string; title: string; signal_type: string | null; signal_date: string; source_url: string;
    relevance: string | null; search_implication: string | null; suggested_action: string | null; notes: string | null;
  }>;
  executions: Array<{
    id: string; monitor_type: string; execution_key: string; started_at: string; completed_at: string | null;
    status: string; scope: Record<string, unknown>; scheduler: string; dependency_note: string | null; summary: Record<string, unknown>; failures: unknown[];
  }>;
  notifications: Array<{ id: string; notification_type: string; title: string; state: string; created_at: string }>;
};

const sessionKey = 'orbit.crm.session';

function config() {
  // Keep Vite variables as direct static references so portable Sites builds
  // replace them in the browser bundle. Runtime-only environment variables are
  // not available after this client module has been compiled.
  const url = import.meta.env.VITE_SUPABASE_URL;
  const key = import.meta.env.VITE_SUPABASE_PUBLISHABLE_KEY;
  return url && key ? { url: url.replace(/\/$/, ''), key } : null;
}

function storedSession(): OrbitSession | null {
  try {
    const raw = window.localStorage.getItem(sessionKey);
    return raw ? (JSON.parse(raw) as OrbitSession) : null;
  } catch {
    return null;
  }
}

function saveSession(session: OrbitSession) {
  window.localStorage.setItem(sessionKey, JSON.stringify(session));
}

export function clearOrbitSession() {
  window.localStorage.removeItem(sessionKey);
}

export async function signIn(email: string, password: string) {
  const supabase = config();
  if (!supabase) throw new Error('Supabase browser configuration is missing.');
  const response = await fetch(`${supabase.url}/auth/v1/token?grant_type=password`, {
    method: 'POST',
    headers: { apikey: supabase.key, 'Content-Type': 'application/json' },
    body: JSON.stringify({ email, password }),
  });
  const body = (await response.json().catch(() => ({}))) as Record<string, unknown>;
  if (!response.ok || typeof body.access_token !== 'string' || typeof body.refresh_token !== 'string') {
    throw new Error(typeof body.error_description === 'string' ? body.error_description : 'Authentication failed.');
  }
  saveSession(body as unknown as OrbitSession);
}

async function accessToken() {
  const supabase = config();
  const session = storedSession();
  if (!supabase || !session) throw new Error('Sign in is required.');
  const expiresAt = session.expires_at ?? 0;
  if (expiresAt * 1000 > Date.now() + 60_000) return { supabase, token: session.access_token };

  const response = await fetch(`${supabase.url}/auth/v1/token?grant_type=refresh_token`, {
    method: 'POST',
    headers: { apikey: supabase.key, 'Content-Type': 'application/json' },
    body: JSON.stringify({ refresh_token: session.refresh_token }),
  });
  const refreshed = (await response.json().catch(() => ({}))) as Record<string, unknown>;
  if (!response.ok || typeof refreshed.access_token !== 'string' || typeof refreshed.refresh_token !== 'string') {
    clearOrbitSession();
    throw new Error('The session expired. Please sign in again.');
  }
  saveSession(refreshed as unknown as OrbitSession);
  return { supabase, token: refreshed.access_token as string };
}

export async function getDashboardSnapshot(): Promise<DashboardSnapshot> {
  const { supabase, token } = await accessToken();
  const response = await fetch(`${supabase.url}/rest/v1/rpc/get_dashboard_snapshot`, {
    method: 'POST',
    headers: {
      apikey: supabase.key,
      Authorization: `Bearer ${token}`,
      'Content-Type': 'application/json',
      Accept: 'application/json',
    },
    body: JSON.stringify({ p_task_limit: 8, p_activity_limit: 8 }),
  });
  const body = await response.json().catch(() => null);
  if (!response.ok || !body || typeof body !== 'object') throw new Error('The CRM dashboard could not be loaded.');
  return parseDashboardSnapshot(body) as DashboardSnapshot;
}

export async function getMvpSnapshot(): Promise<MvpSnapshot> {
  const { supabase, token } = await accessToken();
  const response = await fetch(`${supabase.url}/rest/v1/rpc/get_orbit_mvp_snapshot`, {
    method: 'POST',
    headers: {
      apikey: supabase.key,
      Authorization: `Bearer ${token}`,
      'Content-Type': 'application/json',
      Accept: 'application/json',
    },
    body: JSON.stringify({ p_limit: 12 }),
  });
  const body = await response.json().catch(() => null);
  if (!response.ok || !body || typeof body !== 'object') throw new Error('The Orbit monitoring view could not be loaded.');
  const snapshot = parseMvpSnapshot(body) as MvpSnapshot;
  // A busy process can exhaust the shared recent-history window. Read one
  // latest row per process through the existing authenticated owner RLS.
  const latest = await readLatestProcessExecutions(fetch, supabase.url, {
    apikey: supabase.key, Authorization: `Bearer ${token}`, Accept: 'application/json',
  });
  return parseMvpSnapshot({ ...snapshot, executions: mergeExecutionHistory(snapshot.executions, latest) }) as MvpSnapshot;
}

export function hasBrowserConfig() {
  return Boolean(config());
}

export async function getJobRadar(signal?: AbortSignal) {
  const { supabase, token } = await accessToken();
  return readJobRadar(fetch, supabase.url, {apikey:supabase.key,Authorization:`Bearer ${token}`,Accept:'application/json'}, cohort.companies.map(row=>row.company),signal);
}

export function hasOrbitSession() {
  return Boolean(storedSession());
}

export type CrmRecordKind = 'task' | 'interaction' | 'opportunity' | 'application';
export async function getCrmRecordContext(kind: CrmRecordKind, id: string, signal: AbortSignal): Promise<Record<string, unknown> | null> {
  const { supabase, token } = await accessToken();
  if (signal.aborted) throw new DOMException('Cancelled', 'AbortError');
  const response = await fetch(`${supabase.url}/rest/v1/rpc/get_crm_record_context`, {
    method: 'POST', signal,
    headers: { apikey: supabase.key, Authorization: `Bearer ${token}`, 'Content-Type': 'application/json', Accept: 'application/json' },
    body: JSON.stringify({ p_kind: kind, p_id: id }),
  });
  if (!response.ok) throw new Error('Record context unavailable.');
  const body: unknown = await response.json();
  if (body === null) return null;
  if (typeof body !== 'object' || Array.isArray(body) || typeof (body as Record<string, unknown>).title !== 'string') throw new Error('Invalid record context.');
  return body as Record<string, unknown>;
}

export async function dismissJobPosting(id: string, reason: string) {
  const { supabase, token } = await accessToken();
  const call = async (name: string, body: Record<string, string>) => {
    const response = await fetch(`${supabase.url}/rest/v1/rpc/${name}`, {
      method: 'POST', headers: { apikey: supabase.key, Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
      body: JSON.stringify(body),
    });
    if (!response.ok) throw new Error('Dismissal could not be verified.');
    return response.json();
  };
  await call('dismiss_job_posting', { p_job_id: id, p_reason: reason.trim() });
  const saved = await call('read_back_job_dismissal', { p_job_id: id });
  if (!saved || typeof saved !== 'object' || Array.isArray(saved)) throw new Error('Invalid dismissal readback.');
  const record = saved as Record<string, unknown>;
  if (record.job_posting_id !== id || record.reason !== reason.trim() || typeof record.dismissed_at !== 'string') throw new Error('Invalid dismissal readback.');
  return saved as { job_posting_id: string; reason: string; dismissed_at: string; assessment_id: string | null };
}

export type JobPostingPromotion = {
  saved: true;
  application_created: false;
  job_posting: { id: string; opportunity_id: string; title: string; status: string; source_url: string; company_id: string };
  opportunity: { id: string; title: string; status: string | null; company_id: string };
};

export async function promoteJobPostingToOpportunity(id: string): Promise<JobPostingPromotion> {
  const { supabase, token } = await accessToken();
  const operationKey = `portal-job-promotion-${crypto.randomUUID()}`;
  const call = async (name: string, body: Record<string, string>) => {
    const response = await fetch(`${supabase.url}/rest/v1/rpc/${name}`, {
      method: 'POST',
      headers: { apikey: supabase.key, Authorization: `Bearer ${token}`, 'Content-Type': 'application/json', Accept: 'application/json' },
      body: JSON.stringify(body),
    });
    if (!response.ok) throw new Error('Job posting promotion could not be verified.');
    return response.json();
  };

  await call('promote_job_posting_to_opportunity', { p_job_id: id, p_operation_key: operationKey });
  const saved = await call('read_back_job_posting_promotion', { p_operation_key: operationKey });
  return parseJobPostingPromotion(saved, id) as JobPostingPromotion;
}

export async function getTaskForUpdate(id: string): Promise<{id: string; title: string; state: string; lock_version: number}> {
  const {supabase,token}=await accessToken();
  const response=await fetch(`${supabase.url}/rest/v1/tasks?id=eq.${encodeURIComponent(id)}&authority_state=eq.commitment&select=id,title,state,lock_version&limit=1`,{headers:{apikey:supabase.key,Authorization:`Bearer ${token}`,Accept:'application/json'}});
  const body: unknown=await response.json();
  if(!response.ok||!Array.isArray(body)||body.length!==1)throw new Error('Task unavailable.');
  const task=body[0];
  if(task.id!==id||typeof task.title!=='string'||typeof task.state!=='string'||!Number.isSafeInteger(task.lock_version))throw new Error('Invalid task.');
  return task;
}
export async function updateTaskProgress(id: string,state: string,comment: string,version: number,key: string) {
  const {supabase,token}=await accessToken();
  const call=async(name: string,payload: Record<string,unknown>)=>{
    const response=await fetch(`${supabase.url}/rest/v1/rpc/${name}`,{method:'POST',headers:{apikey:supabase.key,Authorization:`Bearer ${token}`,'Content-Type':'application/json'},body:JSON.stringify(payload)});
    const body: unknown=await response.json().catch(()=>null);
    if(!response.ok)throw new Error(body && typeof body==='object' && 'code' in body && body.code==='40001'?'stale':'Task save unverified.');
    return body;
  };
  await call('update_task_progress',{p_task_id:id,p_state:state,p_comment:comment.trim(),p_expected_lock_version:version,p_operation_key:key});
  const saved=await call('read_back_task_update',{p_operation_key:key});
  if(!saved||typeof saved!=='object'||!('event' in saved)||!('task' in saved))throw new Error('Invalid task readback.');
  const result=saved as {task:{id:string};event:{task_id:string;new_state:string;note:string|null;occurred_at:string}};
  if(result.task.id!==id||result.event.task_id!==id||result.event.new_state!==state||result.event.note!==(comment.trim()||null)||typeof result.event.occurred_at!=='string')throw new Error('Task readback mismatch.');
  return result;
}
