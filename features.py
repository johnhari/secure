import re

# -------------
# 1. READ HTML
# -------------
with open('marketing/index.html', 'r', encoding='utf-8') as f:
    html = f.read()

# -------------
# 2. WHATSAPP FAB
# -------------
whatsapp_html = '''
    <!-- WhatsApp FAB -->
    <a href="https://wa.me/919999999999?text=Hi,%20I%20want%20to%20purchase%20BIG%20SHOT%20Pro" target="_blank" class="whatsapp-fab" style="position:fixed; bottom:60px; right:20px; background:#25D366; color:white; width:60px; height:60px; border-radius:50%; display:flex; justify-content:center; align-items:center; box-shadow:0 0 20px rgba(37,211,102,0.5); z-index:1000; animation:pulse-border 2s infinite;">
        <svg viewBox="0 0 24 24" width="32" height="32" fill="white">
            <path d="M17.472 14.382c-.297-.149-1.758-.867-2.03-.967-.273-.099-.471-.148-.67.15-.197.297-.767.966-.94 1.164-.173.199-.347.223-.644.075-.297-.15-1.255-.463-2.39-1.475-.883-.788-1.48-1.761-1.653-2.059-.173-.297-.018-.458.13-.606.134-.133.298-.347.446-.52.149-.174.198-.298.298-.497.099-.198.05-.371-.025-.52-.075-.149-.669-1.612-.916-2.207-.242-.579-.487-.5-.669-.51-.173-.008-.371-.01-.57-.01-.198 0-.52.074-.792.372-.272.297-1.04 1.016-1.04 2.479 0 1.462 1.065 2.875 1.213 3.074.149.198 2.096 3.2 5.077 4.487.709.306 1.262.489 1.694.625.712.227 1.36.195 1.871.118.571-.085 1.758-.719 2.006-1.413.248-.694.248-1.289.173-1.413-.074-.124-.272-.198-.57-.347m-5.421 7.403h-.004a9.87 9.87 0 01-5.031-1.378l-.361-.214-3.741.982.998-3.648-.235-.374a9.86 9.86 0 01-1.51-5.26c.001-5.45 4.436-9.884 9.888-9.884 2.64 0 5.122 1.03 6.988 2.898a9.825 9.825 0 012.893 6.994c-.003 5.45-4.437 9.884-9.885 9.884m8.413-18.297A11.815 11.815 0 0012.05 0C5.495 0 .16 5.335.157 11.892c0 2.096.547 4.142 1.588 5.945L.057 24l6.305-1.654a11.882 11.882 0 005.683 1.448h.005c6.554 0 11.89-5.335 11.893-11.893a11.821 11.821 0 00-3.48-8.413z"/>
        </svg>
    </a>
'''
if 'class="whatsapp-fab"' not in html:
    html = html.replace('</body>', whatsapp_html + '\n</body>')


# -------------
# 3. URGENCY TIMER
# -------------
timer_html = '''
    <div class="urgency-timer glass" style="text-align: center; margin-bottom: 2rem; padding: 15px; border-color: var(--bear-red); animation: pulse-border 2s infinite; width: 100%; box-sizing: border-box;">
        <h4 style="color: var(--bear-red); margin-bottom: 5px; font-size: 1.2rem;">⏳ 50% OFF FLASH SALE ENDS IN</h4>
        <div id="countdown" style="font-size: 2.5rem; font-family: 'Courier New', monospace; font-weight: bold; color: #fff; letter-spacing: 2px;">
            02:45:10
        </div>
    </div>
'''
if 'class="urgency-timer' not in html:
    html = html.replace('<div class="pricing-grid">', timer_html + '\n            <div class="pricing-grid">')

timer_js = '''
    <!-- Timer Script -->
    <script>
        let time = 2 * 3600 + 45 * 60 + 10;
        setInterval(() => {
            time--;
            if(time < 0) time = 2 * 3600 + 45 * 60 + 10;
            let h = Math.floor(time / 3600).toString().padStart(2, '0');
            let m = Math.floor((time % 3600) / 60).toString().padStart(2, '0');
            let s = (time % 60).toString().padStart(2, '0');
            let el = document.getElementById('countdown');
            if(el) el.innerText = h + ':' + m + ':' + s;
        }, 1000);
    </script>
'''
if 'id="countdown"' not in html:
    html = html.replace('</body>', timer_js + '\n</body>')


