import runsData from './data/runs.json'
import { formatDuration, formatParsecs, rankRuns, type SmugglingRun } from './lib/runs'

const runs = rankRuns(runsData as SmugglingRun[])

export default function App() {
  return (
    <main className="board">
      <h1>Kessel Run</h1>
      <p className="tagline">The galaxy's smuggling-run leaderboard. Shortest route wins.</p>
      <table>
        <thead>
          <tr>
            <th>#</th>
            <th>Pilot</th>
            <th>Ship</th>
            <th>Route</th>
            <th>Time</th>
          </tr>
        </thead>
        <tbody>
          {runs.map((run, i) => (
            <tr key={run.id}>
              <td>{i + 1}</td>
              <td>{run.pilot}</td>
              <td>{run.ship}</td>
              <td>{formatParsecs(run.parsecs)}</td>
              <td>{formatDuration(run.hours)}</td>
            </tr>
          ))}
        </tbody>
      </table>
    </main>
  )
}
