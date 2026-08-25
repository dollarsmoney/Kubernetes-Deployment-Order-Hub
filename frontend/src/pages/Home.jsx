import { useState } from 'react';
import { AnimatePresence, motion } from 'framer-motion';
import { ShoppingBag } from 'lucide-react';

import Navbar from '../components/Navbar.jsx';
import HeroScene from '../components/HeroScene.jsx';
import Hero from '../components/Hero.jsx';
import Categories from '../components/Categories.jsx';
import RestaurantSection from '../components/RestaurantSection.jsx';
import FoodSection from '../components/FoodSection.jsx';
import PromoSection from '../components/PromoSection.jsx';
import DownloadApp from '../components/DownloadApp.jsx';
import Footer from '../components/Footer.jsx';
import ApiStatusBadge from '../components/ApiStatusBadge.jsx';

import { useCatalog, formatNaira } from '../lib/hooks.js';

/**
 * Home — the single page.
 *
 * STATE LIVES HERE, and only here. Four pieces:
 *   location        the delivery area, shared by the navbar and the hero
 *   activeCategory  the category filter, set by Categories, read by FoodSection
 *   cart            an array of dishes
 *   catalog         restaurants + foods, from useCatalog()
 *
 * No Redux, no Zustand, no Context. With four values and one page, a state
 * library would be more code than it saves. Prop drilling only becomes a
 * problem several levels deep, and nothing here is more than two.
 *
 * Knowing WHEN you do not need a tool is worth as much as knowing how to use
 * one.
 */
export default function Home() {
  const [location, setLocation] = useState('Lekki Phase 1, Lagos');
  const [activeCategory, setActiveCategory] = useState(null);
  const [cart, setCart] = useState([]);

  const { restaurants, foods, source } = useCatalog();

  const addToCart = (food) => setCart((current) => [...current, food]);

  const cartTotal = cart.reduce((sum, item) => sum + Number(item.price), 0);

  const handleCategorySelect = (category) => {
    setActiveCategory(category);

    // Scroll the dishes section into view when a filter is applied, so the
    // result of the click is actually visible on mobile — where the grid is
    // otherwise below the fold. `smooth` is inherited from html in index.css.
    if (category) {
      requestAnimationFrame(() => {
        document.getElementById('dishes')?.scrollIntoView({ behavior: 'smooth' });
      });
    }
  };

  return (
    <div className="min-h-screen bg-white">
      <Navbar
        location={location}
        onLocationChange={setLocation}
        cartCount={cart.length}
      />

      <main>
        {/* The illustrated street is the hero and owns the page's <h1>. */}
        <HeroScene location={location} onLocationChange={setLocation} />

        {/* The former hero, now the food-photography section. It no longer
            needs `location` — the picker moved up into HeroScene. */}
        <Hero />

        <Categories active={activeCategory} onSelect={handleCategorySelect} />

        <RestaurantSection restaurants={restaurants} />

        <FoodSection
          foods={foods}
          activeCategory={activeCategory}
          onAdd={addToCart}
        />

        <PromoSection />

        <DownloadApp />
      </main>

      <Footer />

      {/* --------------------------------------------------------------- */}
      {/* FLOATING CART BAR                                                */}
      {/* --------------------------------------------------------------- */}
      {/* Appears only once something is in the cart, and springs up from   */}
      {/* below. A spring rather than a duration because the bar is a       */}
      {/* physical-feeling object arriving, not a fade.                     */}
      <AnimatePresence>
        {cart.length > 0 && (
          <motion.div
            initial={{ y: 100, opacity: 0 }}
            animate={{ y: 0, opacity: 1 }}
            exit={{ y: 100, opacity: 0 }}
            transition={{ type: 'spring', damping: 26, stiffness: 320 }}
            className="fixed inset-x-4 bottom-4 z-30 mx-auto max-w-md sm:inset-x-auto sm:right-6"
          >
            <button
              type="button"
              className="flex w-full items-center gap-4 rounded-2xl bg-ink-900 px-5 py-4 text-white shadow-float transition hover:bg-ink-800"
            >
              <span className="relative grid h-10 w-10 shrink-0 place-items-center rounded-xl bg-brand-600">
                <ShoppingBag className="h-5 w-5" />
                <motion.span
                  key={cart.length}
                  initial={{ scale: 0.5 }}
                  animate={{ scale: 1 }}
                  className="absolute -right-1.5 -top-1.5 grid h-5 w-5 place-items-center rounded-full bg-jollof-400 text-[0.65rem] font-extrabold text-ink-900"
                >
                  {cart.length}
                </motion.span>
              </span>

              <span className="flex-1 text-left">
                <span className="block text-xs text-white/60">
                  {cart.length} {cart.length === 1 ? 'item' : 'items'} · to{' '}
                  {location.split(',')[0]}
                </span>
                <span className="block font-display text-base font-bold">
                  {formatNaira(cartTotal)}
                </span>
              </span>

              <span className="shrink-0 rounded-full bg-white px-4 py-2 font-display text-sm font-bold text-ink-900">
                Checkout
              </span>
            </button>
          </motion.div>
        )}
      </AnimatePresence>

      <ApiStatusBadge source={source} />
    </div>
  );
}
