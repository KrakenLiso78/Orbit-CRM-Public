'use client';
import { useState } from 'react';
import { syntheticMarket } from '../lib/synthetic-market.mjs';
export default function MarketUniverse({ lang }: { lang: 'es' | 'en' }) {
  const [company, setCompany] = useState('all');
  const es = lang === 'es';
  const rows = syntheticMarket.companies.filter(row => company === 'all' || row.id === company);
  return <section className="shell section universe-section" aria-labelledby="universe-heading">
    <h2 id="universe-heading">{es ? 'Empresas ficticias' : 'Fictional companies'}</h2>
    <div className="market-filters"><label>{es ? 'Empresa' : 'Company'}<select value={company} onChange={event => setCompany(event.target.value)}><option value="all">{es ? 'Todas' : 'All'}</option>{syntheticMarket.companies.map(row => <option key={row.id} value={row.id}>{row.company}</option>)}</select></label><output>{rows.length} / 25</output><button type="button" onClick={() => setCompany('all')}>{es ? 'Restablecer' : 'Reset'}</button></div>
    <div className="universe-grid">{rows.map(row => <article className="universe-card" key={row.id}><h3>{row.company}</h3><p>{es ? 'Ejemplo sintético; no es una empresa, un análisis ni una fuente real.' : 'Synthetic example; not a real company, analysis or source.'}</p></article>)}</div>
  </section>;
}
