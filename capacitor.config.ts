import type { CapacitorConfig } from '@capacitor/cli';

const config: CapacitorConfig = {
  appId: 'ch.takt.transitworld',
  appName: 'Takt',
  webDir: 'dist',
  backgroundColor: '#f5f4ef',
  ios: { contentInset: 'never', preferredContentMode: 'mobile' },
};

export default config;