# -------------
# 4. INTERACTIVE TERMINAL PREVIEW
# -------------
demo_modal = '''
    <!-- Demo Modal -->
    <div id="demoModal" class="modal-overlay" style="display:none; position:fixed; top:0; left:0; width:100%; height:100%; background:rgba(0,0,0,0.9); z-index:9999; justify-content:center; align-items:center; flex-direction:column;">
        <div class="glass" style="width:90%; max-width:800px; height:60vh; position:relative; overflow:hidden; border:1px solid var(--bull-green); display:flex; flex-direction:column; align-items:center; justify-content:center; background: #0a0f14;">
            <h2 style="color:var(--bull-green); margin-bottom:20px; animation:blink 1s infinite;">● LIVE FEED ACTIVE</h2>
            <div style="font-family:monospace; font-size: clamp(1rem, 4vw, 1.5rem); color:#fff; text-align: center;">
                Processing TBT Data... <br>
                <span style="color:var(--bull-green)">Buy Delta: +4500</span> <br>
                <span style="color:var(--bear-red)">Sell Delta: -1200</span>
            </div>
            
            <div id="demo-lock" style="display:none; position:absolute; top:0; left:0; width:100%; height:100%; background:rgba(0,0,0,0.85); flex-direction:column; justify-content:center; align-items:center; backdrop-filter:blur(5px); padding: 20px; text-align: center;">
                <h3 style="color:var(--bear-red); font-size: clamp(1.5rem, 5vw, 2rem); margin-bottom:10px;">🔒 FEED LOCKED</h3>
                <p>Purchase Pro to unlock live execution and signals.</p>
                <a href="#checkout-section" onclick="closeDemo()" class="cta-button" style="margin-top:20px;">PURCHASE PRO</a>
            </div>
            
            <button onclick="closeDemo()" style="position:absolute; top:10px; right:15px; background:none; border:none; color:white; font-size:1.5rem; cursor:pointer;">✕</button>
        </div>
    </div>
    <script>
        function openDemo() {
            document.getElementById('demoModal').style.display = 'flex';
            document.getElementById('demo-lock').style.display = 'none';
            setTimeout(() => {
                document.getElementById('demo-lock').style.display = 'flex';
            }, 5000);
        }
        function closeDemo() {
            document.getElementById('demoModal').style.display = 'none';
        }
    </script>
'''
if 'id="demoModal"' not in html:
    html = html.replace('</body>', demo_modal + '\n</body>')
    # Replace CTA button
    html = html.replace('<a href="/access_terminal/" class="cta-button terminal-launch">', '<a href="javascript:void(0)" onclick="openDemo()" class="cta-button terminal-launch">')
    html = html.replace('OPEN WEB TERMINAL', 'TRY LIVE DEMO')


