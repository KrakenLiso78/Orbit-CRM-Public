// Fictional presentation fixtures only: no original company cohort or forecasts.
export const syntheticMarket = {
  companies: Array.from({ length: 25 }, (_, index) => ({
    id: `synthetic-company-${index + 1}`,
    company: `Synthetic Company ${String(index + 1).padStart(2, '0')}`,
    legacy_rank: index < 15 ? index + 1 : null,
    projection: index < 13
      ? { status: 'carried_q3_orbit_estimate', rank_range: [Math.max(1, index), index + 3] }
      : { status: 'not_reviewed', rank_range: null },
  })),
};
