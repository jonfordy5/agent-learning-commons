export const ORCA_STAGING_ENVIRONMENT = 'orca-staging';
export const ORCA_STAGING_PROJECT_REF = 'vbziibatnejoswsdggga';
export const ORCA_STAGING_PROJECT_URL = 'https://vbziibatnejoswsdggga.supabase.co';
export const ORCA_STAGING_PUBLISHABLE_KEY = 'sb_publishable_vUOZ5qC2FQVsh7MUyEmHQA_j211UdHH';

export function isOrcaStagingEnvironment() {
  const pagesRepo = window.location.hostname === 'jonfordy5.github.io'
    && window.location.pathname.split('/').filter(Boolean)[0] === 'orca-staging';
  return pagesRepo || new URLSearchParams(window.location.search).get('environment') === ORCA_STAGING_ENVIRONMENT;
}

export async function selectSupabaseConfig() {
  if (!isOrcaStagingEnvironment()) {
    const { SUPABASE_PROJECT_URL, SUPABASE_PUBLISHABLE_KEY } = await import('./orca-production-config.mjs');
    return {
      isOrcaStaging: false,
      projectUrl: SUPABASE_PROJECT_URL,
      publishableKey: SUPABASE_PUBLISHABLE_KEY,
    };
  }
  const projectUrl = new URL(ORCA_STAGING_PROJECT_URL);
  if (
    projectUrl.protocol !== 'https:'
    || projectUrl.hostname !== `${ORCA_STAGING_PROJECT_REF}.supabase.co`
    || !ORCA_STAGING_PUBLISHABLE_KEY.startsWith('sb_publishable_')
  ) {
    throw new Error('ORCA staging configuration is invalid; refusing to connect.');
  }

  return {
    isOrcaStaging: true,
    projectUrl: projectUrl.href.replace(/\/$/, ''),
    publishableKey: ORCA_STAGING_PUBLISHABLE_KEY,
  };
}

export function orcaStagingHref(path, params = {}) {
  const url = new URL(path, window.location.href);
  if (url.origin !== window.location.origin) {
    throw new Error('ORCA staging links must remain on this website.');
  }
  for (const [key, value] of Object.entries(params)) {
    if (value !== undefined && value !== null && value !== '') {
      url.searchParams.set(key, String(value));
    }
  }
  url.searchParams.set('environment', ORCA_STAGING_ENVIRONMENT);
  return `${url.pathname}${url.search}${url.hash}`;
}

export function showOrcaStagingIndicator() {
  const indicator = document.getElementById('staging-indicator');
  if (indicator) indicator.hidden = !isOrcaStagingEnvironment();
}
