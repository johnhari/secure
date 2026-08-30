const axios = require('axios');
const EventEmitter = require('events');

class YahooService extends EventEmitter {
    constructor() {
        super();
        this.baseUrl = 'https://query1.finance.yahoo.com/v8/finance/chart';
        this.symbols = {
            'NIFTY50': '^NSEI',
            'BANKNIFTY': '^NSEBANK'
        };
        this.pollingInterval = 5000; // 5 seconds
        this.pollingTimer = null;
        this.isAuthenticated = true; // No auth needed for public Yahoo API
    }

    /**
     * Fetch Intraday Candles
     */
    async fetchIntradayCandles(symbol, interval = '5minute', range = '3d') {
        let yahooSymbol = this.symbols[symbol];
        if (!yahooSymbol) {
            if (symbol.startsWith('^') || symbol.endsWith('.NS')) {
                yahooSymbol = symbol;
            } else {
                yahooSymbol = `${symbol}.NS`;
            }
        }

        // Yahoo intervals: 1m, 2m, 5m, 15m, 30m, 60m, 90m, 1h, 1d, 5d, 1wk, 1mo, 3mo
        const yahooInterval = interval === '5minute' ? '5m' : '1m';

        try {
            const url = `${this.baseUrl}/${yahooSymbol}?interval=${yahooInterval}&range=${range}&includePrePost=false`;
            console.log(`Fetching Yahoo historical data for ${symbol}: ${url}`);

            const response = await axios.get(url, {
                headers: {
                    'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36'
                }
            });

            if (response.data && response.data.chart && response.data.chart.result) {
                const result = response.data.chart.result[0];
                const timestamps = result.timestamp;
                const quote = result.indicators.quote[0];

                if (!timestamps || !quote) return [];

                const candles = [];
                for (let i = 0; i < timestamps.length; i++) {
                    if (quote.open[i] === null) continue;

                    candles.push({
                        timestamp: timestamps[i] * 1000,
                        open: quote.open[i],
                        high: quote.high[i],
                        low: quote.low[i],
                        close: quote.close[i],
                        volume: quote.volume[i] || 0,
                        symbol: symbol
                    });
                }
                return candles;
            }
            return [];
        } catch (error) {
            console.error(`Error fetching Yahoo candles for ${symbol}:`, error.message);
            return [];
        }
    }

    /**
     * Start polling for live data
     */
    startPolling() {
        if (this.pollingTimer) return;

        console.log('Starting Yahoo Finance polling...');
        this.pollingTimer = setInterval(() => {
            this.pollAllSymbols();
        }, this.pollingInterval);

        // Initial poll
        this.pollAllSymbols();
    }

    async pollAllSymbols() {
        for (const symbol of Object.keys(this.symbols)) {
            await this.pollSymbol(symbol);
        }
    }

    async pollSymbol(symbol) {
        try {
            const yahooSymbol = this.symbols[symbol];
            const url = `${this.baseUrl}/${yahooSymbol}?interval=1m&range=1d&includePrePost=false`;

            const response = await axios.get(url, {
                headers: {
                    'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36'
                },
                timeout: 5000
            });

            if (response.data && response.data.chart && response.data.chart.result) {
                const result = response.data.chart.result[0];
                const meta = result.meta;
                const price = meta.regularMarketPrice;

                if (price) {
                    const tick = {
                        symbol: symbol,
                        price: price,
                        volume: meta.regularMarketVolume || 0,
                        timestamp: Date.now(),
                        // Yahoo doesn't give full OHLC for the tick in meta usually, 
                        // but we can provide the last regular market OHLC if needed.
                        open: meta.chartPreviousClose || price, // Simple approximation if needed
                        high: price,
                        low: price
                    };
                    this.emit('tick', tick);
                }
            }
        } catch (error) {
            console.error(`Error polling Yahoo for ${symbol}:`, error.message);
        }
    }

    /**
     * Close connection
     */
    close() {
        if (this.pollingTimer) {
            clearInterval(this.pollingTimer);
            this.pollingTimer = null;
        }
    }
}

async function initializeYahoo() {
    const service = new YahooService();
    // No auth step needed for Yahoo
    service.startPolling();
    return service;
}

module.exports = {
    YahooService,
    initializeYahoo
};
