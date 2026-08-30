const axios = require('axios');
const speakeasy = require('speakeasy');
const WebSocket = require('ws');
const EventEmitter = require('events');

class MStockService extends EventEmitter {
    constructor() {
        super();
        this.sessionToken = null;
        this.wsConnection = null;
        this.isAuthenticated = false;
        this.reconnectAttempts = 0;
        this.maxReconnectAttempts = 10;
        this.reconnectDelay = 5000;

        this.config = {
            appCode: process.env.MSTOCK_APP_CODE,
            userId: process.env.MSTOCK_USER_ID,
            password: process.env.MSTOCK_PASSWORD,
            totpSecret: process.env.MSTOCK_TOTP_SECRET,
            privateKey: process.env.MSTOCK_PRIVATE_KEY || process.env.MSTOCK_APP_CODE,
            apiUrl: process.env.MSTOCK_API_URL || 'https://api.mstock.trade',
            wsUrl: process.env.MSTOCK_WS_URL || 'wss://ws.mstock.trade'
        };

        // Instruments to subscribe to
        this.instruments = {
            'NIFTY50': { exchange: 'NSE', exchangeCode: '1', token: 'Nifty 50', instrumentToken: '26000' },
            'BANKNIFTY': { exchange: 'NSE', exchangeCode: '1', token: 'Nifty Bank', instrumentToken: '26009' }
        };
    }

    /**
     * Fetch Intraday Candles
     */
    async fetchIntradayCandles(symbol, interval = '5minute') {
        if (!this.isAuthenticated) {
            throw new Error('Not authenticated');
        }

        const instrument = this.instruments[symbol];
        if (!instrument) {
            throw new Error(`Unknown instrument: ${symbol}`);
        }

        try {
            const url = `${this.config.apiUrl}/openapi/typeb/instruments/intraday/${instrument.exchangeCode}/${instrument.instrumentToken}/${interval}`;
            console.log(`Fetching intraday data (Type B) for ${symbol}: ${url}`);

            const response = await axios.get(url, {
                headers: {
                    'X-Mirae-Version': '1',
                    'Authorization': `token ${this.config.appCode}:${this.sessionToken}`,
                    'Content-Type': 'application/json',
                    'X-PrivateKey': this.config.privateKey
                }
            });

            if (response.data && response.data.status === 'success' && response.data.data && response.data.data.candles) {
                // Map to app format: [time, open, high, low, close, volume]
                // API format: ["2025-03-13T12:03:00+05", open, high, low, close, volume]
                return response.data.data.candles.map(c => ({
                    timestamp: new Date(c[0]).getTime(),
                    open: parseFloat(c[1]),
                    high: parseFloat(c[2]),
                    low: parseFloat(c[3]),
                    close: parseFloat(c[4]),
                    volume: parseInt(c[5]),
                    symbol: symbol
                })).reverse(); // Usually APIs return newest first, we might want chronological? 
                // Actually Chart libs usually want chronological. API example shows descending time? 
                // 12:03, 12:02. Yes, descending. So we reverse.
            } else {
                console.warn(`No candle data found for ${symbol}`);
                return [];
            }
        } catch (error) {
            console.error(`Error fetching intraday candles for ${symbol}:`, error.message);
            return [];
        }
    }

    /**
     * Generate TOTP code
     */
    generateTOTP() {
        if (!this.config.totpSecret) {
            throw new Error('TOTP secret not configured');
        }

        return speakeasy.totp({
            secret: this.config.totpSecret,
            encoding: 'base32'
        });
    }

    /**
     * Authenticate with m.Stock API
     */
    async authenticate() {
        try {
            console.log('Authenticating with m.Stock API...');

            const totp = this.generateTOTP();

            // Type B uses /connect/login followed by session verification
            // However, many implementations use a unified login if available.
            // We'll try the /connect/login flow which is standard for Type B.
            const loginUrl = `${this.config.apiUrl}/connect/login`;
            console.log(`Attempting Type B login at ${loginUrl}`);

            const response = await axios.post(loginUrl, {
                userId: this.config.userId,
                password: this.config.password,
                appCode: this.config.appCode
            }, {
                headers: {
                    'Content-Type': 'application/json',
                    'X-PrivateKey': this.config.privateKey
                },
                timeout: 10000
            });

            // After login, we need to verify TOTP to get the final session token
            if (response.data && response.data.status === 'success') {
                console.log('Login step 1 success, verifying TOTP...');
                const verifyUrl = `${this.config.apiUrl}/verifytotp`;

                const verifyResponse = await axios.post(verifyUrl, {
                    userId: this.config.userId,
                    totp: totp,
                    appCode: this.config.appCode
                }, {
                    headers: {
                        'Content-Type': 'application/json',
                        'X-PrivateKey': this.config.privateKey
                    },
                    timeout: 10000
                });

                if (verifyResponse.data && verifyResponse.data.jwtToken) {
                    this.sessionToken = verifyResponse.data.jwtToken;
                    this.isAuthenticated = true;
                    console.log('m.Stock Type B authentication successful');
                    return true;
                } else if (verifyResponse.data && verifyResponse.data.sessionToken) {
                    this.sessionToken = verifyResponse.data.sessionToken;
                    this.isAuthenticated = true;
                    console.log('m.Stock Type B authentication successful');
                    return true;
                }
            }

            throw new Error('Authentication flow failed');
        } catch (error) {
            console.error('m.Stock authentication failed:', error.message);
            this.isAuthenticated = false;
            throw error;
        }
    }

