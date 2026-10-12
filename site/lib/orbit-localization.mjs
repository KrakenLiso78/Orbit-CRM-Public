// Translate controlled display values; retain original notes and unknown source text.
const labels = {
  submitted: ['Enviada', 'Submitted'], rejected: ['Rechazada', 'Rejected'], interview: ['Entrevista', 'Interview'], cancelled: ['Cancelada', 'Cancelled'], withdrawn: ['Retirada', 'Withdrawn'], offer: ['Oferta recibida', 'Offer received'], accepted: ['Aceptada', 'Accepted'], reopened: ['Reabierta', 'Reopened'], follow_up: ['Seguimiento', 'Follow-up'], correction: ['Corrección', 'Correction'], other: ['Otro', 'Other'],
  commented: ['Comentario', 'Comment'],
  created: ['Creada', 'Created'], postponed: ['Pospuesta', 'Postponed'], started: ['Iniciada', 'Started'], completed: ['Completada', 'Completed'], blocked: ['Bloqueada', 'Blocked'], corrected: ['Corregida', 'Corrected'],
  '0-Backlog': ['Pendiente', 'Backlog'], '1-En curso': ['En curso', 'In progress'], '2-Completada': ['Completada', 'Completed'], '3-Bloqueada': ['Bloqueada', 'Blocked'], '4-Cancelada': ['Cancelada', 'Cancelled'],
  'Contacto hecho': ['Contacto hecho', 'Contact made'], 'Nueva': ['Nueva', 'New'], 'Archivada': ['Archivada', 'Archived'], 'Usada en outreach': ['Usada en contacto profesional', 'Used in outreach'],
  open: ['Abierta', 'Open'], closed: ['Cerrada', 'Closed'], unknown: ['Desconocido', 'Unknown'], unavailable: ['No disponible', 'Unavailable'],
  rechazada: ['Rechazada', 'Rejected'], cerrada: ['Cerrada', 'Closed'], screening: ['Evaluación inicial', 'Screening'],
  succeeded: ['Completada', 'Succeeded'], partial: ['Parcial', 'Partial'], failed: ['Fallida', 'Failed'], running: ['En curso', 'Running'], queued: ['En cola', 'Queued'],
  job_discovery: ['Búsqueda de empleo', 'Job discovery'], market_review: ['Revisión de mercado', 'Market review'],
  codex_local: ['Codex local', 'Local Codex'], manual: ['Manual', 'Manual'], sites: ['Sites', 'Sites'], supabase: ['Supabase', 'Supabase'],
  website: ['Web', 'Website'],
  direct: ['Solicitud directa', 'Direct application'], referral: ['Referencia profesional', 'Referral'], networking: ['Contacto profesional', 'Networking'],
  hybrid: ['Híbrido', 'Hybrid'], remote: ['Remoto', 'Remote'], onsite: ['Presencial', 'On-site'], 'on-site': ['Presencial', 'On-site'],
};
export function localizeValue(value, lang) {
  if (typeof value !== 'string') return String(value ?? '');
  const pair = labels[value] ?? labels[value.toLowerCase()];
  return pair ? pair[lang === 'es' ? 0 : 1] : value;
}
