import { motion } from 'framer-motion';
import { Apple, Bell, MapPinned, Play, Star, Wallet } from 'lucide-react';

const FEATURES = [
  { icon: MapPinned, text: 'Live rider tracking on a real map' },
  { icon: Bell, text: 'Alerts when your food leaves the kitchen' },
  { icon: Wallet, text: 'Save cards, transfer, or pay on delivery' },
];

/**
 * DownloadApp — the app section, built around a CSS phone mockup.
 *
 * The phone is pure markup: nested rounded divs for the frame, bezel and
 * notch, with a screenshot-style layout inside. No image asset, no 3D library,
 * nothing to license — and it stays sharp on every display.
 *
 * The whole device tilts on hover via a CSS transform, which is what stops it
 * reading as a flat rectangle.
 */
export default function DownloadApp() {
  return (
    <section
      id="app"
      className="relative overflow-hidden bg-ink-950 py-20 sm:py-28"
    >
      {/* Ambient glows */}
      <div aria-hidden className="pointer-events-none absolute inset-0">
        <div className="absolute -left-20 top-10 h-96 w-96 rounded-full bg-brand-600/25 blur-3xl" />
        <div className="absolute -right-20 bottom-0 h-96 w-96 rounded-full bg-jollof-500/20 blur-3xl" />
      </div>

      <div className="container-x relative grid items-center gap-16 lg:grid-cols-2">
        {/* ----------------------------- COPY ----------------------------- */}
        <div>
          <motion.span
            initial={{ opacity: 0, y: 16 }}
            whileInView={{ opacity: 1, y: 0 }}
            viewport={{ once: true }}
            transition={{ duration: 0.5 }}
            className="chip bg-white/10 text-white ring-1 ring-white/20 backdrop-blur"
          >
            📱 Jollof Run for iOS &amp; Android
          </motion.span>

          <motion.h2
            initial={{ opacity: 0, y: 24 }}
            whileInView={{ opacity: 1, y: 0 }}
            viewport={{ once: true }}
            transition={{ duration: 0.6, delay: 0.08, ease: [0.16, 1, 0.3, 1] }}
            className="mt-5 text-balance font-display text-4xl font-extrabold leading-[1.1] text-white sm:text-5xl"
          >
            Track your rider all the way to your gate.
          </motion.h2>

          <motion.p
            initial={{ opacity: 0, y: 20 }}
            whileInView={{ opacity: 1, y: 0 }}
            viewport={{ once: true }}
            transition={{ duration: 0.6, delay: 0.16 }}
            className="mt-5 max-w-lg text-lg leading-relaxed text-white/65"
          >
            Order in three taps, watch your food leave the kitchen, and know
            exactly when to come downstairs. No more “I have reached your
            estate” with no idea where that is.
          </motion.p>

          <ul className="mt-8 space-y-4">
            {FEATURES.map((feature, i) => (
              <motion.li
                key={feature.text}
                initial={{ opacity: 0, x: -20 }}
                whileInView={{ opacity: 1, x: 0 }}
                viewport={{ once: true }}
                transition={{ delay: 0.24 + i * 0.09, duration: 0.5 }}
                className="flex items-center gap-3.5 text-white/85"
              >
                <span className="grid h-10 w-10 shrink-0 place-items-center rounded-xl bg-white/10 text-jollof-300 ring-1 ring-white/10">
                  <feature.icon className="h-5 w-5" />
                </span>
                {feature.text}
              </motion.li>
            ))}
          </ul>

          {/* Store buttons. Original markup — no Apple/Google badge artwork,
              which is trademarked and has its own usage rules. */}
          <motion.div
            initial={{ opacity: 0, y: 20 }}
            whileInView={{ opacity: 1, y: 0 }}
            viewport={{ once: true }}
            transition={{ delay: 0.5, duration: 0.6 }}
            className="mt-10 flex flex-wrap gap-3"
          >
            {[
              { icon: Apple, top: 'Download on the', bottom: 'App Store' },
              { icon: Play, top: 'Get it on', bottom: 'Google Play' },
            ].map((store) => (
              <a
                key={store.bottom}
                href="#app"
                className="group flex items-center gap-3 rounded-2xl bg-white px-5 py-3 text-ink-900 transition hover:bg-jollof-100"
              >
                <store.icon className="h-7 w-7 transition-transform group-hover:scale-110" />
                <span className="text-left leading-tight">
                  <span className="block text-[0.65rem] font-medium uppercase tracking-wide text-ink-500">
                    {store.top}
                  </span>
                  <span className="block font-display text-base font-bold">
                    {store.bottom}
                  </span>
                </span>
              </a>
            ))}
          </motion.div>

          <motion.p
            initial={{ opacity: 0 }}
            whileInView={{ opacity: 1 }}
            viewport={{ once: true }}
            transition={{ delay: 0.6 }}
            className="mt-6 flex items-center gap-2 text-sm text-white/50"
          >
            <span className="flex">
              {/* Keyed by star position (1-5) rather than the array index.
                  A fixed five-star rating never reorders, so the index would
                  be harmless here — but mapping over real values keeps one
                  rule enforced everywhere instead of carrying an exception. */}
              {[1, 2, 3, 4, 5].map((star) => (
                <Star key={star} className="h-4 w-4 fill-jollof-400 text-jollof-400" />
              ))}
            </span>
            4.8 from 34,000+ reviews
          </motion.p>
        </div>

        {/* -------------------------- PHONE MOCKUP -------------------------- */}
        <motion.div
          initial={{ opacity: 0, y: 50, rotate: -8 }}
          whileInView={{ opacity: 1, y: 0, rotate: -4 }}
          viewport={{ once: true, margin: '-100px' }}
          transition={{ duration: 0.9, ease: [0.16, 1, 0.3, 1] }}
          className="mx-auto w-full max-w-[19rem]"
        >
          <div className="group relative rounded-[2.75rem] bg-ink-800 p-3 shadow-float ring-1 ring-white/10 transition-transform duration-500 hover:rotate-0 hover:scale-[1.03]">
            {/* Notch */}
            <div className="absolute left-1/2 top-3 z-20 h-6 w-28 -translate-x-1/2 rounded-b-2xl bg-ink-800" />

            <div className="relative aspect-[9/19] overflow-hidden rounded-[2.25rem] bg-white">
              {/* Screen: a hero photo with an order-status card over it */}
              <img
                src="https://images.unsplash.com/photo-1596797038530-2c107229654b?auto=format&fit=crop&w=600&q=80"
                alt="Jollof Run app order tracking screen"
                loading="lazy"
                className="h-2/5 w-full object-cover"
              />

              <div className="space-y-3 p-4">
                <div className="rounded-2xl bg-brand-50 p-3.5 ring-1 ring-brand-100">
                  <p className="text-[0.65rem] font-bold uppercase tracking-wider text-brand-600">
                    On the way
                  </p>
                  <p className="mt-1 font-display text-sm font-bold text-ink-900">
                    Arriving in 12 minutes
                  </p>

                  {/* Progress bar that fills when it scrolls into view */}
                  <div className="mt-3 h-1.5 overflow-hidden rounded-full bg-brand-100">
                    <motion.div
                      initial={{ width: '0%' }}
                      whileInView={{ width: '72%' }}
                      viewport={{ once: true }}
                      transition={{ delay: 0.9, duration: 1.4, ease: 'easeOut' }}
                      className="h-full rounded-full bg-brand-600"
                    />
                  </div>

                  <p className="mt-2 text-[0.7rem] text-ink-500">
                    Chidi is 1.2km away · 🛵
                  </p>
                </div>

                {[
                  { name: 'Party Jollof Rice', price: '₦3,500' },
                  { name: 'Ram Suya', price: '₦4,500' },
                ].map((item) => (
                  <div
                    key={item.name}
                    className="flex items-center justify-between rounded-xl bg-ink-50 px-3 py-2.5"
                  >
                    <span className="truncate text-xs font-semibold text-ink-800">
                      {item.name}
                    </span>
                    <span className="shrink-0 text-xs font-bold text-ink-900">
                      {item.price}
                    </span>
                  </div>
                ))}

                <div className="flex items-center justify-between border-t border-ink-100 pt-3">
                  <span className="text-xs text-ink-500">Total</span>
                  <span className="font-display text-base font-extrabold text-ink-900">
                    ₦8,600
                  </span>
                </div>
              </div>
            </div>
          </div>
        </motion.div>
      </div>
    </section>
  );
}
