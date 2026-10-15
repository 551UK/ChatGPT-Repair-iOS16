#!/usr/bin/env python3
"""Local cross-build: pip install ziglang==0.13.0; provide iOS SDK, ldid, and LLVM ld64.lld.
Usage: python scripts/build_local.py /path/iPhoneOS16.5.sdk /path/ldid /path/ld64.lld
Theos Makefile remains available for standard macOS/Theos builds.
"""
import pathlib,sys,subprocess,shutil
root=pathlib.Path(__file__).resolve().parents[1]
sdk=pathlib.Path(sys.argv[1]).resolve();ldid=str(pathlib.Path(sys.argv[2]).resolve())
linker=str(pathlib.Path(sys.argv[3]).absolute())
build=root/'build';build.mkdir(exist_ok=True)
common=[sys.executable,'-m','ziglang','cc','-target','aarch64-ios.16.0','-isysroot',str(sdk),'-isystem',str(sdk/'usr/include'),'-F'+str(sdk/'System/Library/Frameworks'),'-fobjc-arc','-fblocks','-Wno-deprecated-declarations','-Wno-nullability-completeness','-O2','-fno-lto']
files=next(x for x in (root/'Makefile').read_text().splitlines() if x.startswith('ChatGPTRepair_FILES')).split('=',1)[1].split()
objects=[]
for f in files:
 out=build/(pathlib.Path(f).stem+'.o')
 subprocess.run(common+['-c',str(root/f),'-o',str(out)],check=True)
 assert out.stat().st_size>0, 'Compiler produced an empty object: '+f
 objects.append(str(out))
dylib=build/'ChatGPTRepair.dylib'
# Use LLVM's Mach-O linker, not Zig 0.13's experimental Mach-O linker.
subprocess.run([linker,'-dylib','-arch','arm64','-platform_version','ios','16.0','16.5','-syslibroot',str(sdk),'-L'+str(sdk/'usr/lib'),'-F'+str(sdk/'System/Library/Frameworks'),'-framework','Foundation','-framework','UIKit','-framework','CoreGraphics','-lobjc','-lSystem','-headerpad','0x1000','-install_name','/var/jb/Library/MobileSubstrate/DynamicLibraries/ChatGPTRepair.dylib',*objects,'-o',str(dylib)],check=True)
subprocess.run([ldid,'-S',str(dylib)],check=True)
subprocess.run([sys.executable,str(root/'tests/check_macho_load.py'),str(dylib)],check=True)
subprocess.run([sys.executable,str(root/'tests/check_arm64_bridge.py'),str(dylib)],check=True)
print(dylib)
