import re

with open('marketing/index.html', 'r', encoding='utf-8') as f:
    html = f.read()

# ----------------------------------------
# 1. TRADINGVIEW LIVE TICKER
# ----------------------------------------
tv_ticker_html = '''
<!-- TradingView Widget BEGIN -->
<div class="tradingview-widget-container" style="position: fixed; bottom: 0; width: 100%; z-index: 1000; left: 0; border-top: 1px solid rgba(255,255,255,0.1);">
  <div class="tradingview-widget-container__widget"></div>
  <script type="text/javascript" src="https://s3.tradingview.com/external-embedding/embed-widget-ticker-tape.js" async>
  {
  "symbols": [
    {
      "proName": "BSE:SENSEX",
      "title": "BSE SENSEX"
    },
    {
      "proName": "NSE:NIFTY",
      "title": "NIFTY 50"
    },
    {
      "proName": "NSE:BANKNIFTY",
      "title": "BANKNIFTY"
    },
    {
      "proName": "NSE:RELIANCE",
      "title": "RELIANCE"
    },
    {
      "proName": "NSE:HDFCBANK",
      "title": "HDFCBANK"
    }
  ],
  "showSymbolLogo": true,
  "isTransparent": false,
  "displayMode": "adaptive",
  "colorTheme": "dark",
  "locale": "in"
}
  </script>
</div>
<!-- TradingView Widget END -->
'''

# Remove old dummy ticker
old_ticker_pattern = re.compile(r'<!-- Live Market Ticker -->.*?</div>\s*</div>', re.DOTALL)
html = old_ticker_pattern.sub('', html)

if 'embed-widget-ticker-tape.js' not in html:
    html = html.replace('</body>', tv_ticker_html + '\n</body>')


# ----------------------------------------
# 2. MARQUEE (LATEST UPDATES)
# ----------------------------------------
marquee_html = '''
    <div class="updates-marquee glass" style="position: fixed; top: 60px; left: 0; width: 100%; height: 35px; display: flex; align-items: center; z-index: 999; border-bottom: 1px solid rgba(255, 255, 255, 0.05); font-size: 0.85rem; overflow: hidden; white-space: nowrap; background: rgba(5,10,15,0.85); backdrop-filter: blur(10px);">
        <div style="background: linear-gradient(135deg, var(--bull-green), #00b359); color: #000; font-weight: 800; padding: 0 20px; height: 100%; display: flex; align-items: center; z-index: 10; box-shadow: 2px 0 10px rgba(0,255,128,0.3);">LATEST UPDATES</div>
        <div style="flex: 1; overflow: hidden;">
            <div style="display: inline-block; padding-left: 100%; animation: ticker 25s linear infinite;">
                <span style="color: white; margin-right: 50px;">🚨 BIG SHOT V2.0 Web Terminal is now Live!</span>
                <span style="color: var(--bull-green); margin-right: 50px;">🔥 MEGA OFFER: 50% Off Flash Sale ends tonight!</span>
                <span style="color: var(--bear-red); margin-right: 50px;">📉 Institutional Footprints detected on Nifty 50</span>
                <span style="color: white; margin-right: 50px;">🚀 Next-gen Trading execution engine deployed</span>
            </div>
        </div>
    </div>
'''
if 'class="updates-marquee' not in html:
    html = html.replace('</nav>', '</nav>\n' + marquee_html)


# ----------------------------------------
# 3. HERO CAROUSEL
# ----------------------------------------
# We will wrap the existing hero content in a carousel slide and add a second slide.
hero_content_pattern = re.compile(r'(<div class="hero-content">.*?</div>)', re.DOTALL)
match = hero_content_pattern.search(html)

