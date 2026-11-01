"""Assemble a Windows x64 test delivery from a verified Web build and runtimes.
No user's database, browser profile, SDK path or credentials are copied.
Usage: python tools/BuildPortable.py --output <new-folder> --node <node.exe>
       --postgres <pgsql-folder> --postgres-zip <original-zip> --pnpm <pnpm.mjs>
       --vc-redist <official-vc_redist.x64.exe>
"""
import argparse, hashlib, json, os, pathlib, shutil, subprocess, urllib.request, zipfile

p = argparse.ArgumentParser()
for name in ('output','node','postgres','postgres-zip','pnpm','vc-redist'):
    p.add_argument('--'+name, required=True)
a=p.parse_args()
src=pathlib.Path(__file__).resolve().parents[1]
out=pathlib.Path(a.output).resolve()
if out.exists(): raise SystemExit('Output must be a new directory, to protect existing data.')
out.mkdir(parents=True)
(out/'source').mkdir()
files=subprocess.check_output(['git','-c','core.quotepath=false','ls-files','--cached','--others','--exclude-standard'],cwd=src,text=True,encoding='utf-8').splitlines()
for rel in files:
    file=src/rel
    if any(part in ('node_modules','build','.git','data','logs') for part in pathlib.PurePosixPath(rel).parts) or file.name.startswith('.env') or file.suffix.lower() in ('.sqlite','.db') or file.name == 'local.properties': continue
    if rel.startswith('.vscode/') or file.suffix.lower() in ('.md','.docx','.pptx','.pdf'): continue
    if not file.is_file(): continue
    target=out/'source'/rel
    target.parent.mkdir(parents=True,exist_ok=True)
    shutil.copy2(file,target)
for rel in ('android/gradlew','android/gradlew.bat','android/gradle/wrapper/gradle-wrapper.jar'):
    shutil.copy2(src/rel,out/'source'/rel)
(out/'runtime/node').mkdir(parents=True)
shutil.copy2(a.node,out/'runtime/node/node.exe')
shutil.copytree(a.postgres,out/'runtime/postgres')
with zipfile.ZipFile(a.postgres_zip) as z:
    for name in ('server_license.txt','commandlinetools_3rd_party_licenses.txt'):
        (out/'runtime/postgres'/name).write_bytes(z.read('pgsql/'+name))
urllib.request.urlretrieve('https://raw.githubusercontent.com/nodejs/node/v24.19.0/LICENSE',out/'runtime/node/LICENSE')
env={**os.environ,'PATH':str(pathlib.Path(a.node).parent)+os.pathsep+os.environ.get('PATH',''),'CI':'true','pnpm_config_pm_on_fail':'ignore'}
for service in ('auth-server','server','chat-server'):
    subprocess.run([a.node,a.pnpm,'install','--frozen-lockfile','--ignore-scripts','--node-linker=hoisted'],cwd=out/'source'/service,env=env,check=True)
shutil.copytree(src/'build/web',out/'web')
(out/'launcher').mkdir()
for name in ('portable.mjs','seed.mjs','short-path.ps1'):
    shutil.copy2(src/'tools/portable'/name,out/'launcher'/name)
for name in ('Start.bat','Stop.bat','Check.bat','Install-Windows-Runtime.bat','QUICKSTART.txt'):
    if (src/'tools/portable'/name).exists():shutil.copy2(src/'tools/portable'/name,out/name)
(out/'prerequisites').mkdir()
shutil.copy2(a.vc_redist,out/'prerequisites/vc_redist.x64.exe')
# The final archive is produced only after smoke tests on a separate copy.
manifest={
 'edition':'Global Village Portable 2026-10-15','platform':'Windows x64',
 'node':'24.19.0','postgresql':'16.15','portableWeb':True,
 'incomingArchiveSha256':'4546d406b593c34cef25e811ea4e4e74f3115f43c32524339f20b5461b567e01',
 'nodeSource':'https://nodejs.org/','postgresSource':'https://www.postgresql.org/download/windows/',
 'dataIncluded':False,
}
(out/'package.json').write_text(json.dumps(manifest,indent=2),encoding='utf-8')
print('Assembled',out)
