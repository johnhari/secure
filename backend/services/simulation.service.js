const EventEmitter = require('events');

class SimulationService extends EventEmitter {
    constructor() {
        super();
        this.isActive = false;
        this.intervals = {};

        // Initial prices
        this.prices = {
            'NIFTY50': 21450.0,
            'BANKNIFTY': 47800.0
        };
    }

    start() {
        if (this.isActive) return;
        this.isActive = true;
        console.log('Starting market simulation...');

        // Start tick generation for each symbol
        Object.keys(this.prices).forEach(symbol => {
            this.intervals[symbol] = setInterval(() => {
                this.generateTick(symbol);
            }, 500); // 2 ticks per second for smoothness
        });
    }

    stop() {
        this.isActive = false;
        Object.values(this.intervals).forEach(clearInterval);
        this.intervals = {};
        console.log('Stopped market simulation.');
    }

    generateTick(symbol) {
        // Random price movement
        const change = (Math.random() - 0.5) * 5; // +/- 2.5 points
        this.prices[symbol] += change;

        // Ensure price has 2 decimal places
        const price = Math.round(this.prices[symbol] * 100) / 100;

        const tick = {
            symbol: symbol,
            price: price,
            volume: Math.floor(Math.random() * 100) + 10,
            timestamp: Date.now(),
            // Mock OHLC for current minute (simplified)
            open: price,
            high: price + Math.random(),
            low: price - Math.random(),
            ltp: price
        };

        this.emit('tick', tick);
    }
}

module.exports = SimulationService;
