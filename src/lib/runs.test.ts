import { describe, expect, it } from 'vitest'
import { formatDuration, formatParsecs, rankRuns, type SmugglingRun } from './runs'

const run = (id: number, parsecs: number, hours: number): SmugglingRun => ({
  id,
  pilot: `p${id}`,
  ship: `s${id}`,
  parsecs,
  hours,
})

describe('rankRuns', () => {
  it('orders by fewest parsecs', () => {
    const ranked = rankRuns([run(1, 13, 10), run(2, 11.5, 20), run(3, 12, 15)])
    expect(ranked.map((r) => r.id)).toEqual([2, 3, 1])
  })

  it('breaks parsec ties by hours', () => {
    const ranked = rankRuns([run(1, 12, 18), run(2, 12, 14)])
    expect(ranked.map((r) => r.id)).toEqual([2, 1])
  })

  it('does not mutate its input', () => {
    const input = [run(1, 13, 10), run(2, 11.5, 20)]
    rankRuns(input)
    expect(input.map((r) => r.id)).toEqual([1, 2])
  })
})

describe('formatParsecs', () => {
  it('renders one decimal with unit', () => {
    expect(formatParsecs(11.5)).toBe('11.5 pc')
    expect(formatParsecs(12)).toBe('12.0 pc')
  })
})

describe('formatDuration', () => {
  it('renders hours and rounded minutes', () => {
    expect(formatDuration(14.2)).toBe('14h 12m')
  })

  it('renders an exact-hour value with 0m', () => {
    expect(formatDuration(15.0)).toBe('15h 0m')
  })

  it('carries rounded minutes into the next hour instead of showing 60m', () => {
    expect(formatDuration(14.999)).toBe('15h 0m')
    expect(formatDuration(14.999)).not.toBe('14h 60m')
  })
})
