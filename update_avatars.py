import os
import shutil
import re
import glob

brain_dir = r"C:\Users\PUTIN\.gemini\antigravity-ide\brain\81ec1ca3-ebb8-4407-92bb-c71aa7674832"
assets_dir = r"c:\Users\PUTIN\Desktop\ADVANCEORDERFLOW\marketing\assets"
html_path = r"c:\Users\PUTIN\Desktop\ADVANCEORDERFLOW\marketing\index.html"

# Step 1: Find the generated images
def find_latest_image(prefix):
    files = glob.glob(os.path.join(brain_dir, f"{prefix}_*.png"))
    if not files:
        return None
    return sorted(files)[-1] # get latest if multiple

img_trading = find_latest_image("avatar_trading")
img_pet = find_latest_image("avatar_pet")
img_man = find_latest_image("avatar_indian_man")
img_woman = find_latest_image("avatar_indian_woman")

# Step 2: Copy them to assets
if img_trading: shutil.copy(img_trading, os.path.join(assets_dir, "avatar_trading.png"))
if img_pet: shutil.copy(img_pet, os.path.join(assets_dir, "avatar_pet.png"))
if img_man: shutil.copy(img_man, os.path.join(assets_dir, "avatar_indian_man.png"))
if img_woman: shutil.copy(img_woman, os.path.join(assets_dir, "avatar_indian_woman.png"))

print("Images copied.")

# Step 3: Update HTML
with open(html_path, 'r', encoding='utf-8') as f:
    content = f.read()

# List of avatars to cycle through
avatars = [
    "assets/murugan_avatar.png",
    "assets/avatar_trading.png",
    "assets/avatar_indian_man.png",
    "assets/avatar_indian_woman.png",
    "assets/avatar_pet.png",
    "assets/shiva_avatar.png",
    "assets/avatar_indian_woman.png",
    "assets/avatar_trading.png",
    "assets/avatar_indian_man.png",
    "assets/shiva_avatar.png",
    "assets/avatar_indian_woman.png",
    "assets/avatar_pet.png"
]

avatar_index = 0
def replace_review_avatar(match):
    global avatar_index
    full_img_tag = match.group(0)
    src = match.group(1)
    
    if avatar_index < len(avatars):
        new_src = avatars[avatar_index]
        avatar_index += 1
        return full_img_tag.replace(src, new_src)
    return full_img_tag

# We look for img tags inside the reviews section specifically. 
# They currently have src starting with https://ui-avatars.com or ./assets/murugan_avatar.png
content = re.sub(r'<img loading="lazy" src="([^"]+)" style="width: 40px; height: 40px; border-radius: 50%;" alt="[^"]+">', replace_review_avatar, content)

with open(html_path, 'w', encoding='utf-8') as f:
    f.write(content)

print(f"Replaced {avatar_index} avatars in HTML.")
