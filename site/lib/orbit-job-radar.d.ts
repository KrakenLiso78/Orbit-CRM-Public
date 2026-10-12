export type CareerSource = {id:string; company:string; source_name:string; source_url:string; geography:string; source_scope:string; cadence_days:number; status:string; priority_rank:number; last_checked_at:string|null; last_successful_at:string|null; next_due_at:string|null; last_error:string|null};
export function parseJobRadar(body:unknown, expectedCompanies:string[]):CareerSource[];
export function readJobRadar(fetcher:typeof fetch,url:string,headers:Record<string,string>,expectedCompanies:string[],signal?:AbortSignal):Promise<CareerSource[]>;
