'use client';
/* oxlint-disable jsx-a11y/no-noninteractive-tabindex -- Keyboard scrolling for the labelled overflow region. */
import { buildRankFlow } from '../lib/rank-flow.mjs';
import { syntheticMarket } from '../lib/synthetic-market.mjs';

export default function RankFlow({ lang }: { lang: 'es' | 'en' }) {
  const es = lang === 'es';
  const model = buildRankFlow(syntheticMarket);
  return <figure className="radar-flow" aria-labelledby="radar-flow-caption">
    <figcaption id="radar-flow-caption"><strong>{es ? '25 empresas ficticias · gráfico de demostración' : '25 fictional companies · demonstration graphic'}</strong><p>{es ? 'Todas las posiciones y rangos son ficticios. No representan datos ni previsiones reales.' : 'Every position and range is fictional. These are not real data or forecasts.'}</p></figcaption>
    <section className="radar-flow-scroll" aria-label={es ? 'Gráfico de demostración; desplazamiento horizontal' : 'Demonstration graphic; horizontal scrolling'} tabIndex={0}>
      <svg className="radar-flow-svg" viewBox={`0 0 1080 ${model.height}`} aria-labelledby="radar-svg-title radar-svg-desc">
        <title id="radar-svg-title">{es ? 'Empresas ficticias y rangos de ejemplo' : 'Fictional companies and example ranges'}</title>
        <desc id="radar-svg-desc">{es ? 'Las posiciones visuales no inventan valores para los ejemplos sin evidencia. Todos los valores disponibles también son ficticios.' : 'Display positions assign no values to examples without evidence. All available values are also fictional.'}</desc>
        <text x="18" y="25" className="radar-axis">{es ? 'POSICIÓN FICTICIA' : 'FICTIONAL POSITION'}</text>
        <text x="700" y="25" className="radar-axis">{es ? 'RANGO FICTICIO' : 'FICTIONAL RANGE'}</text>
        <text x="18" y={model.unrankedHeadingY} className="radar-group">{es ? 'Sin posición de ejemplo' : 'No example position'}</text>
        <text x="700" y={model.unavailableHeadingY} className="radar-group">{es ? 'Sin rango de ejemplo' : 'No example range'}</text>
        {model.rows.map(row => <g key={row.id} data-company-id={row.id} className={`radar-company ${row.projected ? 'same' : 'unknown'}`}>
          <title>{`${row.name}: ${row.rank ?? '—'} → ${row.projected?.join('–') ?? '—'}`}</title>
          <path d={`M 385 ${row.leftY} C 480 ${row.leftY}, 555 ${row.rightY}, 665 ${row.rightY}`} />
          <circle cx="385" cy={row.leftY} r="4" /><circle cx="665" cy={row.rightY} r="4" />
          <text x="18" y={row.leftY + 5} className="radar-rank">{row.rank ?? '—'}</text>
          <text x="55" y={row.leftY + 5}>{row.name}</text>
          <text x="700" y={row.rightY + 5}>{row.name}</text>
          <text x="1055" y={row.rightY + 5} textAnchor="end" className="radar-rank">{row.projected?.join('–') ?? '—'}</text>
        </g>)}
      </svg>
    </section>
  </figure>;
}
