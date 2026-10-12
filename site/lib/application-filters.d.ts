type FilterRow = {company_name: string; current_state?: string | null; channel: string; submitted_at: string; role_title?: string | null};
export function parseApplicationRegister(body: unknown): Array<FilterRow & {id: string}>;
export function filterApplications<T extends FilterRow>(rows: T[], filters: {company?: string; state?: string; query?: string; channel?: string; from?: string; to?: string}): T[];
