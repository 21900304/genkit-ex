/*
const { onRequest } = require('firebase-functions/v2/https');
const { setGlobalOptions } = require('firebase-functions/v2');
const express = require('express');
const WebSocket = require('ws');
const admin = require('firebase-admin');
const { genkit } = require('genkit');
const { googleAI, gemini15Flash } = require('@genkit-ai/googleai');

// Firebase Admin SDK 초기화
admin.initializeApp({
credential: admin.credential.applicationDefault(),
});

// Firebase Functions 전역 설정
setGlobalOptions({
maxInstances: 10,
timeoutSeconds: 540,
memory: '1GiB',
region: 'us-central1'
});

// Express 앱과 HTTP 서버 설정
const app = express();
const server = require('http').createServer(app);

// CORS 설정
const corsOptions = {
origin: (origin, callback) => {
if (!origin || origin.startsWith('http://localhost')) {
callback(null, true);
} else {
callback(new Error('Not allowed by CORS'));
}
},
methods: ['GET', 'POST', 'OPTIONS'],
allowedHeaders: ['*'],
credentials: true
};

app.use(require('cors')(corsOptions));

// WebSocket 서버 설정
const wss = new WebSocket.Server({
noServer: true,
clientTracking: true,
handleProtocols: (protocols) => {
if (typeof protocols === 'string') {
return protocols === 'websocket' ? protocols : false;
}
if (Array.isArray(protocols)) {
return protocols.includes('websocket') ? 'websocket' : false;
}
return false;
},
perMessageDeflate: {
zlibDeflateOptions: {
chunkSize: 1024,
memLevel: 7,
level: 3
},
zlibInflateOptions: {
chunkSize: 10 * 1024
},
clientNoContextTakeover: true,
serverNoContextTakeover: true,
serverMaxWindowBits: 10,
concurrencyLimit: 10,
threshold: 1024
}
});

// 클라이언트 연결 관리
const clients = new Map();

// 클라이언트 연결 관리 클래스
class ClientConnection {
constructor(ws, connectionId) {
this.ws = ws;
this.connectionId = connectionId;
this.isAuthenticated = false;
this.lastActivityTime = Date.now();
this.pingInterval = null;
this.setupPingPong();

console.log('New client connection:', {
connectionId: this.connectionId,
timestamp: new Date().toISOString(),
isAuthenticated: this.isAuthenticated
});
}

setupPingPong() {
this.pingInterval = setInterval(() => {
if (Date.now() - this.lastActivityTime > 30000) {
console.log('Client inactive:', {
connectionId: this.connectionId,
lastActivity: new Date(this.lastActivityTime).toISOString()
});
this.cleanup();
return;
}

if (this.ws.readyState === WebSocket.OPEN) {
this.ws.ping();
console.log('Ping sent:', {
connectionId: this.connectionId,
timestamp: new Date().toISOString()
});
}
}, 15000);
}

cleanup() {
console.log('Cleaning up connection:', {
connectionId: this.connectionId,
timestamp: new Date().toISOString()
});
clearInterval(this.pingInterval);
if (this.ws.readyState === WebSocket.OPEN) {
this.ws.close();
}
clients.delete(this.connectionId);
}

updateActivity() {
this.lastActivityTime = Date.now();
}
}

// WebSocket 인증 처리
async function authenticateWebSocket(token) {
console.log('Starting authentication process');

try {
if (process.env.FUNCTIONS_EMULATOR) {
const decodedToken = JSON.parse(Buffer.from(token.split('.')[1], 'base64').toString());
console.log('Emulator authentication successful:', {
uid: decodedToken.uid,
timestamp: new Date().toISOString()
});
return decodedToken;
} else {
const decodedToken = await admin.auth().verifyIdToken(token);
console.log('Production authentication successful:', {
uid: decodedToken.uid,
timestamp: new Date().toISOString()
});
return decodedToken;
}
} catch (error) {
console.error('Authentication failed:', error);
throw new Error('Authentication failed: ' + error.message);
}
}

// AI 응답 생성
async function generateAIResponse(question, ws) {
console.log('Generating AI response:', {
questionLength: question.length,
timestamp: new Date().toISOString()
});

try {
const ai = genkit({
provider: googleAI({
apiKey: process.env.GOOGLE_AI_API_KEY
})
});

const stream = await ai.generateStream({
model: gemini15Flash,
prompt: question,
config: {
temperature: 0.7,
maxTokens: 1000,
},
});

for await (const chunk of stream) {
if (ws.readyState === WebSocket.OPEN) {
ws.send(JSON.stringify({
type: 'chunk',
content: chunk,
timestamp: new Date().toISOString()
}));
} else {
console.log('Stream terminated - WebSocket closed');
break;
}
}

if (ws.readyState === WebSocket.OPEN) {
ws.send(JSON.stringify({
type: 'complete',
timestamp: new Date().toISOString()
}));
}
} catch (error) {
console.error('AI generation error:', error);
if (ws.readyState === WebSocket.OPEN) {
ws.send(JSON.stringify({
type: 'error',
error: 'AI processing failed: ' + error.message,
timestamp: new Date().toISOString()
}));
}
}
}

// WebSocket 서버 이벤트 처리
wss.on('connection', async (ws, req) => {
const connectionId = Date.now().toString();
const client = new ClientConnection(ws, connectionId);
clients.set(connectionId, client);

console.log('New WebSocket connection:', {
connectionId,
timestamp: new Date().toISOString(),
headers: req.headers,
url: req.url,
method: req.method
});

ws.on('pong', () => {
client.updateActivity();
console.log('Pong received:', {
connectionId,
timestamp: new Date().toISOString()
});
});

ws.on('message', async (message) => {
console.log('Message received:', {
connectionId,
messageLength: message.length,
timestamp: new Date().toISOString()
});

try {
const data = JSON.parse(message.toString());
client.updateActivity();

switch (data.type) {
case 'auth':
try {
await authenticateWebSocket(data.token);
client.isAuthenticated = true;
ws.send(JSON.stringify({
type: 'status',
status: 'authenticated',
timestamp: new Date().toISOString()
}));
} catch (error) {
console.error('Authentication failed:', error);
ws.send(JSON.stringify({
type: 'error',
error: 'Authentication failed: ' + error.message,
timestamp: new Date().toISOString()
}));
client.cleanup();
}
break;

case 'question':
if (!client.isAuthenticated) {
ws.send(JSON.stringify({
type: 'error',
error: 'Not authenticated',
timestamp: new Date().toISOString()
}));
return;
}
await generateAIResponse(data.question, ws);
break;

default:
console.warn('Unknown message type:', data.type);
ws.send(JSON.stringify({
type: 'error',
error: 'Unknown message type',
timestamp: new Date().toISOString()
}));
}
} catch (error) {
console.error('Message processing error:', error);
ws.send(JSON.stringify({
type: 'error',
error: 'Message processing failed: ' + error.message,
timestamp: new Date().toISOString()
}));
}
});

ws.on('close', (code, reason) => {
console.log('Connection closed:', {
connectionId,
code,
reason: reason.toString(),
timestamp: new Date().toISOString()
});
client.cleanup();
});

ws.on('error', (error) => {
console.error('WebSocket error:', {
connectionId,
error: error.message,
stack: error.stack,
timestamp: new Date().toISOString()
});
client.cleanup();
});
});

// WebSocket 업그레이드 핸들러
const handleUpgrade = (request, socket, head) => {
const path = request.url || request.originalUrl || '/';
//const path = 'ws://localhost:5001/ai-project-738a2/us-central1/aiCodeFeedbackStream';
const expectedPath = '/aiCodeFeedbackStream';
const requestOrigin = request.headers.origin;
const isValidOrigin = !requestOrigin || requestOrigin.startsWith('http://localhost');

*/
/* console.log('WebSocket upgrade request:', {
    path,
    expectedPath,
    isValidPath: path === expectedPath,
    origin: requestOrigin,
    isValidOrigin,
    headers: request.headers,
    timestamp: new Date().toISOString()
  }); *//*


console.log('WebSocket upgrade request:', {
path,
origin: requestOrigin,
isValidOrigin,
headers: request.headers,
timestamp: new Date().toISOString()
});

try {
wss.handleUpgrade(request, socket, head, (ws) => {
wss.emit('connection', ws, request);
});
} catch (error) {
console.error('WebSocket upgrade error:', {
error: error.message,
stack: error.stack,
timestamp: new Date().toISOString()
});
socket.destroy();
}
};

// HTTP 서버 업그레이드 이벤트 처리
server.on('upgrade', (request, socket, head) => {
handleUpgrade(request, socket, head);
});

// Cloud Function 엔드포인트
exports.aiCodeFeedbackStream = onRequest(async (req, res) => {
if (req.method === 'OPTIONS') {
res.set({
'Access-Control-Allow-Origin': '*',
'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
'Access-Control-Allow-Headers': '*',
'Access-Control-Max-Age': '3600'
}).status(204).send('');
return;
}

if (req.headers.upgrade?.toLowerCase() === 'websocket') {
handleUpgrade(req, req.socket, Buffer.alloc(0));
} else {
res.status(426).send('Upgrade Required');
}
});*/
