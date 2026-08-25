import { motion, useReducedMotion } from 'framer-motion';
import { Clock, Star } from 'lucide-react';

const FLOATING_CARDS = [
  {
    src: 'https://images.unsplash.com/photo-1604329760661-e71dc83f8f26?auto=format&fit=crop&w=420&q=80',
    alt: 'Plate of Nigerian party jollof rice',
    label: 'Party Jollof',
    meta: '25 min',
    className: 'left-0 top-10 w-40 sm:w-48',
    animation: 'animate-float',
  },
  {
    src: 'https://images.unsplash.com/photo-1529193591184-b1d58069ecdd?auto=format&fit=crop&w=420&q=80',
    alt: 'Charcoal-grilled suya skewers',
    label: 'Ram Suya',
    meta: '20 min',
    className: 'bottom-16 left-8 w-36 sm:w-44',
    animation: 'animate-float-slow',
  },
  {
    src: 'https://images.unsplash.com/photo-1567620905732-2d1ec7ab7445?auto=format&fit=crop&w=420&q=80',
    alt: 'Bowl of egusi soup with pounded yam',
    label: 'Egusi & Yam',
    meta: '35 min',
    className: 'right-2 top-24 w-36 sm:w-44',
    animation: 'animate-float',
  },
];

const rise = {
  hidden: { opacity: 0, y: 28 },
  show: (i = 0) => ({
    opacity: 1,
    y: 0,
    transition: { delay: 0.08 * i, duration: 0.7, ease: [0.16, 1, 0.3, 1] },
  }),
};

/**
 * Hero — the food-photography section, directly below HeroScene.
 *
 * This used to be the page's hero. When the illustrated street was promoted to
 * the top, the headline, location picker and "Find food" CTA moved up into
 * HeroScene and this kept the photography and the social proof.
 *
 * IT DELIBERATELY USES <h2>, NOT <h1>. HeroScene owns the single <h1>. Two
 * <h1>s on one page is a genuine accessibility and SEO defect — screen-reader
 * users navigating by heading get two competing "titles" for the same document.
 *
 * The entrance animations are `whileInView` rather than `animate`, because this
 * section now starts below the fold: firing on mount would mean the animation
 * has already finished by the time anyone scrolls to it.
 */
