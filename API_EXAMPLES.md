# API Examples

This document provides sample JSON payloads for WebSocket messages and REST API endpoints.

## WebSocket Stream

### Connection
```
ws://localhost:3000/stream?token=<firebase_id_token>
```

### Server → Client Messages

#### 1. Connected Message
```json
{
  "type": "connected",
  "message": "Connected to Orderflow stream",
  "user": {
    "uid": "abc123xyz",
    "role": "viewer"
  }
}
```

#### 2. Candle Update
```json
{
  "type": "candle",
  "data": {
    "symbol": "NIFTY50",
    "candleKey": "NIFTY50-20251231-0915",
    "timeStart": 1735623900000,
    "timeEnd": 1735624200000,
    "open": 24500.50,
    "high": 24520.75,
    "low": 24495.25,
    "close": 24510.00,
    "volume": 125000,
    "buyerCount": 50000,
    "sellerCount": 40000
  }
}
```

#### 3. Subscription Confirmation
```json
{
  "type": "subscribed",
  "instruments": ["NIFTY50", "BANKNIFTY"]
}
```

#### 4. Pong (Heartbeat Response)
```json
{
  "type": "pong",
  "timestamp": 1735623900000
}
```

#### 5. Error Message
```json
{
  "type": "error",
  "message": "Market data service error"
}
```

### Client → Server Messages

#### 1. Subscribe to Instruments
```json
{
  "type": "subscribe",
  "instruments": ["NIFTY50"]
}
```

#### 2. Unsubscribe from Instruments
```json
{
  "type": "unsubscribe",
  "instruments": ["BANKNIFTY"]
}
```

#### 3. Ping (Keep-Alive)
```json
{
  "type": "ping"
}
```

---

## REST API Endpoints (Admin Only)

### 1. POST /api/admin/orderflow
Save buyer/seller count for a candle.

**Request Headers:**
```
Authorization: Bearer <firebase_id_token>
Content-Type: application/json
```

**Request Body:**
```json
{
  "candleKey": "NIFTY50-20251231-0915",
  "buyerCount": 50000,
  "sellerCount": 40000
}
```

**Success Response (200):**
```json
{
  "success": true,
  "data": {
    "candleKey": "NIFTY50-20251231-0915",
    "buyerCount": 50000,
    "sellerCount": 40000,
    "updatedBy": "abc123xyz",
    "updatedAt": {
      "_seconds": 1735623900,
      "_nanoseconds": 0
    },
    "createdAt": {
      "_seconds": 1735623900,
      "_nanoseconds": 0
    }
  }
}
```

**Error Response (400):**
```json
{
  "error": "buyerCount and sellerCount must be numbers"
}
```

**Error Response (401):**
```json
{
  "error": "Unauthorized: No token provided"
}
```

**Error Response (403):**
```json
{
  "error": "Forbidden: Admin access required"
}
```

---

### 2. GET /api/admin/orderflow/:candleKey
Get orderflow data for a specific candle.

**Request Headers:**
```
Authorization: Bearer <firebase_id_token>
```

**Example Request:**
```
GET /api/admin/orderflow/NIFTY50-20251231-0915
```

**Success Response (200):**
```json
{
  "success": true,
  "data": {
    "candleKey": "NIFTY50-20251231-0915",
    "buyerCount": 50000,
    "sellerCount": 40000,
    "updatedBy": "abc123xyz",
    "updatedAt": {
      "_seconds": 1735623900,
      "_nanoseconds": 0
    }
  }
}
```

**Error Response (404):**
```json
{
  "error": "Orderflow data not found"
}
```

---

### 3. GET /api/admin/orderflow?symbol=NIFTY50&date=2025-12-31
Query orderflow data by symbol and date.

**Request Headers:**
```
Authorization: Bearer <firebase_id_token>
```

**Query Parameters:**
- `symbol` (required): "NIFTY50" or "BANKNIFTY"
- `date` (optional): ISO date string, defaults to today

**Example Request:**
```
GET /api/admin/orderflow?symbol=NIFTY50&date=2025-12-31
```

**Success Response (200):**
```json
{
  "success": true,
  "count": 2,
  "data": [
    {
      "id": "NIFTY50-20251231-0915",
      "candleKey": "NIFTY50-20251231-0915",
      "buyerCount": 50000,
      "sellerCount": 40000,
      "updatedBy": "abc123xyz",
      "updatedAt": {
        "_seconds": 1735623900,
        "_nanoseconds": 0
      }
    },
    {
      "id": "NIFTY50-20251231-0920",
      "candleKey": "NIFTY50-20251231-0920",
      "buyerCount": 55000,
      "sellerCount": 45000,
      "updatedBy": "abc123xyz",
      "updatedAt": {
        "_seconds": 1735624200,
        "_nanoseconds": 0
      }
    }
  ]
}
```

**Error Response (400):**
```json
{
  "error": "symbol query parameter is required"
}
```

---

### 4. DELETE /api/admin/orderflow/cleanup?beforeDate=2025-12-30
Delete old orderflow data (cleanup endpoint).

**Request Headers:**
```
Authorization: Bearer <firebase_id_token>
```

**Query Parameters:**
- `beforeDate` (required): ISO date string

**Example Request:**
```
DELETE /api/admin/orderflow/cleanup?beforeDate=2025-12-30
```

**Success Response (200):**
```json
{
  "success": true,
  "deletedCount": 150
}
```

---

## Candle Key Format

Candle keys follow this format:
```
{symbol}-{YYYYMMDD}-{HHMM}
```

Examples:
- `NIFTY50-20251231-0915` (NIFTY50 on Dec 31, 2025 at 09:15)
- `BANKNIFTY-20251231-1030` (BANKNIFTY on Dec 31, 2025 at 10:30)

Time is aligned to 5-minute boundaries:
- 09:15, 09:20, 09:25, 09:30, ... 15:25, 15:30

---

## Error Codes

| Status Code | Meaning |
|-------------|---------|
| 200 | Success |
| 400 | Bad Request (validation error) |
| 401 | Unauthorized (no token or invalid token) |
| 403 | Forbidden (not admin) |
| 404 | Not Found (resource doesn't exist) |
| 500 | Internal Server Error |

---

## Testing with cURL

### Save Orderflow Data
```bash
curl -X POST http://localhost:3000/api/admin/orderflow \
  -H "Authorization: Bearer YOUR_FIREBASE_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "candleKey": "NIFTY50-20251231-0915",
    "buyerCount": 50000,
    "sellerCount": 40000
  }'
```

### Get Orderflow Data
```bash
curl -X GET "http://localhost:3000/api/admin/orderflow?symbol=NIFTY50&date=2025-12-31" \
  -H "Authorization: Bearer YOUR_FIREBASE_TOKEN"
```

---

## Testing with WebSocket Client (JavaScript)

```javascript
const WebSocket = require('ws');

const token = 'YOUR_FIREBASE_TOKEN';
const ws = new WebSocket(`ws://localhost:3000/stream?token=${token}`);

ws.on('open', () => {
  console.log('Connected');
  
  // Subscribe to NIFTY50
  ws.send(JSON.stringify({
    type: 'subscribe',
    instruments: ['NIFTY50']
  }));
});

ws.on('message', (data) => {
  const message = JSON.parse(data.toString());
  console.log('Received:', message);
});

ws.on('close', () => {
  console.log('Disconnected');
});
```
