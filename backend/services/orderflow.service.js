const admin = require('firebase-admin');
const moment = require('moment-timezone');

/**
 * Orderflow Service - Manages buyer/seller count data
 */
class OrderflowService {
    constructor() {
        this.db = admin.firestore();
        this.collectionName = process.env.FIRESTORE_COLLECTION_ORDERFLOW || 'orderflow';
        this.timezone = process.env.TIMEZONE || 'Asia/Kolkata';
    }

    /**
     * Get simulated orderflow data based on candle size, symbol and momentum
     */
    getSimulatedData(candle) {
        const symbol = candle.symbol || 'NIFTY50';
        const range = Math.abs(candle.high - candle.low);
        const isGreen = candle.close >= candle.open;

        // Calculate duration in minutes (default to 5 for closed candles)
        const duration = Math.max(1, (candle.timeEnd - candle.timeStart) / (60 * 1000));
        const velocity = range / duration; // points per minute

        const isBankNifty = symbol.includes('BANKNIFTY');

        // Spike session tracking
        if (!this.spikeSustain) this.spikeSustain = {};
        if (!this.spikeSustain[symbol]) this.spikeSustain[symbol] = { startTime: 0, isActive: false };

        const spikeThreshold = isBankNifty ? 50 : 20;
        const isSpiking = velocity > spikeThreshold;

        if (isSpiking) {
            if (!this.spikeSustain[symbol].isActive) {
                this.spikeSustain[symbol].isActive = true;
                this.spikeSustain[symbol].startTime = Date.now();
            }
        } else {
            this.spikeSustain[symbol].isActive = false;
        }

        // Institutional check: 1 hour sustain
        const sustainDurationMs = Date.now() - this.spikeSustain[symbol].startTime;
        const isInstitutional = this.spikeSustain[symbol].isActive && sustainDurationMs > (60 * 60 * 1000);

        // Base ranges (BANKNIFTY is ~2.5x NIFTY50)
        let min, max, secondaryMin, secondaryMax;

        if (isBankNifty) {
            if (isSpiking) {
                min = 18000; max = 35000;
                secondaryMin = 1000; secondaryMax = 4000;
            } else if (velocity > 20) {
                min = 8000; max = 18000;
                secondaryMin = 2000; secondaryMax = 6000;
            } else {
                min = 3000; max = 8000;
                secondaryMin = 2000; secondaryMax = 6000;
            }
        } else {
            // NIFTY50
            if (isSpiking) {
                min = 9000; max = 18000;
                secondaryMin = 500; secondaryMax = 2000;
            } else if (velocity > 10) {
                min = 4000; max = 9000;
                secondaryMin = 1000; secondaryMax = 3000;
            } else {
                min = 1200; max = 4000;
                secondaryMin = 1000; secondaryMax = 3000;
            }
        }

        const primaryCount = Math.floor(Math.random() * (max - min + 1)) + min;
        const secondaryCount = Math.floor(Math.random() * (secondaryMin + Math.random() * (secondaryMax - secondaryMin)));

        // Simulate Imbalances (Stacked Orders)
        // Generate 0-3 imbalance levels where orders are "stacked"
        const imbalances = [];
        const numImbalances = Math.floor(Math.random() * 4); // 0 to 3

        for (let i = 0; i < numImbalances; i++) {
            // Pick a random price level within the candle range
            const priceLevel = Math.random() * (candle.high - candle.low) + candle.low;
            // Align to tick size (assuming 0.05 tick)
            const alignedPrice = Math.round(priceLevel * 20) / 20;

            imbalances.push({
                price: alignedPrice,
                // Randomly assign buy or sell imbalance
                type: Math.random() > 0.5 ? 'buy' : 'sell',
                // Size relative to primary volume
                size: Math.floor(primaryCount * (Math.random() * 0.5 + 0.2)) // 20-70% of total volume at this level
            });
        }

        return {
            buyerCount: isGreen ? primaryCount : secondaryCount,
            sellerCount: isGreen ? secondaryCount : primaryCount,
            isInstitutional: isInstitutional,
            imbalances: imbalances
        };
    }

