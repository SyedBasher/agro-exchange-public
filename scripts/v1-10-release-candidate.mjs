import fs from 'node:fs';

const read=p=>fs.readFileSync(p,'utf8');
const must=(ok,msg)=>{if(!ok){console.error('FAIL:',msg);process.exitCode=1;}else console.log('PASS:',msg);};

const replay=read('docs/V1_10_DATABASE_REPLAY_ORDER.md');
const setup=read('docs/BACKEND_SETUP.md');
const architecture=read('docs/ARCHITECTURE.md');
const app=read('app.js');
const hardening=read('backend/v1-8-hardening.js');
const identityStage=read('database/pilot_identity_stage.sql');
const identityOnboarding=read('docs/V1_10_IDENTITY_ONBOARDING.md');

const ordered=[
  'database/lifecycle_authorization_hardening_v1_10.sql',
  'database/dispute_party_continuity_v1_10.sql',
  'database/cancellation_inventory_integrity_v1_10.sql',
  'database/quantity_reconciliation_integrity_v1_10.sql',
  'database/monetary_reconciliation_integrity_v1_10.sql',
  'database/trade_state_machine_integrity_v1_10.sql',
  'database/dispute_entry_continuity_v1_10.sql'
];

let last=-1;
for(const p of ordered){
  must(fs.existsSync(p),'Required v1.10 database file exists: '+p);
  const at=replay.indexOf(p);
  must(at>last,'Replay order contains '+p+' after prior hardening layer');
  last=at;
}

must(setup.includes('docs/V1_10_DATABASE_REPLAY_ORDER.md'),'Backend setup points to authoritative v1.10 replay order');
must(setup.includes('Do not reconstruct the database by running only'),'Backend setup warns against obsolete prototype-only replay');
must(architecture.startsWith('# Agro-Exchange architecture v1.10'),'Architecture is versioned for v1.10 release candidate');
must(hardening.includes('v1.10 controlled staging'),'Visible staging label reports v1.10');

const workflowModules=[
  'backend/buyer-workflow.js',
  'backend/trade-workflow.js',
  'backend/qc-workflow.js',
  'backend/logistics-workflow.js',
  'backend/settlement-workflow.js',
  'backend/dispute-workflow.js',
  'backend/admin-workflow.js',
  'backend/v1-9-operations.js'
];
for(const p of workflowModules){
  must(app.includes("'"+p+"'"),'Production bootstrap includes workflow module: '+p);
}
must(!app.includes('backend/demo-settlement-seed.js'),'Production bootstrap excludes legacy demo settlement seeding');

const stateMachine=read('database/trade_state_machine_integrity_v1_10.sql');
must(stateMachine.includes('trade_status_transition_guard_v1_10'),'Central state-machine trigger is part of release source');
const health=read('database/trade_state_machine_health.sql');
must(health.includes('settled_payment_total_mismatch'),'Release source includes state-machine health diagnostics');
must(identityStage.includes('WAITING_FOR_SECOND_AUTH_IDENTITY'),'Identity-stage diagnostic recognizes the one-user starting state');
must(identityStage.includes('FIRST_ADMIN_CANDIDATE_READY'),'Identity-stage diagnostic recognizes first-admin readiness');
must(identityStage.includes('FULL_ROLE_MATRIX_READY'),'Identity-stage diagnostic recognizes full role readiness');
must(!/email|phone|token|magic[_ -]?link/i.test(identityStage.replace(/^--.*$/gm,'')),'Identity-stage SQL does not expose participant contact/auth secrets');
must(identityOnboarding.includes('v1.9 staging frontend'),'Identity onboarding documents the v1.9 identity-only boundary');
must(identityOnboarding.includes('must wait until the **v1.10 release-candidate frontend** is deployed'),'Identity onboarding blocks transaction testing on the old frontend');

if(process.exitCode)process.exit(process.exitCode);
console.log('v1.10 release-candidate repository gates passed');
