import os
import zipfile

def zip_folder(folder_path, output_path):
    print(f"Creating ZIP archive: {output_path}")
    with zipfile.ZipFile(output_path, 'w', zipfile.ZIP_DEFLATED) as zipf:
        for root, dirs, files in os.walk(folder_path):
            # Skip heavy build and dart_tool directories
            dirs[:] = [d for d in dirs if d not in ['.dart_tool', 'build', '.git', '.gradle', 'node_modules']]
            for file in files:
                file_path = os.path.join(root, file)
                arcname = os.path.relpath(file_path, folder_path)
                zipf.write(file_path, arcname)
    print("Archive created successfully.")

if __name__ == "__main__":
    src_dir = r"c:\Users\PUTIN\Desktop\ADVANCEORDERFLOW\orderflow"
    dest_zip = r"c:\Users\PUTIN\Desktop\ADVANCEORDERFLOW\Orderflow_Project_Updated.zip"
    zip_folder(src_dir, dest_zip)
