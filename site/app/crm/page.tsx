'use client';

import { useCallback, useEffect, useRef, useState } from 'react';
import Link from 'next/link';
import Image from 'next/image';
import Executions from './executions';
import TaskEditor from './task-editor';
import RecordNotes from './record-notes';
import JobRadar from './job-radar';
import { parseNoteFields } from '../../lib/orbit-note-fields.mjs';
import { CircleHelp } from 'lucide-react';
import { dismissJobPosting, promoteJobPostingToOpportunity, clearOrbitSession, CrmRecordKind, getCrmRecordContext, DashboardSnapshot, getDashboardSnapshot, getMvpSnapshot, hasBrowserConfig, hasOrbitSession, MvpSnapshot, signIn } from '../../lib/orbit-crm';

import { localizeValue } from '../../lib/orbit-localization.mjs';

type Lang = 'es' | 'en';
function formatDate(value: string | null, lang: Lang) {
  if (!value) return lang === 'es' ? 'Sin fecha' : 'No date';
  return new Intl.DateTimeFormat(lang === 'es' ? 'es-ES' : 'en-GB', { dateStyle: 'medium' }).format(new Date(value));
}

function displayText(...values: unknown[]) {
  const value = values.find((candidate) => typeof candidate === 'string');
  return typeof value === 'string' ? value : '';
}

