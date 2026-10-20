#!/usr/bin/env node

import { randomUUID } from 'node:crypto';
import { createInterface } from 'node:readline/promises';
import { stdin, stdout } from 'node:process';

const projectUrlInput = process.env.ORCA_STAGING_URL;
const publishableKey = process.env.ORCA_STAGING_PUBLISHABLE_KEY;

if (!projectUrlInput || !publishableKey) {
  throw new Error(
    'Set ORCA_STAGING_URL and ORCA_STAGING_PUBLISHABLE_KEY from the Orca-staging project settings.'
  );
}

if (publishableKey.startsWith('sb_secret_')) {
  throw new Error('Service/secret keys are forbidden; use the Orca-staging publishable/anon key.');
}
if (publishableKey.startsWith('eyJ')) {
  let keyClaims;
  try {
    keyClaims = JSON.parse(
      Buffer.from(publishableKey.split('.')[1], 'base64url').toString('utf8')
    );
  } catch {
    throw new Error('Unrecognized Supabase key; use the Orca-staging publishable/anon key.');
  }
  if (keyClaims.role !== 'anon') {
    throw new Error('Only an anon JWT or publishable key is allowed; service-role keys are forbidden.');
  }
} else if (!publishableKey.startsWith('sb_publishable_')) {
  throw new Error('Use the Orca-staging publishable key or legacy anon JWT; no other key is accepted.');
}

const projectUrl = new URL(projectUrlInput);
if (
  projectUrl.protocol !== 'https:' ||
  projectUrl.hostname.split('.').length < 3 ||
  !projectUrl.hostname.endsWith('.supabase.co') ||
  projectUrl.pathname !== '/'
) {
  throw new Error('ORCA_STAGING_URL must be the HTTPS Supabase project URL.');
}

if (!stdin.isTTY || !stdout.isTTY || typeof stdin.setRawMode !== 'function') {
  throw new Error('Run this harness in an interactive terminal; credentials are prompted securely.');
}

const projectRef = projectUrl.hostname.split('.')[0];
const authClients = [];

async function promptLine(prompt) {
  const readline = createInterface({ input: stdin, output: stdout });
  try {
    return await readline.question(prompt);
  } finally {
    readline.close();
  }
}

function requireValue(value, label) {
  if (value === null || value === undefined || value === '') {
    throw new Error(`Missing expected ${label}. Stop and review the staging state.`);
  }
  return value;
}

function parseJson(text) {
  if (!text) return null;
  try {
    return JSON.parse(text);
  } catch {
    return { message: text };
  }
}

class HttpError extends Error {
  constructor(operation, response, body) {
    super(
      `${operation} returned HTTP ${response.status}: ${
        body?.message ?? body?.msg ?? response.statusText
      }${body?.code ? ` (${body.code})` : ''}`
    );
    this.name = 'HttpError';
    this.status = response.status;
    this.code = body?.code;
  }
}

async function postJson(path, body, accessToken, operation) {
  const headers = {
    apikey: publishableKey,
    'Content-Type': 'application/json',
  };
  if (accessToken) headers.Authorization = `Bearer ${accessToken}`;

  const response = await fetch(new URL(path, projectUrl), {
    method: 'POST',
    headers,
    body: JSON.stringify(body),
  });
  const result = parseJson(await response.text());
  if (!response.ok) throw new HttpError(operation, response, result);
  return result;
}

async function getRows(path, accessToken) {
  const headers = { apikey: publishableKey };
  if (accessToken) headers.Authorization = `Bearer ${accessToken}`;
  const response = await fetch(new URL(path, projectUrl), { headers });
  const result = parseJson(await response.text());
  if (!response.ok) throw new HttpError(`GET ${path}`, response, result);
  if (!Array.isArray(result)) {
    throw new Error(`GET ${path} returned an unexpected response shape.`);
  }
  return result;
}

async function signIn(email, password, label) {
  const session = await postJson(
    '/auth/v1/token?grant_type=password',
    { email, password },
    null,
    `${label} Supabase Auth sign-in`
  );
  requireValue(session?.access_token, `${label} access token`);
  requireValue(session?.user?.id, `${label} Auth user ID`);
  const client = { accessToken: session.access_token, userId: session.user.id };
  authClients.push(client);
  return client;
}

async function signOutLocal(client) {
  const response = await fetch(
    new URL('/auth/v1/logout?scope=local', projectUrl),
    {
      method: 'POST',
      headers: {
        apikey: publishableKey,
        Authorization: `Bearer ${client.accessToken}`,
      },
    }
  );
  if (!response.ok) {
    throw new HttpError(
      'Supabase Auth local sign-out',
      response,
      parseJson(await response.text())
    );
  }
}

