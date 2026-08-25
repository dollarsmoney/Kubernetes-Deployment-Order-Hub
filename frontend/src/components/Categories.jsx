import { motion } from 'framer-motion';
import { CATEGORIES } from '../lib/fallback.js';

/**
 * Categories — the horizontal category rail.
 *
 * Two techniques worth noting:
 *
 * 1. CSS SCROLL SNAP (`.rail` in index.css). snap-x + snap-mandatory means a
 *    flick on mobile settles neatly on a card instead of drifting to a random
 *    half-card position. Three utility classes, no JavaScript, no library.
 *
 * 2. whileInView instead of animate. The cards animate when they SCROLL INTO
 *    VIEW rather than on mount. `once: true` means it plays a single time —
 *    without it, elements re-animate every time they re-enter the viewport,
 *    which is distracting rather than delightful.
 */
export default function Categories({ active, onSelect }) {
  return (
    <section className="container-x py-16 sm:py-20" id="categories">
      <div className="mb-8 flex flex-wrap items-end justify-between gap-4">
        <div>
          <h2 className="section-title">What are you craving?</h2>
          <p className="section-sub">
            Tap a category to filter the menu below.
          </p>
        </div>

        {active && (
          <button
            type="button"
            onClick={() => onSelect(null)}
            className="btn-ghost btn-md"
          >
            Clear filter
          </button>
        )}
      </div>

      <div className="rail fade-right -mx-1 px-1">
        {CATEGORIES.map((category, i) => {
          const isActive = active === category.key;

          return (
            <motion.button
              key={category.key}
              type="button"
              onClick={() => onSelect(isActive ? null : category.key)}
              initial={{ opacity: 0, y: 20 }}
              whileInView={{ opacity: 1, y: 0 }}
              viewport={{ once: true, margin: '-60px' }}
              transition={{ delay: i * 0.05, duration: 0.5, ease: [0.16, 1, 0.3, 1] }}
              whileHover={{ y: -6 }}
              whileTap={{ scale: 0.96 }}
              className={`rail-item group w-[7.5rem] rounded-3xl p-4 text-center ring-1 transition-shadow sm:w-[8.5rem] ${
                isActive
                  ? 'bg-brand-600 text-white shadow-brand ring-brand-600'
                  : 'bg-white text-ink-800 shadow-card ring-ink-100 hover:shadow-card-hover'
              }`}
              aria-pressed={isActive}
            >
              <span
                className={`mx-auto mb-3 grid h-16 w-16 place-items-center rounded-2xl bg-gradient-to-br text-3xl transition-transform duration-300 group-hover:scale-110 ${
                  isActive ? 'from-white/25 to-white/10' : category.tint
                }`}
              >
                {category.emoji}
              </span>

              <span className="block font-display text-sm font-bold leading-tight">
                {category.label}
              </span>
            </motion.button>
          );
        })}
      </div>
    </section>
  );
}
