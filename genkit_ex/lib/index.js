const {genkit} = require("genkit");
const {googleAI, gemini15Flash} = require("@genkit-ai/googleai");
const admin = require("firebase-admin");
const functions = require("firebase-functions");

if (process.env.FUNCTIONS_EMULATOR) {
  admin.initializeApp({
    projectId: "ai-project-738a2",
    credential: admin.credential.applicationDefault(),
  });
} else {
  admin.initializeApp();
}

const db = admin.firestore();
if (process.env.FUNCTIONS_EMULATOR) {
  db.settings({
    host: "localhost:8080",
    ssl: false,
  });
}

const apiKey = "AIzaSyDmQ6I08_rhL2cEIols8N0fmXVYYyUHqHI";

const ai = genkit({
  plugins: [
    googleAI({
      apiKey: apiKey,
    }),
  ],
});

const promptTemplates = {
  "codeFeedback": "I will provide you with Flutter code" +
    "and specific requirements. " +
    "Please analyze the code " +
    "and provide suggestions based on the requirements.\n\n" +
    "Flutter Code:\n" +
    "${code}\n\n" +
    "Requirements:\n" +
    "${requirements}\n\n" +
    "Please provide:\n" +
    "1. Analysis of how well the code meets the requirements\n" +
    "2. Specific suggestions for improvements or modifications\n" +
    "3. Code examples for suggested changes if necessary\n" +
    "4. Best practices and optimization recommendations",
  "codeGeneration": "Please generate a coding problem" +
    "based on the following specifications." +
    "The problem should be challenging but solvable, and include:\n" +
    "1. A clear problem statement\n" +
    "2. Input and output specifications\n" +
    "3. Example inputs and expected outputs\n" +
    "4. Constraints or limitations\n" +
    "5. Hints for solving (optional)\n\n" +
    "Specifications: ${specifications}",
  "qna": "Please provide a detailed and accurate" +
    " answer to the following question:\n\n${question}",
};

/**
 * Executes streaming AI flow with the given input and response object
 * @param {Object} input - The input containing question, type and auth data
 * @param {Object} res - The response object for streaming
 * @return {Promise<void>}
 */
async function executeStreamingAIFlow(input, res) {
  const db = admin.firestore();
  let docRef;
  try {
    const requestType = input.requestType || "qna";
    let prompt = " ";
    if (requestType === "codeFeedback") {
      const [code, requirements] =
          input.question.split(/,\s*\[|\]/).filter(Boolean);
      if (code && requirements) {
        prompt = promptTemplates["codeFeedback"]
            .replace("${code}", code)
            .replace("${requirements}", requirements);
      } else {
        prompt = input.question;
      }
    } else if (requestType === "codeGeneration") {
      prompt = promptTemplates["codeGeneration"]
          .replace("${specifications}", input.question);
    } else {
      prompt = promptTemplates["qna"].replace("${question}", input.question);
    }
    res.setHeader("Content-Type", "text/event-stream");
    res.setHeader("Cache-Control", "no-cache");
    res.setHeader("Connection", "keep-alive");
    res.setHeader("X-Accel-Buffering", "no");

    docRef = db.collection("streaming_feedback").doc();
    await docRef.set({
      userId: input.auth.uid,
      question: input.question,
      requestType: requestType,
      timestamp: new Date().toISOString(),
      status: "streaming",
    });

    const RESPONSE_TIMEOUT = 300000;
    const responseTimeout = setTimeout(() => {
      if (res.writableEnded) return;
      res.write(`data: ${JSON.stringify({
        error: "Response timeout exceeded",
      })}\n\n`);
      res.end();
      if (docRef) {
        docRef.update({
          status: "timeout",
          error: "Response timeout exceeded",
          completedAt: new Date().toISOString(),
        }).catch((err) => console.error("Error updating timeout status:", err));
      }
    }, RESPONSE_TIMEOUT);

    const keepAlivePing = setInterval(() => {
      if (!res.writableEnded) {
        res.write(": keep-alive ping\n\n");
      } else {
        clearInterval(keepAlivePing);
      }
    }, 30000);

    const aiResponse = await ai.generate({
      model: gemini15Flash,
      prompt: prompt,
      config: {
        temperature: 0.7,
        stream: true,
      },
    });

    let fullResponse = "";

    if (aiResponse.stream) {
      for await (const chunk of aiResponse.stream) {
        if (res.writableEnded) break;
        const text = chunk.text || "";
        if (text) {
          fullResponse += text;
          res.write(`data: ${JSON.stringify({text})}\n\n`);
          if (fullResponse.length % 500 === 0) {
            try {
              await docRef.update({
                feedback: fullResponse,
                status: "streaming",
                lastUpdated: new Date().toISOString(),
              });
            } catch (updateError) {
              console.warn("Error updating streaming progress:", updateError);
            }
          }
        }
      }
    } else if (aiResponse.message) {
      const messageContent = typeof aiResponse.message === "string" ?
        aiResponse.message :
        aiResponse.message.content?.[0]?.text || aiResponse.message.toString();
      fullResponse = messageContent;
      res.write(`data: ${JSON.stringify({text: messageContent})}\n\n`);
    }

    clearTimeout(responseTimeout);
    clearInterval(keepAlivePing);
    await docRef.update({
      feedback: fullResponse,
      status: "completed",
      completedAt: new Date().toISOString(),
    });
    res.write(`data: {"done": true}\n\n`);
    res.end();
  } catch (error) {
    console.error("AI Flow execution error:", error);
    if (docRef) {
      try {
        await docRef.update({
          status: "error",
          error: error.message,
          completedAt: new Date().toISOString(),
        });
      } catch (updateError) {
        console.error("Error updating Firestore document:", updateError);
      }
    }
    if (!res.writableEnded) {
      res.write(`data: ${JSON.stringify({
        error: error.message || "An error occurred during processing",
      })}\n\n`);
      res.end();
    }
  }
}

exports.aiStreamingFeedback = functions.https.onRequest(async (req, res) => {
  try {
    res.set("Access-Control-Allow-Origin", "*");
    res.set("Access-Control-Allow-Methods", "GET, POST");
    res.set("Access-Control-Allow-Headers", "Content-Type, Authorization");
    if (req.method === "OPTIONS") {
      res.status(204).send(" ");
      return;
    }

    const authHeader = req.headers.authorization;
    if (!authHeader || !authHeader.startsWith("Bearer ")) {
      res.status(403).json({error: "Unauthorized: No token provided"});
      return;
    }

    const idToken = authHeader.split("Bearer ")[1];

    try {
      let decodedToken;
      if (process.env.FUNCTIONS_EMULATOR) {
        decodedToken = JSON.parse(
            Buffer.from(idToken.split(".")[1], "base64").toString(),
        );
      } else {
        decodedToken = await admin.auth().verifyIdToken(idToken);
      }

      if (!req.body || !req.body.question) {
        res.status(400).json({error: "Invalid request: question is required"});
        return;
      }

      await executeStreamingAIFlow({
        question: req.body.question,
        requestType: req.body.requestType || "qna",
        auth: {
          uid: decodedToken.sub || decodedToken.user_id,
          email_verified: decodedToken.email_verified,
        },
      }, res);
    } catch (verifyError) {
      console.error("Token verification failed:", verifyError);
      res.status(403).json({error: "Unauthorized: Invalid token"});
    }
  } catch (error) {
    console.error("Function execution error:", error);
    res.status(500).json({error: "Internal Server Error"});
  }
});