if match and 'class="carousel-slide"' not in html:
    original_hero_content = match.group(1)
    
    # We create a slider container
    carousel_html = f'''
    <div class="hero-carousel" style="position: relative; width: 100%; max-width: 800px; margin: 0 auto; overflow: hidden;">
        <div class="carousel-track" id="heroTrack" style="display: flex; transition: transform 0.5s ease-in-out; width: 200%;">
            
            <!-- Slide 1: Original Hero -->
            <div class="carousel-slide" style="width: 50%; display: flex; justify-content: center; align-items: center; padding: 20px;">
                {original_hero_content.replace('data-aos', 'data-no-aos')}
            </div>

            <!-- Slide 2: Flash Sale Promo -->
            <div class="carousel-slide" style="width: 50%; display: flex; flex-direction: column; justify-content: center; align-items: center; padding: 20px;">
                <div class="badge" style="background: rgba(255,51,102,0.1); color: var(--bear-red); border-color: rgba(255,51,102,0.3);">FLASH SALE ENDS TONIGHT</div>
                <h1 style="color: var(--bear-red); font-size: clamp(2rem, 6vw, 4rem); margin: 20px 0;">50% OFF LIFETIME PRO</h1>
                <p class="hero-subtitle">Unlock real-time institutional data feeds and proprietary signals for a fraction of the cost.</p>
                <div class="action-buttons">
                    <a href="#checkout-section" class="cta-button" style="background: var(--bear-red); box-shadow: 0 10px 30px rgba(255,51,102,0.3);">CLAIM OFFER NOW</a>
                </div>
            </div>

        </div>
        
        <!-- Carousel Controls -->
        <div class="carousel-dots" style="display: flex; justify-content: center; gap: 10px; margin-top: 30px;">
            <div class="dot active" onclick="setSlide(0)" style="width: 12px; height: 12px; border-radius: 50%; background: var(--bull-green); cursor: pointer; transition: 0.3s;"></div>
            <div class="dot" onclick="setSlide(1)" style="width: 12px; height: 12px; border-radius: 50%; background: rgba(255,255,255,0.2); cursor: pointer; transition: 0.3s;"></div>
        </div>
    </div>
    
    <script>
        let currentSlide = 0;
        function setSlide(index) {{
            currentSlide = index;
            document.getElementById('heroTrack').style.transform = `translateX(-${{index * 50}}%)`;
            const dots = document.querySelectorAll('.dot');
            dots.forEach((dot, i) => {{
                dot.style.background = i === index ? (index === 0 ? 'var(--bull-green)' : 'var(--bear-red)') : 'rgba(255,255,255,0.2)';
            }});
        }}
        // Auto slide
        setInterval(() => {{
            setSlide(currentSlide === 0 ? 1 : 0);
        }}, 6000);
    </script>
    '''
    html = hero_content_pattern.sub(carousel_html, html)


# ----------------------------------------
# 4. GLASSY CHATBOT FAB
# ----------------------------------------
chatbot_html = '''
    <!-- Glassy Chatbot Assistant -->
    <a href="https://wa.me/919999999999?text=Hi,%20I%20need%20help%20with%20BIG%20SHOT%20Pro" target="_blank" class="chatbot-fab" style="position:fixed; bottom:70px; right:20px; width:70px; height:70px; border-radius:50%; z-index:1000; animation:float-bot 3s ease-in-out infinite, pulse-border 2s infinite;">
        <div style="width: 100%; height: 100%; background: rgba(0, 255, 128, 0.1); border: 2px solid rgba(0, 255, 128, 0.4); border-radius: 50%; box-shadow: 0 0 20px rgba(0,255,128,0.4), inset 0 0 15px rgba(0,255,128,0.2); backdrop-filter: blur(10px); display: flex; align-items: center; justify-content: center; overflow: hidden; position: relative;">
            <img src="assets/chatbot_avatar.png" style="width: 80%; height: 80%; object-fit: contain; z-index: 2; transform: translateY(2px);" alt="Chat Assistant">
            <div style="position: absolute; top: 50%; left: 50%; transform: translate(-50%, -50%); width: 40px; height: 40px; background: rgba(0, 255, 128, 0.6); filter: blur(20px); z-index: 1;"></div>
        </div>
        <span style="position:absolute; top:0; right:0; width:18px; height:18px; background:var(--bear-red); border-radius:50%; border:3px solid #050a0f; box-shadow: 0 0 10px var(--bear-red);"></span>
    </a>
'''

# Remove old WhatsApp FAB
wa_pattern = re.compile(r'<!-- WhatsApp FAB -->.*?</a>', re.DOTALL)
html = wa_pattern.sub('', html)

if 'class="chatbot-fab"' not in html:
    html = html.replace('</body>', chatbot_html + '\n</body>')


# Modify padding top to accommodate marquee
html = html.replace('padding-top: 100px;', 'padding-top: 130px;')

with open('marketing/index.html', 'w', encoding='utf-8') as f:
    f.write(html)


# ----------------------------------------
# UPDATE CSS
# ----------------------------------------
with open('marketing/style.css', 'r', encoding='utf-8') as f:
    css = f.read()

# Add float-bot animation if not exists
if '@keyframes float-bot' not in css:
    css += '''
@keyframes float-bot {
    0% { transform: translateY(0px); }
    50% { transform: translateY(-10px); }
    100% { transform: translateY(0px); }
}
'''
    with open('marketing/style.css', 'w', encoding='utf-8') as f:
        f.write(css)

print("SUCCESS: 4 new features added.")
