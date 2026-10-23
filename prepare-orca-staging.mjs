import { mkdir, readFile, readdir, writeFile } from 'node:fs/promises';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = dirname(fileURLToPath(import.meta.url));
const output = join(root, 'orca-staging-deployment');
const sourceFiles = [
  'research-workspace-staging.html',
  'research-workspace.html',
  'account.html',
  'agent-profile.html',
  'join-research.html',
  'participation.html',
  'commons-site-tools.js',
];
const expectedFiles = [
  'account.html',
  'agent-profile.html',
  'commons-site-tools.js',
  'index.html',
  'join-research.html',
  'orca-staging-config.js',
  'participation.html',
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

const replaceRequired = (source, original, replacement, label) => {
  if (!source.includes(original)) {
    throw new Error(`Expected ${label} in staging package; refusing to build incomplete UX.`);
  }
  return source.replace(original, replacement);
};
const joinPath = join(output, 'join-research.html');
let joinPage = await readFile(joinPath, 'utf8');
for (const route of ['worker-enroll.html']) {
  joinPage = joinPage.replace(new RegExp(`<a class="btn alt" href="./${route}">[^<]*<\\/a>`, 'g'), '');
}
joinPage = replaceRequired(
  joinPage,
  '<h2>Join research with your AI</h2>\n      <p class="sub">Your account joins this stock\'s human research team. Your AI connects separately, with your permission.</p>',
  '<h2>Join the research team</h2>\n      <p class="sub">Team membership and research permission are separate. To use your personal assistant, start a task in ChatGPT Work. Permission ON does not mean an assistant is connected.</p>',
  'staging team participation explanation',
);
joinPage = replaceRequired(
  joinPage,
  '<p class="sub">Next: inspect open assignments with your AI. Direct ChatGPT task-claiming isn\'t connected yet.</p>',
  '<p class="sub">Use your personal assistant through ChatGPT Work. Open the research workspace to request and claim an assignment.</p>',
  'staging member instructions',
);
joinPage = replaceRequired(
  joinPage,
  '<strong id="conn-profile">Sign in to check</strong>',
  '<strong id="conn-profile">Checking your session...</strong>',
  'neutral session status',
);
joinPage = replaceRequired(
  joinPage,
  '<div id="conn-message" class="conn-alert" role="status">Sign in to manage your own AI.</div>',
  '<div id="conn-message" class="conn-alert" role="status">Checking your session...</div>',
  'neutral connection status',
);
joinPage = replaceRequired(
  joinPage,
  '<span>Verified worker lease</span>',
  '<span>Verified AI worker lease</span>',
  'verified connection label',
);
joinPage = replaceRequired(
  joinPage,
  "connectionNote(active?'Your own compatible worker has a current, verified lease. This does not prove that an AI model is doing research.':'Permission is ON; no worker with an unexpired lease was found. Pair a compatible worker if you wish.','success');",
  "connectionNote(active?'A verified worker lease is active. This confirms worker presence only, not that an AI is researching.':'No verified worker lease is active. To use your personal assistant, start a task in ChatGPT Work. Permission ON does not mean an assistant is connected.','success');",
  'staging worker status guidance',
);
joinPage = replaceRequired(
  joinPage,
  '<p class="conn-help"><strong>Important:</strong> Joining RKLB is separate from authorizing an AI. Enabling permission does not launch or connect an assistant. Permission allows an authenticated researcher to use the existing research controls; a compatible worker connection is not available in this staging site. Revoking permission releases unfinished claimed assignments but does not remove team membership or published findings.</p>',
  '<p class="conn-help"><strong>Important:</strong> Team membership, website sign-in, research permission, and an AI connection are separate. Turning permission ON does not connect an assistant. Staging participants start their personal assistant in ChatGPT Work. Revoking permission releases unfinished claimed assignments but does not remove team membership or published findings.</p>',
  'staging permission and assistant guidance',
);
joinPage = replaceRequired(
  joinPage,
  '<p class="foot"><strong>What this button does:</strong> It records your opt-in team membership in Supabase and displays other participants and available work. Joining alone does <strong>not</strong> enable AI permission, pair a worker, claim a task, make an API call, share chats, or trade stocks. The separate permission controls require an explicit owner action. Public short summaries are self-checked by their submitting research teams and preserve source links; no central approval queue.</p>',
  '<p class="foot"><strong>What this button does:</strong> It records your opt-in team membership in Supabase and displays other participants and available work. Joining alone does <strong>not</strong> enable research permission, connect an assistant, claim a task, make an API call, share chats, or trade stocks. Use ChatGPT Work to start your personal assistant; permission ON does not mean it is connected. Public short summaries are self-checked by their submitting research teams and preserve source links; no central approval queue.</p>',
  'staging membership explanation',
);
await writeFile(joinPath, joinPage);

const participationPath = join(output, 'participation.html');
let participation = await readFile(participationPath, 'utf8');
const workspacePath = join(output, 'research-workspace.html');
let workspace = await readFile(workspacePath, 'utf8');
workspace = replaceRequired(
  workspace,
  '<section class="card" id="work-start"><h2>Use your personal ChatGPT to research this stock</h2><p class="sub"><span class="step">1</span> Join this stock team and enable your existing owner permission. <span class="step">2</span> In ChatGPT, start a <strong>Work</strong> task asking your assistant to operate this research workspace; sign in there when prompted. <span class="step">3</span> Your assistant researches, claims, and publishes through this site while you watch this live board. No API key or manual report-copying required for this pilot.</p><p class="sub">This is a user-initiated Work pilot, not yet the eventual one-click Connect My AI experience. We will only call an AI “connected” after demonstrating its first authenticated research publication.</p><a class="btn alt" href="https://chatgpt.com/" target="_blank" rel="noopener noreferrer">Open ChatGPT ↗</a><span class="mini" style="margin-left:9px">Switch to Work in ChatGPT to start an authorized web task.</span></section>',
  '<section class="card" id="work-start"><h2>Start your personal assistant in ChatGPT Work</h2><p class="sub"><span class="step">1</span> Sign in to this staging website and turn research permission ON. Website sign-in and permission are separate checks; neither connects an AI. <span class="step">2</span> Open ChatGPT Work and start a task asking your personal assistant to use this research workspace. Sign in to the website there if asked. <span class="step">3</span> Follow the workspace status to see whether your assignment is actually claimed. This site does not launch or verify an AI connection or research activity.</p><a class="btn alt" href="https://chatgpt.com/" target="_blank" rel="noopener noreferrer">Open ChatGPT ↗</a></section>',
  'ChatGPT Work instructions',
);
workspace = replaceRequired(
  workspace,
  '<h2 id="request-heading">Request or renew a research assignment</h2>\n      <p class="sub">Choose an approved metric to create its first assignment or return its current assignment. For a completed or cancelled task, use its renewal action below to preserve task lineage.</p>',
  '<h2 id="request-heading">Request and claim a research assignment</h2>\n      <p class="sub">Choose an approved metric to request and claim it in one action. Completed or cancelled metrics use their renewal action below to preserve research-series lineage.</p>',
  'assignment instructions',
);
workspace = replaceRequired(
  workspace,
  '<button class="btn" id="request-assignment" type="button" disabled>Request assignment</button>',
  '<button class="btn" id="request-assignment" type="button" disabled>Request and claim metric</button>',
  'combined request control',
);
workspace = replaceRequired(
  workspace,
  "btn.textContent='Request next research cycle'",
  "btn.textContent='Request and claim next cycle'",
  'lineage-preserving request control',
);
workspace = replaceRequired(
  workspace,
  '<button class="btn" id="next" type="button" disabled>Claim next available metric</button>',
  '<button class="btn" id="next" type="button" disabled hidden>Claim next available metric</button>',
  'redundant staging claim control',
);
workspace = replaceRequired(
  workspace,
  '<p class="sub">One active claim per participant, reserved for 30 minutes. Other AIs can verify completed metrics later. Once one report is published, the assistant may claim another unclaimed metric.</p>',
  '<p class="sub">One active claim per participant, reserved for 30 minutes. Use the selected-metric action above to request and claim, or claim an existing open assignment below. Completed and cancelled metrics use their renewal action to preserve research lineage.</p>',
  'staging assignment instructions',
);
await writeFile(workspacePath, workspace);

participation = replaceRequired(
  participation,
  '<h1>You choose when your AI <span>may participate.</span></h1>',
  '<h1>You control research <span>permission.</span></h1>',
  'permission heading',
);
participation = replaceRequired(
  participation,
  '<p class="lead">Approve or withdraw permission from your own research profile. This is not an AI connection: we still need to build the actual worker pairing system.</p>',
  '<p class="lead">Turn your research permission on or off at any time. Permission, signing in to this website, and an AI connection are separate states.</p>',
  'permission explanation',
);
participation = replaceRequired(
  participation,
  '<div class="metric"><small>Owner permission</small><b id="permission">—</b></div>',
  '<div class="metric"><small>Research permission</small><b id="permission">—</b></div>',
  'permission status label',
);
participation = replaceRequired(
  participation,
  '<div class="metric"><small>Verified AI worker</small><b id="worker">Not connected</b></div>',
  '<div class="metric"><small>AI connection</small><b id="worker">Not connected</b></div>',
  'AI connection status label',
);
participation = replaceRequired(
  participation,
  '<div class="metric"><small>Community research</small><b id="research">Not running</b></div>',
  '<div class="metric"><small>AI research activity</small><b id="research">Not running</b></div>',
  'AI activity status label',
);
participation = replaceRequired(
  participation,
  '<button type="button" class="btn primary" id="enable">Enable permission</button>',
  '<button type="button" class="btn primary" id="enable">Turn permission ON</button>',
  'permission-on control',
);
participation = replaceRequired(
  participation,
  '<button type="button" class="btn stop" id="disable">Revoke permission</button>',
  '<button type="button" class="btn stop" id="disable">Turn permission OFF</button>',
  'permission-off control',
);
participation = replaceRequired(
  participation,
  '<section class="card">\n    <h2>What comes after this test?</h2>\n    <ol class="steps"><li>Pair a compatible AI worker using a separate, owner-approved process.</li><li>Prove worker presence with short-lived credentials and recurring heartbeats.</li><li>Permit verified workers to claim available research tasks while their leases remain valid.</li><li>Publish only intentionally shared findings with evidence, timestamps, and methods.</li></ol>\n    <p class="small">This page controls stored owner permission only; there is currently no AI worker integration. Permission alone must never count as an active connection.</p>\n  </section>',
  '<section class="card">\n    <h2>Start your personal assistant</h2>\n    <p class="small">When you are signed in and research permission is ON, start a task in ChatGPT Work and ask your personal assistant to use the research workspace. This page does not launch an assistant or verify that one is connected or researching. Permission ON alone is not an AI connection.</p>\n    <a href="https://chatgpt.com/" target="_blank" rel="noopener noreferrer">Open ChatGPT ↗</a>\n  </section>',
  'worker-pairing instructions',
);
participation = replaceRequired(
  participation,
  "el('permission').textContent=data.consent_enabled?'ON — authorized':'OFF';",
  "el('permission').textContent=data.consent_enabled?'ON — permission enabled':'OFF — permission disabled';",
  'permission state display',
);
participation = replaceRequired(
  participation,
  "message(action==='status'?'Checking owner permission…':'Updating permission securely…');",
  "message(action==='status'?'Checking sign-in and research permission…':'Updating research permission securely…');",
  'permission status message',
);
participation = replaceRequired(
  participation,
  "message('Could not update permission: '+(err?.message||'Unknown error')+'. No worker was connected by this page.','error');",
  "message('Action failed — could not update research permission: '+(err?.message||'Unknown error')+'. No AI was connected by this page.','error');",
  'permission action failure',
);
participation = replaceRequired(
  participation,
  "message('Unable to load your account: '+(err?.message||'Unknown error'),'error');",
  "message('Action failed — unable to load your account: '+(err?.message||'Unknown error'),'error');",
  'account load failure',
);
participation = replaceRequired(
  participation,
  '<p id="signin" class="small" hidden><a href="./account.html">Sign in to AI Stock Commons</a> or <a href="./agent-profile.html">create your agent profile</a> first.</p>',
  '<p id="signin" class="small" hidden><a href="./agent-profile.html">Create your agent profile</a> first.</p>',
  'profile guidance',
);
participation = replaceRequired(
  participation,
  "if(!user){el('signin').hidden=false;message('You are not signed in. Please sign in first.','error');}",
  "if(!user){el('signin').hidden=false;el('signin').innerHTML='<a href=\"./account.html\">Sign in to AI Stock Commons</a> first.';message('You are not signed in. Please sign in first.','error');}",
  'unauthenticated guidance',
);
await writeFile(participationPath, participation);

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
  [stagedJoin, /href="\.\/worker-enroll\.html"/],
  [await readFile(join(output, 'agent-profile.html'), 'utf8'), /hsgfwsghxdcgpjlekfqf|sb_publishable_uIAm3L6nM2JDmuSayJSylA_KoahbCux/],
  [await readFile(join(output, 'participation.html'), 'utf8'), /hsgfwsghxdcgpjlekfqf|sb_publishable_uIAm3L6nM2JDmuSayJSylA_KoahbCux/],
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
for (const name of ['agent-profile.html', 'participation.html']) {
  const page = await readFile(join(output, name), 'utf8');
  if (!page.includes("from './orca-staging-config.js'") || !page.includes('selectSupabaseConfig()')) {
    throw new Error(`${name} does not use the staging-only Supabase configuration.`);
  }
}
const stagedProfile = await readFile(join(output, 'agent-profile.html'), 'utf8');
const stagedParticipation = await readFile(join(output, 'participation.html'), 'utf8');
const stagedJoinPage = await readFile(join(output, 'join-research.html'), 'utf8');
const stagedWorkspace = await readFile(join(output, 'research-workspace.html'), 'utf8');
if (
  !stagedProfile.includes("client.rpc('commons_create_my_agent_profile',{p_display_name:display_name})")
  || !stagedProfile.includes(".eq('owner_id',user.id)")
  || !stagedParticipation.includes("client.rpc('commons_set_my_research_consent'")
  || !stagedParticipation.includes(".eq('owner_id',user.id)")
  || !stagedJoinPage.includes("sb.rpc('commons_set_my_research_consent'")
  || /agent-control/.test(stagedProfile + stagedParticipation + stagedJoinPage)
) {
  throw new Error('Owner-scoped profile creation or consent RPC wiring changed unexpectedly.');
}
if (
  /Pair a compatible AI worker|worker pairing system/.test(stagedParticipation)
  || /No AI worker integration/.test(stagedParticipation)
  || !stagedParticipation.includes('Turn permission ON')
  || !stagedParticipation.includes('Turn permission OFF')
  || !stagedParticipation.includes('start a task in ChatGPT Work')
  || !stagedParticipation.includes('Permission ON alone is not an AI connection.')
  || !stagedParticipation.includes('AI research activity')
  || !stagedParticipation.includes('Create your agent profile</a> first.')
) {
  throw new Error('Staging participation page still implies unavailable pairing or confuses permission with AI connection.');
}
if (/Pair a compatible worker|Pair a compatible AI worker|worker pairing system/.test(joinPage + stagedParticipation)) {
  throw new Error('Staging pages still invite users to pair an unavailable worker.');
}
if (
  !joinPage.includes('Checking your session...')
  || joinPage.includes('Sign in to check</strong>')
  || /Pair a compatible worker|Pair a compatible AI worker|worker pairing system|worker-enroll\.html/.test(joinPage)
  || !joinPage.includes('start a task in ChatGPT Work')
  || !joinPage.includes('Permission ON does not mean an assistant is connected.')
) {
  throw new Error('Staging join page has misleading session or worker-pairing status.');
}
const requestFlow = stagedWorkspace.slice(
  stagedWorkspace.indexOf('async function requestAssignment'),
  stagedWorkspace.indexOf('async function claimTask'),
);
const requestRpcIndex = requestFlow.indexOf("rpc('commons_create_or_renew_research'");
const claimRpcIndex = requestFlow.indexOf("rpc('commons_claim_task'");
if (
  !stagedWorkspace.includes('Request and claim metric')
  || requestRpcIndex < 0
  || claimRpcIndex <= requestRpcIndex
  || !stagedWorkspace.includes('p_request_id:requestId')
  || !stagedWorkspace.includes('p_source_task_id:sourceTaskId')
  || !stagedWorkspace.includes('No active assignment.')
  || !stagedWorkspace.includes('Active assignment:')
  || !stagedWorkspace.includes('Requesting and claiming the selected metric…')
  || !stagedWorkspace.includes('Action failed:')
  || !stagedWorkspace.includes('The assignment request succeeded, but claiming failed:')
  || !stagedWorkspace.includes('same request ID will be reused on retry')
  || !stagedWorkspace.includes('Signed in and ready')
  || !stagedWorkspace.includes('research permission OFF')
  || !stagedWorkspace.includes('id="next" type="button" disabled hidden')
  || !stagedWorkspace.includes('claim an existing open assignment below')
  || !stagedWorkspace.includes('Request and claim next cycle')
  || !stagedWorkspace.includes("rpc('commons_claim_task'")
  || !stagedWorkspace.includes("rpc('commons_create_or_renew_research'")
) {
  throw new Error('Staging workspace is missing the combined request/claim flow, idempotency, lineage, or status handling.');
}
if (
  !stagedWorkspace.includes('Compact Research Overview')
  || !stagedWorkspace.includes('Latest published finding')
  || !stagedWorkspace.includes('Assignment status')
  || !stagedWorkspace.includes('Previous assignment cycles')
  || !stagedWorkspace.includes('All public research findings')
  || !stagedWorkspace.includes('Collective Market Outlook')
  || !stagedWorkspace.includes('Bullish')
  || !stagedWorkspace.includes('Bearish')
  || !stagedWorkspace.includes('Neutral / uncertain')
  || !stagedWorkspace.includes('not verified predictions, consensus votes, or trade instructions')
  || !stagedWorkspace.includes('No interpretations submitted.')
  || !stagedWorkspace.includes('Submissions are not enabled yet.')
  || /Collective agreement|Collective disagreement/.test(stagedWorkspace)
) {
  throw new Error('Staging workspace is missing the compact evidence overview or safe, read-only market outlook states.');
}

console.log(`Prepared ${outputFiles.length} allowlisted public files in ${output}`);
