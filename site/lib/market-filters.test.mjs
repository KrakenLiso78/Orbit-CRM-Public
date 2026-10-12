import assert from 'node:assert/strict';
import test from 'node:test';

import { ALL_FILTER, filterMarketCompanies } from './market-filters.mjs';

const companies = [
  { company: 'Alpha', movement: 1, therapeuticAreas: ['oncology'], crmCategory: 'veeva' },
  { company: 'Beta', movement: 0, therapeuticAreas: ['immunology', 'oncology'], crmCategory: 'salesforce' },
  { company: 'Gamma', movement: -1, therapeuticAreas: ['vaccines'], crmCategory: 'not_public' },
];

const defaults = { company: ALL_FILTER, trend: ALL_FILTER, therapeuticArea: ALL_FILTER, crm: ALL_FILTER };

void test('returns every company when filters are unset', () => {
  assert.deepEqual(filterMarketCompanies(companies, defaults), companies);
});

void test('filters independently by company, trend, therapeutic area, and CRM', () => {
  assert.deepEqual(filterMarketCompanies(companies, { ...defaults, company: 'Alpha' }).map((item) => item.company), ['Alpha']);
  assert.deepEqual(filterMarketCompanies(companies, { ...defaults, trend: 'stable' }).map((item) => item.company), ['Beta']);
  assert.deepEqual(filterMarketCompanies(companies, { ...defaults, therapeuticArea: 'oncology' }).map((item) => item.company), ['Alpha', 'Beta']);
  assert.deepEqual(filterMarketCompanies(companies, { ...defaults, crm: 'not_public' }).map((item) => item.company), ['Gamma']);
});

void test('combines filters and does not mutate the input', () => {
  const before = structuredClone(companies);
  const result = filterMarketCompanies(companies, { ...defaults, movement: 0, therapeuticArea: 'oncology', crm: 'salesforce' });
  assert.deepEqual(result.map((item) => item.company), ['Beta']);
  assert.deepEqual(companies, before);
});

 void test('uses chart rank movement even when sales classifications disagree', () => {
  const rows = [
    ['Eli Lilly', 0, 'growth'], ['Pfizer', -8, 'deterioration'], ['Johnson & Johnson', -2, 'growth'],
    ['AstraZeneca', 1, 'growth'], ['Merck / MSD', -3, 'stable'], ['Roche', 0, 'growth'],
    ['AbbVie', 3, 'growth'], ['Novartis', -1, 'stable'], ['Sanofi', 2, 'growth'], ['Bristol Myers Squibb', -2, 'deterioration'],
  ].map(([company, movement, trend]) => ({company, movement, trend, therapeuticAreas: [], crmCategory: 'veeva'}));
  const names = trend => filterMarketCompanies(rows, {...defaults, trend}).map(row => row.company);
  assert.deepEqual(names('growth'), ['AstraZeneca', 'AbbVie', 'Sanofi']);
  assert.deepEqual(names('stable'), ['Eli Lilly', 'Roche']);
  assert.deepEqual(names('deterioration'), ['Pfizer', 'Johnson & Johnson', 'Merck / MSD', 'Novartis', 'Bristol Myers Squibb']);
  assert.deepEqual(filterMarketCompanies(rows, {...defaults, company: 'Johnson & Johnson', trend: 'growth'}), []);
});
