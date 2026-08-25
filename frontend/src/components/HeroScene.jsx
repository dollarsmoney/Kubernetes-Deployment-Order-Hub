import { motion } from 'framer-motion';
import { ArrowRight, Zap } from 'lucide-react';
import LocationPicker from './LocationPicker.jsx';
import StreetScene from './StreetScene.jsx';

const CITIES = [
  'Surulere', 'Lekki', 'Yaba', 'Wuse II', 'Ikeja GRA', 'Maitama',
  'Gbagada', 'Trans Amadi', 'Victoria Island', 'Gwarinpa', 'Ajah', 'Garki',
];

/** Entrance stagger. One place, so the rhythm stays coherent across elements. */
const rise = {
  hidden: { opacity: 0, y: 28 },
  show: (i = 0) => ({
    opacity: 1,
    y: 0,
    transition: {
      delay: 0.08 * i,
      duration: 0.7,
      // Decelerates hard at the end. Framer's default easeOut is fine; this is
      // noticeably more "designed".
      ease: [0.16, 1, 0.3, 1],
    },
  }),
};

/**
 * HeroScene — the top of the page.
 *
 * The illustrated street IS the hero, with the headline, location picker and
 * CTA laid over it.
 *
 * ---------------------------------------------------------------------------
 * THE COPY IS HTML, NOT SVG TEXT
 * ---------------------------------------------------------------------------
 * It would be easy to drop <text> elements into StreetScene and be done. Don't:
 * SVG text is not reliably selectable, browser translation skips it, and an
 * <h1> inside a decorative aria-hidden graphic is invisible to search engines
 * and screen readers alike. Real HTML on top, decoration underneath.
 *
 * ---------------------------------------------------------------------------
 * RESPONSIVE STRATEGY
 * ---------------------------------------------------------------------------
 *   < sm   the scene is IN FLOW, a band below the copy
 *   sm+    the scene is ABSOLUTE, filling the bottom of the stage, copy over it
 *
 * One element, switched with `relative sm:absolute` — not two copies of the
 * scene with `hidden`/`sm:block`, which would ship the whole illustration twice.
 *
 * At 375px there is simply nowhere legible to put a headline, a location picker
 * and a button on top of a street. Stacking there is the correct layout, not a
 * consolation prize.
 */
