require('dotenv').config();
const { initializeMStock } = require('./services/mstock.service');

(async () => {
    console.log('--- m.Stock API Verification ---');
    if (!process.env.MSTOCK_USER_ID) {
        console.error('ERROR: MSTOCK_USER_ID is missing in .env');
        process.exit(1);
    }

    try {
        console.log('Attempting to authenticate...');
        const service = await initializeMStock();
        console.log('SUCCESS: Authentication worked!');
        console.log('Connected to WebSocket.');
        service.close();
        process.exit(0);
    } catch (error) {
        console.error('FAILURE: Could not connect to m.Stock.');
        console.error('Reason:', error.message);
        process.exit(1);
    }
})();