async function readSecret(prompt) {
  stdout.write(prompt);
  stdin.setRawMode(true);
  stdin.resume();

  return new Promise((resolve, reject) => {
    let value = '';
    let finished = false;
    const finish = (error) => {
      if (finished) return;
      finished = true;
      stdin.off('data', onData);
      stdin.setRawMode(false);
      stdout.write('\n');
      if (error) reject(error);
      else resolve(value);
    };
    const onData = (chunk) => {
      for (const character of chunk.toString('utf8')) {
        if (character === '\u0003') {
          finish(new Error('Cancelled by user.'));
          return;
        }
        if (character === '\r' || character === '\n') {
          finish();
          return;
        }
        if (character === '\u007f' || character === '\b') {
          value = value.slice(0, -1);
          continue;
        }
        if (character >= ' ') value += character;
      }
    };
    stdin.on('data', onData);
  });
}

function assert(condition, message) {
  if (!condition) throw new Error(message);
}

async function expectRejected(operation, label, expectedCode) {
  try {
    await operation();
  } catch (error) {
    if (error instanceof HttpError) {
      assert(
        error.code === expectedCode,
        `${label}: expected SQLSTATE ${expectedCode}, got ${error.code ?? 'no error code'}.`
      );
      console.log(`PASS: ${label} (HTTP ${error.status}${error.code ? `, ${error.code}` : ''})`);
      return;
    }
    throw error;
  }
  throw new Error(`${label}: request unexpectedly succeeded.`);
}

async function verifyProfile(client, expectedName, label) {
  const rows = await getRows(
    `/rest/v1/agent_profiles?select=id,display_name,opted_in&owner_id=eq.${client.userId}`,
    client.accessToken
  );
  assert(rows.length === 1, `${label} must have exactly one visible agent profile.`);
  assert(
    rows[0].display_name === expectedName,
    `${label} Auth account does not match the expected staging profile ${expectedName}.`
  );
  assert(rows[0].opted_in === true, `${label} research permission must be enabled.`);

  const memberships = await getRows(
    `/rest/v1/stock_research_memberships?select=ticker&user_id=eq.${client.userId}&ticker=eq.RKLB`,
    client.accessToken
  );
  assert(memberships.length === 1, `${label} must have RKLB membership.`);
}

async function verifyTask(client, taskId) {
  const rows = await getRows(
    `/rest/v1/research_tasks?select=id,ticker,status,claimed_owner_id,claimed_until,research_series_id,renewed_from_task_id&id=eq.${taskId}`,
    client.accessToken
  );
  assert(rows.length === 1, `Expected exactly one visible task for ${taskId}.`);
  return rows[0];
}

async function rpc(client, name, args) {
  return postJson(
    `/rest/v1/rpc/${name}`,
    args,
    client.accessToken,
    `RPC ${name}`
  );
}

