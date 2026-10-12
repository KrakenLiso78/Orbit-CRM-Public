const states = ['active', 'manual_review', 'unavailable', 'paused'];
const validDate = value => value === null || (typeof value === 'string' && Number.isFinite(Date.parse(value)));

export function parseJobRadar(body, expectedCompanies) {
  if (!Array.isArray(body) || body.length >= 100) throw new Error('Invalid or truncated Orbit job radar.');
  const seen = new Set();
  const rows = body.map(row => {
    if (!row || typeof row.id !== 'string' || seen.has(row.id) || !row.companies || typeof row.companies.name !== 'string'
      || typeof row.source_name !== 'string' || typeof row.source_url !== 'string' || !row.source_url.startsWith('https://')
      || !states.includes(row.status) || !Number.isInteger(row.cadence_days) || row.cadence_days < 1 || row.cadence_days > 31
      || !Number.isInteger(row.priority_rank) || row.priority_rank < 1
      || !validDate(row.last_checked_at) || !validDate(row.last_successful_at) || !validDate(row.next_due_at)
      || (row.last_error !== null && typeof row.last_error !== 'string')) throw new Error('Invalid Orbit career-source evidence.');
    seen.add(row.id);
    return { ...row, company: row.companies.name };
  }).filter(row => expectedCompanies.includes(row.company));
  if (new Set(rows.map(row => row.company)).size !== expectedCompanies.length) throw new Error('The saved Orbit radar does not cover the complete approved company universe.');
  return rows.sort((a,b) => a.priority_rank-b.priority_rank || a.company.localeCompare(b.company));
}

export async function readJobRadar(fetcher, url, headers, expectedCompanies, signal) {
  const query = new URLSearchParams({select:'id,source_name,source_url,geography,source_scope,cadence_days,status,priority_rank,last_checked_at,last_successful_at,next_due_at,last_error,companies!inner(name)',order:'priority_rank.asc,id.asc',limit:'100'});
  const response = await fetcher(`${url}/rest/v1/career_sources?${query}`, {headers,signal});
  if (!response.ok) throw new Error('The Orbit job radar could not be loaded.');
  return parseJobRadar(await response.json(), expectedCompanies);
}
