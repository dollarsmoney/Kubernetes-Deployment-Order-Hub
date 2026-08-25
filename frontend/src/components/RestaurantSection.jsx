import { useState } from 'react';
import { motion } from 'framer-motion';
import { Search, SlidersHorizontal } from 'lucide-react';
import RestaurantCard from './RestaurantCard.jsx';

const SORTS = [
  { key: 'rating', label: 'Top rated' },
  { key: 'fastest', label: 'Fastest' },
  { key: 'cheapest', label: 'Cheapest delivery' },
];

/**
 * RestaurantSection — restaurant discovery.
 *
 * Search and sort run entirely CLIENT-SIDE, over the array already in memory.
 *
 * That is a deliberate choice, not laziness, and it is worth being able to
 * defend: with a few dozen restaurants, filtering in the browser is instant
 * and costs zero API calls. Sending every keystroke to the backend would add
 * latency, load, and a debounce you now have to maintain — to produce a worse
 * experience.
 *
 * At a few thousand rows the calculus flips and this moves server-side, which
 * is exactly why db.list_restaurants() already accepts a `search` parameter.
 * The API is ready for it; the frontend just does not need it yet.
 */
export default function RestaurantSection({ restaurants }) {
  const [query, setQuery] = useState('');
  const [sort, setSort] = useState('rating');

  const filtered = restaurants
    .filter((restaurant) => {
      if (!query) return true;
      const haystack =
        `${restaurant.name} ${restaurant.cuisine} ${restaurant.location}`.toLowerCase();
      return haystack.includes(query.toLowerCase());
    })
    .sort((a, b) => {
      if (sort === 'fastest') return a.delivery_time_mins - b.delivery_time_mins;
      if (sort === 'cheapest') return a.delivery_fee - b.delivery_fee;
      return b.rating - a.rating;
    });

  return (
    <section id="restaurants" className="bg-ink-50/60 py-16 sm:py-24">
      <div className="container-x">
        {/* --------------------------- HEADER --------------------------- */}
        <motion.div
          initial={{ opacity: 0, y: 24 }}
          whileInView={{ opacity: 1, y: 0 }}
          viewport={{ once: true, margin: '-80px' }}
          transition={{ duration: 0.6, ease: [0.16, 1, 0.3, 1] }}
          className="mb-9"
        >
          <span className="chip mb-4 bg-brand-50 text-brand-700">
            <SlidersHorizontal className="h-3.5 w-3.5" />
            {restaurants.length} kitchens near you
          </span>

          <h2 className="section-title">Kitchens delivering to you</h2>
          <p className="section-sub">
            Real bukas, real cooks. Every kitchen is vetted, and every rating is
            from a customer who actually ordered.
          </p>
        </motion.div>

        {/* ----------------------- SEARCH AND SORT ----------------------- */}
        <div className="mb-9 flex flex-col gap-3 sm:flex-row sm:items-center">
          <label className="relative flex-1">
            <Search className="pointer-events-none absolute left-4 top-1/2 h-4.5 w-4.5 -translate-y-1/2 text-ink-400" />
            <input
              value={query}
              onChange={(event) => setQuery(event.target.value)}
              placeholder="Search restaurants, cuisines or areas…"
              className="w-full rounded-2xl border-0 bg-white py-3.5 pl-11 pr-4 text-sm shadow-card ring-1 ring-ink-100 transition placeholder:text-ink-400 focus:ring-2 focus:ring-brand-500"
            />
          </label>

          <div className="flex gap-2 overflow-x-auto scrollbar-hide">
            {SORTS.map((option) => (
              <button
                key={option.key}
                type="button"
                onClick={() => setSort(option.key)}
                className={`shrink-0 rounded-full px-4 py-2.5 text-sm font-semibold transition ${
                  sort === option.key
                    ? 'bg-ink-900 text-white'
                    : 'bg-white text-ink-600 ring-1 ring-ink-200 hover:bg-ink-50'
                }`}
              >
                {option.label}
              </button>
            ))}
          </div>
        </div>

        {/* ----------------------------- GRID ----------------------------- */}
        {filtered.length === 0 ? (
          <div className="rounded-3xl bg-white py-20 text-center shadow-card ring-1 ring-ink-100">
            <p className="text-4xl">🍽️</p>
            <p className="mt-4 font-display text-xl font-bold text-ink-900">
              Nothing matches “{query}”
            </p>
            <p className="mt-2 text-ink-500">Try a different dish or area.</p>
            <button
              type="button"
              onClick={() => setQuery('')}
              className="btn-ghost btn-md mt-6"
            >
              Clear search
            </button>
          </div>
        ) : (
          <div className="grid gap-6 sm:grid-cols-2 lg:grid-cols-3">
            {filtered.map((restaurant, index) => (
              <RestaurantCard
                // key is the restaurant id, NOT the array index. With an index
                // key, React reuses the wrong DOM nodes when the sort order
                // changes and the image-load states end up on the wrong cards.
                key={restaurant.id}
                restaurant={restaurant}
                index={index}
              />
            ))}
          </div>
        )}
      </div>
    </section>
  );
}
