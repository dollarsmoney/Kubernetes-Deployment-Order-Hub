import { useState } from 'react';
import { AnimatePresence, motion } from 'framer-motion';
import { Check, Plus, Star } from 'lucide-react';
import { formatNaira } from '../lib/hooks.js';

/**
 * FoodCard — a single dish.
 *
 * THE ADD-TO-CART MICRO-INTERACTION:
 *   click -> the button swaps to a tick for 1.2s -> swaps back
 *
 * AnimatePresence with mode="popLayout" cross-fades the two icons in place
 * instead of one appearing below the other mid-transition.
 *
 * Why bother: the cart badge in the navbar is far from the button and easy to
 * miss on mobile. Confirming AT the point of interaction is what stops people
 * tapping "add" three times because nothing appeared to happen.
 */
export default function FoodCard({ food, index = 0, onAdd }) {
  const [loaded, setLoaded] = useState(false);
  const [justAdded, setJustAdded] = useState(false);

  const {
    name,
    description,
    price,
    image_url: imageUrl,
    category,
    restaurant_name: restaurantName,
    restaurant_rating: restaurantRating,
  } = food;

  const handleAdd = () => {
    onAdd?.(food);
    setJustAdded(true);
    setTimeout(() => setJustAdded(false), 1200);
  };

  return (
    <motion.article
      initial={{ opacity: 0, y: 24 }}
      whileInView={{ opacity: 1, y: 0 }}
      viewport={{ once: true, margin: '-60px' }}
      transition={{
        delay: Math.min(index * 0.05, 0.35),
        duration: 0.55,
        ease: [0.16, 1, 0.3, 1],
      }}
      whileHover={{ y: -6 }}
      className="group flex h-full flex-col overflow-hidden rounded-3xl bg-white shadow-card ring-1 ring-ink-100 transition-shadow duration-300 hover:shadow-card-hover"
    >
      <div className="relative aspect-[4/3] overflow-hidden bg-ink-100">
        {!loaded && <div className="skeleton absolute inset-0" />}

        <img
          src={imageUrl}
          alt={name}
          loading="lazy"
          onLoad={() => setLoaded(true)}
          className={`h-full w-full object-cover transition-all duration-700 ease-out group-hover:scale-[1.07] ${
            loaded ? 'opacity-100' : 'opacity-0'
          }`}
        />

        <span className="absolute left-3 top-3 chip bg-white/95 text-ink-700 shadow-sm backdrop-blur">
          {category}
        </span>

        {/* Price pill, bottom-right of the image */}
        <span className="absolute bottom-3 right-3 rounded-full bg-ink-900/85 px-3 py-1.5 font-display text-sm font-bold text-white backdrop-blur">
          {formatNaira(price)}
        </span>
      </div>

      <div className="flex flex-1 flex-col p-5">
        <h3 className="truncate font-display text-base font-bold text-ink-900 transition-colors group-hover:text-brand-600">
          {name}
        </h3>

        <p className="mt-1.5 line-clamp-2 flex-1 text-sm leading-relaxed text-ink-500">
          {description}
        </p>

        <div className="mt-4 flex items-center justify-between gap-3 border-t border-ink-100 pt-4">
          <div className="min-w-0">
            <p className="truncate text-xs font-semibold text-ink-700">
              {restaurantName}
            </p>
            {restaurantRating != null && (
              <p className="mt-0.5 flex items-center gap-1 text-xs text-ink-400">
                <Star className="h-3 w-3 fill-jollof-400 text-jollof-400" />
                {Number(restaurantRating).toFixed(1)}
              </p>
            )}
          </div>

          <motion.button
            type="button"
            onClick={handleAdd}
            whileTap={{ scale: 0.88 }}
            aria-label={`Add ${name} to cart`}
            className={`grid h-10 w-10 shrink-0 place-items-center rounded-full transition-colors duration-200 ${
              justAdded
                ? 'bg-emerald-500 text-white'
                : 'bg-brand-600 text-white shadow-brand hover:bg-brand-700'
            }`}
          >
            <AnimatePresence mode="popLayout" initial={false}>
              {justAdded ? (
                <motion.span
                  key="check"
                  initial={{ scale: 0, rotate: -90 }}
                  animate={{ scale: 1, rotate: 0 }}
                  exit={{ scale: 0, rotate: 90 }}
                  transition={{ duration: 0.2 }}
                >
                  <Check className="h-5 w-5" />
                </motion.span>
              ) : (
                <motion.span
                  key="plus"
                  initial={{ scale: 0, rotate: 90 }}
                  animate={{ scale: 1, rotate: 0 }}
                  exit={{ scale: 0, rotate: -90 }}
                  transition={{ duration: 0.2 }}
                >
                  <Plus className="h-5 w-5" />
                </motion.span>
              )}
            </AnimatePresence>
          </motion.button>
        </div>
      </div>
    </motion.article>
  );
}
