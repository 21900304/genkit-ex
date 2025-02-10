const {genkit, z} = require("genkit");
const {googleAI, gemini15Flash} = require("@genkit-ai/googleai");
const admin = require("firebase-admin");
const functions = require("firebase-functions");

// Firebase Admin SDK 초기화
if (process.env.FUNCTIONS_EMULATOR) {
  admin.initializeApp({
    projectId: "ai-project-738a2",
    credential: admin.credential.applicationDefault()
  });
} else {
  admin.initializeApp();
}

const ai = genkit({
  plugins: [
    googleAI({
      apiKey: "AIzaSyDmQ6I08_rhL2cEIols8N0fmXVYYyUHqHI",
    }),
  ],
});

let docRef;

async function executeStreamingAIFlow(input, res) {  // 'response'를 'res'로 변경
  const db = admin.firestore();

  try {
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

    res.setHeader('Content-Type', 'text/event-stream');
    res.setHeader('Cache-Control', 'no-cache');
    res.setHeader('Connection', 'keep-alive');

    docRef = db.collection('streaming_feedback').doc();

    await docRef.set({
      userId: input.auth.uid,
      question: input.question,
      timestamp: new Date().toISOString(),
      status: 'streaming'
    });

    const aiResponse = await ai.generate({  // 'response'를 'aiResponse'로 변경
      model: gemini15Flash,
      prompt: prompt,
      config: {
        temperature: 0.7,
        stream: true,
      },
    });

    let fullResponse = '';

    if (aiResponse.message) {
      const messageContent = typeof aiResponse.message === 'string'
        ? aiResponse.message
        : aiResponse.message.content?.[0]?.text || aiResponse.message.toString();

      fullResponse = messageContent;
      res.write(`data: ${JSON.stringify({ text: messageContent })}\n\n`);
    }

    await docRef.update({
      feedback: fullResponse,  // 순수 텍스트만 저장
      status: 'completed',
      completedAt: new Date().toISOString()
    });

    res.write('data: {"done": true}\n\n');
    res.end();

  } catch (error) {
    console.error('AI Flow execution error:', error);

    if (docRef) {
      try {
        await docRef.update({
          status: 'error',
          error: error.message,
          completedAt: new Date().toISOString()
        });
      } catch (updateError) {
        console.error('Error updating Firestore document:', updateError);
      }
    }

    res.write(`data: ${JSON.stringify({ error: error.message })}\n\n`);
    res.end();
  }
}

exports.aiStreamingFeedback = functions.https.onRequest(async (req, res) => {
  try {
    const authHeader = req.headers.authorization;
    if (!authHeader || !authHeader.startsWith('Bearer ')) {
      res.status(403).json({ error: 'Unauthorized: No token provided' });
      return;
    }

    const idToken = authHeader.split('Bearer ')[1];

    try {
      let decodedToken;
      if (process.env.FUNCTIONS_EMULATOR) {
        decodedToken = JSON.parse(
          Buffer.from(idToken.split('.')[1], 'base64').toString()
        );
      } else {
        decodedToken = await admin.auth().verifyIdToken(idToken);
      }

      if (!req.body || !req.body.question) {
        res.status(400).json({ error: 'Invalid request: question is required' });
        return;
      }

      await executeStreamingAIFlow({
        question: req.body.question,
        auth: {
          uid: decodedToken.sub || decodedToken.user_id,
          email_verified: decodedToken.email_verified
        }
      }, res);

    } catch (verifyError) {
      console.error('Token verification failed:', verifyError);
      res.status(403).json({ error: 'Unauthorized: Invalid token' });
    }
  } catch (error) {
    console.error('Function execution error:', error);
    res.status(500).json({ error: 'Internal Server Error' });
  }
});