export default function CrmDashboard() {
  const [editingTask,setEditingTask]=useState<string | null>(null);
  const [taskSaved,setTaskSaved]=useState(false);
  const [promotingJobId, setPromotingJobId] = useState<string | null>(null);
  const [promotionNotice, setPromotionNotice] = useState<'success' | 'error' | null>(null);
  const [dismissRole, setDismissRole] = useState<MvpSnapshot['job_roles'][number] | null>(null);
  const [dismissReason, setDismissReason] = useState('');
  const [dismissBusy, setDismissBusy] = useState(false);
  const [dismissError, setDismissError] = useState(false);
  const [dismissNotice, setDismissNotice] = useState(false);
  const dismissalDialog = useRef<HTMLDialogElement>(null);
  useEffect(() => {
    const element = dismissalDialog.current;
    if (!element) return;
    if (dismissRole) element.showModal(); else element.close();
  }, [dismissRole]);
  async function confirmDismissal(event: { preventDefault(): void }) {
    event.preventDefault();
    if (!dismissRole || !dismissReason.trim() || dismissBusy) return;
    setDismissBusy(true); setDismissError(false);
    try {
      const saved = await dismissJobPosting(dismissRole.id, dismissReason);
      setMvp(current => current ? { ...current, job_roles: current.job_roles.filter(job => job.id !== dismissRole.id), dismissed_jobs: [{ id: dismissRole.id, title: dismissRole.title, company_name: dismissRole.company_name, reason: saved.reason, dismissed_at: saved.dismissed_at, assessment_id: saved.assessment_id }, ...current.dismissed_jobs.filter(job => job.id !== dismissRole.id)] } : current);
      setDismissRole(null); setDismissNotice(true);
      // Refill the visible shortlist from the source of truth after confirmed readback.
      void getMvpSnapshot().then(setMvp).catch(() => {});
    } catch { setDismissError(true); } finally { setDismissBusy(false); }
  }
  async function promoteRole(role: MvpSnapshot['job_roles'][number]) {
    if (promotingJobId) return;
    const applicationTab = window.open('', '_blank');
    if (applicationTab) {
      applicationTab.opener = null;
      applicationTab.document.title = 'Orbit CRM';
      applicationTab.document.body.textContent = lang === 'es' ? 'Guardando tu decisión en Orbit…' : 'Saving your decision in Orbit…';
    }
    setPromotingJobId(role.id); setPromotionNotice(null);
    try {
      const saved = await promoteJobPostingToOpportunity(role.id);
      const refreshed = await getDashboardSnapshot();
      setSnapshot(refreshed); setPromotionNotice('success');
      if (applicationTab) applicationTab.location.replace(saved.job_posting.source_url);
      else window.location.assign(saved.job_posting.source_url);
    } catch {
      applicationTab?.close(); setPromotionNotice('error');
    } finally {
      setPromotingJobId(null);
    }
  }
  const [metricHelp, setMetricHelp] = useState<string | null>(null);
  const [lang, setLang] = useState<Lang>('es');
  useEffect(() => { document.documentElement.lang = lang; document.title = 'Orbit CRM'; }, [lang]);
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [snapshot, setSnapshot] = useState<DashboardSnapshot | null>(null);
  const [mvp, setMvp] = useState<MvpSnapshot | null>(null);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [signedIn, setSignedIn] = useState(false);

  const [tab, setTab] = useState('crm');
  const [selected, setSelected] = useState<Record<string, unknown> | null>(null);
  const [recordContext, setRecordContext] = useState<{ id: unknown; data: Record<string, unknown> | null } | null>(null);
  const [contextStatus, setContextStatus] = useState<'loading' | 'ready' | 'error'>('loading');
  useEffect(() => {
    if (!selected) return;
    const controller = new AbortController();
    getCrmRecordContext(selected._kind as CrmRecordKind, String(selected.id), controller.signal)
      .then((data) => { if (!controller.signal.aborted) { setRecordContext({ id: selected.id, data }); setContextStatus('ready'); } })
      .catch(() => { if (!controller.signal.aborted) setContextStatus('error'); });
    return () => controller.abort();
  }, [selected]);
  function openRecord(record: Record<string, unknown>, kind: CrmRecordKind) {
    setRecordContext(null); setContextStatus('loading'); setSelected({ ...record, _kind: kind });
  }
  const dialog = useRef<HTMLDialogElement>(null);
  useEffect(() => {
    const element = dialog.current;
    if (!element) return;
    if (selected) { element.showModal(); const body = element.querySelector('.crm-dialog-body'); if (body) body.scrollTop = 0; }
    else element.close();
    const dismissOutside = (event: MouseEvent) => {
      if (event.target !== element) return;
      const rect = element.getBoundingClientRect();
      if (event.clientX < rect.left || event.clientX > rect.right || event.clientY < rect.top || event.clientY > rect.bottom) setSelected(null);
    };
    element.addEventListener('click', dismissOutside);
    return () => element.removeEventListener('click', dismissOutside);
  }, [selected]);

  // Keep privacy and data-provenance guidance understandable without backend terminology.
  const copy = lang === 'es' ? {
    private: 'Orbit · espacio privado', title: 'Orbit CRM', intro: 'Cada persona solo puede consultar sus propios datos, y estos se leen directamente de Supabase, que es nuestra fuente de verdad. La información entra a través de ChatGPT y de las herramientas de Orbit, que comprueban que los datos son correctos antes de guardarlos.', login: 'Iniciar sesión', loginIntro: 'Esta vista solo muestra registros del propietario autenticado.', email: 'Correo electrónico', password: 'Contraseña', enter: 'Entrar', checking: 'Comprobando…', logout: 'Cerrar sesión', config: 'Configuración pendiente', configBody: 'Faltan la URL y la publishable key de Supabase para activar la vista privada.', updating: 'Actualizando…', tasks: 'Próximas tareas', completedTasks: 'Tareas completadas', interactions: 'Interacciones recientes', opportunities: 'Oportunidades activas', applications: 'Candidaturas registradas', noTasks: 'No hay tareas abiertas.', noCompletedTasks: 'No hay tareas completadas.', noInteractions: 'No hay interacciones.', noOpportunities: 'No hay oportunidades activas.', noApplications: 'No hay candidaturas registradas.', state: 'Estado', latest: 'Último evento', origin: 'Origen', history: 'Historial', noState: 'Sin estado registrado', jobs: 'Empleo · evaluaciones actuales', market: 'Inteligencia de mercado · señales recientes', execution: 'Ejecuciones verificables', noJobs: 'No hay puestos evaluados.', noMarket: 'No hay señales recientes.', score: 'encaje con el perfil', confidence: 'confianza', source: 'Fuente oficial', gaps: 'Brechas', action: 'Acción sugerida', partial: 'Parcial', mac: 'Las programaciones locales dependen de que este Mac y su sesión autenticada estén disponibles.', back: '← Inicio', metrics: { contacts: 'Contactos registrados', companies: 'Empresas registradas', open_tasks: 'Tareas abiertas', applications: 'Candidaturas registradas', opportunities: 'Oportunidades registradas' }, tabs: { crm: 'CRM', jobs: 'Empleos y encaje', market: 'Inteligencia de mercado', executions: 'Ejecuciones' }, close: 'Cerrar', missing: 'No registrado', context: 'Contexto registrado', contextLoading: 'Cargando contexto…', contextError: 'No se pudo cargar el contexto. Cierra la ventana y vuelve a abrirla para reintentar.', noContext: 'No hay notas ni contexto narrativo registrado para este elemento.', unavailable: 'Este registro no está disponible.', original: 'Texto original registrado; se conserva en su idioma de origen.', loadFailed: 'No se pudieron cargar los datos. Vuelve a intentarlo.', authFailed: 'No se pudo iniciar sesión. Comprueba tus datos de acceso.',
  } : {
    private: 'Orbit · private workspace', title: 'Orbit CRM', intro: 'Each person can only view their own data, which is read directly from Supabase, our source of truth. Information comes in through ChatGPT and the Orbit tools, which check that the data is correct before saving it.', login: 'Sign in', loginIntro: 'This view only shows records belonging to the authenticated owner.', email: 'Email', password: 'Password', enter: 'Sign in', checking: 'Checking…', logout: 'Sign out', config: 'Configuration pending', configBody: 'The Supabase URL and publishable key are required to activate the private view.', updating: 'Refreshing…', tasks: 'Upcoming tasks', completedTasks: 'Completed tasks', interactions: 'Recent interactions', opportunities: 'Active opportunities', applications: 'Recorded applications', noTasks: 'No open tasks.', noCompletedTasks: 'No completed tasks.', noInteractions: 'No interactions.', noOpportunities: 'No active opportunities.', noApplications: 'No recorded applications.', state: 'State', latest: 'Latest event', origin: 'Source', history: 'History', noState: 'No recorded state', jobs: 'Jobs · current assessments', market: 'Market intelligence · recent signals', execution: 'Verifiable executions', noJobs: 'No assessed roles.', noMarket: 'No recent signals.', score: 'profile-to-role fit', confidence: 'confidence', source: 'Official source', gaps: 'Gaps', action: 'Suggested action', partial: 'Partial', mac: 'Local schedules depend on this Mac and its authenticated session being available.', back: '← Home', metrics: { contacts: 'Recorded contacts', companies: 'Registered companies', open_tasks: 'Open tasks', applications: 'Recorded applications', opportunities: 'Recorded opportunities' }, tabs: { crm: 'CRM', jobs: 'Jobs and fit', market: 'Market intelligence', executions: 'Executions' }, close: 'Close', missing: 'Not recorded', context: 'Recorded context', contextLoading: 'Loading context…', contextError: 'Context could not be loaded. Close and reopen this window to retry.', noContext: 'No notes or narrative context are recorded for this item.', unavailable: 'This record is unavailable.', original: 'Original recorded text; retained in its source language.', loadFailed: 'Data could not be loaded. Please try again.', authFailed: 'Sign-in failed. Check your credentials.',
  };

  const metricDefinitions: Record<string, string> = lang === 'es' ? {
    contacts: 'Total de contactos de tu CRM que no están archivados. No indica si has hablado con ellos recientemente.',
    companies: 'Total de empresas registradas en tu CRM que no están archivadas.',
    open_tasks: 'Todas tus tareas excepto las completadas y canceladas. Incluye tareas pendientes, en curso y pospuestas; no solo las vencidas.',
    applications: 'Total de candidaturas registradas, en cualquier estado: incluye enviadas, rechazadas y retiradas. No cuenta puestos descubiertos ni puntuaciones de encaje.',
    opportunities: 'Total de oportunidades de tu CRM que no están archivadas, incluidas las cerradas o rechazadas. No es el número de vacantes activas.',
  } : {
    contacts: 'Total CRM contacts that are not archived. This does not indicate whether you have spoken with them recently.',
    companies: 'Total registered CRM companies that are not archived.',
    open_tasks: 'All your tasks except completed and cancelled ones. Includes pending, in-progress and postponed tasks, not only overdue tasks.',
    applications: 'Total recorded applications in any state, including submitted, rejected and withdrawn. Discovered roles and fit assessments are not counted.',
    opportunities: 'Total CRM opportunities that are not archived, including closed or rejected ones. This is not the number of active vacancies.',
  };

  const fieldLabels: Record<string, string> = {
    notes: lang === 'es' ? 'Notas' : 'Notes',
    source_summary: lang === 'es' ? 'Conversación de origen' : 'Source conversation',
    source_result: lang === 'es' ? 'Resultado de la conversación' : 'Conversation outcome',
    source_next_step: lang === 'es' ? 'Siguiente acción acordada' : 'Agreed next action',
    source_occurred_at: lang === 'es' ? 'Fecha de la conversación' : 'Conversation date',
    contacts: lang === 'es' ? 'Personas vinculadas' : 'Linked people',
    opportunity_title: lang === 'es' ? 'Oportunidad vinculada' : 'Linked opportunity',
    insight: lang === 'es' ? 'Información relevante' : 'Insight',
    result: lang === 'es' ? 'Resultado' : 'Outcome',
    next_step: lang === 'es' ? 'Próximo paso' : 'Next step',
    follow_up_at: lang === 'es' ? 'Seguimiento previsto' : 'Follow-up date',
    task_type: lang === 'es' ? 'Tipo de tarea' : 'Task type',
    target_role: lang === 'es' ? 'Puesto objetivo' : 'Target role',
    role_fit: lang === 'es' ? 'Encaje con el puesto' : 'Role fit',
    primary_risk: lang === 'es' ? 'Riesgo registrado' : 'Recorded risk',
    location: lang === 'es' ? 'Ubicación' : 'Location',
    work_mode: lang === 'es' ? 'Modalidad' : 'Work arrangement',
    submission_evidence: lang === 'es' ? 'Evidencia de candidatura' : 'Submission evidence',
    missing_snapshot_reason: lang === 'es' ? 'Descripción del puesto no disponible' : 'Missing role description',
    missing_material_reason: lang === 'es' ? 'Materiales no disponibles' : 'Missing materials',

    due_at: lang === 'es' ? 'Fecha prevista' : 'Due date',
    state: lang === 'es' ? 'Estado' : 'State',
    priority: lang === 'es' ? 'Prioridad' : 'Priority',
    completed_at: lang === 'es' ? 'Completada' : 'Completed',
    source_interaction_title: lang === 'es' ? 'Interacción de origen' : 'Source interaction',
    events: lang === 'es' ? 'Historial reciente' : 'Recent history',
    interaction_type: lang === 'es' ? 'Tipo de interacción' : 'Interaction type',
    occurred_at: lang === 'es' ? 'Fecha' : 'Date',
    summary: lang === 'es' ? 'Resumen' : 'Summary',
    status: lang === 'es' ? 'Estado' : 'Status',
    next_step_at: lang === 'es' ? 'Próximo paso' : 'Next step',
    company_name: lang === 'es' ? 'Empresa' : 'Company',
    role_title: lang === 'es' ? 'Puesto' : 'Role',
    submitted_at: lang === 'es' ? 'Fecha de candidatura' : 'Submission date',
    channel: lang === 'es' ? 'Canal' : 'Channel',
    current_state: lang === 'es' ? 'Estado actual' : 'Current state',
    state_recorded_at: lang === 'es' ? 'Fecha del estado' : 'State date',
    latest_event_type: lang === 'es' ? 'Último evento' : 'Latest event',
    latest_event_at: lang === 'es' ? 'Fecha del último evento' : 'Latest event date',
    latest_event_note: lang === 'es' ? 'Nota del último evento' : 'Latest event note',
  };
  function contextValue(key: string, value: unknown): string {
    if (value === null || value === '') return copy.missing;
    if (key === 'contacts' && Array.isArray(value)) return value.map((contact) => `${contact.name}${contact.job_title ? ` · ${contact.job_title}` : ''}`).join('\n');
    if (key === 'events' && Array.isArray(value)) return value.length ? value.map((event) => `${localizeValue(event.event_type, lang)} · ${formatDate(event.occurred_at, lang)}${event.previous_state && event.new_state && event.previous_state !== event.new_state ? ` · ${localizeValue(event.previous_state, lang)} → ${localizeValue(event.new_state, lang)}` : ''}${event.note ? ` — ${event.note}` : ''}`).join('\n') : copy.missing;
    if (key.endsWith('_at') && typeof value === 'string') return formatDate(value, lang);
    return ['state', 'status', 'current_state', 'latest_event_type', 'channel', 'interaction_type'].includes(key) ? localizeValue(value, lang) : typeof value === 'string' ? value : JSON.stringify(value);
  }

  // React state setters are stable; the compiler currently fails to infer that
  // for this callback after the owner-only promotion action was added.
  // oxlint-disable react/react-compiler
  const load = useCallback(async () => {
    setLoading(true); setError(null);
    try {
      const [crm, monitoring] = await Promise.all([getDashboardSnapshot(), getMvpSnapshot()]);
      setSnapshot(crm); setMvp(monitoring); setSignedIn(true);
    } catch {
      setError('load'); setSignedIn(hasOrbitSession());
    } finally { setLoading(false); }
  }, []);
  // oxlint-enable react/react-compiler
  useEffect(() => { if (hasOrbitSession()) window.setTimeout(() => void load(), 0); }, [load]);
  async function submit(event: { preventDefault(): void }) {
    event.preventDefault(); setLoading(true); setError(null);
    try { await signIn(email, password); setSignedIn(true); setPassword(''); await load(); }
    catch { setError('auth'); setLoading(false); }
  }
  function signOut() { setEditingTask(null); setDismissRole(null); setSelected(null); clearOrbitSession(); setSnapshot(null); setMvp(null); setSignedIn(false); }
  const language = <div className="lang-toggle" aria-label={lang === 'es' ? 'Idioma' : 'Language'}><button onClick={() => setLang('es')} aria-pressed={lang === 'es'}>ES</button><button onClick={() => setLang('en')} aria-pressed={lang === 'en'}>EN</button></div>;

  const topbar = <header className="site-header crm-topbar"><Link className="crm-topbar-home" href="/">{copy.back}</Link><div className="crm-session-actions">{language}{signedIn && <button className="crm-signout" type="button" onClick={signOut}>{copy.logout}</button>}</div></header>;

  if (!hasBrowserConfig()) return <>{topbar}<main className="crm-shell"><section className="crm-card crm-login"><Link className="crm-login-brand" href="/" aria-label={copy.back}><Image src="/orbit-crm-wordmark.png" alt="Orbit CRM" width={2172} height={724} unoptimized /></Link><h1>{copy.config}</h1><p>{copy.configBody}</p><div className="crm-links"><Link href="/">{copy.back}</Link></div></section></main></>;
  if (!signedIn) return <>{topbar}<main className="crm-shell"><section className="crm-card crm-login"><Link className="crm-login-brand" href="/" aria-label={copy.back}><Image src="/orbit-crm-wordmark.png" alt="Orbit CRM" width={2172} height={724} unoptimized /></Link><div className="crm-login-head"><div><p className="eyebrow">{copy.private}</p><h1>{copy.login}</h1><p>{copy.loginIntro}</p></div></div><form onSubmit={submit} className="crm-form"><label>{copy.email}<input type="email" value={email} onChange={(event) => setEmail(event.target.value)} required autoComplete="username" /></label><label>{copy.password}<input type="password" value={password} onChange={(event) => setPassword(event.target.value)} required autoComplete="current-password" /></label><button type="submit" disabled={loading}>{loading ? copy.checking : copy.enter}</button></form><div className="crm-links"><Link href="/">{copy.back}</Link></div>{error && <p role="alert" className="crm-error">{error === 'auth' ? copy.authFailed : copy.loadFailed}</p>}</section></main></>;

  const detail = recordContext?.id === selected?.id ? recordContext?.data : null;
  const narrativeKeys = ['notes', 'summary', 'source_summary', 'insight', 'result', 'source_result', 'next_step', 'source_next_step', 'submission_evidence'];
  const orderedKeys = [...narrativeKeys, 'contacts', 'company_name', 'opportunity_title', 'source_interaction_title', 'source_occurred_at', 'events', ...Object.keys(fieldLabels)];
  const detailFields = [...new Set(orderedKeys)].filter((key) => detail && detail[key] !== null && detail[key] !== undefined && detail[key] !== '' && (!Array.isArray(detail[key]) || (detail[key] as unknown[]).length > 0));

  const primaryContextKeys = ['status', 'state', 'current_state', 'priority', 'company_name', 'due_at', 'occurred_at', 'submitted_at', ...narrativeKeys];
  const importedValues = typeof detail?.notes === 'string' ? parseNoteFields(detail.notes, displayText(selected?.title)).entries.map(entry => entry.value.trim()) : [];
  const duplicatedFields = detailFields.filter(key => key !== 'notes' && narrativeKeys.includes(key) && typeof detail?.[key] === 'string' && importedValues.includes(String(detail[key]).trim()));
  const primaryFields = [...new Set(primaryContextKeys)].filter(key => detailFields.includes(key) && !duplicatedFields.includes(key));
  const secondaryFields = detailFields.filter(key => !primaryFields.includes(key) && !duplicatedFields.includes(key));
  const contextField = (key: string) => <div key={key} className={narrativeKeys.includes(key) || key === 'events' ? 'crm-context-wide' : undefined}><dt>{fieldLabels[key]}</dt><dd>{narrativeKeys.includes(key) && typeof detail?.[key] === 'string' ? <RecordNotes text={detail[key]} title={displayText(selected?.title)} lang={lang} /> : contextValue(key, detail?.[key])}</dd></div>;
  return <>{topbar}<main className="crm-shell">
    {editingTask && <TaskEditor id={editingTask} lang={lang} onClose={()=>setEditingTask(null)} onSaved={()=>{setEditingTask(null);setTaskSaved(true);void load();}} />}
    {taskSaved && <output className="crm-wide">{lang==='es'?'Cambios de la tarea guardados y verificados.':'Task changes saved and verified.'}</output>}
    <dialog ref={dismissalDialog} className="crm-dialog" aria-labelledby="dismiss-title" onCancel={event => { if (dismissBusy) event.preventDefault(); else setDismissRole(null); }} onPointerDown={event => { if (event.target !== event.currentTarget || dismissBusy) return; const r = event.currentTarget.getBoundingClientRect(); if (event.clientX < r.left || event.clientX > r.right || event.clientY < r.top || event.clientY > r.bottom) setDismissRole(null); }}>
      <div className="crm-dialog-head"><h2 id="dismiss-title">{lang === 'es' ? 'Desactivar oferta' : 'Dismiss role'}</h2><button type="button" className="crm-dialog-close" aria-label={copy.close} disabled={dismissBusy} onClick={() => setDismissRole(null)}>×</button></div>
      <form className="crm-form crm-dismiss-form" onSubmit={confirmDismissal}><strong>{dismissRole?.company_name} · {dismissRole?.title}</strong><p>{lang === 'es' ? 'Se retirará de tu lista y se guardarán el motivo y la fecha. La vacante y las candidaturas conservarán su historial.' : 'This removes the role from your shortlist and records the reason and date. Vacancy and application history are preserved.'}</p><label>{lang === 'es' ? 'Motivo de desactivación' : 'Reason for dismissal'}<textarea autoFocus required maxLength={2000} rows={4} value={dismissReason} disabled={dismissBusy} onChange={event => setDismissReason(event.target.value)} /></label>{dismissError && <p role="alert" className="crm-error">{lang === 'es' ? 'No se ha podido verificar el guardado. Conservamos tu motivo; vuelve a intentarlo.' : 'The save could not be verified. Your reason is retained; please retry.'}</p>}<div className="crm-role-actions"><button type="button" disabled={dismissBusy} onClick={() => setDismissRole(null)}>{lang === 'es' ? 'Cancelar' : 'Cancel'}</button><button type="submit" disabled={dismissBusy || !dismissReason.trim()}>{dismissBusy ? copy.checking : lang === 'es' ? 'Confirmar desactivación' : 'Confirm dismissal'}</button></div></form>
    </dialog>
    <section className="crm-heading"><div><p className="eyebrow">{copy.private}</p><h1 className="crm-brand-title" aria-label={copy.title}><Link href="/" aria-label={copy.back}><Image src="/orbit-crm-wordmark.png" alt="Orbit CRM" width={2172} height={724} unoptimized /></Link></h1></div><p className="crm-intro">{copy.intro}</p><div className="crm-links"><Link href="/">{copy.back}</Link></div></section>
    {error && <p role="alert" className="crm-error crm-wide">{error === 'auth' ? copy.authFailed : copy.loadFailed}</p>}{loading && <p className="crm-muted crm-wide">{copy.updating}</p>}
    {snapshot && <><section className="crm-metrics">{Object.entries(snapshot.counts).map(([label, value]) => <article className="crm-metric" key={label}><div className="crm-metric-title"><span>{copy.metrics[label as keyof typeof copy.metrics]}</span><button className="crm-kpi-help" type="button" aria-label={`${lang === 'es' ? 'Cómo se calcula' : 'How it is calculated'}: ${copy.metrics[label as keyof typeof copy.metrics]}`} aria-expanded={metricHelp === label} aria-controls={`kpi-help-${label}`} onClick={() => setMetricHelp(metricHelp === label ? null : label)}><CircleHelp aria-hidden="true" /></button></div><strong>{value}</strong>{metricHelp === label && <p className="crm-kpi-definition" id={`kpi-help-${label}`}>{metricDefinitions[label]}</p>}</article>)}</section></>}
    <div className="crm-tabs" role="tablist" aria-label={copy.title}>{Object.entries(copy.tabs).map(([key, label], index, entries) => <button key={key} id={`tab-${key}`} role="tab" aria-selected={tab === key} aria-controls={`panel-${key}`} tabIndex={tab === key ? 0 : -1} onClick={() => setTab(key)} onKeyDown={(event) => { const next = event.key === 'ArrowRight' ? (index + 1) % entries.length : event.key === 'ArrowLeft' ? (index + entries.length - 1) % entries.length : event.key === 'Home' ? 0 : event.key === 'End' ? entries.length - 1 : null; if (next !== null) { event.preventDefault(); setTab(entries[next][0]); document.getElementById(`tab-${entries[next][0]}`)?.focus(); } }}>{label}</button>)}</div>
    <section id="panel-crm" role="tabpanel" aria-labelledby="tab-crm" hidden={tab !== 'crm'} tabIndex={0}>{snapshot && <section className="crm-grid">
      <article className="crm-card"><h2>{copy.tasks}</h2>{snapshot.due_tasks.length ? <ul>{snapshot.due_tasks.map((task) => <li key={task.id}><button type="button" className="crm-record" onClick={() => openRecord(task, 'task')}><strong>{task.title}</strong><span>{formatDate(task.due_at, lang)} · {localizeValue(task.state, lang)}</span></button><button type="button" className="crm-task-edit" aria-label={`${lang==='es'?'Actualizar tarea':'Update task'}: ${task.title}`} onClick={()=>{setTaskSaved(false);setEditingTask(task.id);}}>{lang==='es'?'Comentar / cambiar estado':'Comment / change state'}</button></li>)}</ul> : <p className="crm-muted">{copy.noTasks}</p>}</article>
      <article className="crm-card"><h2>{copy.applications}</h2>{snapshot.recent_applications.length ? <ul>{snapshot.recent_applications.map((item) => <li key={item.id}><button type="button" className="crm-record" onClick={() => openRecord(item, 'application')}><strong>{item.company_name}{item.role_title ? ` · ${item.role_title}` : ''}</strong><span>{formatDate(item.submitted_at, lang)} · {localizeValue(item.channel, lang)}</span><span><b>{copy.state}:</b> {item.current_state ? localizeValue(item.current_state, lang) : copy.noState}{item.state_recorded_at ? ` · ${formatDate(item.state_recorded_at, lang)}` : ''}</span></button></li>)}</ul> : <p className="crm-muted">{copy.noApplications}</p>}</article>
      <article className="crm-card"><h2>{copy.interactions}</h2>{snapshot.recent_interactions.length ? <ul>{snapshot.recent_interactions.map((item) => <li key={item.id}><button type="button" className="crm-record" onClick={() => openRecord(item, 'interaction')}><strong>{item.title}</strong><span>{formatDate(item.occurred_at, lang)}</span></button></li>)}</ul> : <p className="crm-muted">{copy.noInteractions}</p>}</article>
      <article className="crm-card"><h2>{copy.opportunities}</h2>{snapshot.active_opportunities.length ? <ul>{snapshot.active_opportunities.map((item) => <li key={item.id}><button type="button" className="crm-record" onClick={() => openRecord(item, 'opportunity')}><strong>{item.title}</strong><span>{item.status ? localizeValue(item.status, lang) : '—'} · {formatDate(item.next_step_at, lang)}</span></button></li>)}</ul> : <p className="crm-muted">{copy.noOpportunities}</p>}</article>
      <article className="crm-card"><h2>{copy.completedTasks}</h2>{snapshot.recent_completed_tasks.length ? <ul>{snapshot.recent_completed_tasks.map((task) => <li key={task.id}><button type="button" className="crm-record" onClick={() => openRecord(task, 'task')}><strong>{task.title}</strong><span>{formatDate(task.completed_at, lang)}</span></button></li>)}</ul> : <p className="crm-muted">{copy.noCompletedTasks}</p>}</article>
    </section>}</section>
    {mvp && <section className="crm-monitoring">
      <article id="panel-jobs" role="tabpanel" aria-labelledby="tab-jobs" hidden={tab !== 'jobs'} tabIndex={0} className="crm-card crm-span"><h2>{copy.jobs}</h2><JobRadar lang={lang} />{dismissNotice && <output>{lang === 'es' ? 'Oferta desactivada. Motivo y fecha guardados.' : 'Role dismissed. Reason and date saved.'}</output>}{promotionNotice === 'success' && <output>{lang === 'es' ? 'Oportunidad creada y verificada. La candidatura se completa en la web de la empresa.' : 'Opportunity created and verified. Complete the application on the employer website.'}</output>}{promotionNotice === 'error' && <p role="alert" className="crm-error">{lang === 'es' ? 'No se pudo verificar la oportunidad. No se ha registrado ninguna candidatura.' : 'The opportunity could not be verified. No application was recorded.'}</p>}{mvp.job_roles.length ? <div className="crm-role-grid">{mvp.job_roles.map((role) => <section className="crm-role" key={role.id}><div className="crm-role-heading"><div><p className="crm-company">{role.company_name}</p><h3>{role.title}</h3></div><strong className="crm-score">{role.score ?? '—'} <small>{copy.score}</small></strong></div><p>{role.location ?? '—'} · {role.work_arrangement ? localizeValue(role.work_arrangement, lang) : '—'} · {formatDate(role.last_seen_at, lang)}</p><p className="crm-muted">{copy.original}</p><p>{role.rationale}</p><p><b>{copy.confidence}:</b> {role.confidence === null ? '—' : `${Math.round(role.confidence * 100)}%`}</p>{role.gaps.length > 0 && <p><b>{copy.gaps}:</b> {role.gaps.join(' · ')}</p>}<div className="crm-role-actions"><a href={role.source_url} target="_blank" rel="noreferrer">{copy.source} ↗</a><button type="button" disabled={promotingJobId !== null} onClick={() => void promoteRole(role)}>{promotingJobId === role.id ? copy.checking : lang === 'es' ? 'Avanzar y abrir candidatura' : 'Pursue and open application'}</button><button type="button" disabled={promotingJobId !== null} onClick={() => { setDismissReason(''); setDismissError(false); setDismissRole(role); }}>{lang === 'es' ? 'Desactivar oferta' : 'Dismiss role'}</button></div></section>)}</div> : <p className="crm-muted">{copy.noJobs}</p>}{mvp.dismissed_jobs.length > 0 && <details className="crm-dismissed-history"><summary>{lang === 'es' ? 'Ofertas desactivadas' : 'Dismissed roles'} ({mvp.dismissed_jobs.length})</summary><ul>{mvp.dismissed_jobs.map(job => <li key={job.id}><strong>{job.company_name} · {job.title}</strong><span>{formatDate(job.dismissed_at, lang)}</span><p>{job.reason}</p></li>)}</ul></details>}</article>
      <article id="panel-market" role="tabpanel" aria-labelledby="tab-market" hidden={tab !== 'market'} tabIndex={0} className="crm-card crm-span"><h2>{copy.market}</h2>{mvp.market_signals.length ? <div className="crm-signal-grid">{mvp.market_signals.map((signal) => <section className="crm-signal" key={signal.id}><p className="crm-company">{signal.signal_type} · {formatDate(signal.signal_date, lang)}</p><p className="crm-muted">{copy.original}</p><h3>{signal.title}</h3><p>{signal.search_implication}</p><p><b>{copy.action}:</b> {signal.suggested_action}</p><a href={signal.source_url} target="_blank" rel="noreferrer">{copy.source} ↗</a></section>)}</div> : <p className="crm-muted">{copy.noMarket}</p>}</article>
      <article id="panel-executions" role="tabpanel" aria-labelledby="tab-executions" hidden={tab !== 'executions'} tabIndex={0} className="crm-card crm-span"><Executions executions={mvp.executions} lang={lang} /></article>
    </section>}
    <dialog ref={dialog} className="crm-dialog" aria-labelledby="crm-dialog-title" onClose={() => { if (!dialog.current?.open) setSelected(null); }}>
      {selected && <><div className="crm-dialog-head"><div><p className="eyebrow">{copy.context}</p><h2 id="crm-dialog-title">{displayText(selected.title, selected.role_title, selected.company_name)}</h2></div><button type="button" className="crm-dialog-close" aria-label={copy.close} onClick={() => setSelected(null)} autoFocus>×</button></div><div className="crm-dialog-body" aria-busy={contextStatus === 'loading'}>
        {contextStatus === 'loading' && <output>{copy.contextLoading}</output>}
        {contextStatus === 'error' && <p role="alert" className="crm-error">{copy.contextError}</p>}
        {contextStatus === 'ready' && !detail && <p>{copy.unavailable}</p>}
        {detail && <><p className="crm-muted">{copy.original}</p>{!narrativeKeys.some((key) => detail[key]) && <p className="crm-context-empty">{copy.noContext}</p>}<dl className="crm-context-main">{primaryFields.map(contextField)}</dl>{secondaryFields.length > 0 && <details className="crm-note-extra"><summary>{lang === 'es' ? 'Más información registrada' : 'More recorded information'}</summary><dl>{secondaryFields.map(contextField)}</dl></details>}</>}
      </div></>}
    </dialog>
  </main></>;
}
