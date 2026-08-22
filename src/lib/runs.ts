export interface SmugglingRun {
  id: number
  pilot: string
  ship: string
  parsecs: number
  hours: number
}

/** Leaderboard order: shortest route (fewest parsecs) wins; ties broken by elapsed hours. */
export function rankRuns(runs: SmugglingRun[]): SmugglingRun[] {
  return [...runs].sort((a, b) => a.parsecs - b.parsecs || a.hours - b.hours)
}

export function formatParsecs(parsecs: number): string {
  return `${parsecs.toFixed(1)} pc`
}
