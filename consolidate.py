import re
import os

with open('marketing/index.html', 'r', encoding='utf-8') as f:
    content = f.read()

# 1. Remove "technical-section" (how-it-works)
content = re.sub(r'<section class="technical-section container" id="how-it-works">.*?</section>', '', content, flags=re.DOTALL)

# 2. Remove "simplicity" section
content = re.sub(r'<section class="simplicity container" data-aos="fade-up">.*?</section>', '', content, flags=re.DOTALL)

# 3. Simplify gallery to 4 images
gallery_pattern = re.compile(r'(<section class="gallery container">.*?)<div class="gallery-grid">(.*?)</div>\s*</section>', re.DOTALL)
gallery_match = gallery_pattern.search(content)

if gallery_match:
    gallery_prefix = gallery_match.group(1)
    grid_content = gallery_match.group(2)
    
    # Extract individual screenshot containers
    screenshots = re.findall(r'<div class="screenshot-container".*?</div>', grid_content, flags=re.DOTALL)
    
    # Keep only the first 4 screenshots
    reduced_screenshots = '\n'.join(screenshots[:4])
    
    # Rebuild gallery section
    new_gallery = f'{gallery_prefix}<div class="gallery-grid" style="display: grid; grid-template-columns: repeat(auto-fit, minmax(200px, 1fr)); gap: 1rem;">\n{reduced_screenshots}\n</div>\n</section>'
    
    content = content[:gallery_match.start()] + new_gallery + content[gallery_match.end():]

# 4. Consolidate pricing and payment by wrapping them in a flex container for desktop side-by-side
sales_pattern = re.compile(r'<section class="sales-section".*?</section>', re.DOTALL)
payment_pattern = re.compile(r'<section id="payment-section".*?</section>', re.DOTALL)

sales_match = sales_pattern.search(content)
payment_match = payment_pattern.search(content)

if sales_match and payment_match:
    sales_html = sales_match.group(0)
    payment_html = payment_match.group(0)
    
    # Remove large paddings and margins to tighten
    sales_html = sales_html.replace('padding: 60px 40px', 'padding: 20px')
    sales_html = sales_html.replace('margin-bottom: 3rem', 'margin-bottom: 1rem')
    payment_html = payment_html.replace('padding: 100px 0', 'padding: 20px 0')
    payment_html = payment_html.replace('margin-top: 50px', 'margin-top: 20px')
    
    # Remove them from their original spots
    content = content.replace(sales_html, '')
    content = content.replace(payment_html, '')
    
    # Combine them into a new single section
    combined_checkout = f"""
    <!-- Consolidated Checkout Section -->
    <section id="checkout-section" class="container" style="display: flex; flex-wrap: wrap; gap: 2rem; padding: 40px 0; justify-content: center; align-items: stretch;">
        <div style="flex: 1; min-width: 350px;">
            {sales_html.replace('<section class="sales-section" data-aos="fade-up">', '<div data-aos="fade-up">').replace('</section>', '</div>')}
        </div>
        <div style="flex: 1; min-width: 350px;">
            {payment_html.replace('<section id="payment-section" class="payment-section">', '<div>').replace('</section>', '</div>')}
        </div>
    </section>
    """
    
    # Insert combined checkout right before footer
    footer_pos = content.find('<footer')
    if footer_pos != -1:
        content = content[:footer_pos] + combined_checkout + '\n' + content[footer_pos:]
    else:
        content += combined_checkout

# Write back
with open('marketing/index.html', 'w', encoding='utf-8') as f:
    f.write(content)

print("HTML optimized successfully.")
