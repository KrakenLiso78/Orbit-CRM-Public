export const ALL_FILTER: 'all';

export type MarketFilters = {
  company: string;
  trend: string;
  therapeuticArea: string;
  crm: string;
};

export type FilterableMarketCompany = {
  company: string;
  movement: number;
  therapeuticAreas: string[];
  crmCategory: string;
};

export function filterMarketCompanies<T extends FilterableMarketCompany>(companies: T[], filters: MarketFilters): T[];

export function rankMovementTrend(movement: number): 'growth' | 'stable' | 'deterioration';
