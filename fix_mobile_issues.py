import re

file_path_html = r'c:\Users\PUTIN\Desktop\ADVANCEORDERFLOW\marketing\index.html'
file_path_css = r'c:\Users\PUTIN\Desktop\ADVANCEORDERFLOW\marketing\style.css'

# --- HTML FIXES ---
with open(file_path_html, 'r', encoding='utf-8') as f:
    html_content = f.read()

# Fix Marquee inline top
html_content = html_content.replace('top: 60px;', '')

# Fix Profit Container class
# Find the specific section and replace screenshot-container with profit-container
# The profit section has id="earn-profits"
profit_section_match = re.search(r'<section id="earn-profits".*?</section>', html_content, re.DOTALL)
if profit_section_match:
    profit_section = profit_section_match.group(0)
    new_profit_section = profit_section.replace('class="screenshot-container glass"', 'class="profit-container glass"')
    new_profit_section = new_profit_section.replace('object-fit: cover;', 'object-fit: contain;')
    html_content = html_content.replace(profit_section, new_profit_section)

with open(file_path_html, 'w', encoding='utf-8') as f:
    f.write(html_content)

# --- CSS FIXES ---
with open(file_path_css, 'r', encoding='utf-8') as f:
    css_content = f.read()

new_css = """
/* Marquee Mobile Fix */
.updates-marquee {
    top: 60px !important;
}
@media (max-width: 768px) {
    .updates-marquee {
        top: 110px !important;
    }
}

/* Profit Images Uncropped */
.profit-container {
    border-radius: 20px;
    overflow: hidden;
    position: relative;
    background: rgba(0,0,0,0.5);
    display: flex;
    flex-direction: column;
}
.profit-container img {
    width: 100%;
    height: auto;
    object-fit: contain !important;
    display: block;
}
"""

with open(file_path_css, 'a', encoding='utf-8') as f:
    f.write("\n" + new_css + "\n")

print("Fixes applied.")
