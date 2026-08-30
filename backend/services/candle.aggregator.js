const moment = require('moment-timezone');

/**
 * Candle Aggregator - Aggregates ticks into 5-minute OHLC candles
 */
class CandleAggregator {
    constructor(timezone = 'Asia/Kolkata') {
        this.timezone = timezone;
        this.currentCandles = {}; // symbol -> current candle
        this.candleInterval = 5; // minutes
        this.listeners = [];
        this.tickListeners = [];
    }

    /**
     * Add listener for completed candles
     */
    onCandleComplete(callback) {
        this.listeners.push(callback);
    }

    /**
     * Add listener for tick updates (every price change)
     */
    onTickUpdate(callback) {
        this.tickListeners.push(callback);
    }

    /**
     * Get candle key for a timestamp
     */
    getCandleKey(symbol, timestamp) {
        const time = moment(timestamp).tz(this.timezone);
        const minute = Math.floor(time.minute() / this.candleInterval) * this.candleInterval;

        const alignedTime = time.clone().minute(minute).second(0).millisecond(0);

        const dateStr = alignedTime.format('YYYYMMDD');
        const timeStr = alignedTime.format('HHmm');

        return `${symbol}-${dateStr}-${timeStr}`;
    }

    /**
     * Get candle start time
     */
    getCandleStartTime(timestamp) {
        const time = moment(timestamp).tz(this.timezone);
        const minute = Math.floor(time.minute() / this.candleInterval) * this.candleInterval;
        return time.clone().minute(minute).second(0).millisecond(0);
    }

    /**
     * Get candle end time
     */
    getCandleEndTime(startTime) {
        return startTime.clone().add(this.candleInterval, 'minutes');
    }

    /**
     * Process a tick and update/create candles
     */
    processTick(tick) {
        const { symbol, price, volume, timestamp } = tick;

        if (!symbol || !price) {
            return;
        }

        const candleStartTime = this.getCandleStartTime(timestamp);
        const candleKey = this.getCandleKey(symbol, timestamp);

        // Check if we need to complete the previous candle
        if (this.currentCandles[symbol] && this.currentCandles[symbol].candleKey !== candleKey) {
            // Previous candle is complete
            const completedCandle = { ...this.currentCandles[symbol] };
            this.emitCandle(completedCandle);

            // Start new candle
            this.currentCandles[symbol] = null;
        }

        // Create or update current candle
        if (!this.currentCandles[symbol]) {
            // Create new candle
            this.currentCandles[symbol] = {
                symbol,
                candleKey,
                timeStart: candleStartTime.valueOf(),
                timeEnd: this.getCandleEndTime(candleStartTime).valueOf(),
                open: price,
                high: price,
                low: price,
                close: price,
                volume: volume || 0,
                tickCount: 1
            };
        } else {
            // Update existing candle
            const candle = this.currentCandles[symbol];
            candle.high = Math.max(candle.high, price);
            candle.low = Math.min(candle.low, price);
            candle.close = price;
            candle.volume += (volume || 0);
            candle.tickCount++;
        }

        // Emit update for every tick
        this.emitTickUpdate(this.currentCandles[symbol]);
    }

    /**
     * Force complete current candle (useful for testing or market close)
     */
    forceCompleteCandle(symbol) {
        if (this.currentCandles[symbol]) {
            const completedCandle = { ...this.currentCandles[symbol] };
            this.emitCandle(completedCandle);
            this.currentCandles[symbol] = null;
        }
    }

    /**
     * Emit candle to all listeners
     */
    emitCandle(candle) {
        console.log(`Candle complete: ${candle.candleKey} O:${candle.open} H:${candle.high} L:${candle.low} C:${candle.close}`);
        this.listeners.forEach(callback => callback(candle));
    }

    /**
     * Emit tick update to all listeners
     */
    emitTickUpdate(candle) {
        this.tickListeners.forEach(callback => callback(candle));
    }

    /**
     * Get current candle (in progress) for a symbol
     */
    getCurrentCandle(symbol) {
        return this.currentCandles[symbol] || null;
    }

    /**
     * Check if market is open
     */
    isMarketOpen() {
        const now = moment().tz(this.timezone);
        const currentTime = now.format('HHmm');

        const marketOpen = process.env.MARKET_OPEN_TIME?.replace(':', '') || '0915';
        const marketClose = process.env.MARKET_CLOSE_TIME?.replace(':', '') || '1540';

        // Check if it's a weekday (Mon-Fri)
        const isWeekday = now.day() >= 1 && now.day() <= 5;

        return isWeekday && currentTime >= marketOpen && currentTime < marketClose;
    }

    /**
     * Schedule market close candle completion
     */
    scheduleMarketCloseComplete() {
        const now = moment().tz(this.timezone);
        const marketCloseTime = process.env.MARKET_CLOSE_TIME || '15:40';
        const [hour, minute] = marketCloseTime.split(':');

        const closeTime = now.clone().hour(parseInt(hour)).minute(parseInt(minute)).second(0);

        if (now.isAfter(closeTime)) {
            // Market already closed today, schedule for tomorrow
            closeTime.add(1, 'day');
        }

        const msUntilClose = closeTime.diff(now);

        setTimeout(() => {
            console.log('Market close - completing all candles');
            Object.keys(this.currentCandles).forEach(symbol => {
                this.forceCompleteCandle(symbol);
            });

            // Schedule next day's market close
            this.scheduleMarketCloseComplete();
        }, msUntilClose);

        console.log(`Market close scheduled for ${closeTime.format('YYYY-MM-DD HH:mm:ss')}`);
    }
}

module.exports = CandleAggregator;
