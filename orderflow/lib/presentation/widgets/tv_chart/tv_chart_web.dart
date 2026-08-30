// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'dart:ui_web' as ui_web;
import 'package:flutter/material.dart';

// Dart triple-quoted strings: backtick ` needs NO escaping.
// Use \$ to prevent Dart interpolation where we want JS ${...} template syntax.
String _buildHtml(String initialSymbol) => '''
<!DOCTYPE html>
<html>
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<style>
*{margin:0;padding:0;box-sizing:border-box;}
body{background:#060B12;width:100vw;height:100vh;overflow:hidden;font-family:'Courier New',monospace;}
#toolbar{position:absolute;top:8px;left:8px;display:flex;gap:6px;z-index:100;align-items:center;}
.sym-btn{
  background:rgba(0,188,212,0.08);border:1px solid rgba(0,188,212,0.25);color:#00BCD4;
  padding:4px 12px;border-radius:4px;cursor:pointer;font-size:10px;font-weight:bold;
  letter-spacing:1px;transition:all 0.2s;outline:none;
}
.sym-btn.active,.sym-btn:hover{background:rgba(0,188,212,0.22);border-color:#00BCD4;}
#status{position:absolute;top:8px;right:8px;color:rgba(0,188,212,0.6);font-size:9px;letter-spacing:1.5px;z-index:100;}
#pricebox{position:absolute;top:38px;left:8px;z-index:100;}
#pval{color:#fff;font-size:22px;font-weight:bold;letter-spacing:1px;}
#pchg{font-size:11px;letter-spacing:0.5px;margin-top:2px;}
#loader{
  position:absolute;top:50%;left:50%;transform:translate(-50%,-50%);
  color:rgba(0,188,212,0.7);font-size:11px;letter-spacing:2px;text-align:center;z-index:200;
}
#cc{width:100%;height:100%;}
</style>
</head>
<body>
<div id="toolbar">
  <button class="sym-btn active" id="btn-nifty"  onclick="sw('NIFTY50')">NIFTY 50</button>
  <button class="sym-btn"        id="btn-bank"   onclick="sw('BANKNIFTY')">BANK NIFTY</button>
  <button class="sym-btn"        id="btn-fin"    onclick="sw('FINNIFTY')">FIN NIFTY</button>
</div>
<div id="pricebox">
  <div id="pval">—</div>
  <div id="pchg" style="color:#26a69a;">CONNECTING...</div>
</div>
<div id="status">⟳ LOADING</div>
<div id="loader">INITIALIZING CHART ENGINE...</div>
<div id="cc"></div>

<script src="https://unpkg.com/lightweight-charts@4.2.0/dist/lightweight-charts.standalone.production.js"
  onerror="document.getElementById('loader').textContent='CDN LOAD FAILED — CHECK NETWORK'">
</script>
<script>
// ── Symbol map ──────────────────────────────────────────────────────────────
var SYM = {
  'NIFTY50':     '^NSEI',
  'BANKNIFTY':   '^NSEBANK',
  'FINNIFTY':    '^CNXFIN',
  'MIDCAPNIFTY': '^NSEMDCP50'
};

var cur = '$initialSymbol';
var chart, cs, vs, timer;

// ── Init chart ───────────────────────────────────────────────────────────────
function initChart() {
  if (typeof LightweightCharts === 'undefined') {
    document.getElementById('loader').textContent = 'CHART LIBRARY NOT LOADED — CHECK NETWORK';
    return;
  }
  var cc = document.getElementById('cc');
  chart = LightweightCharts.createChart(cc, {
    width:  window.innerWidth,
    height: window.innerHeight,
    layout: {
      background: { type: 'solid', color: '#060B12' },
      textColor: 'rgba(255,255,255,0.55)',
      fontSize: 10,
      fontFamily: "'Courier New', monospace"
    },
    grid: {
      vertLines: { color: 'rgba(255,255,255,0.03)' },
      horzLines: { color: 'rgba(255,255,255,0.03)' }
    },
    crosshair: {
      mode: 1,
      vertLine: { color: 'rgba(0,188,212,0.5)', width: 1, style: 1 },
      horzLine: { color: 'rgba(0,188,212,0.5)', width: 1, style: 1, labelBackgroundColor: '#00BCD4' }
    },
    rightPriceScale: {
      borderColor: 'rgba(255,255,255,0.05)',
      textColor:   'rgba(255,255,255,0.55)',
      scaleMargins: { top: 0.08, bottom: 0.22 }
    },
    timeScale: {
      borderColor: 'rgba(255,255,255,0.05)',
      timeVisible: true,
      secondsVisible: false
    },
    handleScroll: { mouseWheel: true, pressedMouseMove: true, horzTouchDrag: true, vertTouchDrag: false },
    handleScale:  { axisPressedMouseMove: true, mouseWheel: true, pinch: true }
  });

  cs = chart.addCandlestickSeries({
    upColor:      '#26a69a',
    downColor:    '#ef5350',
    borderVisible: false,
    wickUpColor:   '#26a69a',
    wickDownColor: '#ef5350',
    priceFormat:   { type: 'price', precision: 2, minMove: 0.05 }
  });

  vs = chart.addHistogramSeries({
    color:        '#26a69a',
    priceFormat:  { type: 'volume' },
    priceScaleId: 'vol'
  });
  chart.priceScale('vol').applyOptions({ scaleMargins: { top: 0.82, bottom: 0 } });

  chart.subscribeCrosshairMove(function(p) {
    if (!p || !p.seriesData) return;
    var d = p.seriesData.get(cs);
    if (d) document.getElementById('pval').textContent = d.close.toFixed(2);
  });

  window.addEventListener('resize', function() {
    chart.applyOptions({ width: window.innerWidth, height: window.innerHeight });
  });
}

// ── Parse Yahoo response ──────────────────────────────────────────────────────
function parse(data) {
  var res = data && data.chart && data.chart.result && data.chart.result[0];
  if (!res) return null;
  var ts    = res.timestamp;
  var q     = res.indicators && res.indicators.quote && res.indicators.quote[0];
  if (!ts || !q) return null;

  var candles = [], vols = [];
  for (var i = 0; i < ts.length; i++) {
    if (!q.open[i] || !q.close[i] || !q.high[i] || !q.low[i]) continue;
    var t    = ts[i];
    var d    = new Date(t * 1000);
    // Filter 9:15–15:40 IST = 3:45–10:10 UTC (225–610 minutes from midnight UTC)
    var tot  = d.getUTCHours() * 60 + d.getUTCMinutes();
    if (tot < 225 || tot >= 610) continue;
    candles.push({ time: t, open: q.open[i], high: q.high[i], low: q.low[i], close: q.close[i] });
    vols.push({
      time:  t,
      value: (q.volume && q.volume[i]) || 0,
      color: q.close[i] >= q.open[i] ? 'rgba(38,166,154,0.35)' : 'rgba(239,83,80,0.35)'
    });
  }
  if (candles.length === 0) return null;
  candles.sort(function(a,b){ return a.time - b.time; });
  vols.sort(function(a,b){ return a.time - b.time; });
  return { candles: candles, vols: vols };
}

// ── Fetch helpers ─────────────────────────────────────────────────────────────
function yahooUrl(sym) {
  var ySym = SYM[sym] || sym;
  var now  = Math.floor(Date.now() / 1000);
  var p1   = now - 3 * 86400;
  return 'https://query1.finance.yahoo.com/v8/finance/chart/' + ySym
    + '?interval=5m&period1=' + p1 + '&period2=' + now;
}

function tryFetch(proxyUrl) {
  return fetch(proxyUrl, { cache: 'no-cache' })
    .then(function(r) {
      if (!r.ok) throw new Error('HTTP ' + r.status);
      return r.json();
    });
}

async function load(sym) {
  setStatus('⟳ FETCHING...', 'rgba(255,165,0,0.8)');
  var base   = yahooUrl(sym);
  var proxy1 = 'https://api.allorigins.win/raw?url=' + encodeURIComponent(base);
  var proxy2 = 'https://corsproxy.io/?' + encodeURIComponent(
    'https://query2.finance.yahoo.com/v8/finance/chart/'
    + (SYM[sym] || sym) + '?interval=5m&range=5d'
  );

  var result = null;

  try { result = parse(await tryFetch(proxy1)); } catch(e) { console.warn('proxy1 failed', e); }
  if (!result) {
    try { result = parse(await tryFetch(proxy2)); } catch(e) { console.warn('proxy2 failed', e); }
  }

  if (!result) {
    setStatus('✗ NO DATA', '#ef5350');
    document.getElementById('pchg').textContent = 'NETWORK ERROR — RETRY IN 60s';
    document.getElementById('pchg').style.color = '#ef5350';
    return;
  }

  // Hide loader on first successful load
  document.getElementById('loader').style.display = 'none';

  cs.setData(result.candles);
  vs.setData(result.vols);
  chart.timeScale().fitContent();

  var last  = result.candles[result.candles.length - 1];
  var first = result.candles[0];
  var chg   = last.close - first.open;
  var pct   = ((chg / first.open) * 100).toFixed(2);
  var sign  = chg >= 0 ? '+' : '';

  document.getElementById('pval').textContent = last.close.toFixed(2);
  document.getElementById('pchg').textContent = sign + chg.toFixed(2) + ' (' + sign + pct + '%)';
  document.getElementById('pchg').style.color = chg >= 0 ? '#26a69a' : '#ef5350';
  setStatus('● LIVE', 'rgba(0,188,212,0.8)');
}

function setStatus(txt, col) {
  var el = document.getElementById('status');
  el.textContent = txt;
  el.style.color  = col;
}

function sw(sym) {
  cur = sym;
  var map = { 'NIFTY50': 'btn-nifty', 'BANKNIFTY': 'btn-bank', 'FINNIFTY': 'btn-fin' };
  document.querySelectorAll('.sym-btn').forEach(function(b){ b.classList.remove('active'); });
  if (map[sym]) document.getElementById(map[sym]).classList.add('active');
  load(sym);
  clearInterval(timer);
  timer = setInterval(function(){ load(cur); }, 60000);
}

// ── Bootstrap ─────────────────────────────────────────────────────────────────
window.addEventListener('load', function() {
  initChart();
  sw(cur);
});
</script>
</body>
</html>
''';

// Use a stable unique key per symbol to avoid re-registration errors
final _registered = <String>{};

Widget buildTvChart(String symbol) {
  final viewId = 'tv-chart-$symbol';

  if (!_registered.contains(viewId)) {
    _registered.add(viewId);

    final iframe = html.IFrameElement()
      ..style.border  = 'none'
      ..style.width   = '100%'
      ..style.height  = '100%'
      // allow-same-origin needed for srcdoc to run scripts properly
      ..setAttribute('sandbox', 'allow-scripts allow-same-origin')
      ..srcdoc = _buildHtml(symbol);

    ui_web.platformViewRegistry.registerViewFactory(
      viewId,
      (_) => iframe,
    );
  }

  return HtmlElementView(viewType: viewId);
}
