import { useState } from 'react';
import { AnimatePresence, motion } from 'framer-motion';
import { Menu, ShoppingBag, X } from 'lucide-react';
import Logo from './Logo.jsx';
import LocationPicker from './LocationPicker.jsx';
import { useLockBodyScroll, useScrolled } from '../lib/hooks.js';

const NAV_LINKS = [
  { label: 'Restaurants', href: '#restaurants' },
  { label: 'Dishes', href: '#dishes' },
  { label: 'Offers', href: '#offers' },
  { label: 'Get the app', href: '#app' },
];

/**
 * Navbar — sticky header.
 *
 * TWO STATES, driven by scroll position:
 *   at the top   transparent, sitting over the hero's warm gradient
 *   scrolled     white, blurred, with a hairline border and a soft shadow
 *
 * The transition is the single cheapest thing you can do to make a site feel
 * built rather than assembled.
 */
export default function Navbar({ location, onLocationChange, cartCount = 0 }) {
  const [menuOpen, setMenuOpen] = useState(false);
  const scrolled = useScrolled(12);

  useLockBodyScroll(menuOpen);

  return (
    <>
      <header
        className={`fixed inset-x-0 top-0 z-40 transition-all duration-300 ${
          scrolled
            ? // backdrop-blur on a translucent background is what makes content
              // scrolling underneath look intentional rather than messy.
              'border-b border-ink-100 bg-white/85 shadow-sm backdrop-blur-xl'
            : 'bg-transparent'
        }`}
      >
        <nav className="container-x flex h-[4.5rem] items-center gap-4">
          <Logo />

          {/* Location picker — hidden on mobile, where it lives in the hero */}
          <div className="ml-2 hidden lg:block">
            <LocationPicker value={location} onChange={onLocationChange} />
          </div>

          <div className="flex-1" />

          <ul className="hidden items-center gap-1 md:flex">
            {NAV_LINKS.map((link) => (
              <li key={link.href}>
                <a
                  href={link.href}
                  className="group relative rounded-full px-3.5 py-2 text-sm font-semibold text-ink-600 transition hover:text-ink-900"
                >
                  {link.label}
                  {/* Underline grows from the centre on hover. */}
                  <span className="absolute inset-x-3.5 bottom-1 h-0.5 origin-center scale-x-0 rounded-full bg-brand-600 transition-transform duration-300 group-hover:scale-x-100" />
                </a>
              </li>
            ))}
          </ul>

          <div className="flex items-center gap-2">
            {/* Cart */}
            <button
              type="button"
              className="relative grid h-10 w-10 place-items-center rounded-full text-ink-700 transition hover:bg-ink-100"
              aria-label={`Cart, ${cartCount} items`}
            >
              <ShoppingBag className="h-5 w-5" />
              <AnimatePresence>
                {cartCount > 0 && (
                  <motion.span
                    initial={{ scale: 0 }}
                    animate={{ scale: 1 }}
                    exit={{ scale: 0 }}
                    className="absolute -right-0.5 -top-0.5 grid h-5 w-5 place-items-center rounded-full bg-brand-600 text-[0.65rem] font-bold text-white ring-2 ring-white"
                  >
                    {cartCount}
                  </motion.span>
                )}
              </AnimatePresence>
            </button>

            <a href="#app" className="btn-primary btn-md hidden sm:inline-flex">
              Order now
            </a>

            {/* Mobile menu toggle */}
            <button
              type="button"
              onClick={() => setMenuOpen(true)}
              className="grid h-10 w-10 place-items-center rounded-full text-ink-800 transition hover:bg-ink-100 md:hidden"
              aria-label="Open menu"
            >
              <Menu className="h-6 w-6" />
            </button>
          </div>
        </nav>
      </header>

      {/* ------------------------------------------------------------------ */}
      {/* MOBILE DRAWER                                                       */}
      {/* ------------------------------------------------------------------ */}
      {/* AnimatePresence is what lets the drawer animate OUT. Without it,    */}
      {/* React unmounts the element instantly and the exit animation never   */}
      {/* renders — the drawer just vanishes.                                 */}
      <AnimatePresence>
        {menuOpen && (
          <>
            <motion.div
              initial={{ opacity: 0 }}
              animate={{ opacity: 1 }}
              exit={{ opacity: 0 }}
              onClick={() => setMenuOpen(false)}
              className="fixed inset-0 z-50 bg-ink-950/40 backdrop-blur-sm md:hidden"
            />

            <motion.aside
              initial={{ x: '100%' }}
              animate={{ x: 0 }}
              exit={{ x: '100%' }}
              transition={{ type: 'spring', damping: 30, stiffness: 300 }}
              className="fixed inset-y-0 right-0 z-50 flex w-[86%] max-w-sm flex-col bg-white shadow-float md:hidden"
            >
              <div className="flex items-center justify-between border-b border-ink-100 px-5 py-4">
                <Logo />
                <button
                  type="button"
                  onClick={() => setMenuOpen(false)}
                  className="grid h-10 w-10 place-items-center rounded-full text-ink-700 transition hover:bg-ink-100"
                  aria-label="Close menu"
                >
                  <X className="h-5 w-5" />
                </button>
              </div>

              <div className="border-b border-ink-100 p-5">
                <LocationPicker
                  value={location}
                  onChange={onLocationChange}
                  variant="large"
                />
              </div>

              <nav className="flex-1 overflow-y-auto p-3">
                {NAV_LINKS.map((link, i) => (
                  <motion.a
                    key={link.href}
                    href={link.href}
                    onClick={() => setMenuOpen(false)}
                    // Stagger: each link slides in slightly after the one
                    // above it. 0.05s apart reads as one motion, not four.
                    initial={{ opacity: 0, x: 24 }}
                    animate={{ opacity: 1, x: 0 }}
                    transition={{ delay: 0.08 + i * 0.05 }}
                    className="block rounded-xl px-4 py-3.5 font-display text-lg font-semibold text-ink-800 transition hover:bg-ink-50"
                  >
                    {link.label}
                  </motion.a>
                ))}
              </nav>

              <div className="border-t border-ink-100 p-5">
                <a
                  href="#app"
                  onClick={() => setMenuOpen(false)}
                  className="btn-primary btn-lg w-full"
                >
                  Order now
                </a>
              </div>
            </motion.aside>
          </>
        )}
      </AnimatePresence>
    </>
  );
}
