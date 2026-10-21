import { mkdir, readFile, readdir, writeFile } from 'node:fs/promises';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = dirname(fileURLToPath(import.meta.url));
const output = join(root, 'orca-staging-deployment');
const sourceFiles = [
  'research-workspace-staging.html',
  'research-workspace.html',
  'account.html',
  'join-research.html',
  'commons-site-tools.js',
];
const expectedFiles = [
  'account.html',
  'commons-site-tools.js',
  'index.html',
  'join-research.html',
  'orca-staging-config.js',
  'research-workspace-staging.html',
  'research-workspace.html',
];

const stagingConfigSource = await readFile(join(root, 'orca-staging-config.js'), 'utf8');
const configValue = (name) => {
  const match = stagingConfigSource.match(new RegExp(`export const ${name} = '([^']+)';`));
  if (!match) throw new Error(`Missing staging setting ${name}; refusing to build deployment files.`);
  return match[1];
};
const environment = configValue('ORCA_STAGING_ENVIRONMENT');
const projectRef = configValue('ORCA_STAGING_PROJECT_REF');
const projectUrl = configValue('ORCA_STAGING_PROJECT_URL');
const publishableKey = configValue('ORCA_STAGING_PUBLISHABLE_KEY');
if (projectRef !== 'vbziibatnejoswsdggga' || !publishableKey.startsWith('sb_publishable_')) {
  throw new Error('Staging project identity or publishable key is invalid; refusing to build deployment files.');
}

await mkdir(output, { recursive: true });
const existingFiles = await readdir(output);
const unexpectedFiles = existingFiles.filter((name) => name !== '.git' && !expectedFiles.includes(name));
if (unexpectedFiles.length) {
  throw new Error(`Unexpected files in staging output directory: ${unexpectedFiles.join(', ')}. Remove or review them manually.`);
}

for (const name of sourceFiles) {
  await writeFile(join(output, name), await readFile(join(root, name)));
}
await writeFile(join(output, 'index.html'), await readFile(join(root, 'research-workspace-staging.html')));
const indexPath = join(output, 'index.html');
let indexPage = await readFile(indexPath, 'utf8');
const redirectStatement = '    window.location.replace(target.href);';
if (!indexPage.includes(redirectStatement)) {
  throw new Error('Expected staging root redirect not found; refusing to lose Auth callback state.');
}
indexPage = indexPage.replace(
  redirectStatement,
  `    target.hash = window.location.hash;
    ${redirectStatement.trim()}`,
);
await writeFile(indexPath, indexPage);

const stagingConfig = `const ORCA_STAGING_ENVIRONMENT = '${environment}';
const ORCA_STAGING_PROJECT_REF = '${projectRef}';
const ORCA_STAGING_PROJECT_URL = '${projectUrl}';
const ORCA_STAGING_PUBLISHABLE_KEY = '${publishableKey}';

export function isOrcaStagingEnvironment() {
  return true;
}

export async function selectSupabaseConfig() {
  const projectUrl = new URL(ORCA_STAGING_PROJECT_URL);
  if (
    projectUrl.protocol !== 'https:'
    || projectUrl.hostname !== \`\${ORCA_STAGING_PROJECT_REF}.supabase.co\`
    || !ORCA_STAGING_PUBLISHABLE_KEY.startsWith('sb_publishable_')
  ) {
    throw new Error('ORCA staging configuration is invalid; refusing to connect.');
  }
  return {
    isOrcaStaging: true,
    projectUrl: projectUrl.href.replace(/\\/$/, ''),
    publishableKey: ORCA_STAGING_PUBLISHABLE_KEY,
  };
}

export function orcaStagingHref(path, params = {}) {
  const url = new URL(path, window.location.href);
  if (
    url.origin !== window.location.origin
    || !url.pathname.startsWith('/orca-staging/')
  ) {
    throw new Error('ORCA staging links must remain within the staging website.');
  }
  for (const [key, value] of Object.entries(params)) {
    if (value !== undefined && value !== null && value !== '') {
      url.searchParams.set(key, String(value));
    }
  }
  url.searchParams.set('environment', ORCA_STAGING_ENVIRONMENT);
  return \`\${url.pathname}\${url.search}\${url.hash}\`;
}

export function showOrcaStagingIndicator() {
  const indicator = document.getElementById('staging-indicator');
  if (indicator) indicator.hidden = false;
}
`;
await writeFile(join(output, 'orca-staging-config.js'), stagingConfig);

