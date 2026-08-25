import { AnimatePresence, motion } from 'framer-motion';
import { UtensilsCrossed } from 'lucide-react';
import FoodCard from './FoodCard.jsx';

/**
 * FoodSection — food discovery.
 *
 * The `layout` prop on each motion element is doing real work here. When the
 * category filter changes and the grid reflows, Framer Motion's FLIP animation
 * slides surviving cards to their new positions instead of teleporting them.
 *
 * That is the difference between a filter that feels like a page reload and one
 * that feels like an app. It is also the single most expensive animation on the
 * page, which is why it is used here and nowhere else.
 */
export default function FoodSection({ foods, activeCategory, onAdd }) {
  const visible = activeCategory
    ? foods.filter((food) => food.category === activeCategory)
    : foods;

  return (
    <section id="dishes" className="container-x py-16 sm:py-24">
      <motion.div
        initial={{ opacity: 0, y: 24 }}
        whileInView={{ opacity: 1, y: 0 }}
        viewport={{ once: true, margin: '-80px' }}
        transition={{ duration: 0.6, ease: [0.16, 1, 0.3, 1] }}
        className="mb-9 flex flex-wrap items-end justify-between gap-4"
      >
        <div>
          <span className="chip mb-4 bg-jollof-100 text-jollof-600">
            <UtensilsCrossed className="h-3.5 w-3.5" />
            {visible.length} {visible.length === 1 ? 'dish' : 'dishes'}
            {activeCategory ? ` in ${activeCategory}` : ' available'}
          </span>

          <h2 className="section-title">
            {activeCategory ? `${activeCategory} right now` : 'Popular right now'}
          </h2>
          <p className="section-sub">
            What Lagos, Abuja and PH are ordering this week.
          </p>
        </div>
      </motion.div>

      {visible.length === 0 ? (
        <div className="rounded-3xl bg-ink-50 py-20 text-center">
          <p className="text-4xl">🥘</p>
          <p className="mt-4 font-display text-xl font-bold text-ink-900">
            No dishes in {activeCategory} yet
          </p>
          <p className="mt-2 text-ink-500">
            Pick another category — there is plenty going.
          </p>
        </div>
      ) : (
        <motion.div layout className="grid gap-6 sm:grid-cols-2 lg:grid-cols-4">
          <AnimatePresence mode="popLayout">
            {visible.map((food, index) => (
              <motion.div
                key={food.id}
                layout
                // exit runs when a card is filtered OUT. Without it, removed
                // cards vanish instantly while the survivors slide — which
                // looks like a rendering glitch rather than a filter.
                exit={{ opacity: 0, scale: 0.9 }}
                transition={{ duration: 0.3 }}
              >
                <FoodCard food={food} index={index} onAdd={onAdd} />
              </motion.div>
            ))}
          </AnimatePresence>
        </motion.div>
      )}
    </section>
  );
}
