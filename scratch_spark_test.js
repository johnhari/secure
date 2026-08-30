const axios = require('axios');

const NIFTY_STOCKS = [
    'ADANIENT', 'ADANIPORTS', 'APOLLOHOSP', 'ASIANPAINT', 'AXISBANK',
    'BAJAJ-AUTO', 'BAJFINANCE', 'BAJAJFINSV', 'BPCL', 'BHARTIARTL',
    'BRITANNIA', 'CIPLA', 'COALINDIA', 'DIVISLAB', 'DRREDDY',
    'EICHERMOT', 'GRASIM', 'HCLTECH', 'HDFCBANK', 'HDFCLIFE',
    'HEROMOTOCO', 'HINDALCO', 'HINDUNILVR', 'ICICIBANK', 'ITC',
    'INDUSINDBK', 'INFY', 'JSWSTEEL', 'KOTAKBANK', 'LTIM',
    'LT', 'M&M', 'MARUTI', 'NTPC', 'NESTLEIND',
    'ONGC', 'POWERGRID', 'RELIANCE', 'SBILIFE', 'SBIN',
    'SHRIRAMFIN', 'SUNPHARMA', 'TCS', 'TATACONSUM', 'TATAMOTORS',
    'TATASTEEL', 'TECHM', 'TITAN', 'ULTRACEMCO', 'WIPRO'
];

async function testSpark() {
    const chunk = NIFTY_STOCKS.slice(0, 15);
    const symbols = chunk.map(s => {
        if (s.startsWith('^') || s.endsWith('.NS')) return s;
        return `${s}.NS`;
    }).join(',');

    const url = `https://query1.finance.yahoo.com/v7/finance/spark?symbols=${symbols}&range=1d&interval=5m`;
    const headers = {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/121.0.0.0 Safari/537.36',
        'Accept': '*/*',
        'Accept-Language': 'en-US,en;q=0.9',
        'Origin': 'https://finance.yahoo.com',
        'Referer': 'https://finance.yahoo.com/'
    };

    try {
        console.log('Fetching chunk of 15 spark data from Yahoo...');
        const response = await axios.get(url, { headers });
        console.log('Status:', response.status);
        if (response.data && response.data.spark && response.data.spark.result) {
            console.log('Number of symbols returned:', response.data.spark.result.length);
            const firstResult = response.data.spark.result[0];
            console.log('First symbol details:', JSON.stringify(firstResult.symbol));
            console.log('First symbol response:', JSON.stringify(firstResult.response[0]?.meta));
        } else {
            console.log('Response structure invalid:', response.data);
        }
    } catch (err) {
        console.error('Error fetching spark data:', err.message);
        if (err.response) {
            console.error('Response Status:', err.response.status);
            console.error('Response Data:', err.response.data);
        }
    }
}

testSpark();
