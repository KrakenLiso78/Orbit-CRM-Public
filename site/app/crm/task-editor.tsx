'use client';
import { useEffect, useRef, useState } from 'react';
import { getTaskForUpdate, updateTaskProgress } from '../../lib/orbit-crm';
import { localizeValue } from '../../lib/orbit-localization.mjs';

type Task = { id: string; title: string; state: string; lock_version: number };
export default function TaskEditor({ id, lang, onClose, onSaved }: { id: string; lang: 'es' | 'en'; onClose: () => void; onSaved: () => void }) {
  const dialog = useRef<HTMLDialogElement>(null);
  const attempt = useRef<{ signature: string; key: string } | null>(null);
  const [task,setTask] = useState<Task | null>(null);
  const [state,setState] = useState('');
  const [comment,setComment] = useState('');
  const [busy,setBusy] = useState(false);
  const [loading,setLoading] = useState(true);
  const [error,setError] = useState<'load' | 'stale' | 'save' | null>(null);
  const es = lang === 'es';
  async function reloadTask() {
    setLoading(true); setError(null);
    try { const saved = await getTaskForUpdate(id); setTask(saved); setState(saved.state); attempt.current=null; }
    catch { setError('load'); } finally { setLoading(false); }
  }
  useEffect(() => {
    const element=dialog.current; element?.showModal();
    let cancelled=false;
    getTaskForUpdate(id).then(saved => { if (!cancelled) { setTask(saved); setState(saved.state); } }).catch(() => { if(!cancelled) setError('load'); }).finally(() => { if(!cancelled) setLoading(false); });
    return () => { cancelled=true; element?.close(); };
  },[id]);
  async function save(event: {preventDefault(): void}) {
    event.preventDefault(); if(!task || busy || (state===task.state && !comment.trim())) return;
    setBusy(true); setError(null);
    const signature=JSON.stringify([id,state,comment.trim(),task.lock_version]);
    if(attempt.current?.signature!==signature) attempt.current={signature,key:`task-ui:${crypto.randomUUID()}`};
    try { await updateTaskProgress(id,state,comment,task.lock_version,attempt.current.key); onSaved(); }
    catch(error) { setError(error instanceof Error && error.message==='stale' ? 'stale' : 'save'); } finally { setBusy(false); }
  }
  return <dialog ref={dialog} className="crm-dialog crm-task-editor" aria-labelledby="task-edit-title" onCancel={event=>{if(busy)event.preventDefault();else onClose();}} onPointerDown={event=>{if(busy || event.target!==event.currentTarget)return; const r=event.currentTarget.getBoundingClientRect();if(event.clientX<r.left||event.clientX>r.right||event.clientY<r.top||event.clientY>r.bottom)onClose();}}>
    <div className="crm-dialog-head"><h2 id="task-edit-title">{es?'Actualizar tarea':'Update task'}</h2><button type="button" className="crm-dialog-close" aria-label={es?'Cerrar':'Close'} disabled={busy} onClick={onClose}>×</button></div>
    <form className="crm-form crm-dismiss-form" onSubmit={save}>
      {loading && <output>{es?'Cargando tarea…':'Loading task…'}</output>}
      {task && <><strong>{task.title}</strong><label>{es?'Estado':'State'}<select value={state} disabled={busy||loading||error==='stale'} onChange={event=>setState(event.target.value)}>{['0-Backlog','1-En curso','3-Bloqueada','2-Completada','4-Cancelada'].map(value=><option key={value} value={value}>{localizeValue(value,lang)}</option>)}</select></label><label>{es?'Comentario':'Comment'}<textarea rows={3} maxLength={2000} value={comment} disabled={busy||loading} onChange={event=>setComment(event.target.value)} /></label><p className="crm-muted">{es?'El comentario se añadirá al historial, sin sustituir las notas anteriores.':'The comment is added to the history without replacing earlier notes.'}</p></>}
      {error && <p role="alert" className="crm-error">{error==='stale'?(es?'La tarea ha cambiado. Recárgala y revisa el estado antes de guardar; conservamos tu comentario.':'The task changed. Reload and review its state before saving; your comment is retained.'):error==='load'?(es?'No se pudo cargar la tarea.':'The task could not be loaded.'):(es?'No se pudo verificar el guardado. Conservamos tu comentario; puedes reintentar.':'The save could not be verified. Your comment is retained; you can retry.')}</p>}
      {(error==='stale'||error==='load') && <button type="button" disabled={busy||loading} onClick={()=>void reloadTask()}>{es?'Recargar tarea':'Reload task'}</button>}
      <div className="crm-role-actions"><button type="button" disabled={busy} onClick={onClose}>{es?'Cancelar':'Cancel'}</button><button type="submit" disabled={busy||loading||!task||error==='stale'||(state===task.state&&!comment.trim())}>{busy?(es?'Guardando…':'Saving…'):(es?'Guardar cambios':'Save changes')}</button></div>
    </form>
  </dialog>;
}
