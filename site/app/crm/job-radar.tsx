'use client';
import { useEffect, useState } from 'react';
import { getJobRadar } from '../../lib/orbit-crm';
import type { CareerSource } from '../../lib/orbit-job-radar';

export default function JobRadar({ lang }: { lang:'es'|'en' }) {
  const [state,setState]=useState<{rows:CareerSource[]|null;error:boolean}>({rows:null,error:false});
  useEffect(()=>{const controller=new AbortController();getJobRadar(controller.signal).then(rows=>{if(!controller.signal.aborted)setState({rows,error:false});}).catch(()=>{if(!controller.signal.aborted)setState({rows:null,error:true});});return()=>controller.abort();},[]);
  const es=lang==='es';
  const labels:Record<string,string>={active:es?'Activa':'Active',manual_review:es?'Revisión manual / cobertura parcial':'Manual review / partial coverage',unavailable:es?'No disponible':'Unavailable',paused:es?'En pausa':'Paused'};
  const date=(value:string|null)=>value?new Intl.DateTimeFormat(es?'es-ES':'en-GB',{dateStyle:'short',timeStyle:'short',timeZone:'Europe/Madrid'}).format(new Date(value)):(es?'Sin comprobar':'Not checked');
  return <section className="job-radar" aria-labelledby="job-radar-heading"><h3 id="job-radar-heading">Orbit Job Monitor · {es?'Radar de 25 empresas':'25-company radar'}</h3><p className="crm-muted">{es?'Todas las empresas permanecen en el radar aunque no haya ofertas preseleccionadas. Las comprobaciones usan los sitios oficiales; la cobertura parcial no equivale a cero vacantes.':'Every company remains in the radar even without shortlisted roles. Checks use official sources; partial coverage does not mean zero vacancies.'}</p>
    {state.error?<p role="alert" className="crm-error">{es?'No se pudo verificar el radar completo. No se muestra un registro incompleto como correcto.':'The complete radar could not be verified. An incomplete registry is not presented as successful.'}</p>:!state.rows?<p>{es?'Cargando radar…':'Loading radar…'}</p>:<><p><b>{new Set(state.rows.map(row=>row.company)).size}/25</b> · {es?'empresas registradas':'registered companies'}</p><details><summary>{es?'Ver empresas, fuentes y comprobaciones':'View companies, sources and checks'}</summary><div className="universe-grid">{state.rows.map(row=><article className="universe-card" key={row.id}><h4>{row.company}</h4><p><b>{labels[row.status]}</b></p><p>{es?'Frecuencia:':'Cadence:'} {row.cadence_days===1?(es?'diaria':'daily'):(es?`cada ${row.cadence_days} días`:`every ${row.cadence_days} days`)}</p><p>{es?'Última comprobación:':'Last check:'} {date(row.last_checked_at)}</p><p>{es?'Próxima revisión:':'Next due:'} {date(row.next_due_at)}</p><a href={row.source_url} target="_blank" rel="noreferrer">{es?'Fuente oficial de empleo':'Official careers source'} ↗</a>{row.last_error&&<details><summary>{es?'Limitación registrada (texto original)':'Recorded limitation (original text)'}</summary><p className="crm-muted">{row.last_error}</p></details>}</article>)}</div></details></>}
  </section>;
}
