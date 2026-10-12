const processes = ['job_discovery', 'market_review'];
const fields = 'id,monitor_type,execution_key,started_at,completed_at,status,scope,scheduler,dependency_note,summary,failures';

function validRun(run) {
  return run && typeof run === 'object' && !Array.isArray(run)
    && typeof run.id === 'string' && processes.includes(run.monitor_type)
    && Number.isFinite(Date.parse(run.started_at))
    && typeof run.execution_key === 'string' && typeof run.scheduler === 'string'
    && ['running', 'succeeded', 'partial', 'failed'].includes(run.status)
    && (run.completed_at === null || Number.isFinite(Date.parse(run.completed_at)))
    && (run.dependency_note === null || typeof run.dependency_note === 'string')
    && run.scope && typeof run.scope === 'object' && !Array.isArray(run.scope)
    && run.summary && typeof run.summary === 'object' && !Array.isArray(run.summary)
    && Array.isArray(run.failures);
}

export async function readLatestProcessExecutions(fetcher, url, headers) {
  const rows = await Promise.all(processes.map(async (process) => {
    const query = new URLSearchParams({ select: fields, monitor_type: `eq.${process}`, order: 'started_at.desc,id.desc', limit: '1' });
    const response = await fetcher(`${url}/rest/v1/monitor_executions?${query}`, { headers });
    if (!response.ok) throw new Error('The latest Orbit executions could not be loaded.');
    const body = await response.json();
    if (!Array.isArray(body) || body.length > 1 || body.some((run) => !validRun(run) || run.monitor_type !== process)) {
      throw new Error('Invalid latest Orbit execution response.');
    }
    return body;
  }));
  return rows.flat();
}

export function mergeExecutionHistory(recent, latest) {
  if (![...recent, ...latest].every(validRun)) throw new Error('Invalid Orbit execution history.');
  return [...new Map([...recent, ...latest].map((run) => [run.id, run])).values()]
    .sort((a, b) => Date.parse(b.started_at) - Date.parse(a.started_at) || b.id.localeCompare(a.id));
}
