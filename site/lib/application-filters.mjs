export function parseApplicationRegister(body) {
  if (!Array.isArray(body)) throw new Error('Application register unavailable');
  const seen = new Set();
  for (const row of body) {
    if (!row || typeof row.id !== 'string' || !/^[a-f0-9]{8}-(?:[a-f0-9]{4}-){3}[a-f0-9]{12}$/i.test(row.id)
      || seen.has(row.id) || typeof row.company_name !== 'string' || typeof row.channel !== 'string'
      || typeof row.submitted_at !== 'string' || !Number.isFinite(Date.parse(row.submitted_at))
      || (row.role_title !== null && typeof row.role_title !== 'string')
      || (row.current_state !== null && typeof row.current_state !== 'string')) throw new Error('Application register unavailable');
    seen.add(row.id);
  }
  return body;
}

export function filterApplications(rows, filters) {
  const { company = '', state = '', query = '', channel = '', from = '', to = '' } = filters;
  return rows.filter(row => (!company || row.company_name === company)
    && (!state || (row.current_state ?? 'unknown') === state)
    && (!channel || row.channel === channel)
    && (!from || row.submitted_at.slice(0, 10) >= from)
    && (!to || row.submitted_at.slice(0, 10) <= to)
    && (!query || [row.company_name, row.role_title].join(' ').toLocaleLowerCase().includes(query.toLocaleLowerCase())));
}
