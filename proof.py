import re

with open('marketing/index.html', 'r', encoding='utf-8') as f:
    content = f.read()

# 1. Add 'Proof' to the navigation menu
nav_links_pattern = r'(<a href="#features" class="nav-link">Features</a>)'
content = re.sub(nav_links_pattern, r'\1\n                <a href="#proof" class="nav-link">Proof</a>', content)

# 2. Construct the full Proof section with all 11 images
proof_section = '''
    <section id="proof" class="gallery container" style="padding-top: 60px;">
        <div class="badge" data-aos="fade-up" style="display: block; width: fit-content; margin: 0 auto 1rem;">Live Proof</div>
        <h2 style="font-size: clamp(1.8rem, 5vw, 3rem); margin-bottom: 2rem; text-align: center;" data-aos="fade-up">Terminal Gallery & Signals</h2>
        
        <div class="gallery-grid" style="display: grid; grid-template-columns: repeat(auto-fit, minmax(200px, 1fr)); gap: 1rem;">
            <div class="screenshot-container" data-aos="zoom-in">
                <img src="assets/app_icon.jpg" alt="BIG SHOT App Icon">
                <div class="screenshot-label">BIG SHOT APP</div>
            </div>
            <div class="screenshot-container" data-aos="zoom-in">
                <img src="assets/splash_screen.jpg" alt="Splash Screen">
                <div class="screenshot-label">MASTER THE ORDERFLOW</div>
            </div>
            <div class="screenshot-container" data-aos="zoom-in">
                <img src="assets/risk_disclosure.jpg" alt="Risk Disclosure">
                <div class="screenshot-label">RISK DISCLOSURE</div>
            </div>
            <div class="screenshot-container" data-aos="zoom-in">
                <img src="assets/liquidity_exit.jpg" alt="Liquidity Exit Signal">
                <div class="screenshot-label">LIQUIDITY EXIT ANALYZER</div>
            </div>
            <div class="screenshot-container" data-aos="zoom-in">
                <img src="assets/selling_pressure.jpg" alt="Selling Pressure Signal">
                <div class="screenshot-label">SELLING PRESSURE DETECTOR</div>
            </div>
            <div class="screenshot-container" data-aos="zoom-in">
                <img src="assets/whale_block.jpg" alt="Whale Block Signal">
                <div class="screenshot-label">WHALE BLOCK INDICATOR</div>
            </div>
            <div class="screenshot-container" data-aos="zoom-in">
                <img src="assets/retail_trap.jpg" alt="Retail Trap Signal">
                <div class="screenshot-label">RETAIL TRAP IDENTIFIER</div>
            </div>
            <div class="screenshot-container" data-aos="zoom-in">
                <img src="assets/market_flow.jpg" alt="Market Flow Analysis">
                <div class="screenshot-label">INSTITUTIONAL FEED ACTIVE</div>
            </div>
            <div class="screenshot-container" data-aos="zoom-in">
                <img src="assets/terminal_shot_green.png" alt="Big Shot Terminal Green Signal">
                <div class="screenshot-label">BULLISH ACCUMULATION</div>
            </div>
            <div class="screenshot-container" data-aos="zoom-in">
                <img src="assets/terminal_shot_red.png" alt="Big Shot Terminal Red Signal">
                <div class="screenshot-label">BEARISH DISTRIBUTION</div>
            </div>
            <div class="screenshot-container" data-aos="zoom-in">
                <img src="assets/terminal_shot_nifty.png" alt="Nifty Orderflow Analysis">
                <div class="screenshot-label">NIFTY FULL DEPTH ANALYSIS</div>
            </div>
        </div>
    </section>
'''

old_gallery_pattern = re.compile(r'<section class="gallery container">.*?</section>', re.DOTALL)
if old_gallery_pattern.search(content):
    content = old_gallery_pattern.sub(proof_section, content)
else:
    content = content.replace('<!-- Consolidated Checkout Section -->', proof_section + '\n    <!-- Consolidated Checkout Section -->')

with open('marketing/index.html', 'w', encoding='utf-8') as f:
    f.write(content)

print('Added Proof section and menu link.')
