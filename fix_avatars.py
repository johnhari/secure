import re
import urllib.parse

file_path = r'c:\Users\PUTIN\Desktop\ADVANCEORDERFLOW\marketing\index.html'
with open(file_path, 'r', encoding='utf-8') as f:
    content = f.read()

def replace_avatar(match):
    full_img_tag = match.group(0)
    src = match.group(1)
    # Extract alt text
    alt_match = re.search(r'alt="([^"]+)"', full_img_tag)
    if alt_match:
        name = alt_match.group(1)
        # URL encode the name
        encoded_name = urllib.parse.quote(name)
        new_src = f"https://ui-avatars.com/api/?name={encoded_name}&background=00ff9d&color=000&bold=true"
        return full_img_tag.replace(src, new_src)
    return full_img_tag

# Regex to find img tags with randomuser.me
content = re.sub(r'<img[^>]+src="(https://randomuser\.me[^"]+)"[^>]*>', replace_avatar, content)

with open(file_path, 'w', encoding='utf-8') as f:
    f.write(content)

print("Avatars updated.")
