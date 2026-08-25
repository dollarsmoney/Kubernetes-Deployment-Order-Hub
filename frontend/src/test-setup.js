// Runs once before every test file (see vitest.config.js `setupFiles`).

import '@testing-library/jest-dom/vitest';
import { cleanup } from '@testing-library/react';
import { afterEach, vi } from 'vitest';

afterEach(() => {
  // Unmount anything still rendered. Without this, components leak between
  // tests and a `getByText` picks up a node from a previous test — a failure
  // that only appears when the whole file runs, never when you run one test.
  cleanup();
  vi.restoreAllMocks();
});

// jsdom implements neither of these, and both are used by the app:
//   IntersectionObserver -> Framer Motion's whileInView
//   matchMedia           -> useReducedMotion
// Without stubs, every component test throws before it renders anything.

globalThis.IntersectionObserver = class {
  observe() {}
  unobserve() {}
  disconnect() {}
  takeRecords() {
    return [];
  }
};

Object.defineProperty(window, 'matchMedia', {
  writable: true,
  value: (query) => ({
    matches: false, // reduced motion OFF by default; tests override as needed
    media: query,
    onchange: null,
    addListener: () => {},
    removeListener: () => {},
    addEventListener: () => {},
    removeEventListener: () => {},
    dispatchEvent: () => false,
  }),
});
