import re

file_path = r'c:\Users\PUTIN\Desktop\ADVANCEORDERFLOW\marketing\index.html'
with open(file_path, 'r', encoding='utf-8') as f:
    content = f.read()

# Fix WhatsApp number
content = content.replace('919999999999', '918122965050')

# Fix image names
content = content.replace('assets/profit1.jpg', 'assets/profit_1.jpg')
content = content.replace('assets/profit2.jpg', 'assets/profit_2.jpg')
content = content.replace('assets/profit3.jpg', 'assets/profit_3.jpg')

# Fix top running heading
content = content.replace('class="updates-marquee glass"', 'class="updates-marquee"')
content = content.replace('box-shadow: 2px 0 10px rgba(0,255,128,0.3);">LATEST UPDATES</div>', 'box-shadow: 2px 0 10px rgba(0,255,128,0.3); flex-shrink: 0;">LATEST UPDATES</div>')

with open(file_path, 'w', encoding='utf-8') as f:
    f.write(content)

print("Fixes applied.")
