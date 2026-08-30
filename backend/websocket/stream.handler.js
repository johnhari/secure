const { extractTokenFromWS, verifyWSToken } = require('../middleware/auth.middleware');
const CandleAggregator = require('../services/candle.aggregator');
const fcmService = require('../services/fcm.service');
const OrderflowService = require('../services/orderflow.service');

const candleAggregator = new CandleAggregator();
const orderflowService = new OrderflowService();

const HEAVY_ACTIVITY_THRESHOLD = 1000;
const lastAlertTime = new Map(); // Prevent alert spamming

// Store for active WebSocket clients
const clients = new Map();

/**
 * Setup WebSocket stream handler
 */
function setupStreamHandler(wss, dataService) {
    // Listen to candles from aggregator
    candleAggregator.onCandleComplete(async (candle) => {
        // Merge with orderflow data
        const candleWithOrderflow = await orderflowService.mergeCandleWithOrderflow(candle);

        // Broadcast to all subscribed clients
        broadcastCandle(candleWithOrderflow);
    });

    // Listen to tick updates for real-time price info
    candleAggregator.onTickUpdate(async (candle) => {
        // Merge with orderflow data
        const candleWithOrderflow = await orderflowService.mergeCandleWithOrderflow(candle);

        // Check for heavy activity
        const { symbol, buyerCount, sellerCount } = candleWithOrderflow;
        if ((buyerCount && buyerCount >= HEAVY_ACTIVITY_THRESHOLD) ||
            (sellerCount && sellerCount >= HEAVY_ACTIVITY_THRESHOLD)) {
            const now = Date.now();
            const lastAlert = lastAlertTime.get(symbol) || 0;

            // Alert at most once every 5 minutes per symbol
            if (now - lastAlert > 5 * 60 * 1000) {
                const type = buyerCount >= HEAVY_ACTIVITY_THRESHOLD ? 'BUYING' : 'SELLING';
                const count = buyerCount >= HEAVY_ACTIVITY_THRESHOLD ? buyerCount : sellerCount;

                // fcmService.sendHeavyActivityAlert(symbol, type, count);
                console.log(`[Notification] Skipped heavy activity alert for ${symbol} (${type}: ${count})`);
                lastAlertTime.set(symbol, now);
            }
        }

        // Broadcast to all subscribed clients
        broadcastCandle(candleWithOrderflow);
    });

    // Connect data service tick stream to aggregator
    if (dataService) {
        dataService.on('tick', (tick) => {
            candleAggregator.processTick(tick);
        });

        dataService.on('error', (error) => {
            console.error('Data service error:', error);
            // Broadcast error to clients
            broadcastMessage({
                type: 'error',
                message: 'Market data service error',
                dataSource: 'live',
                status: 'disconnected'
            });
        });

        // Broadcast connection status
        const sourceName = dataService?.constructor.name === 'MStockService' ? 'mstock' : (dataService?.constructor.name === 'YahooService' ? 'yahoo' : 'simulated');
        broadcastMessage({
            type: 'status',
            dataSource: sourceName,
            status: 'connected',
            message: `Live data from ${sourceName.toUpperCase()}`
        });
    } else {
        // No market service
        broadcastMessage({
            type: 'status',
            dataSource: 'simulated',
            status: 'disconnected',
            message: 'Market data API not connected - simulated data'
        });
    }

    // Schedule market close candle completion
    candleAggregator.scheduleMarketCloseComplete();

    // Handle WebSocket connections
    wss.on('connection', async (ws, request) => {
        console.log('New WebSocket connection attempt');

        try {
            // Extract and verify token
            const { token, deviceId } = extractTokenFromWS(request);
            const user = await verifyWSToken(token, deviceId);

            console.log(`WebSocket authenticated: ${user.uid} (${user.role}) on device ${deviceId}`);

            // Store client info
            const clientId = generateClientId();
            clients.set(clientId, {
                ws,
                user,
                deviceId,
                subscriptions: [] // instruments subscribed to
            });

            // Send welcome message
            ws.send(JSON.stringify({
                type: 'connected',
                message: 'Connected to Orderflow stream',
                user: {
                    uid: user.uid,
                    role: user.role
                },
                dataSource: {
                    type: dataService?.constructor.name === 'MStockService' ? 'mstock' : (dataService?.constructor.name === 'YahooService' ? 'yahoo' : 'simulated'),
                    status: dataService ? 'connected' : 'disconnected',
                    message: dataService?.constructor.name === 'MStockService' ? 'Live m.Stock Binary Feed' : (dataService?.constructor.name === 'YahooService' ? 'Live Yahoo Finance data' : 'Simulated data')
                }
            }));

            // Handle incoming messages
            ws.on('message', async (message) => {
                try {
                    const data = JSON.parse(message.toString());
                    await handleClientMessage(clientId, data, dataService);
                } catch (error) {
                    console.error('Error handling client message:', error);
                    ws.send(JSON.stringify({
                        type: 'error',
                        message: 'Invalid message format'
                    }));
                }
            });

            // Handle disconnect
            ws.on('close', () => {
                console.log(`Client disconnected: ${clientId}`);
                clients.delete(clientId);
            });

            // Handle errors
            ws.on('error', (error) => {
                console.error(`WebSocket error for client ${clientId}:`, error);
                clients.delete(clientId);
            });

        } catch (error) {
            console.error('WebSocket authentication failed:', error.message);

            let errorMessage = 'Authentication failed';
            if (error.message === 'MULTIPLE_DEVICE_LOGIN') {
                errorMessage = 'You are already logged in on another device.';
            } else if (error.message === 'UNAPPROVED_USER') {
                errorMessage = 'Access Pending: Please make payment to proceed.';
            }

            ws.send(JSON.stringify({
                type: 'error',
                message: errorMessage,
                code: error.message
            }));

            setTimeout(() => ws.close(), 100);
        }
    });

    console.log('WebSocket stream handler initialized');
}

