import { motion, useScroll, useTransform } from 'framer-motion';
import { useRef } from 'react';
import { ArrowRight, BadgePercent, Gift, Timer } from 'lucide-react';

const PERKS = [
  {
    icon: Timer,
    title: '30 minutes, or free',
    body: 'If your order takes longer than 30 minutes in a covered area, the delivery fee is on us. No forms, no arguing.',
    tint: 'bg-brand-50 text-brand-600',
  },
  {
    icon: BadgePercent,
    title: '₦0 delivery on Wednesdays',
    body: 'Every Wednesday, delivery is free on orders over ₦5,000 from any kitchen in your area.',
    tint: 'bg-jollof-100 text-jollof-600',
  },
  {
    icon: Gift,
    title: 'Refer, and you both eat',
    body: 'Send a friend your code. They get ₦1,500 off their first order, you get ₦1,500 off your next.',
    tint: 'bg-emerald-50 text-emerald-600',
  },
];

export default function PromoSection() {
  const sectionRef = useRef(null);

  // ---------------------------------------------------------------------------
  // PARALLAX
  // ---------------------------------------------------------------------------
  // useScroll gives a 0->1 progress value as the element travels through the
  // viewport. useTransform maps that onto a y offset, so the background image
  // moves more slowly than the page and reads as further away.
  //
  // These are Framer MOTION VALUES, not React state — they update outside the
  // React render cycle, so scrolling does NOT trigger a re-render on every
  // frame. Doing this with useState and a scroll listener is the classic way
  // to make a page janky.
  // ---------------------------------------------------------------------------
  const { scrollYProgress } = useScroll({
    target: sectionRef,
    offset: ['start end', 'end start'],
  });

  const backgroundY = useTransform(scrollYProgress, [0, 1], ['-12%', '12%']);
  const overlayOpacity = useTransform(scrollYProgress, [0, 0.5, 1], [0.85, 0.7, 0.85]);

  return (
    <section id="offers" ref={sectionRef} className="relative">
      {/* ------------------------- PARALLAX BANNER ------------------------- */}
      <div className="relative isolate overflow-hidden">
        <motion.div style={{ y: backgroundY }} className="absolute inset-0 -z-10 scale-110">
          <img
            src="https://images.unsplash.com/photo-1555939594-58d7cb561ad1?auto=format&fit=crop&w=1600&q=80"
            alt=""
            aria-hidden
            loading="lazy"
            className="h-full w-full object-cover"
          />
        </motion.div>

        <motion.div
          style={{ opacity: overlayOpacity }}
          className="absolute inset-0 -z-10 bg-gradient-to-br from-ink-950 via-ink-900 to-brand-900"
        />

        <div className="container-x py-20 sm:py-28">
          <div className="max-w-2xl">
            <motion.span
              initial={{ opacity: 0, y: 16 }}
              whileInView={{ opacity: 1, y: 0 }}
              viewport={{ once: true }}
              transition={{ duration: 0.5 }}
              className="chip bg-white/15 text-white ring-1 ring-white/25 backdrop-blur"
            >
              🔥 This week only
            </motion.span>

            <motion.h2
              initial={{ opacity: 0, y: 24 }}
              whileInView={{ opacity: 1, y: 0 }}
              viewport={{ once: true }}
              transition={{ duration: 0.6, delay: 0.08, ease: [0.16, 1, 0.3, 1] }}
              className="mt-5 text-balance font-display text-4xl font-extrabold leading-[1.1] text-white sm:text-5xl lg:text-6xl"
            >
              Buy one jollof,
              <br />
              get the second at half price.
            </motion.h2>

            <motion.p
              initial={{ opacity: 0, y: 20 }}
              whileInView={{ opacity: 1, y: 0 }}
              viewport={{ once: true }}
              transition={{ duration: 0.6, delay: 0.16 }}
              className="mt-5 max-w-lg text-lg leading-relaxed text-white/75"
            >
              Valid at every kitchen on Jollof Run until Sunday. Use code{' '}
              <span className="rounded-lg bg-white/15 px-2 py-0.5 font-mono font-bold text-jollof-300">
                DOUBLEJOLLOF
              </span>{' '}
              at checkout.
            </motion.p>

            <motion.div
              initial={{ opacity: 0, y: 20 }}
              whileInView={{ opacity: 1, y: 0 }}
              viewport={{ once: true }}
              transition={{ duration: 0.6, delay: 0.24 }}
              className="mt-9 flex flex-wrap gap-3"
            >
              <a href="#restaurants" className="btn-primary btn-lg group">
                Claim the offer
                <ArrowRight className="h-5 w-5 transition-transform group-hover:translate-x-1" />
              </a>
              <a
                href="#app"
                className="btn btn-lg bg-white/10 text-white ring-1 ring-white/25 backdrop-blur transition hover:bg-white/20"
              >
                Get the app
              </a>
            </motion.div>
          </div>
        </div>
      </div>

      {/* ---------------------------- PERK CARDS ---------------------------- */}
      {/* Pulled up over the banner's bottom edge with a negative margin, so the
          cards overlap the boundary. A small trick that stops two stacked
          sections looking like two stacked rectangles. */}
      <div className="container-x relative z-10 -mt-12 pb-16 sm:-mt-16 sm:pb-24">
        <div className="grid gap-5 md:grid-cols-3">
          {PERKS.map((perk, i) => (
            <motion.div
              key={perk.title}
              initial={{ opacity: 0, y: 30 }}
              whileInView={{ opacity: 1, y: 0 }}
              viewport={{ once: true, margin: '-60px' }}
              transition={{ delay: i * 0.1, duration: 0.6, ease: [0.16, 1, 0.3, 1] }}
              whileHover={{ y: -6 }}
              className="rounded-3xl bg-white p-6 shadow-card ring-1 ring-ink-100 transition-shadow hover:shadow-card-hover"
            >
              <span
                className={`mb-4 grid h-12 w-12 place-items-center rounded-2xl ${perk.tint}`}
              >
                <perk.icon className="h-6 w-6" />
              </span>

              <h3 className="font-display text-lg font-bold text-ink-900">
                {perk.title}
              </h3>
              <p className="mt-2 text-sm leading-relaxed text-ink-500">
                {perk.body}
              </p>
            </motion.div>
          ))}
        </div>
      </div>
    </section>
  );
}