async function main() {
  console.log(`Target Supabase project: ${projectUrl.hostname}`);
  const confirmation = await promptLine(
    `Type "${projectRef} staging" to confirm this is Orca-staging: `
  );
  assert(
    confirmation === `${projectRef} staging`,
    'Staging project confirmation did not match; no test requests were made.'
  );

  const emailA = (await promptLine('Researcher A email: ')).trim();
  const emailB = (await promptLine('Researcher B email: ')).trim();
  assert(emailA && emailB, 'Both researcher emails are required.');

  let researcherA;
  let researcherB;
  let passwordA = await readSecret('Researcher A password (input hidden): ');
  try {
    researcherA = await signIn(emailA, passwordA, 'Researcher A');
  } finally {
    passwordA = '';
  }
  let passwordB = await readSecret('Researcher B password (input hidden): ');
  try {
    researcherB = await signIn(emailB, passwordB, 'Researcher B');
  } finally {
    passwordB = '';
  }
  assert(
    researcherA.userId !== researcherB.userId,
    'The two Auth sessions must belong to different users.'
  );
  console.log('PASS: both researchers authenticated through Supabase Auth.');

  await verifyProfile(researcherA, 'ORCA Test Researcher 1', 'Researcher A');
  await verifyProfile(researcherB, 'ORCA Test Researcher 2', 'Researcher B');
  console.log('PASS: authenticated users match the two opted-in RKLB profiles.');

  const existingTasks = await getRows(
    '/rest/v1/research_tasks?select=id&ticker=eq.RKLB&limit=1',
    null
  );
  const existingFindings = await getRows(
    '/rest/v1/commons_research_findings?select=id&ticker=eq.RKLB&limit=1',
    null
  );
  assert(
    existingTasks.length === 0 && existingFindings.length === 0,
    'RKLB has visible task or finding history. Stop; the required read-only metadata preflight must show zero tasks, findings, series, and requests.'
  );
  console.log('PASS: public RKLB task and finding feeds are empty.');

  const runId = randomUUID();
  const initialRequestId = randomUUID();
  const observerRequestId = randomUUID();
  const renewalRequestId = randomUUID();
  const categoryKey = 'sec';
  const metricKey = 'sec.filings_catalysts';
  const initialArgs = {
    p_ticker: 'RKLB',
    p_category_key: categoryKey,
    p_metric_key: metricKey,
    p_request_id: initialRequestId,
    p_source_task_id: null,
  };
  let originalTaskId = null;
  let renewedTaskId = null;
  let findingId = null;
  const manifest = () => ({
    stagingProjectRef: projectRef,
    runId,
    categoryKey,
    metricKey,
    initialRequestId,
    observerRequestId,
    renewalRequestId,
    originalTaskId,
    renewedTaskId,
    findingId,
  });

  try {
    const firstCreate = await rpc(
      researcherA,
      'commons_create_or_renew_research',
      initialArgs
    );
    originalTaskId = requireValue(firstCreate?.id, 'initial task ID');
    assert(firstCreate?.status === 'open', 'The new assignment must start open.');

    const observerArgs = {
      ...initialArgs,
      p_request_id: observerRequestId,
    };
    const [retryCreate, researcherBRequest] = await Promise.all([
      rpc(researcherA, 'commons_create_or_renew_research', initialArgs),
      rpc(researcherB, 'commons_create_or_renew_research', observerArgs),
    ]);
    assert(
      retryCreate?.id === originalTaskId,
      'Researcher A idempotent retry returned a different task ID.'
    );
    assert(
      researcherBRequest?.id === originalTaskId &&
        researcherBRequest?.status === 'open' &&
        retryCreate?.status === 'open',
      'Concurrent cross-user requests did not return the same open assignment.'
    );
    console.log('PASS: concurrent cross-user requests and A’s idempotent retry were safe.');

    const claim = await rpc(researcherA, 'commons_claim_task', {
      p_task_id: originalTaskId,
    });
    assert(claim?.id === originalTaskId, 'Researcher A claim returned a different task.');
    const claimedOriginal = await verifyTask(researcherA, originalTaskId);
    assert(
      claimedOriginal.status === 'claimed' &&
        claimedOriginal.claimed_owner_id === researcherA.userId &&
        Date.parse(claimedOriginal.claimed_until) > Date.now(),
      'Researcher A must hold the active, leased original assignment.'
    );
    console.log('PASS: Researcher A claimed the original assignment.');

    await expectRejected(
      () =>
        rpc(researcherB, 'commons_claim_task', {
          p_task_id: originalTaskId,
        }),
      'Researcher B cannot claim Researcher A’s active assignment',
      'P0001'
    );
    await expectRejected(
      () =>
        rpc(researcherB, 'commons_release_task', {
          p_task_id: originalTaskId,
        }),
      'Researcher B cannot release Researcher A’s assignment',
      'P0001'
    );
    await expectRejected(
      () =>
        rpc(researcherB, 'commons_publish_finding', {
          p_task_id: originalTaskId,
          p_summary:
            `[ORCA STAGING TEST ${runId}] Unauthorized publication attempt ` +
            'against the active assignment; synthetic test only.',
          p_source_urls: ['https://example.com/orca-staging-test'],
          p_observed_at: new Date().toISOString(),
          p_limitations: 'Synthetic authorization-boundary test; not research evidence.',
        }),
      'Researcher B cannot publish to Researcher A’s assignment',
      'P0001'
    );
    const unchangedOriginal = await verifyTask(researcherA, originalTaskId);
    assert(
      unchangedOriginal.status === 'claimed' &&
        unchangedOriginal.claimed_owner_id === researcherA.userId,
      'Rejected unauthorized RPCs changed the original claim.'
    );
    console.log('PASS: denied access attempts left the owner claim unchanged.');

    await expectRejected(
      () =>
        rpc(researcherB, 'commons_create_or_renew_research', initialArgs),
      'Researcher B cannot replay Researcher A’s idempotency key',
      '22023'
    );

    const summary =
      `[ORCA STAGING TEST ${runId}] Synthetic integration-test finding for ` +
      'the ORCA Phase 2 authenticated two-researcher workflow. This is not ' +
      'investment research and contains no factual claim about RKLB.';
    findingId = await rpc(researcherA, 'commons_publish_finding', {
      p_task_id: originalTaskId,
      p_summary: summary,
      p_source_urls: ['https://example.com/orca-staging-test'],
      p_observed_at: new Date().toISOString(),
      p_limitations:
        'Synthetic staging test data only. Not investment research or factual evidence.',
    });
    requireValue(findingId, 'published test finding ID');

    const completedOriginal = await verifyTask(researcherA, originalTaskId);
    assert(
      completedOriginal.status === 'completed' &&
        completedOriginal.claimed_owner_id === null,
      'Publication must complete the original task and clear its claim.'
    );
    const publicFindings = await getRows(
      `/rest/v1/commons_research_findings?select=id,task_id,summary,limitations,ticker&task_id=eq.${originalTaskId}&id=eq.${findingId}`,
      null
    );
    assert(
      publicFindings.length === 1 &&
        publicFindings[0].ticker === 'RKLB' &&
        publicFindings[0].summary === summary &&
        publicFindings[0].limitations.includes('Synthetic staging test data only'),
      'Published synthetic finding was not visible with its test label and limitations.'
    );
    console.log('PASS: finding is publicly readable and the original task is completed.');

    const renewalArgs = {
      p_ticker: 'RKLB',
      p_category_key: categoryKey,
      p_metric_key: metricKey,
      p_request_id: renewalRequestId,
      p_source_task_id: originalTaskId,
    };
    const [firstRenewal, retryRenewal] = await Promise.all([
      rpc(researcherB, 'commons_create_or_renew_research', renewalArgs),
      rpc(researcherB, 'commons_create_or_renew_research', renewalArgs),
    ]);
    renewedTaskId = requireValue(firstRenewal?.id, 'renewed task ID');
    assert(
      renewedTaskId !== originalTaskId &&
        retryRenewal?.id === renewedTaskId &&
        firstRenewal?.status === 'open' &&
        retryRenewal?.status === 'open',
      'Concurrent renewal calls did not return the same new open task.'
    );
    console.log('PASS: Researcher B created one idempotent renewed assignment.');

    const renewalClaim = await rpc(researcherB, 'commons_claim_task', {
      p_task_id: renewedTaskId,
    });
    assert(
      renewalClaim?.id === renewedTaskId,
      'Researcher B claim returned a different renewed assignment.'
    );
    const claimedRenewal = await verifyTask(researcherB, renewedTaskId);
    assert(
      claimedRenewal.status === 'claimed' &&
        claimedRenewal.claimed_owner_id === researcherB.userId &&
        Date.parse(claimedRenewal.claimed_until) > Date.now() &&
        claimedRenewal.renewed_from_task_id === originalTaskId &&
        claimedRenewal.research_series_id === completedOriginal.research_series_id,
      'Researcher B must own the live renewed task linked to the original series and task.'
    );
    console.log('PASS: Researcher B claimed the renewed assignment.');

    const preservedOriginal = await verifyTask(researcherA, originalTaskId);
    const preservedFindings = await getRows(
      `/rest/v1/commons_research_findings?select=id,task_id,summary&task_id=eq.${originalTaskId}&id=eq.${findingId}`,
      null
    );
    const tickerTasks = await getRows(
      '/rest/v1/research_tasks?select=id,ticker,status,renewed_from_task_id&ticker=eq.RKLB&limit=10',
      null
    );
    assert(
      preservedOriginal.status === 'completed' &&
        preservedFindings.length === 1 &&
        preservedFindings[0].summary === summary,
      'Renewal changed or removed the original task or test finding.'
    );
    assert(
      tickerTasks.length === 2 &&
        tickerTasks.some((task) => task.id === originalTaskId) &&
        tickerTasks.some(
          (task) =>
            task.id === renewedTaskId &&
            task.renewed_from_task_id === originalTaskId
        ),
      'Expected exactly the original and linked renewed RKLB assignments.'
    );
    console.log('PASS: original assignment and finding history remain preserved.');
  } catch (error) {
    console.error(`TEST STOPPED: ${error.message}`);
    console.error(
      'If any RPC may have committed, preserve this run manifest and use only the reviewed staging cleanup after verifying every guard:'
    );
    console.error(JSON.stringify(manifest(), null, 2));
    throw error;
  }

  console.log('Cleanup manifest (IDs only; no credentials or session tokens):');
  console.log(JSON.stringify(manifest(), null, 2));
}

main()
  .catch((error) => {
    console.error(error.message);
    process.exitCode = 1;
  })
  .finally(async () => {
    let signOutSucceeded = true;
    for (const client of authClients) {
      try {
        await signOutLocal(client);
        console.log('PASS: Supabase Auth session signed out locally.');
      } catch (error) {
        signOutSucceeded = false;
        console.error(`WARNING: could not sign out an Auth session locally: ${error.message}`);
        process.exitCode = 1;
      }
    }
    if (process.exitCode === undefined && signOutSucceeded) {
      console.log('PASS: two authenticated users completed the staging integration flow.');
    }
  });