export default function Hero() {
  // Framer reads the OS setting, so the ambient float on the photo cards can be
  // switched off for people who need that.
  const reduceMotion = useReducedMotion();

  return (
    <section className="relative overflow-hidden bg-white py-16 sm:py-24">
      <div className="container-x grid items-center gap-14 lg:grid-cols-[1fr_1.05fr] lg:gap-10">
        {/* ---------------------------- COPY ---------------------------- */}
        <div>
          <motion.h2
            variants={rise}
            initial="hidden"
            whileInView="show"
            viewport={{ once: true, margin: '-80px' }}
            custom={0}
            className="section-title text-balance"
          >
            Real kitchens. Real cooks. No ghost brands.
          </motion.h2>

          <motion.p
            variants={rise}
            initial="hidden"
            whileInView="show"
            viewport={{ once: true, margin: '-80px' }}
            custom={1}
            className="section-sub"
          >
            Every kitchen on Jollof Run is a place you could walk into — a buka
            in Surulere, a grill in Wuse, a soup kitchen in Calabar. We visit
            each one before it goes live, and every rating you see comes from
            someone who actually ordered.
          </motion.p>

          {/* ----------------------- SOCIAL PROOF ----------------------- */}
          <motion.div
            variants={rise}
            initial="hidden"
            whileInView="show"
            viewport={{ once: true, margin: '-80px' }}
            custom={2}
            className="mt-10 flex flex-wrap items-center gap-x-8 gap-y-4"
          >
            <div className="flex items-center gap-2.5">
              <div className="flex -space-x-2.5">
                {[
                  'photo-1494790108377-be9c29b29330',
                  'photo-1507003211169-0a1dd7228f2d',
                  'photo-1438761681033-6461ffad8d80',
                  'photo-1500648767791-00dcc994a43e',
                ].map((id) => (
                  <img
                    key={id}
                    src={`https://images.unsplash.com/${id}?auto=format&fit=crop&w=80&h=80&q=80`}
                    alt=""
                    loading="lazy"
                    className="h-9 w-9 rounded-full object-cover ring-2 ring-white"
                  />
                ))}
              </div>
              <div className="text-sm">
                <div className="flex items-center gap-1 font-bold text-ink-900">
                  4.8
                  <Star className="h-3.5 w-3.5 fill-jollof-400 text-jollof-400" />
                </div>
                <p className="text-ink-500">180k+ happy orders</p>
              </div>
            </div>

            <div className="flex items-center gap-2.5">
              <span className="grid h-9 w-9 place-items-center rounded-full bg-white text-brand-600 shadow-card">
                <Clock className="h-4 w-4" />
              </span>
              <div className="text-sm">
                <p className="font-bold text-ink-900">28 min average</p>
                <p className="text-ink-500">door to door</p>
              </div>
            </div>

            <div className="flex items-center gap-2.5">
              <span className="grid h-9 w-9 place-items-center rounded-full bg-white text-emerald-600 shadow-card">
                🛵
              </span>
              <div className="text-sm">
                <p className="font-bold text-ink-900">1,200+ riders</p>
                <p className="text-ink-500">on the road daily</p>
              </div>
            </div>
          </motion.div>
        </div>

        {/* --------------------------- IMAGERY --------------------------- */}
        <motion.div
          initial={{ opacity: 0, scale: 0.94 }}
          whileInView={{ opacity: 1, scale: 1 }}
          viewport={{ once: true, margin: '-80px' }}
          transition={{ duration: 0.9, ease: [0.16, 1, 0.3, 1] }}
          className="relative mx-auto h-[26rem] w-full max-w-lg sm:h-[32rem] lg:h-[34rem]"
        >
          {/* Main dish photo */}
          <div className="absolute inset-x-6 inset-y-0 overflow-hidden rounded-[2.5rem] shadow-float ring-1 ring-ink-900/5">
            <img
              src="https://images.unsplash.com/photo-1604329760661-e71dc83f8f26?auto=format&fit=crop&w=900&q=85"
              alt="A plate of Nigerian jollof rice with grilled chicken and plantain"
              // This is no longer the Largest Contentful Paint element — the
              // hero illustration above it is — so lazy loading is now correct
              // here and saves a request on first paint.
              loading="lazy"
              className="h-full w-full object-cover"
            />
            <div className="absolute inset-0 bg-gradient-to-t from-ink-950/45 via-transparent to-transparent" />
          </div>

          {/* Floating dish cards */}
          {FLOATING_CARDS.map((card, i) => (
            <motion.figure
              key={card.label}
              initial={{ opacity: 0, y: 30, rotate: -4 }}
              whileInView={{ opacity: 1, y: 0, rotate: i % 2 === 0 ? -3 : 3 }}
              viewport={{ once: true, margin: '-80px' }}
              transition={{ delay: 0.2 + i * 0.15, duration: 0.7, ease: [0.16, 1, 0.3, 1] }}
              className={`absolute ${card.className} ${
                reduceMotion ? '' : card.animation
              } overflow-hidden rounded-2xl bg-white p-2 shadow-float ring-1 ring-ink-900/5`}
              style={{ animationDelay: `${i * 1.2}s` }}
            >
              <img
                src={card.src}
                alt={card.alt}
                loading="lazy"
                className="h-24 w-full rounded-xl object-cover sm:h-28"
              />
              <figcaption className="px-1 pb-0.5 pt-2">
                <p className="truncate font-display text-sm font-bold text-ink-900">
                  {card.label}
                </p>
                <p className="flex items-center gap-1 text-xs text-ink-500">
                  <Clock className="h-3 w-3" />
                  {card.meta}
                </p>
              </figcaption>
            </motion.figure>
          ))}
        </motion.div>
      </div>
    </section>
  );
}
