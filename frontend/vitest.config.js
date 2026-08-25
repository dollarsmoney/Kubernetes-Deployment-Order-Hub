// =============================================================================
// vitest.config.js — test runner config
// =============================================================================
// Kept SEPARATE from vite.config.js on purpose. vite.config.js carries a
// `rollupOptions.manualChunks` block that splits react/framer-motion into
// vendor chunks; that setting conflicts with any build where those packages are
// external, and mixing build and test config in one file makes the failure look
// like a test problem rather than a bundler one.
// =============================================================================

import { defineConfig } from 'vitest/config';
import react from '@vitejs/plugin-react';

export default defineConfig({
  plugins: [react()],

  test: {
    // jsdom gives the tests a DOM. Without it, anything that touches
    // `document` — every component render — throws.
    environment: 'jsdom',

    // describe / it / expect / vi available without importing them, matching
    // the globals declared for the test files in eslint.config.js.
    globals: true,

    // Registers @testing-library/jest-dom matchers (toBeInTheDocument etc.)
    // and clears the DOM between tests.
    setupFiles: ['./src/test-setup.js'],

    include: ['src/**/*.test.{js,jsx}'],

    coverage: {
      provider: 'v8',
      reporter: ['text', 'lcov'],
      // Only measure code we actually wrote.
      include: ['src/**/*.{js,jsx}'],
      exclude: ['src/**/*.test.{js,jsx}', 'src/main.jsx', 'src/test-setup.js'],
    },
  },
});
