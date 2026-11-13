import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';

export default defineConfig({
  plugins: [react()],
  build: { rollupOptions: { output: { manualChunks: { three: ['three'] } } } },
  server: {
    host: '0.0.0.0',
    port: 5173,
    strictPort: true,
    watch: {
      // Xcode outputs and test logs may be locked while written or synced by
      // OneDrive. They are independent of the browser app and need no watcher.
      ignored: /(?:^|[/\\])(?:build|ios|native|test-results)(?:[/\\]|$)/,
    },
  },
});
