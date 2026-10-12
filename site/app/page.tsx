import Link from 'next/link';

export default function Home() {
  return (
    <main className="shell section">
      <p className="section-kicker">Open-source software · AGPLv3</p>
      <h1>Orbit CRM Public</h1>
      <p>Private professional relationships, applications, opportunities and follow-ups in your own workspace.</p>
      <p>This source distribution includes no real records, personal profile, market report or original installation configuration. Set up your own service to use the private dashboard.</p>
      <Link className="portal-link" href="/crm">Open your private workspace →</Link>
      <p><a href="https://github.com/KrakenLiso78/Orbit-CRM-Public" target="_blank" rel="noreferrer">Source code · GNU AGPLv3</a></p>
    </main>
  );
}
