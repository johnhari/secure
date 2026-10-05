import os
import sys
import shutil
import zipfile
from datetime import datetime

def create_website_full_backup():
    base_dir = r"c:\Users\PUTIN\Desktop\ADVANCEORDERFLOW"
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    
    # Define primary zip names
    zip_filename_timestamped = f"BIG_SHOT_WEBSITE_FULL_BACKUP_{timestamp}.zip"
    zip_path_workspace = os.path.join(base_dir, zip_filename_timestamped)
    zip_path_updated = os.path.join(base_dir, "BIG_SHOT_WEBSITE_BACKUP_UPDATED.zip")
    
    desktop_dir = r"C:\Users\PUTIN\Desktop"
    zip_path_desktop = os.path.join(desktop_dir, zip_filename_timestamped)
    
    h_backup_dir = r"H:\My Backups"
    zip_path_h = os.path.join(h_backup_dir, zip_filename_timestamped) if os.path.exists(h_backup_dir) else None

    # Exclusions
    EXCLUDE_DIRS = {'node_modules', '.git', '__pycache__', '.dart_tool', '.gradle', 'build', '.idea', '.vscode'}
    EXCLUDE_EXTS = {'.pyc', '.tmp', '.log'}

    # Target folders and files
    targets = [
        ('marketing', 'marketing'),
        ('functions', 'functions'),
        ('backend', 'backend'),
        (r'orderflow\web', 'orderflow/web'),
        ('firebase.json', 'firebase.json'),
        ('.firebaserc', '.firebaserc'),
        ('firestore.rules', 'firestore.rules'),
        ('firestore.indexes.json', 'firestore.indexes.json'),
        ('database.rules.json', 'database.rules.json'),
        ('setup-firebase.bat', 'setup-firebase.bat'),
        ('FIREBASE_SETUP.md', 'FIREBASE_SETUP.md'),
        ('tv_logos.json', 'tv_logos.json'),
    ]

    files_to_zip = []
    total_uncompressed_bytes = 0

    print("=" * 60)
    print("STARTING FULL WEBSITE BACKUP PROCESS")
    print(f"Timestamp: {timestamp}")
    print("=" * 60)

    for target_path, arc_prefix in targets:
        full_target = os.path.join(base_dir, target_path)
        if not os.path.exists(full_target):
            print(f"[WARN] Target path not found: {full_target}")
            continue

        if os.path.isfile(full_target):
            file_size = os.path.getsize(full_target)
            files_to_zip.append((full_target, arc_prefix))
            total_uncompressed_bytes += file_size
        elif os.path.isdir(full_target):
            for root, dirs, files in os.walk(full_target):
                dirs[:] = [d for d in dirs if d not in EXCLUDE_DIRS]
                for f in files:
                    ext = os.path.splitext(f)[1].lower()
                    if ext in EXCLUDE_EXTS:
                        continue
                    file_full = os.path.join(root, f)
                    rel_to_target = os.path.relpath(file_full, full_target)
                    arc_name = os.path.normpath(os.path.join(arc_prefix, rel_to_target)).replace('\\', '/')
                    file_size = os.path.getsize(file_full)
                    files_to_zip.append((file_full, arc_name))
                    total_uncompressed_bytes += file_size

    print(f"\nDiscovered {len(files_to_zip)} website files.")
    print(f"Total uncompressed size: {total_uncompressed_bytes / (1024*1024):.2f} MB")

    # Create the zip archive in workspace
    print(f"\nCompressing into archive: {zip_path_workspace} ...")
    with zipfile.ZipFile(zip_path_workspace, 'w', compression=zipfile.ZIP_DEFLATED, compresslevel=6) as z:
        for file_full, arc_name in files_to_zip:
            z.write(file_full, arc_name)

    compressed_size = os.path.getsize(zip_path_workspace)
    print(f"Successfully created: {zip_path_workspace}")
    print(f"Archive compressed size: {compressed_size / (1024*1024):.2f} MB")

    # Integrity verification
    print("\nVerifying archive integrity (CRC32 test)...")
    with zipfile.ZipFile(zip_path_workspace, 'r') as z:
        bad_file = z.testzip()
        if bad_file:
            raise Exception(f"Corrupted file detected in archive: {bad_file}")
        print("Archive verification PASSED! All 100% of files verified OK.")

    # Update BIG_SHOT_WEBSITE_BACKUP_UPDATED.zip in workspace root
    print(f"\nUpdating {zip_path_updated} ...")
    shutil.copy2(zip_path_workspace, zip_path_updated)
    print("Updated BIG_SHOT_WEBSITE_BACKUP_UPDATED.zip.")

    # Copy to Desktop
    print(f"\nCopying to Desktop: {zip_path_desktop} ...")
    try:
        shutil.copy2(zip_path_workspace, zip_path_desktop)
        print("Desktop copy completed.")
    except Exception as e:
        print(f"[WARN] Failed to copy to Desktop: {e}")

    # Copy to H: backup drive if available
    if zip_path_h:
        print(f"\nCopying to external drive: {zip_path_h} ...")
        try:
            shutil.copy2(zip_path_workspace, zip_path_h)
            print("External drive backup copy completed.")
        except Exception as e:
            print(f"[WARN] Failed to copy to H: drive: {e}")

    print("\n" + "=" * 60)
    print("BACKUP SUMMARY:")
    print(f"- Total Files Backed Up: {len(files_to_zip)}")
    print(f"- Uncompressed Size:     {total_uncompressed_bytes / (1024*1024):.2f} MB")
    print(f"- Compressed ZIP Size:   {compressed_size / (1024*1024):.2f} MB")
    print(f"- Saved Locations:")
    print(f"  1. {zip_path_workspace}")
    print(f"  2. {zip_path_updated}")
    print(f"  3. {zip_path_desktop}")
    if zip_path_h and os.path.exists(zip_path_h):
        print(f"  4. {zip_path_h}")
    print("=" * 60)

if __name__ == "__main__":
    create_website_full_backup()
