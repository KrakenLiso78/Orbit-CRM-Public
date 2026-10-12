'use client';

import type { ReactNode } from 'react';
import type { MvpSnapshot } from '../../lib/orbit-crm';
import { localizeValue } from '../../lib/orbit-localization.mjs';
import { evidenceLabel, executionTime, recordedFailures, resultMetrics } from '../../lib/orbit-executions.mjs';

type Lang = 'es' | 'en';
function Evidence({ value, lang }: { value: unknown; lang: Lang }): ReactNode {
  if (value === null || value === undefined || value === '') return <span>{lang === 'es' ? 'No registrado' : 'Not recorded'}</span>;
  if (Array.isArray(value)) return <ul>{value.map((item, index) => <li key={index}><Evidence value={item} lang={lang} /></li>)}</ul>;
  if (typeof value === 'object') return <dl className="execution-evidence">{Object.entries(value).map(([key, item]) => <div key={key}><dt>{evidenceLabel(key, lang)}</dt><dd><Evidence value={item} lang={lang} /></dd></div>)}</dl>;
  if (typeof value === 'boolean') return <span>{lang === 'es' ? (value ? 'Sí' : 'No') : (value ? 'Yes' : 'No')}</span>;
  return <span>{typeof value === 'string' || typeof value === 'number' ? value : (lang === 'es' ? 'No registrado' : 'Not recorded')}</span>;
}
export default function Executions({ executions, lang }: { executions: MvpSnapshot['executions']; lang: Lang }) {
  const c = lang === 'es' ? {
    title: 'Ejecuciones y resultados', latest: 'Última ejecución por proceso', recent: 'Historial reciente', start: 'Inicio', end: 'Fin', result: 'Resultado registrado', empty: 'No hay ejecuciones registradas.', noResult: 'No hay un resumen del resultado registrado.', incidents: 'Errores y limitaciones', noIncidents: 'Sin incidencias registradas.', noCause: 'La causa no está registrada.', noFailureEvidence: 'El estado indica un resultado incompleto o fallido, pero no hay un motivo registrado.', evidence: 'Ver alcance y comprobaciones', original: 'Los detalles de evidencia se conservan en su idioma original.', schedule: 'Ejecutado mediante', time: 'Horas de Madrid', mac: 'Las programaciones locales dependen de que este Mac y su sesión autenticada estén disponibles.',
  } : {
    title: 'Executions and results', latest: 'Latest run by process', recent: 'Recent history', start: 'Started', end: 'Finished', result: 'Recorded result', empty: 'No recorded executions.', noResult: 'No result summary is recorded.', incidents: 'Errors and limitations', noIncidents: 'No recorded issues.', noCause: 'No cause is recorded.', noFailureEvidence: 'The status indicates an incomplete or failed result, but no reason is recorded.', evidence: 'View scope and checks', original: 'Evidence details are retained in their original language.', schedule: 'Executed through', time: 'Madrid time', mac: 'Local schedules depend on this Mac and its authenticated session being available.',
  };
  const latest = executions.filter((run, index) => executions.findIndex((other) => other.monitor_type === run.monitor_type) === index);
  return <><h2>{c.title}</h2><p className="crm-muted">{c.time} · {c.original}</p>{!executions.length ? <p>{c.empty}</p> : <>
    <h3>{c.latest}</h3><div className="execution-latest">{latest.map((run) => <a href={`#execution-${run.id}`} key={run.id}><strong>{localizeValue(run.monitor_type, lang)}</strong><span>{executionTime(run.started_at, lang)}</span><b className={`execution-status execution-${run.status}`}>{localizeValue(run.status, lang)}</b></a>)}</div>
    <h3>{c.recent}</h3><div className="execution-history">{executions.map((run) => {
      const failures = recordedFailures(run.failures);
      const metrics = resultMetrics(run.summary);
      const narrativeResult = Object.fromEntries(Object.entries(run.summary ?? {}).filter(([key]) => ['completion_scope', 'coverage', 'interpretation'].includes(key)));
      const summaryText = Object.fromEntries(Object.entries(run.summary ?? {}).filter(([key, value]) => typeof value !== 'number' && !['score_label', 'not_hiring_probability', 'completion_scope', 'coverage', 'interpretation'].includes(key)));
      return <details className="execution-run" id={`execution-${run.id}`} key={run.id} open={latest.some((item) => item.id === run.id)}>
        <summary className="execution-heading"><span className="execution-toggle" aria-hidden="true">▸</span><span className="execution-name"><strong>{localizeValue(run.monitor_type, lang)}</strong><span className="execution-date">{executionTime(run.started_at, lang)}</span></span><b className={`execution-status execution-${run.status}`}>{localizeValue(run.status, lang)}</b></summary>
        <p className="crm-muted">{c.start}: {executionTime(run.started_at, lang)} · {c.end}: {executionTime(run.completed_at, lang)}</p>
        <p className="crm-muted">{c.schedule}: {localizeValue(run.scheduler, lang)}</p>
        <h5>{c.result}</h5>{metrics.length > 0 && <dl className="execution-metrics">{metrics.map(([key, value]) => <div key={key}><dt>{evidenceLabel(key, lang)}</dt><dd>{new Intl.NumberFormat(lang === 'es' ? 'es-ES' : 'en-GB').format(value)}</dd></div>)}</dl>}
        {Object.keys(narrativeResult).length > 0 && <Evidence value={narrativeResult} lang={lang} />}
        {!metrics.length && !Object.keys(narrativeResult).length && !Object.keys(summaryText).length && <p>{c.noResult}</p>}
        <h5>{c.incidents}{failures.length > 0 ? ` (${failures.length})` : ''}</h5>{failures.length ? <ul className="execution-issues">{failures.map((failure, index) => <li key={index}>{failure.type && <strong>{evidenceLabel(failure.type, lang)}</strong>}{failure.source && <p><b>{evidenceLabel('source', lang)}:</b> {failure.source}</p>}<p>{failure.reason ?? c.noCause}</p></li>)}</ul> : <p>{['partial', 'failed', 'blocked'].includes(run.status) ? c.noFailureEvidence : c.noIncidents}</p>}
        <details><summary>{c.evidence}</summary>{Object.keys(summaryText).length > 0 && <Evidence value={summaryText} lang={lang} />}<h5>{evidenceLabel('scope', lang)}</h5><Evidence value={run.scope} lang={lang} />{run.dependency_note && <p>{run.dependency_note}</p>}</details>
      </details>;
    })}</div></>}<p className="crm-dependency">{c.mac}</p></>;
}
