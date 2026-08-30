import os
import zipfile
import datetime

workspace_dir = r"C:\Users\PUTIN\Desktop\ADVANCEORDERFLOW"
# Get the current date and time for the filename
timestamp = datetime.datetime.now().strftime("%Y%m%d_%H%M%S")
output_zip = f"C:\\Users\\PUTIN\\Desktop\\ADVANCEORDERFLOW_backup_{timestamp}.zip"

# Exclusion rules
exclude_dirs = {
    ".git", ".gradle", ".idea", ".vscode", "node_modules", "build", ".dart_tool", ".firebase"
}

exclude_files = {
    "app-release.apk",
}

def should_exclude(root, name, is_dir=False):
    # Check directory exclusions
    parts = os.path.normpath(root).split(os.sep)
    for part in parts:
        if part in exclude_dirs:
            return True
            
    if is_dir:
        if name in exclude_dirs:
            return True
    else:
        # File exclusions
        if name in exclude_files:
            return True
        if name.startswith("bugreport-") and name.endswith(".zip"):
            return True
        # Exclude JVM crash logs and replay logs
        if name.startswith("hs_err_pid") or name.startswith("replay_pid"):
            return True
        # Exclude temporary screenshots in root or orderflow root (but keep assets!)
        if name.endswith(".png") or name.endswith(".jpg"):
            if "assets" not in parts:
                return True
    return False

print(f"Starting backup of: {workspace_dir}")
print(f"Target archive: {output_zip}\n")

excluded_files_list = []
included_count = 0

with zipfile.ZipFile(output_zip, 'w', zipfile.ZIP_DEFLATED) as zipf:
    for root, dirs, files in os.walk(workspace_dir):
        # Prune excluded directories from search
        dirs[:] = [d for d in dirs if not should_exclude(root, d, is_dir=True)]
        
        for file in files:
            file_path = os.path.join(root, file)
            if should_exclude(root, file, is_dir=False):
                excluded_files_list.append(os.path.relpath(file_path, workspace_dir))
                continue
                
            # Calculate archive path (relative to workspace)
            arcname = os.path.relpath(file_path, workspace_dir)
            zipf.write(file_path, arcname)
            included_count += 1

size_mb = os.path.getsize(output_zip) / (1024 * 1024)
print(f"Backup complete!")
print(f"Included files: {included_count}")
print(f"Excluded files: {len(excluded_files_list)}")
print(f"Archive size: {size_mb:.2f} MB")
print(f"Saved to: {output_zip}")
