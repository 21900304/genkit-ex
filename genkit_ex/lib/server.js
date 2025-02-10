const express = require('express');
const http = require('http');
const { Server } = require('socket.io');
const { genkit, z } = require('genkit');
const { googleAI, gemini15Flash } = require('@genkit-ai/googleai');

const app = express();
const server = http.createServer(app);
const io = new Server(server, {
    cors: {
      origin: '*',
      methods: ['GET', 'POST'],
      credentials: true,
      allowedHeaders: ['Content-Type', 'Authorization']
    },
    pingTimeout: 60000,
    pingInterval: 25000,
    transports: ['websocket', 'polling']
});

const ai = genkit({
  plugins: [
    googleAI({
      apiKey: "AIzaSyDmQ6I08_rhL2cEIols8N0fmXVYYyUHqHI",
    }),
  ],
});

const userSessions = new Map();
const STREAM_TIMEOUT = 30000;

io.on('connection', (socket) => {
    console.log('Client connected:', socket.id);
    console.log('Transport type:', socket.conn.transport.name);

    socket.on('startStream', async (data) => {
      const { question, userId } = data;
      console.log('Received stream request:', { userId, question });

      try {
        if (userSessions.has(userId)) {
          userSessions.delete(userId);
        }

        userSessions.set(userId, socket.id);

        const streamTimeout = setTimeout(() => {
          if (userSessions.has(userId)) {
            socket.emit('streamError', {
              message: 'Stream timeout exceeded'
            });
            userSessions.delete(userId);
          }
        }, STREAM_TIMEOUT);

        const response = await ai.generate({
          model: gemini15Flash,
          prompt: question,
          config: {
            temperature: 0.7,
            stream: true,
          },
        });

        console.log('Response object structure:', {
          type: typeof response,
          properties: Object.keys(response)
        });

        try {
          // Stream response handling
          if (response.message) {
            const messageText = response.message.content?.[0]?.text || response.message;
            if (userSessions.get(userId) === socket.id) {
              socket.emit('streamData', {
                text: messageText,
                isDone: false
              });
            }
          }

          // Send completion signal
          if (userSessions.get(userId) === socket.id) {
            socket.emit('streamData', {
              text: '',
              isDone: true
            });
          }
        } catch (streamError) {
          console.error('Stream processing error:', streamError);
          if (userSessions.has(userId)) {
            socket.emit('streamError', {
              message: 'Error processing stream data'
            });
          }
        }

        clearTimeout(streamTimeout);

      } catch (error) {
        console.error('Stream error:', error);
        if (userSessions.has(userId)) {
          socket.emit('streamError', {
            message: error.message
          });
        }
      } finally {
        if (userId && userSessions.has(userId)) {
          userSessions.delete(userId);
        }
      }
    });

    socket.on('disconnect', () => {
      console.log('Client disconnected:', socket.id);
      for (const [userId, sessionId] of userSessions.entries()) {
        if (sessionId === socket.id) {
          userSessions.delete(userId);
          console.log('Cleaned up session for user:', userId);
          break;
        }
      }
    });

    socket.on('error', (error) => {
      console.error('Socket error:', error);
      for (const [userId, sessionId] of userSessions.entries()) {
        if (sessionId === socket.id) {
          userSessions.delete(userId);
          console.log('Cleaned up session after error for user:', userId);
          break;
        }
      }
    });
});

const PORT = process.env.PORT || 3001;
server.listen(PORT, () => {
  console.log(`Stream server running on port ${PORT}`);
});

process.on('SIGTERM', () => {
  console.log('SIGTERM received. Cleaning up...');
  server.close(() => {
    console.log('Server closed');
    process.exit(0);
  });
});

app.use((err, req, res, next) => {
  console.error('Server error:', err);
  res.status(500).json({ error: 'Internal server error' });
});