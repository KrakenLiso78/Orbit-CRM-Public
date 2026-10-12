import type { MvpSnapshot } from './orbit-crm';
export function readLatestProcessExecutions(fetcher: typeof fetch, url: string, headers: Record<string, string>): Promise<MvpSnapshot['executions']>;
export function mergeExecutionHistory(recent: MvpSnapshot['executions'], latest: MvpSnapshot['executions']): MvpSnapshot['executions'];
