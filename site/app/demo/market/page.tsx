'use client';
import { useState } from 'react';
import Link from 'next/link';
import RankFlow from '../../rank-flow';
import MarketUniverse from '../../market-universe';
export default function MarketDemo() {
  const [lang, setLang] = useState<'es' | 'en'>('en');
  return <main>
    <header className="shell section"><Link href="/">Orbit CRM Public</Link><div className="lang-toggle"><button aria-pressed={lang === 'es'} onClick={() => setLang('es')}>ES</button><button aria-pressed={lang === 'en'} onClick={() => setLang('en')}>EN</button></div></header>
    <section className="shell executive">
      <h1 className="section-kicker">{lang === 'es' ? 'Demostración de mercado · datos ficticios' : 'Market demonstration · fictional data'}</h1>
      <p className="executive-narrative">{lang === 'es' ? 'El contexto precede al gráfico. Estos 25 ejemplos ilustran rangos y datos ausentes sin publicar información privada ni presentar previsiones reales.' : 'Context precedes the graphic. These 25 examples illustrate ranges and missing evidence without publishing private information or presenting real forecasts.'}</p>
      <RankFlow lang={lang} />
    </section>
    <MarketUniverse lang={lang} />
  </main>;
}
