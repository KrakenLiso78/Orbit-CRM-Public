import { Fragment } from 'react';
import { parseNoteFields } from '../../lib/orbit-note-fields.mjs';

function LinkedText({ text }: { text: string }) {
  const parts = text.split(/(\[[^\]\n]+\]\(https?:\/\/[^\s)]+\)|[^\n()[\]]{1,80}\s*\(https?:\/\/[^\s)]+\)|https?:\/\/[^\s)]+)/g);
  return <>{parts.map((part, index) => {
    const link = part.match(/^\[([^\]]+)\]\((https?:\/\/[^\s)]+)\)$/) ?? part.match(/^(.+?)\s*\((https?:\/\/[^\s)]+)\)$/);
    if (!link && /^https?:\/\//.test(part)) return <a key={index} href={part.replace(/[.,;]+$/, '')} target="_blank" rel="noreferrer">{part.match(/^https?:\/\/([^/]+)/)?.[1] ?? part} ↗</a>;
    return link ? <a key={index} href={link[2]} target="_blank" rel="noreferrer">{link[1].trim()} ↗</a> : <Fragment key={index}>{part}</Fragment>;
  })}</>;
}
function NoteValue({ value, lang }: { value: string; lang: 'es' | 'en' }) {
  if (value.length <= 550) return <div className="crm-note-value"><LinkedText text={value} /></div>;
  return <details className="crm-long-note"><summary>{value.slice(0,180)}… <span>{lang === 'es' ? 'Leer completo' : 'Read in full'}</span></summary><div className="crm-note-value"><LinkedText text={value} /></div></details>;
}
export default function RecordNotes({ text, title, lang }: { text: string; title: string; lang: 'es' | 'en' }) {
  const parsed = parseNoteFields(text, title);
  if (!parsed.entries.length) return <NoteValue value={text} lang={lang} />;
  const main = parsed.entries.filter(entry => /^(notas?|notes?|resumen|summary|pr[oó]ximo paso|next step|narrativa clave|key narrative)$/i.test(entry.label));
  const metadata = parsed.entries.filter(entry => !main.includes(entry));
  return <div className="crm-imported-notes">
    {parsed.text && <NoteValue value={parsed.text} lang={lang} />}
    {main.map((entry,index) => <section className="crm-note-section" key={index}><h3 className="crm-note-label">{entry.label}</h3><NoteValue value={entry.value} lang={lang} /></section>)}
    <details className="crm-note-extra"><summary>{lang === 'es' ? 'Datos del texto original' : 'Original text fields'} ({metadata.length})</summary><dl>{metadata.map((entry,index) => <div key={index}><dt>{entry.label}</dt><dd><LinkedText text={entry.value} /></dd></div>)}</dl><details><summary>{lang === 'es' ? 'Ver texto original completo' : 'View full original text'}</summary><pre>{text}</pre></details></details>
  </div>;
}
