import { useState } from 'react';
import { motion } from 'framer-motion';
import { Bike, Clock, MapPin, Star } from 'lucide-react';
import { formatNaira } from '../lib/hooks.js';

/**
 * RestaurantCard.
 *
 * THE IMAGE TRANSITION, which is most of what sells this card:
 *
 *   - the <img> sits inside a container with `overflow-hidden`
 *   - on hover it scales to 1.08 over 700ms
 *   - the container clips the overflow, so the photo appears to zoom INSIDE
 *     its frame rather than growing past it
 *
 * The card also lifts (`y: -8`) and deepens its shadow at the same time. Three
 * properties moving together is what reads as "designed"; any one alone reads
 * as an accident.
 *
 * LOADING STATE: `loaded` tracks the image's onLoad. Until it fires we show a
 * shimmer skeleton, so a slow connection sees a placeholder instead of a
 * flash of empty grey. Cheap, and it is the difference between "loading" and
 * "broken".
 */
export default function RestaurantCard({ restaurant, index = 0 }) {
  const [loaded, setLoaded] = useState(false);

  const {
    name,
    description,
    image_url: imageUrl,
    rating,
    location,
    cuisine,
    delivery_time_mins: deliveryTime,
    delivery_fee: deliveryFee,
  } = restaurant;

  // A little product texture: free delivery over a threshold, and a "fast"
  // badge. Derived from the data rather than hardcoded per card.
  const freeDelivery = Number(deliveryFee) <= 600;
  const isFast = Number(deliveryTime) <= 25;

  return (
    <motion.article
      initial={{ opacity: 0, y: 28 }}
      whileInView={{ opacity: 1, y: 0 }}
      viewport={{ once: true, margin: '-80px' }}
      transition={{
        // Cap the stagger delay. Without min(), the 20th card in a long grid
        // waits two full seconds before appearing, which looks broken.
        delay: Math.min(index * 0.06, 0.4),
        duration: 0.6,
        ease: [0.16, 1, 0.3, 1],
      }}
      whileHover={{ y: -8 }}
      className="group cursor-pointer overflow-hidden rounded-3xl bg-white shadow-card ring-1 ring-ink-100 transition-shadow duration-300 hover:shadow-card-hover"
    >
      {/* ------------------------------ IMAGE ------------------------------ */}
      <div className="relative aspect-[16/11] overflow-hidden bg-ink-100">
        {!loaded && <div className="skeleton absolute inset-0" />}

        <img
          src={imageUrl}
          alt={name}
          loading="lazy"
          onLoad={() => setLoaded(true)}
          // The zoom. duration-700 is deliberately slow — a fast image zoom
          // feels twitchy, a slow one feels expensive.
          className={`h-full w-full object-cover transition-all duration-700 ease-out group-hover:scale-[1.08] ${
            loaded ? 'opacity-100' : 'opacity-0'
          }`}
        />

        {/* Gradient scrim so white text stays readable over any photo */}
        <div className="absolute inset-0 bg-gradient-to-t from-ink-950/70 via-ink-950/10 to-transparent" />

        {/* Rating badge, top-left */}
        <div className="absolute left-3 top-3 flex items-center gap-1 rounded-full bg-white/95 px-2.5 py-1 text-xs font-bold text-ink-900 shadow-sm backdrop-blur">
          <Star className="h-3.5 w-3.5 fill-jollof-400 text-jollof-400" />
          {Number(rating).toFixed(1)}
        </div>

        {/* Promo badges, top-right */}
        <div className="absolute right-3 top-3 flex flex-col items-end gap-1.5">
          {freeDelivery && (
            <span className="chip bg-emerald-500 text-white shadow-sm">
              Free delivery
            </span>
          )}
          {isFast && (
            <span className="chip bg-jollof-400 text-ink-900 shadow-sm">
              ⚡ Fast
            </span>
          )}
        </div>

        {/* Delivery time, bottom-left over the scrim.
            Slides up slightly on hover to acknowledge the interaction. */}
        <div className="absolute inset-x-4 bottom-3 flex items-center justify-between text-white transition-transform duration-300 group-hover:-translate-y-0.5">
          <span className="flex items-center gap-1.5 text-sm font-semibold">
            <Clock className="h-4 w-4" />
            {deliveryTime} min
          </span>
          <span className="chip bg-white/20 text-white backdrop-blur-sm">
            {cuisine}
          </span>
        </div>
      </div>

      {/* ------------------------------ BODY ------------------------------- */}
      <div className="p-5">
        <h3 className="truncate font-display text-lg font-bold text-ink-900 transition-colors group-hover:text-brand-600">
          {name}
        </h3>

        {/* line-clamp-2 keeps every card the same height regardless of how
            long the description is — the thing that makes a grid look tidy. */}
        <p className="mt-1.5 line-clamp-2 text-sm leading-relaxed text-ink-500">
          {description}
        </p>

        <div className="mt-4 flex items-center justify-between border-t border-ink-100 pt-4 text-sm">
          <span className="flex min-w-0 items-center gap-1.5 text-ink-500">
            <MapPin className="h-4 w-4 shrink-0 text-brand-500" />
            <span className="truncate">{location}</span>
          </span>

          <span className="flex shrink-0 items-center gap-1.5 font-semibold text-ink-700">
            <Bike className="h-4 w-4 text-ink-400" />
            {freeDelivery ? (
              <span className="text-emerald-600">Free</span>
            ) : (
              formatNaira(deliveryFee)
            )}
          </span>
        </div>
      </div>
    </motion.article>
  );
}
