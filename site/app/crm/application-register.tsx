'use client';
import {useEffect,useState} from 'react';
import {DashboardSnapshot,getApplicationRegister} from '../../lib/orbit-crm';
import {localizeValue} from '../../lib/orbit-localization.mjs';
import {filterApplications} from '../../lib/application-filters.mjs';
type Row=DashboardSnapshot['recent_applications'][number];
export default function ApplicationRegister({lang,onOpen}:{lang:'es'|'en';onOpen:(row:Row)=>void}){
 const [rows,setRows]=useState<Row[]>([]),[loading,setLoading]=useState(true),[error,setError]=useState(false);
 const [company,setCompany]=useState(''),[state,setState]=useState(''),[query,setQuery]=useState(''),[channel,setChannel]=useState(''),[from,setFrom]=useState(''),[to,setTo]=useState('');
 const es=lang==='es';
 async function load(){setLoading(true);setError(false);try{setRows(await getApplicationRegister());}catch{setError(true);}finally{setLoading(false);}}
 useEffect(()=>{
  let active=true;
  void getApplicationRegister().then(result=>{if(active)setRows(result);}).catch(()=>{if(active)setError(true);}).finally(()=>{if(active)setLoading(false);});
  return ()=>{active=false;};
 },[]);
 const visible:Row[]=filterApplications(rows,{company,state,query,channel,from,to});
 const options=(values:string[])=>Array.from(new Set(values)).sort();
 function reset(){setCompany('');setState('');setQuery('');setChannel('');setFrom('');setTo('');}
 return <section aria-label={es?'Registro de candidaturas':'Application register'}>
 <h2>{es?'Todas las candidaturas':'All applications'}</h2>
 <p>{es?'Incluye todos los estados y conserva el historial de cada candidatura.':'Includes every state and retains each application’s history.'}</p>
 <div className="crm-register-filters">
 <label>{es?'Buscar empresa o puesto':'Search company or role'}<input type="search" value={query} onChange={e=>setQuery(e.target.value)}/></label>
 <label>{es?'Empresa':'Company'}<select value={company} onChange={e=>setCompany(e.target.value)}><option value="">{es?'Todas las empresas':'All companies'}</option>{options(rows.map(r=>r.company_name)).map(x=><option key={x}>{x}</option>)}</select></label>
 <label>{es?'Estado':'State'}<select value={state} onChange={e=>setState(e.target.value)}><option value="">{es?'Todos los estados':'All states'}</option>{options(['submitted','interview','withdrawn','cancelled','rejected','offer','accepted','reopened',...rows.map(r=>r.current_state??'unknown')]).map(x=><option value={x} key={x}>{x==='unknown'?(es?'Sin estado registrado':'No recorded state'):localizeValue(x,lang)}</option>)}</select></label>
 <label>{es?'Canal':'Channel'}<select value={channel} onChange={e=>setChannel(e.target.value)}><option value="">{es?'Todos los canales':'All channels'}</option>{options(rows.map(r=>r.channel)).map(x=><option value={x} key={x}>{localizeValue(x,lang)}</option>)}</select></label>
 <label>{es?'Desde':'From'}<input type="date" value={from} onInput={e=>setFrom(e.currentTarget.value)}/></label>
 <label>{es?'Hasta':'To'}<input type="date" value={to} onInput={e=>setTo(e.currentTarget.value)}/></label>
 </div>
 <button className="crm-task-edit" type="button" onClick={reset}>{es?'Restablecer filtros':'Reset filters'}</button>
 {loading?<output>{es?'Cargando…':'Loading…'}</output>:error?<div role="alert"><p>{es?'No se pudieron cargar las candidaturas.':'Applications could not be loaded.'}</p><button type="button" onClick={()=>void load()}>{es?'Reintentar':'Retry'}</button></div>:<>
 <output>{visible.length} / {rows.length} {es?'candidaturas':'applications'}</output>
 {visible.length?<div className="crm-register-results">{visible.map(r=><article className="crm-card" key={r.id}><button className="crm-record" type="button" onClick={()=>onOpen(r)}><strong>{r.company_name}{r.role_title?' · '+r.role_title:''}</strong><span>{r.current_state?localizeValue(r.current_state,lang):(es?'Sin estado registrado':'No recorded state')}</span><span>{new Intl.DateTimeFormat(es?'es-ES':'en-GB',{dateStyle:'medium'}).format(new Date(r.submitted_at))} · {localizeValue(r.channel,lang)}</span></button></article>)}</div>:<p>{es?'No hay candidaturas que coincidan con estos filtros.':'No applications match these filters.'}</p>}
 </>}
 </section>;
}