# -------------
# 5. LANGUAGE TOGGLE
# -------------
lang_toggle = '''
            <div class="lang-toggle" onclick="toggleLang()" style="cursor:pointer; background:rgba(255,255,255,0.1); padding:5px 10px; border-radius:20px; font-size:0.8rem; font-weight:bold; margin-left:15px; display:inline-block;">
                <span id="lang-en" style="color:#fff">EN</span> | <span id="lang-ta" style="color:#888">TA</span>
            </div>
            <script>
                let isTa = false;
                function toggleLang() {
                    isTa = !isTa;
                    document.getElementById('lang-en').style.color = isTa ? '#888' : '#fff';
                    document.getElementById('lang-ta').style.color = isTa ? '#fff' : '#888';
                    
                    const title = document.getElementById('main-title');
                    if(title) title.innerText = isTa ? 'பிக் ஷாட் ஆர்டர்ஃப்ளோ (BIG SHOT)' : 'BIG SHOT ORDERFLOW';
                    
                    const sub = document.getElementById('main-sub');
                    if(sub) sub.innerText = isTa ? 'நிறுவன தர சந்தை நுண்ணறிவு. டெஸ்க்டாப் மற்றும் மொபைலுக்கு உகந்த வலை முனையம்.' : 'Institutional-Grade Market Intelligence. Web Terminal optimized for Desktop & Mobile.';
                }
            </script>
'''
if 'class="lang-toggle"' not in html:
    # Insert next to nav-links
    html = html.replace('</div>\n        </div>\n    </nav>', lang_toggle + '\n            </div>\n        </div>\n    </nav>')
    
    # Add IDs to hero text for toggle
    html = html.replace('<h1>பிக் ஷாட் ஆர்டர்ஃப்ளோ (BIG SHOT)</h1>', '<h1 id="main-title">பிக் ஷாட் ஆர்டர்ஃப்ளோ (BIG SHOT)</h1>')
    html = html.replace('<h1 data-aos="zoom-in" data-aos-delay="200">பிக் ஷாட் ஆர்டர்ஃப்ளோ (BIG SHOT)</h1>', '<h1 id="main-title" data-aos="zoom-in" data-aos-delay="200">பிக் ஷாட் ஆர்டர்ஃப்ளோ (BIG SHOT)</h1>')
    html = html.replace('class="hero-subtitle" data-aos="fade-up" data-aos-delay="400">Institutional-Grade', 'id="main-sub" class="hero-subtitle" data-aos="fade-up" data-aos-delay="400">Institutional-Grade')


# -------------
# 6. FAQ ACCORDION
# -------------
faq_html = '''
    <section id="faq-section" class="container" style="padding: 40px 20px; max-width: 800px; margin: 0 auto;">
        <h2 style="text-align: center; margin-bottom: 2rem;">Frequently Asked Questions</h2>
        
        <details class="glass" style="padding: 15px; margin-bottom: 10px; cursor: pointer;">
            <summary style="font-weight: bold; font-size: 1.1rem; outline: none; display: list-item;">Do I need a TrueData API?</summary>
            <p style="margin-top: 10px; color: var(--text-secondary);">No! BIG SHOT has a completely zero-dependency architecture. Our data feed is built-in.</p>
        </details>
        
        <details class="glass" style="padding: 15px; margin-bottom: 10px; cursor: pointer;">
            <summary style="font-weight: bold; font-size: 1.1rem; outline: none; display: list-item;">Does this work on Mobile and PC?</summary>
            <p style="margin-top: 10px; color: var(--text-secondary);">Yes. Our Next-Gen Web Terminal runs smoothly on Desktop Browsers, iOS Safari, and Android Chrome.</p>
        </details>
        
        <details class="glass" style="padding: 15px; margin-bottom: 10px; cursor: pointer;">
            <summary style="font-weight: bold; font-size: 1.1rem; outline: none; display: list-item;">Do I need NinjaTrader?</summary>
            <p style="margin-top: 10px; color: var(--text-secondary);">Absolutely not. BIG SHOT is a standalone web application replacing complex desktop software.</p>
        </details>
        
        <details class="glass" style="padding: 15px; margin-bottom: 10px; cursor: pointer;">
            <summary style="font-weight: bold; font-size: 1.1rem; outline: none; display: list-item;">How fast is the data feed?</summary>
            <p style="margin-top: 10px; color: var(--text-secondary);">We process Tick-by-Tick (TBT) Level 3 Exchange Data, ensuring zero-lag institutional latency.</p>
        </details>
    </section>
'''
if 'Frequently Asked Questions' not in html:
    footer_pos = html.find('<footer>')
    if footer_pos != -1:
        html = html[:footer_pos] + faq_html + '\n    ' + html[footer_pos:]
    else:
        # if footer not found, just put at end of body
        html = html.replace('</body>', faq_html + '\n</body>')


# SAVE
with open('marketing/index.html', 'w', encoding='utf-8') as f:
    f.write(html)

print('Successfully added HTML for 5 conversion features.')
