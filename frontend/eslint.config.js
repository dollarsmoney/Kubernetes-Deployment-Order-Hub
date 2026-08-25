// =============================================================================
// eslint.config.js — ESLint 9 "flat config"
// =============================================================================
// Replaces the `"lint": "echo \"no linter configured\""` stub that used to sit
// in package.json. A lint script that always exits 0 is worse than none: CI
// goes green and nobody notices there is no linter.
//
// Flat config (an exported array) is ESLint 9's format. The older .eslintrc.json
// with `extends` is legacy and most tutorials you will find still use it.
// =============================================================================

import js from '@eslint/js';
import globals from 'globals';
import react from 'eslint-plugin-react';
import reactHooks from 'eslint-plugin-react-hooks';

export default [
  // Ignores first — these apply to every block that follows.
  {
    ignores: ['dist/**', 'node_modules/**', 'coverage/**', '*.config.js'],
  },

  // ---------------------------------------------------------------- Application
  {
    files: ['src/**/*.{js,jsx}'],

    languageOptions: {
      ecmaVersion: 2022,
      sourceType: 'module',
      globals: {
        ...globals.browser,
        ...globals.es2021,
      },
      parserOptions: {
        ecmaFeatures: { jsx: true },
      },
    },

    plugins: {
      react,
      'react-hooks': reactHooks,
    },

    settings: {
      // Without this, eslint-plugin-react warns on every file that it cannot
      // detect the React version.
      react: { version: 'detect' },
    },

    rules: {
      ...js.configs.recommended.rules,
      ...react.configs.recommended.rules,

      // -----------------------------------------------------------------------
      // React 17+ JSX transform: JSX compiles without React being in scope, so
      // these two legacy rules are wrong for this codebase. Vite uses the
      // automatic runtime.
      // -----------------------------------------------------------------------
      'react/react-in-jsx-scope': 'off',
      'react/prop-types': 'off', // no PropTypes in this project by choice

      // -----------------------------------------------------------------------
      // THE RULES THAT CATCH REAL BUGS
      // -----------------------------------------------------------------------
      // Wrong dependency arrays are the single most common React defect —
      // stale closures that work in development and fail under load. Error,
      // not warn: a warning in CI is a warning nobody reads.
      'react-hooks/rules-of-hooks': 'error',
      'react-hooks/exhaustive-deps': 'error',

      // Using an array index as a key makes React reuse the wrong DOM nodes
      // when a list reorders. RestaurantSection sorts its grid, so this is a
      // live hazard here, not a theoretical one.
      'react/no-array-index-key': 'error',

      'no-unused-vars': ['error', { argsIgnorePattern: '^_', varsIgnorePattern: '^_' }],
      'no-console': ['warn', { allow: ['warn', 'error'] }],
      eqeqeq: ['error', 'always', { null: 'ignore' }],
      'prefer-const': 'error',
      'no-var': 'error',
    },
  },

  // ---------------------------------------------------------------------- Tests
  {
    files: ['src/**/*.test.{js,jsx}', 'src/test-setup.js'],
    languageOptions: {
      globals: {
        ...globals.browser,
        // vitest exposes describe/it/expect/vi as globals — see vitest.config.js
        ...globals.vitest,
      },
    },
    rules: {
      'no-console': 'off',
    },
  },
];
