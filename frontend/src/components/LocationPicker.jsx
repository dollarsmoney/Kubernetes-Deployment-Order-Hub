import { useEffect, useRef, useState } from 'react';
import { AnimatePresence, motion } from 'framer-motion';
import { Check, ChevronDown, MapPin, Search } from 'lucide-react';
import { DELIVERY_AREAS } from '../lib/fallback.js';

/**
 * LocationPicker — the delivery-location interaction.
 *
 * A dropdown listing delivery areas grouped by city, with a filter box.
 * Used twice: in the navbar (compact) and in the hero (large).
 *
 * Accessibility work that is easy to skip and shouldn't be:
 *   - aria-expanded / aria-haspopup so screen readers announce the state
 *   - Escape closes it
 *   - a click outside closes it
 *   - the filter input is focused on open, so you can type immediately
 */
export default function LocationPicker({ value, onChange, variant = 'compact' }) {
  const [open, setOpen] = useState(false);
  const [query, setQuery] = useState('');
  const containerRef = useRef(null);
  const inputRef = useRef(null);

  // Close on outside click and on Escape.
  useEffect(() => {
    if (!open) return;

    const onPointerDown = (event) => {
      if (containerRef.current && !containerRef.current.contains(event.target)) {
        setOpen(false);
      }
    };
    const onKeyDown = (event) => {
      if (event.key === 'Escape') setOpen(false);
    };

    document.addEventListener('mousedown', onPointerDown);
    document.addEventListener('keydown', onKeyDown);

    // Focus the filter as soon as the panel opens.
    const focusTimer = setTimeout(() => inputRef.current?.focus(), 60);

    return () => {
      document.removeEventListener('mousedown', onPointerDown);
      document.removeEventListener('keydown', onKeyDown);
      clearTimeout(focusTimer);
    };
  }, [open]);

  const groups = DELIVERY_AREAS.map((group) => ({
    ...group,
    areas: group.areas.filter((area) =>
      `${area} ${group.city}`.toLowerCase().includes(query.toLowerCase()),
    ),
  })).filter((group) => group.areas.length > 0);

  const isLarge = variant === 'large';

  return (
    <div ref={containerRef} className="relative">
      <button
        type="button"
        onClick={() => setOpen((o) => !o)}
        aria-expanded={open}
        aria-haspopup="listbox"
        className={
          isLarge
            ? 'flex w-full items-center gap-3 rounded-2xl bg-white px-5 py-4 text-left shadow-card ring-1 ring-ink-100 transition hover:shadow-card-hover'
            : 'flex items-center gap-2 rounded-full px-3 py-2 text-sm font-semibold text-ink-700 transition hover:bg-ink-100'
        }
      >
        <span
          className={
            isLarge
              ? 'grid h-11 w-11 shrink-0 place-items-center rounded-xl bg-brand-50 text-brand-600'
              : 'text-brand-600'
          }
        >
          <MapPin className={isLarge ? 'h-5 w-5' : 'h-4 w-4'} />
        </span>

        <span className="min-w-0 flex-1">
          {isLarge && (
            <span className="block text-[0.7rem] font-semibold uppercase tracking-wider text-ink-400">
              Deliver to
            </span>
          )}
          <span
            className={
              isLarge
                ? 'block truncate font-display font-bold text-ink-900'
                : 'block max-w-[9rem] truncate'
            }
          >
            {value}
          </span>
        </span>

        {/* The chevron flips when open — a tiny bit of state made visible. */}
        <ChevronDown
          className={`h-4 w-4 shrink-0 text-ink-400 transition-transform duration-200 ${
            open ? 'rotate-180' : ''
          }`}
        />
      </button>

      <AnimatePresence>
        {open && (
          <motion.div
            initial={{ opacity: 0, y: -8, scale: 0.98 }}
            animate={{ opacity: 1, y: 0, scale: 1 }}
            exit={{ opacity: 0, y: -8, scale: 0.98 }}
            transition={{ duration: 0.18, ease: [0.16, 1, 0.3, 1] }}
            className="absolute left-0 z-50 mt-2 max-h-[22rem] w-[19rem] overflow-hidden rounded-2xl bg-white shadow-float ring-1 ring-ink-100"
          >
            <div className="border-b border-ink-100 p-3">
              <div className="flex items-center gap-2 rounded-xl bg-ink-50 px-3 py-2">
                <Search className="h-4 w-4 shrink-0 text-ink-400" />
                <input
                  ref={inputRef}
                  value={query}
                  onChange={(e) => setQuery(e.target.value)}
                  placeholder="Search your area"
                  className="w-full bg-transparent text-sm outline-none placeholder:text-ink-400"
                />
              </div>
            </div>

            <div className="max-h-64 overflow-y-auto p-2">
              {groups.length === 0 && (
                <p className="px-3 py-6 text-center text-sm text-ink-400">
                  We are not in {query || 'that area'} yet — but we are coming.
                </p>
              )}

              {groups.map((group) => (
                <div key={group.city} className="mb-1">
                  <p className="px-3 py-1.5 text-[0.7rem] font-bold uppercase tracking-wider text-ink-400">
                    {group.city}
                  </p>

                  {group.areas.map((area) => {
                    const label = `${area}, ${group.city}`;
                    const selected = label === value;

                    return (
                      <button
                        key={label}
                        type="button"
                        onClick={() => {
                          onChange(label);
                          setOpen(false);
                          setQuery('');
                        }}
                        className={`flex w-full items-center justify-between rounded-lg px-3 py-2 text-left text-sm transition ${
                          selected
                            ? 'bg-brand-50 font-semibold text-brand-700'
                            : 'text-ink-700 hover:bg-ink-50'
                        }`}
                      >
                        {area}
                        {selected && <Check className="h-4 w-4" />}
                      </button>
                    );
                  })}
                </div>
              ))}
            </div>
          </motion.div>
        )}
      </AnimatePresence>
    </div>
  );
}
