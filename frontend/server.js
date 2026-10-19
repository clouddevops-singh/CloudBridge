import express from 'express';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const app = express();
const root = path.dirname(fileURLToPath(import.meta.url));
const dist = path.join(root, 'dist');
app.get('/runtime-config.json', (_req, res) => {
  res.set('Cache-Control', 'no-store');
  res.json({
    tenantId: process.env.ENTRA_TENANT_ID || '',
    clientId: process.env.ENTRA_CLIENT_ID || '',
    apiScope: process.env.ENTRA_API_SCOPE || '',
    apiBaseUrl: process.env.APIM_API_BASE_URL || '',
    // This value is intentionally delivered to the browser. Use only a disposable,
    // rate-limited subscription key; browser-delivered keys cannot be kept secret.
    apimSubscriptionKey: process.env.APIM_SUBSCRIPTION_KEY || ''
  });
});
app.use(express.static(dist, { maxAge: '1h' }));
app.get('*path', (_req, res) => res.sendFile(path.join(dist, 'index.html')));
const port = Number(process.env.PORT || 8080);
app.listen(port, '0.0.0.0', () => console.log(`Web app listening on ${port}`));
