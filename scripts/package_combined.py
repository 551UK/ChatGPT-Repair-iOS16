#!/usr/bin/env python3
"""Create ONE rootless installer from two existing signed, user-supplied tweak DEBs.

This script preserves BOTH Mach-O dylib bytes and their substrate plists exactly.
It is a repackaging procedure, not a source-code restoration of opaque binaries.

Usage:
 python3 scripts/package_combined.py --repair path/to/v53.deb \\
    --compat path/to/ChatGBeFree-2.3.5.deb --out ChatGPTRepair_55.3_iphoneos-arm64.deb
"""
from __future__ import annotations
import argparse, hashlib, pathlib, shutil, subprocess, tempfile, plistlib

TARGET = 'var/jb/Library/MobileSubstrate/DynamicLibraries'

def dpkg_read(deb, field):
    return subprocess.check_output(['dpkg-deb','-f',str(deb),field],text=True).strip()

def digest(p):
    return hashlib.sha256(p.read_bytes()).hexdigest()

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--repair', required=True, type=pathlib.Path)
    ap.add_argument('--compat', required=True, type=pathlib.Path)
    ap.add_argument('--out', required=True, type=pathlib.Path)
    ap.add_argument('--version', default='55.3')
    args = ap.parse_args()
    rv=dpkg_read(args.repair,'Version')
    cv=dpkg_read(args.compat,'Version')
    if rv!='55.3':
        ap.error(f'Expected ChatGPTRepair 55.3 build input; got {rv}')
    if dpkg_read(args.repair,'Package')!='com.551uk.chatgptrepair':
        ap.error('Unexpected repair package identifier')
    if cv!='2.3.5' or dpkg_read(args.compat,'Package')!='com.liam.chatgbefree':
        ap.error('This builder requires the exact tested 2.3.5 compatibility package')
    for deb in (args.repair,args.compat):
        if dpkg_read(deb,'Architecture')!='iphoneos-arm64':
            ap.error('Expected rootless iphoneos-arm64 package')
    with tempfile.TemporaryDirectory() as td:
        tmp=pathlib.Path(td); repair=tmp/'repair'; compat=tmp/'compat'; result=tmp/'merged';meta=tmp/'control'
        for x in (repair,compat,result,meta):x.mkdir()
        subprocess.run(['dpkg-deb','-x',str(args.repair),str(repair)],check=True)
        subprocess.run(['dpkg-deb','-x',str(args.compat),str(compat)],check=True)
        srcs=((repair,'ChatGPTRepair'),(compat,'ChatGBeFree'))
        for extracted,stem in srcs:
            for ext in ('dylib','plist'):
                src=extracted/TARGET/(stem+'.'+ext)
                if not src.is_file():raise RuntimeError(f'Missing {src}')
                dst=result/TARGET/src.name;dst.parent.mkdir(parents=True,exist_ok=True)
                shutil.copy2(src,dst)
                if digest(src)!=digest(dst):raise RuntimeError('Payload changed: '+str(src))
            payload=(extracted/TARGET/(stem+'.plist')).read_bytes()
            if payload.startswith(b'bplist'):
                valid='com.openai.chat' in plistlib.loads(payload).get('Filter',{}).get('Bundles',[])
            else:
                valid=b'com.openai.chat' in payload
            if not valid:raise RuntimeError('Unexpected substrate target for '+stem)
        control=f'''Package: com.551uk.chatgptrepair
Name: ChatGPTRepair
Version: {args.version}
Architecture: iphoneos-arm64
Section: Tweaks
Priority: optional
Maintainer: 551UK
Author: 551UK
Depends: firmware (>= 16.0), mobilesubstrate
Conflicts: com.liam.chatgbefree
Replaces: com.liam.chatgbefree
Description: Restores missing functionality to ChatGPT.
'''
        (meta/'control').write_text(control)
        lic=result/'var/jb/usr/share/doc/chatgptrepair';lic.mkdir(parents=True)
        (lic/'COMPONENTS').write_text('One DEB contains two unmodified compiled components.\n' +
          'ChatGPTRepair: user v53 source in project; compatibility: user-provided 2.3.5 prebuilt dylib.\n' +
          'The full editable 2.3.5 source was not available: do not claim that it can be rebuilt from source.\n' +
          'The combined package title is 551UK ChatGPTRepair. Original third-party rights remain unaffected.\n' +
          'See the GNU GPLv3 licence and original source attribution where applicable.\n')
        (lic/'COMPONENT-SHA256').write_text('\n'.join(f'{digest(result/TARGET/(stem+".dylib"))}  {stem}.dylib' for _,stem in srcs)+'\n')
        forbidden = [p.name for p in result.iterdir() if p.name != 'var']
        if forbidden:
            raise RuntimeError('Non-rootless payload paths: ' + repr(forbidden))
        shutil.copytree(meta,result/'DEBIAN')
        args.out.parent.mkdir(parents=True,exist_ok=True)
        subprocess.run(['dpkg-deb','--build','--root-owner-group',str(result),str(args.out)],check=True)
        print('Created:',args.out,'size:',args.out.stat().st_size)
        print('Repair',rv,'compatibility',cv)
        for _,stem in srcs:
            print(stem,'SHA256',digest(result/TARGET/(stem+'.dylib')))

if __name__=='__main__':main()
