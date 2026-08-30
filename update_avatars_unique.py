import os
import shutil
import re
import glob

brain_dir = r"C:\Users\PUTIN\.gemini\antigravity-ide\brain\81ec1ca3-ebb8-4407-92bb-c71aa7674832"
assets_dir = r"c:\Users\PUTIN\Desktop\ADVANCEORDERFLOW\marketing\assets"
html_path = r"c:\Users\PUTIN\Desktop\ADVANCEORDERFLOW\marketing\index.html"

# Step 1: Find the latest generated images
def find_latest_image(prefix):
    files = glob.glob(os.path.join(brain_dir, f"{prefix}_*.png"))
    if not files:
        return None
    return sorted(files)[-1] # get latest

images_to_copy = [
    ("avatar_trading_2", "avatar_trading_2.png"),
    ("avatar_pet_2", "avatar_pet_2.png"),
    ("avatar_indian_man_2", "avatar_indian_man_2.png"),
    ("avatar_indian_woman_2", "avatar_indian_woman_2.png"),
    ("avatar_god_3", "avatar_god_3.png"),
    ("avatar_pet_3", "avatar_pet_3.png")
]

for prefix, dest_name in images_to_copy:
    src_file = find_latest_image(prefix)
    if src_file:
        shutil.copy(src_file, os.path.join(assets_dir, dest_name))

# Step 2: Update HTML with 12 UNIQUE avatars
with open(html_path, 'r', encoding='utf-8') as f:
    content = f.read()

unique_avatars = [
    "assets/murugan_avatar.png",         # 1. Karthik
    "assets/avatar_trading.png",         # 2. Surya
    "assets/avatar_indian_man.png",      # 3. Vignesh
    "assets/avatar_indian_woman.png",    # 4. Anitha
    "assets/avatar_pet.png",             # 5. Dinesh (Dog)
    "assets/shiva_avatar.png",           # 6. Prakash
    "assets/avatar_indian_woman_2.png",  # 7. Meena
    "assets/avatar_trading_2.png",       # 8. Sathish (Bear)
    "assets/avatar_indian_man_2.png",    # 9. Ramesh
    "assets/avatar_god_3.png",           # 10. Siva (Ganesha)
    "assets/avatar_pet_2.png",           # 11. Kamala (Cat)
    "assets/avatar_pet_3.png"            # 12. Arun (Bunny)
]

avatar_index = 0
def replace_review_avatar(match):
    global avatar_index
    full_img_tag = match.group(0)
    src = match.group(1)
    
    if avatar_index < len(unique_avatars):
        new_src = unique_avatars[avatar_index]
        avatar_index += 1
        return full_img_tag.replace(src, new_src)
    return full_img_tag

# Regex to match the avatar images
content = re.sub(r'<img loading="lazy" src="([^"]+)" style="width: 40px; height: 40px; border-radius: 50%;" alt="[^"]+">', replace_review_avatar, content)

with open(html_path, 'w', encoding='utf-8') as f:
    f.write(content)

print(f"Replaced {avatar_index} avatars with UNIQUE images.")
