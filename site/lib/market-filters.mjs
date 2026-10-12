export const ALL_FILTER = 'all';

export function rankMovementTrend(movement) {
  return movement > 0 ? 'growth' : movement < 0 ? 'deterioration' : 'stable';
}

export function filterMarketCompanies(companies, filters) {
  return companies.filter((company) => {
    if (filters.company !== ALL_FILTER && company.company !== filters.company) return false;
    if (filters.trend !== ALL_FILTER && rankMovementTrend(company.movement) !== filters.trend) return false;
    if (filters.therapeuticArea !== ALL_FILTER && !company.therapeuticAreas.includes(filters.therapeuticArea)) return false;
    if (filters.crm !== ALL_FILTER && company.crmCategory !== filters.crm) return false;
    return true;
  });
}
