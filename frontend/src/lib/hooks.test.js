import { describe, it, expect, vi, beforeEach } from 'vitest';
import { renderHook, waitFor, act } from '@testing-library/react';
import { useCatalog, useScrolled, formatNaira } from './hooks.js';
import { FALLBACK_RESTAURANTS } from './fallback.js';

/**
 * useCatalog's `source` value is the project's own integration indicator.
 *
 *   'api'       the whole chain works: browser -> ALB -> nginx ->
 *               backend-service -> pod -> IRSA -> Secrets Manager -> RDS
 *   'fallback'  the page still renders, but the backend did not answer
 *
 * ApiStatusBadge renders it on screen, and Phase 12's "frontend talks to
 * backend" check is literally "is the badge green". These tests pin that
 * behaviour so a refactor cannot quietly turn the indicator into a decoration.
 */

const API_RESTAURANTS = [
  { id: 99, name: 'From The API', rating: 5, cuisine: 'Test', location: 'x', delivery_time_mins: 1, delivery_fee: 0, description: '', image_url: '' },
];
const API_FOODS = [{ id: 99, restaurant_id: 99, name: 'API dish', price: 1, category: 'Rice', description: '', image_url: '' }];

beforeEach(() => {
  vi.restoreAllMocks();
});

function mockApi({ restaurants = API_RESTAURANTS, foods = API_FOODS } = {}) {
  globalThis.fetch = vi.fn().mockImplementation((url) =>
    Promise.resolve({
      ok: true,
      status: 200,
      statusText: 'OK',
      json: async () => (url.includes('/foods') ? { foods } : { restaurants }),
    }),
  );
}

describe('useCatalog', () => {
  it('starts on fallback data so the page never renders empty', async () => {
    mockApi();
    const { result } = renderHook(() => useCatalog());

    // Before any request resolves there is already something to show.
    expect(result.current.source).toBe('loading');
    expect(result.current.restaurants).toEqual(FALLBACK_RESTAURANTS);

    // Let the in-flight fetch settle before the test ends. Without this the
    // hook's setState lands after teardown and React logs an act() warning —
    // harmless, but warnings nobody can action are how real ones get ignored.
    await waitFor(() => expect(result.current.source).toBe('api'));
  });

  it("switches to source 'api' and swaps in live data on success", async () => {
    mockApi();
    const { result } = renderHook(() => useCatalog());

    await waitFor(() => expect(result.current.source).toBe('api'));

    expect(result.current.restaurants).toEqual(API_RESTAURANTS);
    expect(result.current.foods).toEqual(API_FOODS);
    expect(result.current.error).toBeNull();
  });

  it("falls back without throwing when the backend is unreachable", async () => {
    globalThis.fetch = vi.fn().mockRejectedValue(new Error('connection refused'));
    vi.spyOn(console, 'warn').mockImplementation(() => {});

    const { result } = renderHook(() => useCatalog());

    await waitFor(() => expect(result.current.source).toBe('fallback'));

    // A failed request degrades freshness, not usability.
    expect(result.current.restaurants).toEqual(FALLBACK_RESTAURANTS);
    expect(result.current.error).toBe('connection refused');
  });

  it('keeps fallback data when the API returns an empty list', async () => {
    // The state you hit when RDS is up but seeding has not finished. An empty
    // array is a valid response and a terrible homepage.
    mockApi({ restaurants: [], foods: [] });

    const { result } = renderHook(() => useCatalog());

    await waitFor(() => expect(result.current.source).toBe('api'));
    expect(result.current.restaurants).toEqual(FALLBACK_RESTAURANTS);
  });

  it('issues both requests concurrently, not in series', async () => {
    mockApi();
    renderHook(() => useCatalog());

    await waitFor(() => expect(globalThis.fetch).toHaveBeenCalledTimes(2));

    // Promise.all means two 60ms round-trips cost 60ms, not 120ms.
    const urls = globalThis.fetch.mock.calls.map((c) => c[0]);
    expect(urls.some((u) => u.includes('/restaurants'))).toBe(true);
    expect(urls.some((u) => u.includes('/foods'))).toBe(true);
  });
});

describe('useScrolled', () => {
  it('is false at the top of the page', () => {
    window.scrollY = 0;
    const { result } = renderHook(() => useScrolled(12));

    expect(result.current).toBe(false);
  });

  it('becomes true once past the threshold', () => {
    window.scrollY = 0;
    const { result } = renderHook(() => useScrolled(12));

    act(() => {
      window.scrollY = 100;
      window.dispatchEvent(new Event('scroll'));
    });

    expect(result.current).toBe(true);
  });

  it('reads the current position on mount, not just on scroll', () => {
    // Matters after a refresh part-way down the page: without this the navbar
    // renders transparent over content until you happen to scroll again.
    window.scrollY = 500;
    const { result } = renderHook(() => useScrolled(12));

    expect(result.current).toBe(true);
  });
});

describe('formatNaira', () => {
  it('formats with the Naira symbol and thousands separators', () => {
    // Intl output can vary by ICU build, so assert the parts rather than an
    // exact string — otherwise this passes locally and fails on the runner.
    const formatted = formatNaira(3500);

    expect(formatted).toMatch(/3,500/);
    expect(formatted).toMatch(/₦|NGN/);
  });

  it('shows no decimal places', () => {
    expect(formatNaira(1500)).not.toMatch(/\.\d/);
  });

  it('coerces bad input to zero instead of rendering NaN', () => {
    // Prices arrive from PostgreSQL NUMERIC as strings; a null would otherwise
    // put "₦NaN" on the page.
    expect(formatNaira(undefined)).toMatch(/0/);
    expect(formatNaira(null)).toMatch(/0/);
    expect(formatNaira('4800')).toMatch(/4,800/);
  });
});