const accountPath = join(output, 'account.html');
let account = await readFile(accountPath, 'utf8');
const supabaseUrlBinding = 'const {isOrcaStaging,projectUrl:URL,publishableKey:PUBLISHABLE_KEY}=await selectSupabaseConfig();';
if (!account.includes(supabaseUrlBinding)) {
  throw new Error('Expected account Supabase URL binding not found; refusing to ship an unreviewed account page.');
}
account = account.replace(
  supabaseUrlBinding,
  'const {isOrcaStaging,projectUrl:SUPABASE_URL,publishableKey:PUBLISHABLE_KEY}=await selectSupabaseConfig();',
);
if (!account.includes('client=createClient(URL,PUBLISHABLE_KEY,')) {
  throw new Error('Expected account Supabase client initialization not found; refusing to ship an unreviewed account page.');
}
account = account.replace(
  'client=createClient(URL,PUBLISHABLE_KEY,',
  'client=createClient(SUPABASE_URL,PUBLISHABLE_KEY,',
);
const emailRedirectBlock = /      const stagingRedirectPath=stagingReturnTo==='join-research\.html'\s*\n\s*\?'join-research\.html'\s*\n\s*:'research-workspace\.html';\s*\n\s*const emailRedirectTo=isOrcaStaging\s*\n\s*\? new URL\(orcaStagingHref\('\.\/'\+stagingRedirectPath,\{ticker\}\),location\.href\)\.href\s*\n\s*: 'https:\/\/jonfordy5\.github\.io\/agent-learning-commons\/';/;
if (!emailRedirectBlock.test(account)) {
  throw new Error('Expected account callback block not found; refusing to ship an unreviewed Auth redirect.');
}
account = account.replace(emailRedirectBlock, `      const stagingRedirectPath=stagingReturnTo==='join-research.html'
        ?'join-research.html'
        :'research-workspace.html';
      const emailRedirectTo=new URL(orcaStagingHref('./'+stagingRedirectPath,{ticker}),location.href).href;`);
await writeFile(accountPath, account);

const joinPath = join(output, 'join-research.html');
let joinPage = await readFile(joinPath, 'utf8');
for (const route of ['agent-profile.html', 'participation.html', 'worker-enroll.html']) {
  joinPage = joinPage.replace(new RegExp(`<a class="btn alt" href="./${route}">[^<]*<\\/a>`, 'g'), '');
}
await writeFile(joinPath, joinPage);

const outputFiles = (await readdir(output)).filter((name) => name !== '.git').sort();
if (outputFiles.join('\n') !== [...expectedFiles].sort().join('\n')) {
  throw new Error('Staging output contents did not match the deployment allowlist.');
}

const productionConfig = await readFile(join(output, 'orca-staging-config.js'), 'utf8');
const stagedAccount = await readFile(accountPath, 'utf8');
const stagedJoin = await readFile(joinPath, 'utf8');
const forbidden = [
  [productionConfig, /orca-production-config|agent-learning-commons/],
  [stagedAccount, /orca-production-config|jonfordy5\.github\.io\/agent-learning-commons|projectUrl:URL|createClient\(URL,/],
  [stagedJoin, /href="\.\/(?:agent-profile|participation|worker-enroll)\.html"/],
];
if (forbidden.some(([content, pattern]) => pattern.test(content))) {
  throw new Error('Production configuration, callback, or navigation remains in staging output.');
}
if (
  !stagedAccount.includes('projectUrl:SUPABASE_URL')
  || !stagedAccount.includes('createClient(SUPABASE_URL,')
  || !stagedAccount.includes("new URL(orcaStagingHref('./'+stagingRedirectPath,{ticker}),location.href).href")
) {
  throw new Error('Staging account URL binding or confirmation redirect is invalid.');
}

console.log(`Prepared ${outputFiles.length} allowlisted public files in ${output}`);
