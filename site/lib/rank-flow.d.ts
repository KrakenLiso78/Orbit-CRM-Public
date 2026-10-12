export function buildRankFlow(cohort: { companies: Array<{ id: string; company: string; legacy_rank: number | null; projection: { status: string; rank_range?: number[] | null } }> }, midpointRanks?: Record<string, number>): {
  height: number; rankedCount: number; projectedCount: number; unrankedHeadingY: number; unavailableHeadingY: number;
  rows: Array<{ id: string; name: string; rank: number | null; projected: number[] | null; midpoint: number | null; leftY: number; rightY: number }>;
};
