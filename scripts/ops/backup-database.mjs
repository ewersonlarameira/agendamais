// Requires local PostgreSQL tools and a caller-provided private connection URL.
// Secrets are passed only via inherited process environment, never command arguments/logs.
import {spawn} from 'node:child_process';
import {mkdtemp,mkdir,rm,readFile,writeFile} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join,resolve,basename} from 'node:path';
import {createHash} from 'node:crypto';
import {encryptDump,decryptDump,readBackupKey} from './backup-crypto.mjs';
function connectionEnv(raw){let u;try{u=new URL(raw)}catch{throw Error('Defina BACKUP_DATABASE_URL no ambiente seguro.')}if(!['postgres:','postgresql:'].includes(u.protocol)||!u.hostname||!u.username||!u.password)throw Error('Conexão PostgreSQL incompleta.');return {...process.env,PGHOST:u.hostname,PGPORT:u.port||'5432',PGUSER:decodeURIComponent(u.username),PGPASSWORD:decodeURIComponent(u.password),PGDATABASE:decodeURIComponent(u.pathname.slice(1)),PGSSLMODE:'verify-full',PGSSLROOTCERT:process.env.BACKUP_CA_FILE||'system'};}
async function run(command,args,env){await new Promise((resolve,reject)=>{const p=spawn(command,args,{env,stdio:['ignore','ignore','pipe']});p.stderr.resume();p.on('error',()=>reject(Error(command+' indisponível. Instale ferramentas PostgreSQL 18 compatíveis.')));p.on('exit',code=>code===0?resolve():reject(Error(command+' falhou; confira a conexão e a versão das ferramentas. Saída privada não foi registrada.')));});}
const key=readBackupKey(process.env.BACKUP_KEY_BASE64);const temp=await mkdtemp(join(tmpdir(),'agenda-backup-'));
try{
 const [mode,arg]=process.argv.slice(2);
 if(mode==='create'){
  const env=connectionEnv(process.env.BACKUP_DATABASE_URL);const out=resolve(arg||'private-backups');await mkdir(out,{recursive:true,mode:0o700});
  const dump=join(temp,'database.dump');await run('pg_dump',['--format=custom','--no-owner','--no-privileges','--file',dump],env);
  const stamp=new Date().toISOString().replace(/[:.]/g,'-');const encrypted=join(out,'agenda-'+stamp+'.dump.enc');await encryptDump(dump,encrypted,key);
  const hash=createHash('sha256').update(await readFile(encrypted)).digest('hex');await writeFile(encrypted+'.sha256',hash+'  '+basename(encrypted)+'\n',{mode:0o600,flag:'wx'});
  console.log('Backup criptografado criado. Copie o arquivo e seu checksum para armazenamento externo privado; preserve a chave separadamente.');
 }else if(mode==='verify'){
  if(!arg)throw Error('Informe o arquivo criptografado.');const encrypted=resolve(arg);const expected=(await readFile(encrypted+'.sha256','utf8')).trim().split(/\s+/)[0];const actual=createHash('sha256').update(await readFile(encrypted)).digest('hex');if(expected!==actual)throw Error('Checksum do backup não confere.');
  const dump=join(temp,'verified.dump');await decryptDump(encrypted,dump,key);await run('pg_restore',['--list',dump],process.env);console.log('PASS: checksum, AES-GCM e catálogo pg_restore. Restauração em outro banco ainda precisa ser testada.');
 }else throw Error('Uso: node scripts/ops/backup-database.mjs create [diretório privado] | verify arquivo.dump.enc');
}finally{await rm(temp,{recursive:true,force:true});}
