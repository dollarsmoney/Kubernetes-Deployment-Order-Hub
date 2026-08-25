/**
 * api.js — the only file that talks to the backend.
 *
 * NOTE THE BASE URL: '/api'. A relative path, with no host.
 *
 * That works identically in both environments, which is the whole point:
 *
 *   DEVELOPMENT   Vite's dev-server proxy (vite.config.js) forwards
 *                 /api/* -> http://localhost:8000/*
 *
 *   PRODUCTION    nginx inside the frontend pod (nginx.conf) forwards
 *                 /api/* -> http://backend-service.jollof-run.svc.cluster.local:8000/*
 *
 * Consequences worth stating out loud:
 *
 *   - There is no VITE_API_URL, no runtime config injection, no
 *     window.__ENV__ shim. A static SPA cannot read environment variables at
 *     runtime (it is just files on a CDN), so projects that need a
 *     configurable API host end up with entrypoint scripts that rewrite
 *     JavaScript at container start. We avoid the whole category of problem.
 *
 *   - The browser never learns the backend's address. backend-service is a
 *     ClusterIP with no Ingress rule; it is not routable from the internet.
 *     The only way in is through nginx.
 */

const API_BASE = '/api';

/** Fail a request rather than hanging forever on a dead backend. */
const TIMEOUT_MS = 8000;

async function request(path) {
  // AbortController is how you time out fetch(). fetch() itself has no
  // timeout option and will otherwise wait on the browser's default, which
  // can be minutes.
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), TIMEOUT_MS);

  try {
    const response = await fetch(`${API_BASE}${path}`, {
      signal: controller.signal,
      headers: { Accept: 'application/json' },
    });

    if (!response.ok) {
      throw new Error(`${response.status} ${response.statusText}`);
    }

    return await response.json();
  } finally {
    clearTimeout(timer);
  }
}

export function fetchRestaurants({ search, limit = 50 } = {}) {
  const params = new URLSearchParams();

  // URLSearchParams percent-encodes for us. Building a query string by
  // concatenation is how you end up with a broken URL the first time somebody
  // searches for "fish & chips".
  if (search) params.set('search', search);
  if (limit) params.set('limit', String(limit));

  const qs = params.toString();
  return request(`/restaurants${qs ? `?${qs}` : ''}`);
}

export function fetchRestaurant(id) {
  return request(`/restaurants/${encodeURIComponent(id)}`);
}

export function fetchFoods({ restaurantId, category, limit = 100 } = {}) {
  const params = new URLSearchParams();
  if (restaurantId) params.set('restaurant_id', String(restaurantId));
  if (category) params.set('category', category);
  if (limit) params.set('limit', String(limit));

  const qs = params.toString();
  return request(`/foods${qs ? `?${qs}` : ''}`);
}

export function fetchCategories() {
  return request('/categories');
}

export function fetchHealth() {
  return request('/health');
}
