class NiftyStocks {
  static const Map<String, String> stocks = {
    // --- Nifty 50 constituents ---
    'ADANIENT': 'Adani Enterprises',
    'ADANIPORTS': 'Adani Ports & SEZ',
    'APOLLOHOSP': 'Apollo Hospitals',
    'ASIANPAINT': 'Asian Paints',
    'AXISBANK': 'Axis Bank',
    'BAJAJ-AUTO': 'Bajaj Auto',
    'BAJFINANCE': 'Bajaj Finance',
    'BAJAJFINSV': 'Bajaj Finserv',
    'BPCL': 'Bharat Petroleum',
    'BHARTIARTL': 'Bharti Airtel',
    'BRITANNIA': 'Britannia Industries',
    'CIPLA': 'Cipla',
    'COALINDIA': 'Coal India',
    'DIVISLAB': 'Divi\'s Laboratories',
    'DRREDDY': 'Dr. Reddy\'s Laboratories',
    'EICHERMOT': 'Eicher Motors',
    'GRASIM': 'Grasim Industries',
    'HCLTECH': 'HCL Technologies',
    'HDFCBANK': 'HDFC Bank',
    'HDFCLIFE': 'HDFC Life Insurance',
    'HEROMOTOCO': 'Hero MotoCorp',
    'HINDALCO': 'Hindalco Industries',
    'HINDUNILVR': 'Hindustan Unilever',
    'ICICIBANK': 'ICICI Bank',
    'ITC': 'ITC Limited',
    'INDUSINDBK': 'IndusInd Bank',
    'INFY': 'Infosys',
    'JSWSTEEL': 'JSW Steel',
    'KOTAKBANK': 'Kotak Mahindra Bank',
    'LTIM': 'LTIMindtree',
    'LT': 'Larsen & Toubro',
    'M&M': 'Mahindra & Mahindra',
    'MARUTI': 'Maruti Suzuki',
    'NTPC': 'NTPC Limited',
    'NESTLEIND': 'Nestle India',
    'ONGC': 'Oil & Natural Gas Corp',
    'POWERGRID': 'Power Grid Corp',
    'RELIANCE': 'Reliance Industries',
    'SBILIFE': 'SBI Life Insurance',
    'SBIN': 'State Bank of India',
    'SHRIRAMFIN': 'Shriram Finance',
    'SUNPHARMA': 'Sun Pharmaceutical',
    'TCS': 'Tata Consultancy Services',
    'TATACONSUM': 'Tata Consumer Products',
    'TATAMOTORS': 'Tata Motors',
    'TATASTEEL': 'Tata Steel',
    'TECHM': 'Tech Mahindra',
    'TITAN': 'Titan Company',
    'ULTRACEMCO': 'UltraTech Cement',
    'WIPRO': 'Wipro',

    // --- Other Major NSE F&O Stocks ---
    'AARTIIND': 'Aarti Industries',
    'ABB': 'ABB India',
    'ABBOTINDIA': 'Abbott India',
    'ABCAPITAL': 'Aditya Birla Capital',
    'ABFRL': 'Aditya Birla Fashion & Retail',
    'ACC': 'ACC Limited',
    'ADANIPOWER': 'Adani Power',
    'ALKEM': 'Alkem Laboratories',
    'AMBUJACEM': 'Ambuja Cements',
    'ASTRAL': 'Astral Limited',
    'ATUL': 'Atul Limited',
    'AUBANK': 'AU Small Finance Bank',
    'AUROPHARMA': 'Aurobindo Pharma',
    'BALKRISIND': 'Balkrishna Industries',
    'BALRAMCHIN': 'Balrampur Chini Mills',
    'BANDHANBNK': 'Bandhan Bank',
    'BANKBARODA': 'Bank of Baroda',
    'BATAINDIA': 'Bata India',
    'BEL': 'Bharat Electronics',
    'BHEL': 'Bharat Heavy Electricals',
    'BIOCON': 'Biocon Limited',
    'BOSCHLTD': 'Bosch Limited',
    'CANBK': 'Canara Bank',
    'CANFINHOME': 'Can Fin Homes',
    'CHAMBLFERT': 'Chambal Fertilisers',
    'CHOLAFIN': 'Cholamandalam Investment',
    'COCHINSHIP': 'Cochin Shipyard',
    'COFORGE': 'Coforge Limited',
    'CONCOR': 'Container Corporation',
    'COROMANDEL': 'Coromandel International',
    'CROMPTON': 'Crompton Greaves Consumer',
    'CUMMINSIND': 'Cummins India',
    'DLF': 'DLF Limited',
    'DEEPAKNTR': 'Deepak Nitrite',
    'DELHIVERY': 'Delhivery Limited',
    'ESCORTS': 'Escorts Kubota',
    'EXIDEIND': 'Exide Industries',
    'FEDERALBNK': 'Federal Bank',
    'GLENMARK': 'Glenmark Pharmaceuticals',
    'GMRINFRA': 'GMR Airports Infrastructure',
    'GNFC': 'Gujarat Narmada Valley Fertilizers',
    'GODREJCP': 'Godrej Consumer Products',
    'GODREJPROP': 'Godrej Properties',
    'GRANULES': 'Granules India',
    'GUJGASLTD': 'Gujarat Gas Limited',
    'HAL': 'Hindustan Aeronautics',
    'HAVELLS': 'Havells India',
    'HDFCAMC': 'HDFC Asset Management',
    'HINDCOPPER': 'Hindustan Copper',
    'HINDPETRO': 'Hindustan Petroleum',
    'IPCALAB': 'IPCA Laboratories',
    'IDFC': 'IDFC Limited',
    'IDFCFIRSTB': 'IDFC First Bank',
    'INDIACEM': 'The India Cements',
    'INDIAMART': 'IndiaMART InterMESH',
    'INDIGO': 'InterGlobe Aviation',
    'IOC': 'Indian Oil Corporation',
    'IRCTC': 'IRCTC Limited',
    'IRFC': 'Indian Railway Finance Corp',
    'JINDALSTEL': 'Jindal Steel & Power',
    'JKCEMENT': 'JK Cement',
    'JSL': 'Jindal Stainless',
    'JUBLFOOD': 'Jubilant FoodWorks',
    'KEI': 'KEI Industries',
    'L&TFH': 'L&T Finance Holdings',
    'LALPATHLAB': 'Dr. Lal PathLabs',
    'LICHSGFIN': 'LIC Housing Finance',
    'LUPIN': 'Lupin Limited',
    'MRF': 'MRF Limited',
    'M&MFIN': 'Mahindra & Mahindra Financial',
    'MANAPPURAM': 'Manappuram Finance',
    'MARICO': 'Marico Limited',
    'MCX': 'Multi Commodity Exchange',
    'METROPOLIS': 'Metropolis Healthcare',
    'MFSL': 'Max Financial Services',
    'MGL': 'Mahanagar Gas',
    'MOTILALOFS': 'Motilal Oswal Financial',
    'MPHASIS': 'Mphasis Limited',
    'MRPL': 'Mangalore Refinery & Petrochem',
    'MUTHOOTFIN': 'Muthoot Finance',
    'NATIONALUM': 'National Aluminium Co',
    'NAVINFLUOR': 'Navin Fluorine International',
    'NLCINDIA': 'NLC India Limited',
    'NMDC': 'NMDC Limited',
    'NOCIL': 'NOCIL Limited',
    'OBEROIRLTY': 'Oberoi Realty',
    'OFSS': 'Oracle Financial Services',
    'PAGEIND': 'Page Industries',
    'PATANJALI': 'Patanjali Foods',
    'PEL': 'Piramal Enterprises',
    'PERSISTENT': 'Persistent Systems',
    'PETRONET': 'Petronet LNG',
    'PFC': 'Power Finance Corporation',
    'PIDILITIND': 'Pidilite Industries',
    'PIIND': 'PI Industries',
    'PNB': 'Punjab National Bank',
    'POLYCAB': 'Polycab India',
    'PVRINOX': 'PVR INOX Limited',
    'RAMCOCEM': 'The Ramco Cements',
    'RBLBANK': 'RBL Bank',
    'RECLTD': 'REC Limited',
    'RVNL': 'Rail Vikas Nigam',
    'SAIL': 'Steel Authority of India',
    'SJVN': 'SJVN Limited',
    'SRF': 'SRF Limited',
    'SUPREMEIND': 'Supreme Industries',
    'SYNGENE': 'Syngene International',
    'TATACOMM': 'Tata Communications',
    'TATAELXSI': 'Tata Elxsi',
    'TATACHEM': 'Tata Chemicals',
    'TATAPOWER': 'Tata Power',
    'TRENT': 'Trent Limited',
    'TVSMOTOR': 'TVS Motor Company',
    'UBL': 'United Breweries',
    'UNITDSPR': 'United Spirits',
    'VOLTAS': 'Voltas Limited',
    'WHIRLPOOL': 'Whirlpool of India',
    'YESBANK': 'Yes Bank',
    'ZEEL': 'Zee Entertainment Enterprises',
    'ZYDUSLIFE': 'Zydus Lifesciences',
  };

