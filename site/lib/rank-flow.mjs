// Row positions are presentation coordinates, never inferred company ranks.
export function buildRankFlow(cohort, midpointRanks = {}) {
  const seen = new Set();
  const rows = cohort.companies.map((company, index) => {
    if (!company.id || seen.has(company.id)) throw new Error('Duplicate or missing company identity.');
    seen.add(company.id);
    const rank = Number.isInteger(company.legacy_rank) && company.legacy_rank > 0 ? company.legacy_rank : null;
    const range = company.projection?.rank_range;
    const projected = company.projection?.status === 'carried_q3_orbit_estimate' && Array.isArray(range) && range.length === 2 && range.every(value => Number.isInteger(value) && value > 0) && range[0] <= range[1] ? [...range] : null;
    const midpoint = projected && Number.isInteger(midpointRanks[company.id]) && midpointRanks[company.id] >= projected[0] && midpointRanks[company.id] <= projected[1] ? midpointRanks[company.id] : null;
    return { id: company.id, name: company.company, rank, projected, midpoint, index };
  });
  const left = [...rows].sort((a, b) => (a.rank ?? Infinity) - (b.rank ?? Infinity) || a.index - b.index);
  const right = [...rows].sort((a, b) => (a.midpoint ?? (a.projected ? (a.projected[0] + a.projected[1]) / 2 : Infinity)) - (b.midpoint ?? (b.projected ? (b.projected[0] + b.projected[1]) / 2 : Infinity)) || a.index - b.index);
  const y = (position, unavailable, knownCount) => 86 + position * 38 + (unavailable && position >= knownCount ? 34 : 0);
  const rankedCount = rows.filter(row => row.rank !== null).length;
  const projectedCount = rows.filter(row => row.projected !== null).length;
  return {
    height: 130 + rows.length * 38,
    rankedCount, projectedCount,
    unrankedHeadingY: 80 + rankedCount * 38,
    unavailableHeadingY: 80 + projectedCount * 38,
    rows: left.map((row, index) => ({ ...row, leftY: y(index, row.rank === null, rankedCount), rightY: y(right.findIndex(item => item.id === row.id), row.projected === null, projectedCount) })),
  };
}
