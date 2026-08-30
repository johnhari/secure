import os
import glob

pub_cache = os.path.expandvars(r'%USERPROFILE%\.pub-cache')
if not os.path.exists(pub_cache):
    pub_cache = os.path.expandvars(r'%LOCALAPPDATA%\Pub\Cache')

print(f"Pub cache directory: {pub_cache}")

# Find syncfusion_flutter_charts package folders
search_pattern = os.path.join(pub_cache, '**', 'syncfusion_flutter_charts-*')
folders = glob.glob(search_pattern, recursive=True)
print(f"Found packages: {folders}")

for folder in folders:
    # Look for zoom_pan_behavior.dart or similar
    dart_files = glob.glob(os.path.join(folder, '**', '*zoom*'), recursive=True)
    if dart_files:
        print(f"Found zoom files in {folder}: {dart_files[:5]}")
        # Print contents of the main zoom pan behavior file
        for df in dart_files:
            if df.endswith('zoom_pan_behavior.dart') or df.endswith('zoompan_behavior.dart'):
                print(f"Inspecting {df}")
                with open(df, 'r', encoding='utf-8', errors='ignore') as f:
                    content = f.read()
                    # Find method declarations
                    for line in content.split('\n'):
                        if 'void ' in line or 'class ' in line or ' ZoomPanBehavior' in line:
                            if any(term in line for term in ['class ', 'zoom', 'pan', 'reset', 'scroll']):
                                print("  ", line.strip())
