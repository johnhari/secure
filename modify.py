import re

with open('marketing/index.html', 'r', encoding='utf-8') as f:
    content = f.read()

# Extract reviews section
reviews_pattern = re.compile(r'(    <!-- Reviews Section -->.*?)(?=    <section id="payment-section")', re.DOTALL)
match = reviews_pattern.search(content)
if not match:
    print('Reviews section not found!')
    exit(1)

reviews_html = match.group(1)
content = content.replace(reviews_html, '') # Remove from original position

# List of avatars to inject
avatars = [
    './assets/murugan_avatar.png',
    'https://randomuser.me/api/portraits/men/33.jpg',
    'https://randomuser.me/api/portraits/men/11.jpg',
    'https://randomuser.me/api/portraits/men/22.jpg',
    'https://randomuser.me/api/portraits/men/44.jpg',
    './assets/shiva_avatar.png',
    'https://randomuser.me/api/portraits/women/44.jpg',
    'https://randomuser.me/api/portraits/men/55.jpg',
    'https://randomuser.me/api/portraits/men/66.jpg',
    'https://randomuser.me/api/portraits/men/77.jpg',
    'https://randomuser.me/api/portraits/women/22.jpg',
    'https://randomuser.me/api/portraits/men/88.jpg'
]

# Replace images inside reviews_html
# We have 12 unique reviews, duplicated once (24 total)
img_tags = re.findall(r'<img src="[^"]+"', reviews_html)
for i in range(24):
    if i < len(img_tags):
        avatar = avatars[i % 12] # Cycle through the 12 avatars
        reviews_html = reviews_html.replace(img_tags[i], f'<img src="{avatar}"', 1)

# Insert before <section id="features"
insert_pos = content.find('    <section id="features"')
if insert_pos == -1:
    print('Features section not found!')
    exit(1)

new_content = content[:insert_pos] + reviews_html + '\n' + content[insert_pos:]

with open('marketing/index.html', 'w', encoding='utf-8') as f:
    f.write(new_content)

print('Success!')