  static const Map<String, String> indices = {
    'NIFTY50': 'NIFTY 50',
    'BANKNIFTY': 'BANK NIFTY',
    'FINNIFTY': 'FIN NIFTY',
    'MIDCAPNIFTY': 'MIDCAP NIFTY',
    'SENSEX': 'SENSEX',
    'NIFTYIT': 'NIFTY IT',
    'NIFTYAUTO': 'NIFTY AUTO',
    'NIFTYMETAL': 'NIFTY METAL',
    'NIFTYPHARMA': 'NIFTY PHARMA',
    'NIFTYFMCG': 'NIFTY FMCG',
    'NIFTYINFRA': 'NIFTY INFRA',
    'NIFTYENERGY': 'NIFTY ENERGY',
    'NIFTYMEDIA': 'NIFTY MEDIA',
    'NIFTYREALTY': 'NIFTY REALTY',
    'NIFTYPSE': 'NIFTY PSE',
  };

  /// The 4 core index symbols available to Index-Only subscribers.
  static const Map<String, String> indexOnlySymbols = {
    'NIFTY50': 'NIFTY 50',
    'BANKNIFTY': 'BANK NIFTY',
    'FINNIFTY': 'FIN NIFTY',
    'SENSEX': 'SENSEX',
  };

  /// Returns true if [symbol] is accessible to index-only plan users.
  static bool isIndexOnlyAllowed(String symbol) =>
      indexOnlySymbols.containsKey(symbol.toUpperCase());

  /// Search matching indices and stocks. Returns map of matching symbol to name.
  static Map<String, String> search(String query) {
    if (query.isEmpty) return {};
    final lowerQuery = query.toLowerCase();
    final Map<String, String> matches = {};

    // Check indices first
    indices.forEach((symbol, name) {
      if (symbol.toLowerCase().contains(lowerQuery) || 
          name.toLowerCase().contains(lowerQuery)) {
        matches[symbol] = name;
      }
    });

    // Check stocks
    stocks.forEach((symbol, name) {
      if (symbol.toLowerCase().contains(lowerQuery) || 
          name.toLowerCase().contains(lowerQuery)) {
        matches[symbol] = name;
      }
    });

    return matches;
  }

  /// Search only the 4 index-only symbols (for Index-Only subscribers).
  static Map<String, String> searchIndicesOnly(String query) {
    if (query.isEmpty) return Map.from(indexOnlySymbols);
    final lowerQuery = query.toLowerCase();
    final Map<String, String> matches = {};
    indexOnlySymbols.forEach((symbol, name) {
      if (symbol.toLowerCase().contains(lowerQuery) ||
          name.toLowerCase().contains(lowerQuery)) {
        matches[symbol] = name;
      }
    });
    return matches;
  }
}
