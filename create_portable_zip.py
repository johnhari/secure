import os
import shutil
import zipfile

release_dir = r"c:\Users\PUTIN\Desktop\ADVANCEORDERFLOW\orderflow\build\windows\x64\runner\Release"
sys32_dir = r"C:\Windows\System32"

vc_dlls = [
    'msvcp140.dll',
    'msvcp140_1.dll',
    'msvcp140_2.dll',
    'msvcp140_codecvt_ids.dll',
    'vcruntime140.dll',
    'vcruntime140_1.dll',
    'vccorlib140.dll',
    'concrt140.dll'
]

# Copy MSVC runtime DLLs
for dll in vc_dlls:
    src_dll = os.path.join(sys32_dir, dll)
    dst_dll = os.path.join(release_dir, dll)
    if os.path.exists(src_dll):
        shutil.copy2(src_dll, dst_dll)

included_files = []
for root, dirs, files in os.walk(release_dir):
    for file in files:
        if file.endswith(('.lib', '.exp', '.pdb', '.obj', '.iobj', '.ipdb')):
            continue
        full_path = os.path.join(root, file)
        rel_path = os.path.relpath(full_path, release_dir)
        included_files.append((full_path, rel_path))

# 1. Orderflow_Portable.zip (with root folder Orderflow_Portable)
portable_zip1 = r"c:\Users\PUTIN\Desktop\ADVANCEORDERFLOW\Orderflow_Portable.zip"
print(f"Creating {portable_zip1}...")
with zipfile.ZipFile(portable_zip1, 'w', zipfile.ZIP_DEFLATED) as z:
    for full_path, rel_path in included_files:
        z.write(full_path, arcname=os.path.join("Orderflow_Portable", rel_path))
print(f"Created: {os.path.getsize(portable_zip1)} bytes")

# 2. Orderflow_Portable_Direct.zip (files at root of zip)
portable_zip2 = r"c:\Users\PUTIN\Desktop\ADVANCEORDERFLOW\Orderflow_Portable_Direct.zip"
print(f"Creating {portable_zip2}...")
with zipfile.ZipFile(portable_zip2, 'w', zipfile.ZIP_DEFLATED) as z:
    for full_path, rel_path in included_files:
        z.write(full_path, arcname=rel_path)
print(f"Created: {os.path.getsize(portable_zip2)} bytes")

print("Portable ZIP archives created successfully!")
