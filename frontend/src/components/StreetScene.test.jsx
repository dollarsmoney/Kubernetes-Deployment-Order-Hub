import { describe, it, expect } from 'vitest';
import { render } from '@testing-library/react';
import StreetScene from './StreetScene.jsx';

/**
 * StreetScene structural tests.
 *
 * These lock in properties that are invisible in a screenshot and easy to break
 * during a refactor — the exact traps hit while building it:
 *
 *   - the parked food van's wheels spinning (a vehicle that is not moving)
 *   - the ride keyframes drifting out of step with the viewBox width, so
 *     vehicles vanish before reaching the right-hand edge
 *   - reduced motion snapping every vehicle off-screen and leaving an empty road
 */

const svgOf = (container) => container.querySelector('svg');

describe('StreetScene', () => {
  it('renders exactly one scene, not one per breakpoint', () => {
    const { container } = render(<StreetScene />);

    // Mobile and desktop share ONE instance switched with `relative
    // sm:absolute`. Two instances would ship the whole illustration twice.
    expect(container.querySelectorAll('svg')).toHaveLength(1);
  });

  it('uses the 2000-unit viewBox the ride keyframes are tuned for', () => {
    const { container } = render(<StreetScene />);

    // tailwind.config.js translates vehicles from -320 to 2220 user units.
    // Narrow the viewBox without updating those and traffic disappears early.
    expect(svgOf(container)).toHaveAttribute('viewBox', '0 0 2000 420');
  });

  it('pins the bottom edge so the road is never cropped', () => {
    const { container } = render(<StreetScene />);

    // YMax keeps the road and verge; the empty strip above the rooftops is
    // what gets cut when the container is short.
    expect(svgOf(container)).toHaveAttribute('preserveAspectRatio', 'xMidYMax slice');
  });

  it('is hidden from assistive technology', () => {
    const { container } = render(<StreetScene />);

    // Pure decoration. It must not be announced, and must not intercept clicks
    // on the headline and CTA laid over it.
    expect(svgOf(container)).toHaveAttribute('aria-hidden', 'true');
    expect(svgOf(container).getAttribute('class')).toContain('pointer-events-none');
  });

  describe('traffic', () => {
    it('has four vehicles travelling left to right and one right to left', () => {
      const { container } = render(<StreetScene />);

      // 3 riders + 1 keke going one way, the danfo coming back.
      expect(container.querySelectorAll('.animate-ride')).toHaveLength(4);
      expect(container.querySelectorAll('.animate-ride-reverse')).toHaveLength(1);
    });

    it('spins ten wheels — the parked van accounts for the other two', () => {
      const { container } = render(<StreetScene />);

      // 3 riders x2 + keke x2 + danfo x2 = 10.
      // The food van has two wheels and they must NOT be in this count: it is
      // parked, and wheels turning on a stationary vehicle is the kind of
      // detail nobody consciously notices and everybody feels.
      expect(container.querySelectorAll('.animate-spin-wheel')).toHaveLength(10);
    });

    it('gives every moving vehicle its own duration so none fall into step', () => {
      const { container } = render(<StreetScene />);

      const durations = [...container.querySelectorAll('.animate-ride, .animate-ride-reverse')]
        .map((el) => el.style.animationDuration);

      // Synchronised loops are what make an animation read as cheap.
      expect(new Set(durations).size).toBe(durations.length);
    });

    it('carries the brand mark on each rider’s delivery box', () => {
      const { container } = render(<StreetScene />);

      // The mark reuses the exact path from Logo.jsx rather than a redraw, so
      // the box and the navbar logo cannot drift apart.
      const marks = [...container.querySelectorAll('path')].filter((p) =>
        p.getAttribute('d')?.startsWith('M11 33.5c5.4'),
      );

      expect(marks).toHaveLength(3);
    });
  });
});