    /**
     * Connect to m.Stock WebSocket feed
     */
    async connectWebSocket() {
        if (!this.isAuthenticated) throw new Error('Must authenticate first');

        return new Promise((resolve, reject) => {
            try {
                console.log('Connecting to m.Stock WebSocket (Binary Protocol)...');
                const wsUrl = `${this.config.wsUrl}?API_KEY=${this.config.appCode}&ACCESS_TOKEN=${this.sessionToken}`;

                this.wsConnection = new WebSocket(wsUrl);

                // Important: Set binary type to 'arraybuffer' or 'fragments' depending on lib
                // 'ws' library in node handles binary as Buffer by default.

                this.wsConnection.on('open', () => {
                    console.log('m.Stock WebSocket connected');
                    this.reconnectAttempts = 0;

                    // Send LOGIN message (Required by API)
                    this.wsConnection.send(`LOGIN:${this.sessionToken}`);

                    // Set Mode to LTP (or Quote if needed)
                    this.wsConnection.send(JSON.stringify({ "a": "mode", "v": ["ltp"] }));

                    this.subscribeToInstruments();
                    resolve();
                });

                this.wsConnection.on('message', (data) => {
                    if (Buffer.isBuffer(data)) {
                        this.handleBinaryMessage(data);
                    } else {
                        console.log('Received text message:', data.toString());
                    }
                });

                this.wsConnection.on('error', (err) => {
                    console.error('WS Error:', err);
                    reject(err);
                });

                this.wsConnection.on('close', () => {
                    console.log('WS Closed');
                    this.handleDisconnect();
                });

            } catch (error) {
                reject(error);
            }
        });
    }

    subscribeToInstruments() {
        if (!this.wsConnection || this.wsConnection.readyState !== WebSocket.OPEN) return;

        const tokens = Object.values(this.instruments).map(i => parseInt(i.instrumentToken));
        const msg = JSON.stringify({
            "a": "subscribe",
            "v": tokens
        });
        console.log('Subscribing:', msg);
        this.wsConnection.send(msg);
    }

    handleBinaryMessage(buffer) {
        try {
            // Structure: [NumPackets:2][NumBytes:2][Packet...]
            let offset = 0;
            const numPackets = buffer.readInt16LE(offset); offset += 2;

            for (let i = 0; i < numPackets; i++) {
                const numBytes = buffer.readInt16LE(offset); offset += 2;
                const packetBuffer = buffer.subarray(offset, offset + numBytes);
                offset += numBytes;

                this.parsePacket(packetBuffer);
            }
        } catch (e) {
            console.error('Error parsing binary:', e);
        }
    }

    parsePacket(buffer) {
        // Token is first 4 bytes (int32)
        const token = buffer.readInt32LE(0);

        // Check if it's one of our instruments
        const symbol = Object.keys(this.instruments).find(
            k => parseInt(this.instruments[k].instrumentToken) === token
        );

        if (!symbol) return;

        // Index Packet is 32 bytes (Nifty/BankNifty are indices)
        // Quote Packet is 64+ bytes

        let ltp = 0;
        let volume = 0;
        let open = 0, high = 0, low = 0;

        // Since Nifty/BankNifty are indices, they might use Index Structure (32 bytes)
        // Field	Type	Bytes
        // Token	[int]	0 - 4
        // LTP	    [int]	4 - 8
        // High 	[int]	8 - 12
        // Low  	[int]	12 - 16
        // Open 	[int]	16 - 20
        // Close	[int]	20 - 24

        if (buffer.length === 32) {
            ltp = buffer.readInt32LE(4) / 100.0;
            high = buffer.readInt32LE(8) / 100.0;
            low = buffer.readInt32LE(12) / 100.0;
            open = buffer.readInt32LE(16) / 100.0;
            // Close is at 20-24
        } else {
            // Quote Packet
            // LTP is 4-8
            ltp = buffer.readInt32LE(4) / 100.0;
            volume = buffer.readInt32LE(16); // Volume Traded Today
            open = buffer.readInt32LE(28) / 100.0;
            high = buffer.readInt32LE(32) / 100.0;
            low = buffer.readInt32LE(36) / 100.0;
        }

        const tick = {
            symbol: symbol,
            price: ltp,
            volume: volume, // Index volume might be 0 or derived
            timestamp: Date.now(),
            open: open,
            high: high,
            low: low
        };

        this.emit('tick', tick);
    }

    /**
     * Handle WebSocket disconnect
     */
    async handleDisconnect() {
        this.wsConnection = null;

        if (this.reconnectAttempts < this.maxReconnectAttempts) {
            this.reconnectAttempts++;
            console.log(`Reconnecting to m.Stock WebSocket (attempt ${this.reconnectAttempts})...`);

            setTimeout(async () => {
                try {
                    console.log('Refreshing session token before reconnecting...');
                    await this.authenticate();
                    await this.connectWebSocket();
                } catch (error) {
                    console.error('Reconnection failed:', error.message);
                    // If auth fails, we might want to try again or stop
                    // For now, the loop continues until max attempts
                }
            }, this.reconnectDelay * this.reconnectAttempts);
        } else {
            console.error('Max reconnection attempts reached, giving up');
            this.emit('error', new Error('Max reconnection attempts reached'));
        }
    }

    /**
     * Close connection
     */
    close() {
        if (this.wsConnection) {
            this.wsConnection.close();
            this.wsConnection = null;
        }
        this.isAuthenticated = false;
        this.sessionToken = null;
    }
}

/**
 * Initialize m.Stock service
 */
async function initializeMStock() {
    const service = new MStockService();

    try {
        await service.authenticate();
        await service.connectWebSocket();
        return service;
    } catch (error) {
        console.error('Failed to initialize m.Stock service:', error);
        throw error;
    }
}

module.exports = {
    MStockService,
    initializeMStock
};
