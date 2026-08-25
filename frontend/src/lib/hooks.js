import { useCallback, useEffect, useState } from 'react';
import { fetchFoods, fetchRestaurants } from './api.js';
import { FALLBACK_FOODS, FALLBACK_RESTAURANTS } from './fallback.js';

/**
 * useCatalog — load restaurants and foods, falling back to static data.
 *
 * Returns `source`, which is the interesting part for this project:
 *
 *   'loading'   the requests are in flight
 *   'api'       the backend answered  -> the full chain works:
 *               browser -> ALB -> frontend pod -> nginx -> backend-service
 *               -> backend pod -> IRSA -> Secrets Manager -> RDS
 *   'fallback'  the backend did not answer; showing static data
 *
 * Phase 12's Test 2 ("frontend communicates with backend") is literally
 * "confirm source === 'api'", which the ApiStatusBadge renders on screen. That
 * turns an invisible integration into something you can point a screenshot at.
 */
export function useCatalog() {
  const [restaurants, setRestaurants] = useState(FALLBACK_RESTAURANTS);
  const [foods, setFoods] = useState(FALLBACK_FOODS);
  const [source, setSource] = useState('loading');
  const [error, setError] = useState(null);

  const load = useCallback(async () => {
    try {
      // Promise.all so the two requests overlap instead of running in series.
      // Two 60ms round-trips take 60ms, not 120ms.
      const [restaurantData, foodData] = await Promise.all([
        fetchRestaurants({ limit: 50 }),
        fetchFoods({ limit: 100 }),
      ]);

      // Only replace the fallback if the API actually returned rows. An empty
      // array is a valid response but a terrible homepage — this is the state
      // you hit when RDS is up but seeding has not finished.
      if (restaurantData?.restaurants?.length) {
        setRestaurants(restaurantData.restaurants);
      }
      if (foodData?.foods?.length) {
        setFoods(foodData.foods);
      }

      setSource('api');
      setError(null);
    } catch (err) {
      // Not a crash. The page is already rendering fallback data, so a failed
      // request degrades the page's freshness, not its usability.
      console.warn('[jollof] API unreachable, using fallback data:', err.message);
      setSource('fallback');
      setError(err.message);
    }
  }, []);

  useEffect(() => {
    load();
  }, [load]);

  return { restaurants, foods, source, error, reload: load };
}

/**
 * useScrolled — true once the page has scrolled past `threshold` pixels.
 * Drives the navbar's transition from transparent to solid-with-blur.
 */
export function useScrolled(threshold = 12) {
  const [scrolled, setScrolled] = useState(false);

  useEffect(() => {
    const onScroll = () => setScrolled(window.scrollY > threshold);

    onScroll(); // set the correct state on mount, e.g. after a refresh mid-page

    // passive: true tells the browser this listener will never call
    // preventDefault(), so it can keep scrolling smooth instead of waiting for
    // the handler to finish. Meaningful on low-end Android.
    window.addEventListener('scroll', onScroll, { passive: true });
    return () => window.removeEventListener('scroll', onScroll);
  }, [threshold]);

  return scrolled;
}

/**
 * useLockBodyScroll — stop the page scrolling behind an open mobile drawer.
 * Without this, scrolling the drawer scrolls the page underneath it, which is
 * the single most common mobile-menu bug.
 */
export function useLockBodyScroll(locked) {
  useEffect(() => {
    if (!locked) return;

    const original = document.body.style.overflow;
    document.body.style.overflow = 'hidden';

    return () => {
      document.body.style.overflow = original;
    };
  }, [locked]);
}

/** Format Naira. Intl handles the ₦ symbol and thousands separators for us. */
export function formatNaira(amount) {
  return new Intl.NumberFormat('en-NG', {
    style: 'currency',
    currency: 'NGN',
    maximumFractionDigits: 0,
  }).format(Number(amount) || 0);
}
