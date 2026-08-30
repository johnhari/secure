import re

file_path = r'c:\Users\PUTIN\Desktop\ADVANCEORDERFLOW\marketing\index.html'
with open(file_path, 'r', encoding='utf-8') as f:
    content = f.read()

# Replace <img src="assets/profit...
content = re.sub(r'<img\s+src="(assets/(?:profit|gallery|terminal|app_icon|splash|risk|liquidity|selling|whale|retail|market)[^"]*)"', 
                 r'<img loading="lazy" src="\1"', content)

# Replace <img src="https://randomuser...
content = re.sub(r'<img\s+src="(https://randomuser[^"]*)"', 
                 r'<img loading="lazy" src="\1"', content)

# Replace <img src="./assets/murugan_avatar... and shiva_avatar...
content = re.sub(r'<img\s+src="(\./assets/(?:murugan|shiva)_avatar[^"]*)"', 
                 r'<img loading="lazy" src="\1"', content)

with open(file_path, 'w', encoding='utf-8') as f:
    f.write(content)

print("Lazy loading added.")
