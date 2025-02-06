/*
const {genkit, z} = require("genkit");
const {googleAI, gemini15Flash} = require("@genkit-ai/googleai");
const {firebaseAuth} = require("@genkit-ai/firebase/auth");
const {onFlow} = require("@genkit-ai/firebase/functions");
const {defineSecret} = require("firebase-functions/params");
const admin = require("firebase-admin");
const functions = require("firebase-functions");

// Firebase 초기화 설정
if (process.env.FUNCTIONS_EMULATOR) {
const authHost = '127.0.0.1:9099';
const firestoreHost = '127.0.0.1:8080';

console.log(`Initializing Firebase with emulator hosts:
Auth: ${authHost}
Firestore: ${firestoreHost}`);

admin.initializeApp({
projectId: "your project id,
credential: admin.credential.applicationDefault()
});

process.env.FIREBASE_AUTH_EMULATOR_HOST = authHost;
process.env.FIRESTORE_EMULATOR_HOST = firestoreHost;
} else {
admin.initializeApp();
}

const googleAIapiKey = defineSecret("GOOGLE_AI_API_KEY");

const ai = genkit({
plugins: [
googleAI({
apiKey: "your api key", // 실제 API 키로 교체
}),
],
});

const corsHandler = require('cors')({
origin: true,
credentials: true,
});

// Flow를 별도 함수로 분리하여 관리
async function executeAIFlow(input) {
try {
*/
/* const prompt =
      "This is the Flutter Code I implemented. " +
      `Look at the ${input.question} I developed and suggest` +
      "an error or correction plan"; *//*

const [code, requirements] = input.question.split(/,\s*\[|\]/).filter(Boolean);
const prompt =
"I will provide you with Flutter code and specific requirements. " +
"Please analyze the code and provide suggestions based on the requirements.\n\n" +
"Flutter Code:\n" +
`${code}\n\n` +
"Requirements:\n" +
`${requirements}\n\n` +
"Please provide:\n" +
"1. Analysis of how well the code meets the requirements\n" +
"2. Specific suggestions for improvements or modifications\n" +
"3. Code examples for suggested changes if necessary\n" +
"4. Best practices and optimization recommendations";

const llmResponse = await ai.generate({
model: gemini15Flash,
prompt: prompt,
config: {
temperature: 0.7, // 더 일관된 응답을 위해서 조정, latest : 1
},
});

return llmResponse.text;
} catch (error) {
console.error('AI Flow execution error:', error);
throw error;
}
}

exports.aiCodeFeedback = functions.https.onRequest(async (req, res) => {
// CORS 처리를 먼저 수행
corsHandler(req, res, async () => {
try {
const authHeader = req.headers.authorization;
if (!authHeader || !authHeader.startsWith('Bearer ')) {
res.status(403).json({ error: 'Unauthorized: No token provided' });
return;
}

const idToken = authHeader.split('Bearer ')[1];
console.log('Received token:', idToken.substring(0, 20) + '...');

try {
// 토큰 검증
let decodedToken;
if (process.env.FUNCTIONS_EMULATOR) {
decodedToken = JSON.parse(
Buffer.from(idToken.split('.')[1], 'base64').toString()
);
console.log('Emulator mode: Decoded token:', decodedToken);
} else {
decodedToken = await admin.auth().verifyIdToken(idToken);
}

// 요청 본문 검증
if (!req.body || !req.body.question) {
res.status(400).json({ error: 'Invalid request: question is required' });
return;
}

// AI Flow 실행
const aiResponse = await executeAIFlow({
question: req.body.question,
auth: {
uid: decodedToken.sub || decodedToken.user_id,
email_verified: decodedToken.email_verified
}
});

// 응답 전송
res.status(200).json({ result: aiResponse });

} catch (verifyError) {
console.error('Token verification failed:', verifyError);
res.status(403).json({ error: 'Unauthorized: Invalid token' });
}
} catch (error) {
console.error('Function execution error:', error);
res.status(500).json({ error: 'Internal Server Error' });
}
});
});*/
