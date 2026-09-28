import fs from 'node:fs';
import path from 'node:path';
import { execFileSync } from 'node:child_process';

const root=process.cwd();
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

const selected=tracked.filter(f=>matches(f,includeRx)&&!matches(f,excludeRx));
const snapshotReadmeOnly=tracked.includes('README.md')&&!tracked.includes('README_PUBLIC.md');
if(snapshotReadmeOnly)selected.push('README.md');
const errors=[];const notes=[];

for(const f of selected){
  const normalized='/'+f.toLowerCase().replaceAll('\\','/')+'/';
  for(const frag of manifest.never_publish_path_fragments){
    if(normalized.includes(frag.toLowerCase()))errors.push('Forbidden public path: '+f);
  }
}

for(const f of manifest.public_exclude){
  if(selected.includes(f))errors.push('Explicitly private file selected for export: '+f);
}

const textExt=new Set(['.js','.mjs','.cjs','.css','.html','.md','.json','.yml','.yaml','.toml','.txt','.sql','.example','.webmanifest']);
const secretChecks=[
  [/sb_secret_[A-Za-z0-9_-]+/i,'Supabase secret key'],
  [/SUPABASE_SERVICE_ROLE_KEY\s*[:=]\s*["']?[^\s"'<>]+/i,'Supabase service-role credential'],
  [/TWILIO_AUTH_TOKEN\s*[:=]\s*["']?[^\s"'<>]+/i,'Twilio Auth Token'],
  [/DATABASE_URL\s*[:=]\s*["']?postgres(?:ql)?:\/\/[^:\s]+:[^@\s]+@/i,'database URL containing password'],
  [/-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----/,'private key material'],
  [/\b[A-Z0-9._%+-]+@(gmail|outlook|hotmail|yahoo|icloud)\.(com|net|org)\b/i,'personal free-mail address'],
  [/\+8801\d{9}\b/,'real-looking Bangladesh mobile number']
];

for(const f of selected){
  const ext=path.extname(f).toLowerCase();
  if(!textExt.has(ext)&&!['.env.example','.gitignore'].includes(f))continue;
  let content='';
  try{content=fs.readFileSync(path.join(root,f),'utf8');}catch{continue;}
  for(const [rx,label] of secretChecks){
    if(rx.test(content))errors.push(label+' found in public input: '+f);
  }
}

const rawRuntime=fs.readFileSync(path.join(root,'backend/runtime-config.js'),'utf8');
if(/sb_secret_/i.test(rawRuntime)||/service[_-]?role\s*[:=]\s*['"][^'"]+/i.test(rawRuntime)){
  errors.push('Private runtime config contains a privileged credential; stop before export.');
}
if(!rawRuntime.match(/buildVersion\s*:\s*['"]([^'"]+)['"]/)){
  errors.push('Cannot determine buildVersion for sanitized public runtime config.');
}

const seed=fs.readFileSync(path.join(root,'database/seed.sql'),'utf8');
if(!/simulated development records only/i.test(seed)){
  errors.push('database/seed.sql is public only if it remains explicitly labelled simulated.');
}

const hasPublicReadmeSource=tracked.includes('README_PUBLIC.md');
const hasSnapshotReadme=tracked.includes('README.md')&&!hasPublicReadmeSource;
if(hasPublicReadmeSource&&!selected.includes('README_PUBLIC.md'))errors.push('Public README source is missing from release selection.');
if(hasSnapshotReadme&&!selected.includes('README.md'))errors.push('Clean public snapshot README is missing from release selection.');
if(hasPublicReadmeSource&&selected.includes('README.md'))errors.push('Private development README must not be exported directly from the private source repository.');
if(selected.includes('backend/runtime-config.js'))errors.push('Live runtime-config.js must be generated/sanitized, not copied directly.');

if(errors.length){
  console.error('\nAgro-Exchange public release audit FAILED\n');
  for(const e of [...new Set(errors)])console.error(' - '+e);
  process.exit(1);
}

notes.push('Tracked files inspected: '+tracked.length);
notes.push('Files selected for clean public snapshot: '+selected.length);
notes.push('Private operational docs excluded: '+manifest.public_exclude.length);
notes.push('Live runtime config is excluded and replaced by a sanitized generated file');
notes.push('No forbidden secret/PII pattern was found in selected public inputs');

console.log('Agro-Exchange public release audit PASSED');
for(const n of notes)console.log(' - '+n);
