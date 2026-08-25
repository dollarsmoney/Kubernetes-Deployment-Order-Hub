/** @type {import('tailwindcss').Config} */

/**
 * Jollof Run design tokens.
 *
 * Everything visual is defined here rather than scattered as arbitrary values
 * across components. Changing `brand.600` restyles the entire site.
 */
export default {
  content: ['./index.html', './src/**/*.{js,jsx}'],
  theme: {
    extend: {
      colors: {
        // Primary — a deep rose-red. Warm enough to read as food, saturated
        // enough to hold a CTA.
        brand: {
          50: '#fff1f2',
          100: '#ffe4e6',
          200: '#fecdd3',
          300: '#fda4af',
          400: '#fb7185',
          500: '#f43f5e',
          600: '#e11d48', // the brand colour
          700: '#be123c',
          800: '#9f1239',
          900: '#881337',
        },
        // Secondary — warm amber, for ratings, badges and highlights.
        jollof: {
          50: '#fffbeb',
          100: '#fef3c7',
          200: '#fde68a',
          300: '#fcd34d',
          400: '#fbbf24',
          500: '#f59e0b',
          600: '#d97706',
        },
        // Neutrals — warm-tinted greys (stone, not slate). Cool greys next to
        // food photography look clinical.
        ink: {
          50: '#fafaf9',
          100: '#f5f5f4',
          200: '#e7e5e4',
          300: '#d6d3d1',
          400: '#a8a29e',
          500: '#78716c',
          600: '#57534e',
          700: '#44403c',
          800: '#292524',
          900: '#1c1917',
          950: '#0c0a09',
        },
      },

      fontFamily: {
        // Loaded from Google Fonts in index.html. The fallback stacks matter:
        // if the CDN is slow or blocked, the page still renders in a sensible
        // system font instead of Times New Roman.
        display: ['"Plus Jakarta Sans"', 'system-ui', '-apple-system', 'sans-serif'],
        sans: ['Inter', 'system-ui', '-apple-system', 'sans-serif'],
      },

      // A generous scale for hero headlines.
      fontSize: {
        '7.5xl': ['5.25rem', { lineHeight: '1', letterSpacing: '-0.03em' }],
      },

      // Tailwind's default spacing scale has 3.5 and 5 but nothing between.
      // 1.125rem (18px) is the right size for an icon sitting next to 14px
      // text — 16px reads slightly small, 20px slightly bulky.
      spacing: {
        4.5: '1.125rem',
      },

      borderRadius: {
        '4xl': '2rem',
        '5xl': '2.5rem',
      },

      boxShadow: {
        // Soft, layered shadows. A single large blur reads as cheap; stacking
        // a tight shadow under a wide one is what makes cards feel lifted.
        card: '0 1px 2px rgba(28,25,23,0.04), 0 8px 24px -8px rgba(28,25,23,0.12)',
        'card-hover':
          '0 2px 4px rgba(28,25,23,0.06), 0 24px 48px -12px rgba(28,25,23,0.22)',
        brand: '0 8px 24px -8px rgba(225,29,72,0.5)',
        float: '0 20px 60px -20px rgba(28,25,23,0.35)',
      },

      backgroundImage: {
        'brand-gradient': 'linear-gradient(135deg, #e11d48 0%, #f59e0b 100%)',
        'warm-fade':
          'linear-gradient(180deg, #fff1f2 0%, #fffbeb 55%, #ffffff 100%)',
      },

      keyframes: {
        // Continuous ambient motion. Framer Motion handles entrance and
        // interaction; CSS handles things that just loop forever, because
        // running those through React would re-render on every frame.
        float: {
          '0%, 100%': { transform: 'translateY(0)' },
          '50%': { transform: 'translateY(-14px)' },
        },
        marquee: {
          '0%': { transform: 'translateX(0)' },
          '100%': { transform: 'translateX(-50%)' },
        },
        shimmer: {
          '100%': { transform: 'translateX(100%)' },
        },

        // ---------------------------------------------------------------------
        // StreetScene (components/StreetScene.jsx)
        // ---------------------------------------------------------------------
        // IMPORTANT: these px values are NOT screen pixels.
        //
        // A CSS transform applied to an element INSIDE an <svg> operates in the
        // SVG user coordinate system, so `translateX(2220px)` means 2220
        // viewBox units. The scene's viewBox is `0 0 2000 420`, so the ride
        // animations carry a vehicle from just off the left edge (-320) to just
        // off the right edge (2220) regardless of how big the SVG is rendered.
        //
        // That is exactly what we want: the motion scales with the artwork for
        // free, and never needs a JS resize listener.
        //
        // These MUST stay in step with the viewBox width in StreetScene.jsx.
        // Widen the artwork and forget these, and vehicles vanish before they
        // reach the right-hand edge.
        // ---------------------------------------------------------------------
        ride: {
          '0%': { transform: 'translateX(-320px)' },
          '100%': { transform: 'translateX(2220px)' },
        },
        'ride-reverse': {
          '0%': { transform: 'translateX(2220px)' },
          '100%': { transform: 'translateX(-420px)' },
        },
        'spin-wheel': {
          '0%': { transform: 'rotate(0deg)' },
          '100%': { transform: 'rotate(360deg)' },
        },
        // Suspension over a road that has seen better days. 2 user units is
        // deliberately tiny — any more and the bikes look like they are hopping.
        bob: {
          '0%, 100%': { transform: 'translateY(0)' },
          '50%': { transform: 'translateY(-2px)' },
        },
      },

      animation: {
        float: 'float 6s ease-in-out infinite',
        'float-slow': 'float 9s ease-in-out infinite',
        marquee: 'marquee 32s linear infinite',
        shimmer: 'shimmer 1.6s infinite',

        // Durations are set per-vehicle inline in StreetScene.jsx so each one
        // can be staggered independently; these are just the defaults.
        ride: 'ride 14s linear infinite',
        'ride-reverse': 'ride-reverse 26s linear infinite',
        'spin-wheel': 'spin-wheel 0.5s linear infinite',
        bob: 'bob 0.9s ease-in-out infinite',
      },
    },
  },
  plugins: [],
};
