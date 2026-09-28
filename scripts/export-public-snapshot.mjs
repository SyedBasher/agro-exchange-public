import fs from 'node:fs';
import path from 'node:path';
import { execFileSync } from 'node:child_process';

const root=process.cwd();
const out=path.resolve(root,process.argv[2]||'_public_release/agro-exchange');
const manifest=JSON.parse(fs.readFileSync(path.join(root,'public-release-manifest.json'),'utf8'));

function globToRegExp(glob){
  let out='^';
  for(let i=0;i<glob.length;i++){
    const c=glob[i];
    if(c==='*'){
      if(glob[i+1]==='*'){out+='.*';i++;}
      else out+='[^/]*';
    }else if(c==='?')out+='[^/]';
    else out+=c.replace(/[.+^$(){}|[\]\\]/g,'\\$&');
  }
  return new RegExp(out+'$');
}
const includeRx=manifest.public_include.map(globToRegExp);
const excludeRx=manifest.public_exclude.map(globToRegExp);
const matches=(file,list)=>list.some(rx=>rx.test(file));
const tracked=execFileSync('git',['ls-files','-z'],{cwd:root}).toString('utf8').split('\0').filter(Boolean);

fs.rmSync(out,{recursive:true,force:true});
fs.mkdirSync(out,{recursive:true});

function write(rel,data){
  const target=path.join(out,rel);
  fs.mkdirSync(path.dirname(target),{recursive:true});
  fs.writeFileSync(target,data);
}

for(const file of tracked){
  if(!matches(file,includeRx)||matches(file,excludeRx))continue;
  if(file==='backend/runtime-config.js')continue;
  const dest=manifest.rename[file]||file;
  write(dest,fs.readFileSync(path.join(root,file)));
}

const runtime=fs.readFileSync(path.join(root,'backend/runtime-config.js'),'utf8');
const buildVersion=runtime.match(/buildVersion\s*:\s*['"]([^'"]+)['"]/)?.[1];
if(!buildVersion)throw new Error('Cannot determine buildVersion from backend/runtime-config.js');

const publicRuntime=`// Public-source runtime configuration.
// Use a separate deployment-time configuration for any live environment.
// Publishable browser keys are not privileged, but the public CI snapshot is intentionally decoupled from the live pilot project.
window.AGRO_EXCHANGE_CONFIG = window.AGRO_EXCHANGE_CONFIG || {
  mode: 'supabase',
  environment: 'staging',
  buildVersion: '${buildVersion}',
  supabaseUrl: 'https://YOUR_PROJECT.supabase.co',
  anonKey: 'YOUR_SUPABASE_PUBLISHABLE_KEY',
  accessToken: ''
};
`;
write('backend/runtime-config.js',publicRuntime);

const provenance={
  generated_at:new Date().toISOString(),
  source_commit:execFileSync('git',['rev-parse','HEAD'],{cwd:root}).toString('utf8').trim(),
  source_repository:'private working repository',
  policy_version:manifest.version,
  note:'Clean source snapshot. No Git history or live data is transferred.'
};
write('PUBLIC_SNAPSHOT_PROVENANCE.json',JSON.stringify(provenance,null,2)+'\n');

console.log('Public snapshot generated at '+out);
console.log('Next: inspect the directory, run node scripts/static-smoke.mjs inside it, then push it as a fresh history to the separate public repository.');