export default function HeroScene({ location, onLocationChange }) {
  return (
    <section id="top" className="relative isolate overflow-hidden bg-warm-fade">
      {/* Decorative background wash. aria-hidden + pointer-events-none: pure
          decoration, must not be announced or intercept clicks. */}
      <div aria-hidden className="pointer-events-none absolute inset-0 overflow-hidden">
        <div className="absolute -left-32 -top-32 h-[28rem] w-[28rem] rounded-full bg-brand-200/40 blur-3xl" />
        <div className="absolute -right-24 top-24 h-[26rem] w-[26rem] rounded-full bg-jollof-200/45 blur-3xl" />
      </div>

      {/* ------------------------------------------------------------------ */}
      {/* STAGE — copy and scene share this box so the scene can anchor to    */}
      {/* its bottom without sliding under the marquee below.                 */}
      {/* ------------------------------------------------------------------ */}
      <div className="relative min-h-[clamp(420px,64vh,680px)]">
        {/* ------------------------------ COPY ------------------------------ */}
        <div className="container-x relative z-10 pb-12 pt-28 sm:pb-[clamp(160px,20vw,300px)] sm:pt-32 lg:pt-36">
          {/* max-w-xl keeps the copy in the left third, which is where the
              scene is deliberately kept low (see the composition rule in
              StreetScene.jsx). */}
          <div className="relative max-w-xl">
            {/* Soft scrim, sm and up only. The sky is pale and the headline is
                ink-900, so contrast is never the problem — the problem is
                rooftops rising behind the CTA on wide screens. This lifts the
                text off them without looking like a panel. */}
            <div
              aria-hidden
              className="pointer-events-none absolute -inset-x-8 -inset-y-6 -z-10 hidden rounded-[3rem] bg-gradient-to-r from-white/75 via-white/45 to-transparent blur-xl sm:block"
            />

            <motion.div
              variants={rise}
              initial="hidden"
              animate="show"
              custom={0}
              className="chip mb-6 bg-white text-brand-700 shadow-card ring-1 ring-brand-100"
            >
              <Zap className="h-3.5 w-3.5 fill-jollof-400 text-jollof-500" />
              Now delivering in Lagos, Abuja &amp; Port Harcourt
            </motion.div>

            {/* The page's ONLY <h1>. Hero.jsx below drops to <h2>. */}
            <motion.h1
              variants={rise}
              initial="hidden"
              animate="show"
              custom={1}
              className="text-balance font-display text-[2.75rem] font-extrabold leading-[1.05] tracking-tight text-ink-900 sm:text-6xl lg:text-[4.25rem]"
            >
              Your jollof,{' '}
              <span className="relative whitespace-nowrap">
                <span className="relative z-10 bg-brand-gradient bg-clip-text text-transparent">
                  running
                </span>
                {/* Hand-drawn underline that sweeps in after the headline. */}
                <motion.svg
                  aria-hidden
                  viewBox="0 0 300 20"
                  className="absolute -bottom-1 left-0 z-0 h-4 w-full text-jollof-400"
                  initial={{ pathLength: 0, opacity: 0 }}
                  animate={{ pathLength: 1, opacity: 1 }}
                  transition={{ delay: 0.7, duration: 0.9, ease: 'easeInOut' }}
                >
                  <motion.path
                    d="M4 14C60 6 150 4 296 10"
                    fill="none"
                    stroke="currentColor"
                    strokeWidth="7"
                    strokeLinecap="round"
                  />
                </motion.svg>
              </span>{' '}
              to you.
            </motion.h1>

            <motion.p
              variants={rise}
              initial="hidden"
              animate="show"
              custom={2}
              className="mt-5 max-w-lg text-lg leading-relaxed text-ink-600 sm:text-xl"
            >
              2,400+ kitchens near you. Hot at your door in 30 minutes, or the
              delivery is on us.
            </motion.p>

            {/* ------------------- LOCATION + CTA ------------------- */}
            <motion.div
              variants={rise}
              initial="hidden"
              animate="show"
              custom={3}
              className="mt-8 flex flex-col gap-3 sm:flex-row sm:items-stretch"
            >
              <div className="sm:flex-1">
                <LocationPicker
                  value={location}
                  onChange={onLocationChange}
                  variant="large"
                />
              </div>

              <a
                href="#restaurants"
                className="btn-primary group h-full justify-center px-8 py-4 text-base sm:w-auto"
              >
                Find food
                <ArrowRight className="h-5 w-5 transition-transform duration-200 group-hover:translate-x-1" />
              </a>
            </motion.div>
          </div>
        </div>

        {/* ----------------------------- SCENE ----------------------------- */}
        {/* relative on mobile (in flow, below the copy), absolute from sm up
            (pinned to the bottom of the stage, copy overlaid). */}
        <div className="pointer-events-none relative z-0 sm:absolute sm:inset-x-0 sm:bottom-0">
          <StreetScene className="h-[clamp(150px,42vw,210px)] sm:h-[clamp(210px,25vw,380px)]" />
        </div>
      </div>

      {/* ---------------------------- MARQUEE ---------------------------- */}
      {/* Sits on the section's bottom edge, directly under the grass verge, so
          the hero ends on a hard line rather than trailing off. Pure CSS
          animation — React never re-renders for it. */}
      <div className="relative z-10 overflow-hidden border-y border-ink-100 bg-white/75 py-4 backdrop-blur-sm">
        <div className="flex w-max animate-marquee gap-10 whitespace-nowrap">
          {/* Rendered twice so the loop is seamless: the animation translates
              exactly -50%, landing the copy where the original started. */}
          {[0, 1].map((copy) => (
            <div key={copy} className="flex gap-10">
              {CITIES.map((city) => (
                <span
                  key={`${copy}-${city}`}
                  className="flex items-center gap-2.5 font-display text-sm font-semibold text-ink-400"
                >
                  <span className="h-1.5 w-1.5 rounded-full bg-brand-400" />
                  {city}
                </span>
              ))}
            </div>
          ))}
        </div>
      </div>
    </section>
  );
}
