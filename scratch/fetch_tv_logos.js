const https = require('https');
const fs = require('fs');

const stocks = {
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
    'DIVISLAB': 'Divis Laboratories',
    'DRREDDY': 'Dr. Reddys Laboratories',
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
    'WIPRO': 'Wipro'
};

const indices = {
    'NIFTY50': 'NIFTY',
    'BANKNIFTY': 'BANKNIFTY',
    'FINNIFTY': 'CNXFIN',
    'MIDCAPNIFTY': 'MIDCPNIFTY',
    'SENSEX': 'SENSEX',
};

const allLogos = {};

function fetchLogoId(symbol, isIndex) {
    return new Promise((resolve) => {
        const query = isIndex ? symbol : symbol;
        const exchange = isIndex ? 'NSE' : 'NSE'; // TV sometimes uses BSE for sensex but NSE for Nifty
        const url = `https://symbol-search.tradingview.com/symbol_search/v3/?text=${query}&hl=1&exchange=${exchange}&lang=en&type=${isIndex ? 'index' : 'stock'}`;
        
        https.get(url, (res) => {
            let data = '';
            res.on('data', chunk => data += chunk);
            res.on('end', () => {
                try {
                    const parsed = JSON.parse(data);
                    const match = parsed.find(item => item.symbol === symbol || item.symbol === query);
                    if (match && match.logoid) {
                        allLogos[symbol] = match.logoid;
                    } else if (parsed.length > 0 && parsed[0].logoid) {
                        allLogos[symbol] = parsed[0].logoid;
                    }
                } catch(e) {}
                resolve();
            });
        }).on('error', () => resolve());
    });
}

async function run() {
    for (const symbol of Object.keys(stocks)) {
        await fetchLogoId(symbol, false);
    }
    for (const symbol of Object.keys(indices)) {
        await fetchLogoId(indices[symbol], true); // TV uses these names
        if (allLogos[indices[symbol]]) {
            allLogos[symbol] = allLogos[indices[symbol]];
        }
    }
    fs.writeFileSync('tv_logos.json', JSON.stringify(allLogos, null, 2));
    console.log('Done mapping logos.');
}

run();
