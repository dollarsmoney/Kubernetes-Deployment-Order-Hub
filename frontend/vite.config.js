import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';

export default defineConfig({
  plugins: [react()],

  server: {
    host: '0.0.0.0', // listen on all interfaces so it works inside Docker
    port: 5173,

    // ------------------------------------------------------------------------
    // DEV-ONLY PROXY
    // ------------------------------------------------------------------------
    // In development, Vite serves on :5173 and FastAPI on :8000 — different
    // origins, so a direct fetch would be a CORS request.
    //
    // This proxy makes /api/* same-origin during development, which mirrors
    // exactly what nginx does in production (see frontend/nginx.conf). The
    // application code therefore fetches '/api/restaurants' in BOTH
    // environments and never needs to know an API host.
    //
    // That is the whole reason there is no VITE_API_URL anywhere in this
    // project: there is no environment-specific URL to configure.
    //
    // 'backend' is the docker-compose service name; it resolves to localhost
    // when running `npm run dev` outside Docker.
    // ------------------------------------------------------------------------
    proxy: {
      '/api': {
        target: process.env.VITE_PROXY_TARGET || 'http://localhost:8000',
        changeOrigin: true,
        // The backend has no /api prefix on its routes — it serves
        // /restaurants, not /api/restaurants. Strip the prefix on the way
        // through, exactly as nginx does in production.
        rewrite: (path) => path.replace(/^\/api/, ''),
      },
    },
  },

  build: {
    outDir: 'dist',

    // Source maps make a production bundle debuggable in browser dev tools,
    // at the cost of shipping your original source to anyone who looks.
    // Fine for a portfolio project; think twice for proprietary code.
    sourcemap: true,

    rollupOptions: {
      output: {
        // Split vendor code into its own chunk. React and Framer Motion change
        // far less often than our components, so a separate chunk stays cached
        // in browsers across deploys.
        manualChunks: {
          vendor: ['react', 'react-dom'],
          motion: ['framer-motion'],
        },
      },
    },
  },
});
