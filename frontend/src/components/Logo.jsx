/**
 * Logo.jsx — the Jollof Run mark.
 *
 * Original artwork, drawn as inline SVG rather than an image file.
 *
 * The concept: a rice grain bent into a motion arrow, with a pepper-seed dot
 * riding the curve — "food, moving fast". The steam curl above reads as
 * hot food. Nothing here is borrowed from any existing delivery brand.
 *
 * Inline SVG rather than a .png/.svg asset because it:
 *   - costs zero extra network requests
 *   - recolours with currentColor / props, so one component serves the light
 *     navbar and the dark footer
 *   - stays crisp at any size and on any pixel density
 */

export function LogoMark({ className = 'h-10 w-10' }) {
  return (
    <svg
      viewBox="0 0 48 48"
      className={className}
      role="img"
      aria-label="Jollof Run"
    >
      <defs>
        <linearGradient id="jr-grad" x1="0" y1="0" x2="1" y2="1">
          <stop offset="0%" stopColor="#f43f5e" />
          <stop offset="100%" stopColor="#e11d48" />
        </linearGradient>
      </defs>

      {/* Rounded tile */}
      <rect width="48" height="48" rx="13" fill="url(#jr-grad)" />

      {/* The rice-grain arrow: a thick comma sweeping up to the right */}
      <path
        d="M11 33.5c5.4-1.6 9.1-4 12.4-7.3 3.3-3.3 5.7-7 7.3-12.4l6.3 6.3c-1.6 5.4-4 9.1-7.3 12.4-3.3 3.3-7 5.7-12.4 7.3z"
        fill="white"
        opacity="0.96"
      />

      {/* Motion lines trailing behind it */}
      <path
        d="M9 24.5h6M9 29h4"
        stroke="white"
        strokeWidth="2.2"
        strokeLinecap="round"
        opacity="0.55"
      />

      {/* Pepper-seed dot at the head of the arrow */}
      <circle cx="32.5" cy="15.5" r="3.4" fill="#fbbf24" />

      {/* Steam curl */}
      <path
        d="M20 12c1.6-1.2 1.6-2.8 0-4"
        stroke="white"
        strokeWidth="1.8"
        strokeLinecap="round"
        fill="none"
        opacity="0.75"
      />
    </svg>
  );
}

export default function Logo({ className = '', dark = false, compact = false }) {
  return (
    <a
      href="#top"
      className={`group inline-flex items-center gap-2.5 ${className}`}
      aria-label="Jollof Run, back to top"
    >
      {/* The mark tilts slightly on hover — a small reward for noticing it. */}
      <LogoMark className="h-9 w-9 transition-transform duration-300 group-hover:-rotate-6 group-hover:scale-105 sm:h-10 sm:w-10" />

      {!compact && (
        <span className="font-display text-[1.35rem] font-extrabold leading-none tracking-tight">
          <span className={dark ? 'text-white' : 'text-ink-900'}>Jollof</span>
          <span className="text-brand-600"> Run</span>
        </span>
      )}
    </a>
  );
}
