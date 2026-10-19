import { PublicClientApplication } from '@azure/msal-browser';
import './style.css';

const config = await fetch('/runtime-config.json').then(r => r.json());
const ready = Boolean(config.tenantId && config.clientId && config.apiScope && config.apiBaseUrl);
const msal = ready ? new PublicClientApplication({
  auth: { clientId: config.clientId, authority: `https://login.microsoftonline.com/${config.tenantId}`, redirectUri: window.location.origin },
  cache: { cacheLocation: 'sessionStorage' }
}) : null;
if (msal) await msal.initialize();

document.querySelector('#app').innerHTML = `
  <main class="shell">
    <header><span class="eyebrow">AZURE REFERENCE APP</span><h1>One front door.<br/><em>Two runtimes.</em></h1>
    <p class="intro">A Node.js 22 web client calls a Python API through Azure API Management. Sign in, then follow a request through the gateway.</p></header>
    <section class="panel">
      <div class="row"><div><span class="eyebrow">IDENTITY</span><p id="identity">${ready ? 'Not signed in' : 'Entra ID settings are missing'}</p></div><button id="login" ${ready ? '' : 'disabled'}>Sign in</button><button id="logout" class="secondary" hidden>Sign out</button></div>
      <div class="divider"></div>
      <div class="row"><div><span class="eyebrow">API ROUTE</span><p class="mono">${escapeHtml(config.apiBaseUrl || 'Set VITE_API_BASE_URL')}</p></div><button id="call" class="secondary" ${ready ? '' : 'disabled'}>Call protected API</button></div>
      <pre id="result" aria-live="polite">Sign in with your organization account to request an access token.</pre>
      <p class="note">The browser sends a Microsoft Entra access token and an APIM subscription key directly to the gateway. The subscription key is visible to browser users; use this demo key only for low-risk, rate-limited access.</p>
    </section>
    <footer><span>App Service · Node.js 22</span><span>APIM → Container Apps · Python</span></footer>
  </main>`;

const identity = document.querySelector('#identity');
const result = document.querySelector('#result');
const loginButton = document.querySelector('#login');
const logoutButton = document.querySelector('#logout');
let account = msal?.getAllAccounts()[0];
function paintAccount() { identity.textContent = account?.username || 'Not signed in'; loginButton.hidden = Boolean(account); logoutButton.hidden = !account; }
paintAccount();
loginButton.onclick = async () => { try { await msal.loginRedirect({ scopes: [config.apiScope] }); } catch (e) { result.textContent = e.message; } };
logoutButton.onclick = () => msal.logoutRedirect({ account });
document.querySelector('#call').onclick = async () => {
  try {
    if (!account) throw new Error('Sign in before calling the API.');
    const token = await msal.acquireTokenSilent({ account, scopes: [config.apiScope] });
    const response = await fetch(`${config.apiBaseUrl.replace(/\/$/, '')}/api/v1/hello`, {
      headers: { Authorization: `Bearer ${token.accessToken}`, 'Ocp-Apim-Subscription-Key': config.apimSubscriptionKey }
    });
    const body = await response.json();
    result.textContent = JSON.stringify({ status: response.status, body }, null, 2);
  } catch (e) { result.textContent = `${e.name}: ${e.message}`; }
};
function escapeHtml(s) { return String(s).replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c])); }
