import { describe, it, expect, vi, beforeEach } from 'vitest';
import {
  fetchRestaurants,
  fetchRestaurant,
  fetchFoods,
  fetchCategories,
} from './api.js';

/**
 * api.js contract tests.
 *
 * The property that matters most here is that the base URL stays RELATIVE
 * (`/api`). That is what lets the same bundle work in both environments:
 *
 *   dev   Vite's proxy      /api/* -> localhost:8000/*
 *   prod  nginx in the pod  /api/* -> backend-service:8000/*
 *
 * If an absolute URL ever crept in, the browser would call the backend
 * directly — which would mean publishing the API on the ALB and undoing the
 * "backend is internal only" design.
 */

function mockFetch(body = {}, ok = true) {
  const spy = vi.fn().mockResolvedValue({
    ok,
    status: ok ? 200 : 500,
    statusText: ok ? 'OK' : 'Internal Server Error',
    json: async () => body,
  });
  globalThis.fetch = spy;
  return spy;
}

/** The path every call was made against. */
const calledPath = (spy) => spy.mock.calls[0][0];

beforeEach(() => {
  vi.restoreAllMocks();
});

describe('base URL', () => {
  it('is relative, never absolute', async () => {
    const spy = mockFetch({ restaurants: [] });
    await fetchRestaurants();

    const url = calledPath(spy);
    expect(url.startsWith('/api')).toBe(true);
    expect(url).not.toMatch(/^https?:\/\//);
  });

  it('sends an Accept: application/json header', async () => {
    const spy = mockFetch({ restaurants: [] });
    await fetchRestaurants();

    expect(spy.mock.calls[0][1].headers.Accept).toBe('application/json');
  });
});

describe('fetchRestaurants', () => {
  it('omits the query string entirely when only the default limit applies', async () => {
    const spy = mockFetch({ restaurants: [] });
    await fetchRestaurants();

    expect(calledPath(spy)).toBe('/api/restaurants?limit=50');
  });

  it('includes search when given', async () => {
    const spy = mockFetch({ restaurants: [] });
    await fetchRestaurants({ search: 'suya', limit: 10 });

    expect(calledPath(spy)).toBe('/api/restaurants?search=suya&limit=10');
  });

  it('percent-encodes values rather than concatenating them', async () => {
    const spy = mockFetch({ restaurants: [] });
    await fetchRestaurants({ search: 'fish & chips' });

    const url = calledPath(spy);
    // URLSearchParams encodes the ampersand, so it cannot be read as a
    // parameter separator. Hand-built query strings break on the first
    // customer who searches for something containing "&".
    expect(url).toContain('fish+%26+chips');
    expect(url).not.toContain('fish & chips');
  });

  it('encodes a SQL-injection payload as an ordinary value', async () => {
    const spy = mockFetch({ restaurants: [] });
    await fetchRestaurants({ search: "' OR 1=1--" });

    const url = calledPath(spy);
    expect(url).toContain('search=');
    expect(url).not.toContain("' OR 1=1--"); // encoded, not raw
  });
});

describe('fetchRestaurant', () => {
  it('encodes the path segment', async () => {
    const spy = mockFetch({});
    await fetchRestaurant('1;drop');

    expect(calledPath(spy)).toBe('/api/restaurants/1%3Bdrop');
  });
});

describe('fetchFoods', () => {
  it('maps restaurantId to the API snake_case parameter', async () => {
    const spy = mockFetch({ foods: [] });
    await fetchFoods({ restaurantId: 3, limit: 20 });

    expect(calledPath(spy)).toBe('/api/foods?restaurant_id=3&limit=20');
  });

  it('includes category when supplied', async () => {
    const spy = mockFetch({ foods: [] });
    await fetchFoods({ category: 'Grill' });

    expect(calledPath(spy)).toContain('category=Grill');
  });
});

describe('fetchCategories', () => {
  it('takes no parameters', async () => {
    const spy = mockFetch({ categories: [] });
    await fetchCategories();

    expect(calledPath(spy)).toBe('/api/categories');
  });
});

describe('error handling', () => {
  it('throws on a non-2xx response', async () => {
    mockFetch({}, false);

    await expect(fetchRestaurants()).rejects.toThrow('500');
  });

  it('propagates a network failure', async () => {
    globalThis.fetch = vi.fn().mockRejectedValue(new Error('network down'));

    await expect(fetchRestaurants()).rejects.toThrow('network down');
  });

  it('passes an AbortSignal so a hung backend cannot stall the page', async () => {
    const spy = mockFetch({ restaurants: [] });
    await fetchRestaurants();

    // fetch() has no timeout option; AbortController is the only mechanism.
    // Without it a dead backend leaves the request pending for minutes.
    expect(spy.mock.calls[0][1].signal).toBeInstanceOf(AbortSignal);
  });
});