    /**
     * Generate candle key
     */
    generateCandleKey(symbol, timestamp) {
        const time = moment(timestamp).tz(this.timezone);
        const minute = Math.floor(time.minute() / 5) * 5;
        const alignedTime = time.clone().minute(minute).second(0).millisecond(0);

        const dateStr = alignedTime.format('YYYYMMDD');
        const timeStr = alignedTime.format('HHmm');

        return `${symbol}-${dateStr}-${timeStr}`;
    }

    /**
     * Save orderflow data
     */
    async saveOrderflow(candleKey, buyerCount, sellerCount, updatedBy, isBigSignal = false, candleTime = null, isMediumSignal = false, footprint = null, broadcastPush = true) {
        try {
            // Extract symbol from candleKey (e.g., NIFTY50-20260104-0915)
            const symbol = candleKey.split('-')[0];

            // If merging with existing data, we should get the current doc first
            let existingFootprint = null;
            if (footprint) {
                const doc = await this.db.collection(this.collectionName).doc(candleKey).get();
                if (doc.exists) {
                    existingFootprint = doc.data().footprint;
                }
            }

            const data = {
                candleKey,
                symbol,
                buyerCount: parseInt(buyerCount),
                sellerCount: parseInt(sellerCount),
                isBigSignal: !!isBigSignal,
                isMediumSignal: !!isMediumSignal,
                footprint: this.mergeFootprints(existingFootprint, footprint),
                broadcastPush: !!broadcastPush,
                updatedBy,
                updatedAt: admin.firestore.FieldValue.serverTimestamp(),
                createdAt: admin.firestore.FieldValue.serverTimestamp()
            };

            if (candleTime) {
                data.candleTime = candleTime;
            }

            await this.db.collection(this.collectionName)
                .doc(candleKey)
                .set(data, { merge: true });

            console.log(`Orderflow saved for ${candleKey}`);
            return data;
        } catch (error) {
            console.error('Error saving orderflow:', error);
            throw error;
        }
    }

    /**
     * Get orderflow data by candle key
     */
    async getOrderflow(candleKey) {
        try {
            const doc = await this.db.collection(this.collectionName)
                .doc(candleKey)
                .get();

            if (doc.exists) {
                return doc.data();
            }
            return null;
        } catch (error) {
            console.error('Error getting orderflow:', error);
            throw error;
        }
    }

    /**
     * Get all orderflow data for a symbol and date
     */
    async getOrderflowBySymbolAndDate(symbol, date) {
        try {
            const dateStr = moment(date).tz(this.timezone).format('YYYYMMDD');
            const startKey = `${symbol}-${dateStr}-0000`;
            const endKey = `${symbol}-${dateStr}-2359`;

            const snapshot = await this.db.collection(this.collectionName)
                .where(admin.firestore.FieldPath.documentId(), '>=', startKey)
                .where(admin.firestore.FieldPath.documentId(), '<=', endKey)
                .get();

            const results = [];
            snapshot.forEach(doc => {
                results.push({
                    id: doc.id,
                    ...doc.data()
                });
            });

            return results;
        } catch (error) {
            console.error('Error querying orderflow:', error);
            throw error;
        }
    }

    /**
     * Get current trading date
     */
    getCurrentTradingDate() {
        return moment().tz(this.timezone).format('YYYYMMDD');
    }

    /**
     * Check if candle is from current trading day
     */
    isCurrentTradingDay(candleKey) {
        const currentDate = this.getCurrentTradingDate();
        return candleKey.includes(`-${currentDate}-`);
    }