/**
 * Handle client messages
 */
async function handleClientMessage(clientId, data, dataService) {
    const client = clients.get(clientId);
    if (!client) return;

    const { ws, user } = client;

    switch (data.type) {
        case 'subscribe':
            // Subscribe to instruments
            if (data.instruments && Array.isArray(data.instruments)) {
                client.subscriptions = data.instruments;

                console.log(`Client ${clientId} subscribed to: ${client.subscriptions.join(', ')}`);

                ws.send(JSON.stringify({
                    type: 'subscribed',
                    instruments: client.subscriptions
                }));

                // Fetch and send historical candles
                for (const symbol of client.subscriptions) {
                    try {
                        if (dataService && dataService.fetchIntradayCandles) {
                            console.log(`Fetching history for ${symbol}...`);
                            const histCandles = await dataService.fetchIntradayCandles(symbol, '5minute');

                            // Map to internal format and attach candleKey
                            const formattedCandles = histCandles.map(c => {
                                const candleKey = candleAggregator.getCandleKey(symbol, c.timestamp);
                                return {
                                    ...c,
                                    candleKey,
                                    timeStart: c.timestamp,
                                    timeEnd: c.timestamp + (5 * 60 * 1000)
                                };
                            });

                            // Merge with orderflow in batch
                            const mergedCandles = await orderflowService.batchMergeCandles(formattedCandles);

                            console.log(`Sending ${mergedCandles.length} historical candles for ${symbol}`);

                            // Send in batches to avoid overwhelming the client
                            const batchSize = 20;
                            for (let i = 0; i < mergedCandles.length; i += batchSize) {
                                const chunk = mergedCandles.slice(i, i + batchSize);
                                chunk.forEach(candle => {
                                    ws.send(JSON.stringify({
                                        type: 'candle',
                                        data: candle
                                    }));
                                });
                            }
                        }
                    } catch (error) {
                        console.error(`Error sending history for ${symbol}:`, error);
                    }

                    // Also send the very latest in-progress candle from aggregator
                    const currentCandle = candleAggregator.getCurrentCandle(symbol);
                    if (currentCandle) {
                        const candleWithOrderflow = await orderflowService.mergeCandleWithOrderflow(currentCandle);
                        ws.send(JSON.stringify({
                            type: 'candle',
                            data: candleWithOrderflow
                        }));
                    }
                }
            }
            break;

        case 'unsubscribe':
            // Unsubscribe from instruments
            if (data.instruments && Array.isArray(data.instruments)) {
                client.subscriptions = client.subscriptions.filter(i =>
                    !data.instruments.includes(i)
                );

                console.log(`Client ${clientId} unsubscribed from instruments`);

                ws.send(JSON.stringify({
                    type: 'unsubscribed',
                    instruments: data.instruments
                }));
            }
            break;

        case 'ping':
            // Heartbeat
            ws.send(JSON.stringify({
                type: 'pong',
                timestamp: Date.now()
            }));
            break;

        default:
            ws.send(JSON.stringify({
                type: 'error',
                message: 'Unknown message type'
            }));
    }
}

/**
 * Broadcast candle to subscribed clients
 */
function broadcastCandle(candle) {
    const message = JSON.stringify({
        type: 'candle',
        data: candle
    });

    clients.forEach((client, clientId) => {
        if (client.subscriptions.includes(candle.symbol)) {
            try {
                client.ws.send(message);
            } catch (error) {
                console.error(`Error sending to client ${clientId}:`, error);
            }
        }
    });
}

/**
 * Broadcast message to all clients
 */
function broadcastMessage(message) {
    const payload = JSON.stringify(message);

    clients.forEach((client, clientId) => {
        try {
            client.ws.send(payload);
        } catch (error) {
            console.error(`Error broadcasting to client ${clientId}:`, error);
        }
    });
}

/**
 * Generate unique client ID
 */
function generateClientId() {
    return `client_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`;
}

module.exports = {
    setupStreamHandler
};
