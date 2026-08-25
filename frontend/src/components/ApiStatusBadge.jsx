import { AnimatePresence, motion } from 'framer-motion';
import { CheckCircle2, Loader2, WifiOff } from 'lucide-react';

/**
 * ApiStatusBadge — a floating pill showing where the page's data came from.
 *
 * THIS IS A DEVOPS INSTRUMENT, not decoration.
 *
 * Phase 12's Test 2 is "the frontend communicates with the backend". Without
 * something like this, verifying that means opening dev tools and reading the
 * network tab. With it, the answer is on screen and screenshot-able:
 *
 *   "Live from API"     the whole chain works —
 *                       browser -> ALB -> frontend pod -> nginx ->
 *                       backend-service -> backend pod -> IRSA ->
 *                       Secrets Manager -> RDS
 *
 *   "Demo data"         the page renders, but the backend did not answer.
 *                       Look at: kubectl logs, the backend readiness probe,
 *                       the RDS security group, the IRSA annotation.
 *
 * A real product would not ship this. A teaching project absolutely should:
 * it makes an invisible integration visible.
 */
const STATES = {
  loading: {
    icon: Loader2,
    text: 'Connecting…',
    className: 'bg-ink-900/85 text-white',
    spin: true,
  },
  api: {
    icon: CheckCircle2,
    text: 'Live from API',
    className: 'bg-emerald-600 text-white',
  },
  fallback: {
    icon: WifiOff,
    text: 'Demo data',
    className: 'bg-jollof-500 text-ink-900',
  },
};

export default function ApiStatusBadge({ source }) {
  const state = STATES[source] ?? STATES.loading;
  const Icon = state.icon;

  return (
    <div className="pointer-events-none fixed bottom-5 left-5 z-30">
      <AnimatePresence mode="wait">
        <motion.div
          // key on `source` so changing state remounts the element and the
          // enter/exit animation actually plays.
          key={source}
          initial={{ opacity: 0, y: 12, scale: 0.9 }}
          animate={{ opacity: 1, y: 0, scale: 1 }}
          exit={{ opacity: 0, y: 12, scale: 0.9 }}
          transition={{ duration: 0.25, ease: [0.16, 1, 0.3, 1] }}
          className={`flex items-center gap-2 rounded-full px-3.5 py-2 text-xs font-bold shadow-float backdrop-blur ${state.className}`}
          title={
            source === 'api'
              ? 'Data is coming from the FastAPI backend and PostgreSQL'
              : 'Backend unreachable — showing bundled demo data'
          }
        >
          <Icon className={`h-3.5 w-3.5 ${state.spin ? 'animate-spin' : ''}`} />
          {state.text}
        </motion.div>
      </AnimatePresence>
    </div>
  );
}