    /**
     * Delete old orderflow data (for daily reset)
     */
    async deleteOldOrderflow(beforeDate) {
        try {
            const dateStr = moment(beforeDate).tz(this.timezone).format('YYYYMMDD');

            // Delete all documents with date before the specified date
            const snapshot = await this.db.collection(this.collectionName)
                .where(admin.firestore.FieldPath.documentId(), '<', `ZZZZ-${dateStr}`)
                .get();

            const batch = this.db.batch();
            let count = 0;

            snapshot.forEach(doc => {
                batch.delete(doc.ref);
                count++;
            });

            if (count > 0) {
                await batch.commit();
                console.log(`Deleted ${count} old orderflow records before ${dateStr}`);
            }

            return count;
        } catch (error) {
            console.error('Error deleting old orderflow:', error);
            throw error;
        }
    }

    /**
     * Merge orderflow data with candle
     */
    async mergeCandleWithOrderflow(candle) {
        let orderflow = await this.getOrderflow(candle.candleKey);

        if (!orderflow) {
            const simData = this.getSimulatedData(candle);
            orderflow = {
                buyerCount: simData.buyerCount,
                sellerCount: simData.sellerCount,
                isInstitutional: simData.isInstitutional
            };
        }

        return {
            ...candle,
            buyerCount: orderflow.buyerCount,
            sellerCount: orderflow.sellerCount,
            isInstitutional: orderflow.isInstitutional || false,
            isBigSignal: orderflow.isBigSignal || false,
            isMediumSignal: orderflow.isMediumSignal || false,
            imbalances: orderflow.imbalances || [],
            footprint: orderflow.footprint || null
        };
    }

    /**
     * Batch merge orderflow with multiple candles
     */
    async batchMergeCandles(candles) {
        try {
            // Extract all candle keys
            const candleKeys = candles.map(c => c.candleKey);

            // Fetch all orderflow data in batches (Firestore max 10 per 'in' query)
            const batchSize = 10;
            const orderflowMap = {};

            for (let i = 0; i < candleKeys.length; i += batchSize) {
                const batch = candleKeys.slice(i, i + batchSize);
                const snapshot = await this.db.collection(this.collectionName)
                    .where(admin.firestore.FieldPath.documentId(), 'in', batch)
                    .get();

                snapshot.forEach(doc => {
                    orderflowMap[doc.id] = doc.data();
                });
            }

            // Merge with candles using simulation as fallback
            return candles.map(candle => {
                const manualData = orderflowMap[candle.candleKey];

                if (manualData) {
                    return {
                        ...candle,
                        buyerCount: manualData.buyerCount,
                        sellerCount: manualData.sellerCount,
                        isInstitutional: manualData.isInstitutional || false,
                        isBigSignal: manualData.isBigSignal || false,
                        isMediumSignal: manualData.isMediumSignal || false,
                        imbalances: manualData.imbalances || [],
                        footprint: manualData.footprint || null
                    };
                } else {
                    const simData = this.getSimulatedData(candle);
                    return {
                        ...candle,
                        buyerCount: simData.buyerCount,
                        sellerCount: simData.sellerCount,
                        isInstitutional: simData.isInstitutional
                    };
                }
            });
        } catch (error) {
            console.error('Error batch merging candles:', error);
            // Return candles with simulated data on error
            return candles.map(candle => {
                const simData = this.getSimulatedData(candle);
                return {
                    ...candle,
                    buyerCount: simData.buyerCount,
                    sellerCount: simData.sellerCount,
                    isInstitutional: simData.isInstitutional,
                    imbalances: simData.imbalances || []
                };
            });
        }
    }

    /**
     * Merge Footprint Map
     */
    mergeFootprints(existing, incoming) {
        if (!existing) return incoming;
        if (!incoming) return existing;

        const merged = { ...existing };
        for (const [price, data] of Object.entries(incoming)) {
            if (merged[price]) {
                merged[price].buyVolume = (merged[price].buyVolume || 0) + (data.buyVolume || 0);
                merged[price].sellVolume = (merged[price].sellVolume || 0) + (data.sellVolume || 0);
            } else {
                merged[price] = data;
            }
        }
        return merged;
    }
}

module.exports = OrderflowService;
