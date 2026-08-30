class StockLogos {
  /// Local bundled assets (highest priority — instant load, no network)
  static const Map<String, String> localAssets = {};

  /// Official corporate domains for each Nifty 50 stock + F&O stocks + indices.
  /// Used for Google Favicons (primary) and Clearbit (fallback) logo fetch.
  static const Map<String, String> domains = {
    // ── Indices ──────────────────────────────────────────────────────────────
    'NIFTY50':      'nseindia.com',
    'BANKNIFTY':    'nseindia.com',
    'FINNIFTY':     'nseindia.com',
    'MIDCAPNIFTY':  'nseindia.com',
    'SENSEX':       'bseindia.com',
    'NIFTYIT':      'nseindia.com',
    'NIFTYAUTO':    'nseindia.com',
    'NIFTYMETAL':   'nseindia.com',
    'NIFTYPHARMA':  'nseindia.com',
    'NIFTYFMCG':    'nseindia.com',
    'NIFTYINFRA':   'nseindia.com',
    'NIFTYENERGY':  'nseindia.com',
    'NIFTYMEDIA':   'nseindia.com',
    'NIFTYREALTY':  'nseindia.com',
    'NIFTYPSE':     'nseindia.com',

    // ── Nifty 50 ──────────────────────────────────────────────────────────────
    'ADANIENT':     'adani.com',
    'ADANIPORTS':   'adaniports.com',
    'APOLLOHOSP':   'apollohospitals.com',
    'ASIANPAINT':   'asianpaints.com',
    'AXISBANK':     'axisbank.com',
    'BAJAJ-AUTO':   'bajajauto.com',
    'BAJFINANCE':   'bajajfinserv.in',
    'BAJAJFINSV':   'bajajfinserv.in',
    'BPCL':         'bharatpetroleum.com',
    'BHARTIARTL':   'airtel.in',
    'BRITANNIA':    'britannia.co.in',
    'CIPLA':        'cipla.com',
    'COALINDIA':    'coalindia.in',
    'DIVISLAB':     'divislabs.com',
    'DRREDDY':      'drreddys.com',
    'EICHERMOT':    'eichermotors.com',
    'GRASIM':       'grasim.com',
    'HCLTECH':      'hcltech.com',
    'HDFCBANK':     'hdfcbank.com',
    'HDFCLIFE':     'hdfclife.com',
    'HEROMOTOCO':   'heromotocorp.com',
    'HINDALCO':     'hindalco.com',
    'HINDUNILVR':   'hul.co.in',
    'ICICIBANK':    'icicibank.com',
    'ITC':          'itcportal.com',
    'INDUSINDBK':   'indusind.com',
    'INFY':         'infosys.com',
    'JSWSTEEL':     'jsw.in',
    'KOTAKBANK':    'kotak.com',
    'LTIM':         'ltimindtree.com',
    'LT':           'larsentoubro.com',
    'M&M':          'mahindra.com',
    'MARUTI':       'marutisuzuki.com',
    'NTPC':         'ntpc.co.in',
    'NESTLEIND':    'nestle.in',
    'ONGC':         'ongcindia.com',
    'POWERGRID':    'powergridindia.com',
    'RELIANCE':     'ril.com',
    'SBILIFE':      'sbilife.co.in',
    'SBIN':         'sbi.co.in',
    'SHRIRAMFIN':   'shriramfinance.in',
    'SUNPHARMA':    'sunpharma.com',
    'TCS':          'tcs.com',
    'TATACONSUM':   'tataconsumerproducts.com',
    'TATAMOTORS':   'tatamotors.com',
    'TATASTEEL':    'tatasteel.com',
    'TECHM':        'techmahindra.com',
    'TITAN':        'titan.co.in',
    'ULTRACEMCO':   'ultratechcement.com',
    'WIPRO':        'wipro.com',

    // ── F&O / Midcap Stocks ───────────────────────────────────────────────────
    'AARTIIND':     'aartiindustries.com',
    'ABB':          'abb.com',
    'ABBOTINDIA':   'abbott.co.in',
    'ABCAPITAL':    'adityabirlacapital.com',
    'ABFRL':        'adityabirlaonline.com',
    'ACC':          'acclimited.com',
    'ADANIPOWER':   'adanipower.com',
    'ALKEM':        'alkemlabs.com',
    'AMBUJACEM':    'ambujacement.com',
    'ASTRAL':       'astralpipes.com',
    'ATUL':         'atulltd.com',
    'AUBANK':       'aubank.in',
    'AUROPHARMA':   'aurobindo.com',
    'BALKRISIND':   'bkt-tires.com',
    'BALRAMCHIN':   'balrampurchini.com',
    'BANDHANBNK':   'bandhanbank.com',
    'BANKBARODA':   'bankofbaroda.in',
    'BATAINDIA':    'bata.in',
    'BEL':          'bel-india.in',
    'BHEL':         'bhel.com',
    'BIOCON':       'biocon.com',
    'BOSCHLTD':     'bosch.in',
    'CANBK':        'canarabank.in',
    'CANFINHOME':   'canfinhomes.com',
    'CHAMBLFERT':   'chambalfertilisers.com',
    'CHOLAFIN':     'cholamandalam.com',
    'COCHINSHIP':   'cochinshipyard.com',
    'COFORGE':      'coforge.com',
    'CONCOR':       'concorindia.com',
    'COROMANDEL':   'coromandel.farm',
    'CROMPTON':     'crompton.co.in',
    'CUMMINSIND':   'cummins.in',
    'DLF':          'dlf.in',
    'DEEPAKNTR':    'deepaknitrite.com',
    'DELHIVERY':    'delhivery.com',
    'ESCORTS':      'escortskubota.com',
    'EXIDEIND':     'exideindustries.com',
    'FEDERALBNK':   'federalbank.co.in',
    'GLENMARK':     'glenmarkpharma.com',
    'GMRINFRA':     'gmrgroup.in',
    'GNFC':         'gnfc.in',
    'GODREJCP':     'godrejcp.com',
    'GODREJPROP':   'godrejproperties.com',
    'GRANULES':     'granulesindia.com',
    'GUJGASLTD':    'gujaratgas.com',
    'HAL':          'hal-india.co.in',
    'HAVELLS':      'havells.com',
    'HDFCAMC':      'hdfcfund.com',
    'HINDCOPPER':   'hindustancopper.com',
    'HINDPETRO':    'hindustanpetroleum.com',
    'IPCALAB':      'ipca.com',
    'IDFC':         'idfcfirstbank.com',
    'IDFCFIRSTB':   'idfcfirstbank.com',
    'INDIACEM':     'indiacements.com',
    'INDIAMART':    'indiamart.com',
    'INDIGO':       'goindigo.in',
    'IOC':          'iocl.com',
    'IRCTC':        'irctc.co.in',
    'IRFC':         'irfc.nic.in',
    'JINDALSTEL':   'jindalsteelpower.com',
    'JKCEMENT':     'jkcement.com',
    'JSL':          'jindalstainless.com',
    'JUBLFOOD':     'jubilantfoodworks.com',
    'KEI':          'kei-ind.com',
    'L&TFH':        'ltfs.com',
    'LALPATHLAB':   'lalpathlabs.com',
    'LICHSGFIN':    'lichousing.com',
    'LUPIN':        'lupin.com',
    'MRF':          'mrftyres.com',
    'M&MFIN':       'mahindrafinance.com',
    'MANAPPURAM':   'manappuram.com',
    'MARICO':       'marico.com',
    'MCX':          'mcxindia.com',
    'METROPOLIS':   'metropolisindia.com',
    'MFSL':         'maxlifeinsurance.com',
    'MGL':          'mahanagargas.com',
    'MOTILALOFS':   'motilaloswal.com',
    'MPHASIS':      'mphasis.com',
    'MRPL':         'mrpl.co.in',
    'MUTHOOTFIN':   'muthootfinance.com',
    'NATIONALUM':   'nalcoindia.com',
    'NAVINFLUOR':   'navinfluorine.com',
    'NLCINDIA':     'nlcindia.gov.in',
    'NMDC':         'nmdc.co.in',
    'NOCIL':        'nocil.com',
    'OBEROIRLTY':   'oberoirealty.com',
    'OFSS':         'oracle.com',
    'PAGEIND':      'jockeyindia.com',
    'PATANJALI':    'patanjalifoods.com',
    'PEL':          'piramal.com',
    'PERSISTENT':   'persistent.com',
    'PETRONET':     'petronetlng.com',
    'PFC':          'pfcindia.com',
    'PIDILITIND':   'pidilite.com',
    'PIIND':        'piindustries.com',
    'PNB':          'pnbindia.in',
    'POLYCAB':      'polycab.com',
    'PVRINOX':      'pvrinox.com',
    'RAMCOCEM':     'ramcocements.com',
    'RBLBANK':      'rblbank.com',
    'RECLTD':       'recindia.nic.in',
    'RVNL':         'rvnl.org',
    'SAIL':         'sail.co.in',
    'SJVN':         'sjvn.nic.in',
    'SRF':          'srfindia.com',
    'SUPREMEIND':   'supreme.co.in',
    'SYNGENE':      'syngeneintl.com',
    'TATACOMM':     'tatacomm.com',
    'TATAELXSI':    'tataelxsi.com',
    'TATACHEM':     'tatachemicals.com',
    'TATAPOWER':    'tatapower.com',
    'TRENT':        'trentlimited.com',
    'TVSMOTOR':     'tvsmotor.com',
    'UBL':          'unitedbreweries.com',
    'UNITDSPR':     'diageoindia.com',
    'VOLTAS':       'voltas.com',
    'WHIRLPOOL':    'whirlpoolindia.com',
    'YESBANK':      'yesbank.in',
    'ZEEL':         'zee.com',
    'ZYDUSLIFE':    'zyduslife.com',
  };

  /// Cleans symbols by stripping index suffixes, mapping aliases.
  static String cleanSymbol(String symbol) {
    var clean = symbol.toUpperCase().trim();
    if (clean == '^NSEI' || clean == 'NSEI') return 'NIFTY50';
    if (clean == '^NSEBANK' || clean == 'NSEBANK') return 'BANKNIFTY';
    if (clean.startsWith('^')) {
      clean = clean.substring(1);
    }
    if (clean.contains('.')) {
      clean = clean.split('.').first;
    }
    return clean;
  }

  /// Primary logo URL using Google Favicons — reliable PNG, no CORS issues.
  static String getLogoUrl(String symbol) {
    final clean = cleanSymbol(symbol);
    final domain = domains[clean];
    if (domain == null) return '';
    return 'https://www.google.com/s2/favicons?domain=$domain&sz=128';
  }

  /// Fallback logo URL using Clearbit Logo API.
  static String getFallbackLogoUrl(String symbol) {
    final clean = cleanSymbol(symbol);
    final domain = domains[clean];
    if (domain == null) return '';
    return 'https://logo.clearbit.com/$domain';
  }

  /// Returns true if a logo source exists for this symbol.
  static bool hasLogo(String symbol) {
    final clean = cleanSymbol(symbol);
    return localAssets.containsKey(clean) || domains.containsKey(clean);
  }
}
