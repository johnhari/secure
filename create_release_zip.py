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

print("Copying VC++ Redistributable runtime DLLs into Release build folder...")
for dll in vc_dlls:
    src_dll = os.path.join(sys32_dir, dll)
    dst_dll = os.path.join(release_dir, dll)
    if os.path.exists(src_dll):
        shutil.copy2(src_dll, dst_dll)
        print(f"Copied {dll} to release folder.")

zip_paths = [
    r"c:\Users\PUTIN\Desktop\ADVANCEORDERFLOW\Orderflow_Windows_Release.zip",
    r"c:\Users\PUTIN\Desktop\ADVANCEORDERFLOW\Orderflow_Windows_Release_Latest.zip",
    r"c:\Users\PUTIN\Desktop\ADVANCEORDERFLOW\Orderflow_Windows.zip",
    r"c:\Users\PUTIN\Desktop\ADVANCEORDERFLOW\orderflow\Orderflow_Windows_Release.zip"
]

print("\nScanning release directory for zip packaging...")
included_files = []
for root, dirs, files in os.walk(release_dir):
    for file in files:
        if file.endswith(('.lib', '.exp', '.pdb', '.obj', '.iobj', '.ipdb')):
            continue
        full_path = os.path.join(root, file)
        rel_path = os.path.relpath(full_path, release_dir)
        included_files.append((full_path, rel_path))

for zip_path in zip_paths:
    print(f"Creating zip archive at: {zip_path}")
    with zipfile.ZipFile(zip_path, 'w', zipfile.ZIP_DEFLATED) as z:
        for full_path, rel_path in included_files:
            # Add files to the zip under Orderflow_Windows folder
            z.write(full_path, arcname=os.path.join("Orderflow_Windows", rel_path))
    print(f"Zip created successfully: {os.path.getsize(zip_path)} bytes")

print("\nAll ZIP archives created with MSVC Runtime DLLs included!")
