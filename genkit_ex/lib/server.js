const express = require('express');
const http = require('http');
const { Server } = require('socket.io');
const axios = require('axios');
const EventSource = require('eventsource'); // SSE 클라이언트 라이브러리

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

// Cloud Function URL 설정
const CLOUD_FUNCTION_URL = process.env.CLOUD_FUNCTION_URL ||
  (process.env.NODE_ENV === 'production'
    ? 'https://aistreamingfeedback-exl7rrk7da-uc.a.run.app'
    : 'https://aistreamingfeedback-exl7rrk7da-uc.a.run.app');

// 응답 시간 측정을 위한 세션 저장소
const userSessions = new Map();
const STREAM_TIMEOUT = 60000; // 타임아웃 시간 증가

// 응답 시간 통계 저장소
const responseTimeStats = {
  totalRequests: 0,
  totalResponseTime: 0, // ms 단위
  averageResponseTime: 0, // ms 단위
  averageResponseTimeSeconds: 0, // 초 단위
  minResponseTime: Number.MAX_SAFE_INTEGER, // ms 단위
  minResponseTimeSeconds: 0, // 초 단위
  maxResponseTime: 0, // ms 단위
  maxResponseTimeSeconds: 0, // 초 단위
  responseTimes: []
};

// 요청 유형별 응답 시간 통계 저장소
const requestTypeStats = {
  'codeFeedback': {
    totalRequests: 0,
    totalResponseTime: 0,
    averageResponseTime: 0,
    minResponseTime: Number.MAX_SAFE_INTEGER,
    maxResponseTime: 0
  },
  'codeGeneration': {
    totalRequests: 0,
    totalResponseTime: 0,
    averageResponseTime: 0,
    minResponseTime: Number.MAX_SAFE_INTEGER,
    maxResponseTime: 0
  },
  'qna': {
    totalRequests: 0,
    totalResponseTime: 0,
    averageResponseTime: 0,
    minResponseTime: Number.MAX_SAFE_INTEGER,
    maxResponseTime: 0
  }
};

// 응답 시간 통계 업데이트 함수
function updateResponseTimeStats(responseTime, requestType = 'qna') {
  const responseTimeInSeconds = responseTime / 1000; // ms를 초 단위로 변환

  // 전체 통계 업데이트
  responseTimeStats.totalRequests += 1;
  responseTimeStats.totalResponseTime += responseTime;
  responseTimeStats.averageResponseTime = responseTimeStats.totalResponseTime / responseTimeStats.totalRequests;
  responseTimeStats.averageResponseTimeSeconds = responseTimeStats.averageResponseTime / 1000;

  if (responseTime < responseTimeStats.minResponseTime) {
    responseTimeStats.minResponseTime = responseTime;
    responseTimeStats.minResponseTimeSeconds = responseTimeInSeconds;
  }

  if (responseTime > responseTimeStats.maxResponseTime) {
    responseTimeStats.maxResponseTime = responseTime;
    responseTimeStats.maxResponseTimeSeconds = responseTimeInSeconds;
  }

  // 최근 100개의 응답 시간만 저장
  responseTimeStats.responseTimes.push({
    timestamp: new Date().toISOString(),
    responseTimeMs: responseTime,
    responseTimeSeconds: responseTimeInSeconds.toFixed(2),
    requestType: requestType
  });

  if (responseTimeStats.responseTimes.length > 100) {
    responseTimeStats.responseTimes.shift();
  }

  // 요청 유형별 통계 업데이트
  if (requestTypeStats[requestType]) {
    requestTypeStats[requestType].totalRequests += 1;
    requestTypeStats[requestType].totalResponseTime += responseTime;
    requestTypeStats[requestType].averageResponseTime =
      requestTypeStats[requestType].totalResponseTime / requestTypeStats[requestType].totalRequests;

    if (responseTime < requestTypeStats[requestType].minResponseTime) {
      requestTypeStats[requestType].minResponseTime = responseTime;
    }

    if (responseTime > requestTypeStats[requestType].maxResponseTime) {
      requestTypeStats[requestType].maxResponseTime = responseTime;
    }
  }

  console.log(`New response time (${requestType}): ${responseTime}ms (${responseTimeInSeconds.toFixed(2)}s), Average: ${responseTimeStats.averageResponseTime.toFixed(2)}ms (${responseTimeStats.averageResponseTimeSeconds.toFixed(2)}s)`);
  console.log('--------------------------------------------------------------');
}

io.on('connection', (socket) => {
    console.log('Client connected:', socket.id);
    console.log('Transport type:', socket.conn.transport.name);

    socket.on('startStream', async (data) => {
      const { question, userId, idToken, requestType = 'qna', customTemplate } = data; // 커스텀 템플릿 추가
      console.log('Received stream request:', {
        userId,
        requestType,
        hasCustomTemplate: !!customTemplate, // 커스텀 템플릿 존재 여부 로깅
        question: question.substring(0, 100) + '...'
      });

      // 이미 진행 중인 세션이 있으면 제거
      if (userSessions.has(userId)) {
        const oldSession = userSessions.get(userId);
        if (oldSession.eventSource) {
          oldSession.eventSource.close();
        }
        userSessions.delete(userId);
      }

      // 새 세션 등록 및 시작 시간 기록
      const startTime = Date.now();
      userSessions.set(userId, {
        socketId: socket.id,
        startTime: startTime,
        firstResponseReceived: false,
        completed: false,
        requestType: requestType,
        customTemplate: customTemplate // 커스텀 템플릿 저장
      });

      // 타임아웃 설정
      const streamTimeout = setTimeout(() => {
        if (userSessions.has(userId)) {
          socket.emit('streamError', {
            message: 'Stream timeout exceeded'
          });

          const session = userSessions.get(userId);
          if (session.eventSource) {
            session.eventSource.close();
          }

          userSessions.delete(userId);
        }
      }, STREAM_TIMEOUT);

      try {
        // 처리 중 메시지 전송
        socket.emit('streamData', {
          text: '처리 중입니다...',
          isDone: false,
          requestType: requestType
        });

        // EventSource를 사용한 SSE 연결
        const url = new URL(CLOUD_FUNCTION_URL);
        const headers = {
          'Authorization': `Bearer ${idToken}`,
          'Content-Type': 'application/json'
        };

        // POST 요청 데이터 준비 - 커스텀 템플릿 포함
        const requestData = {
          question,
          requestType
        };

        // 커스텀 템플릿이 제공된 경우에만 추가
        if (customTemplate) {
          requestData.customTemplate = customTemplate;
        }

        // POST 요청을 위한 준비
        const initResponse = await axios({
          method: 'post',
          url: CLOUD_FUNCTION_URL,
          headers: headers,
          data: requestData,
          responseType: 'text'
        });

        if (initResponse.status !== 200) {
          throw new Error(`Failed to initialize stream: ${initResponse.statusText}`);
        }

        console.log('--------------------------------------------------------------');
        console.log(`Stream initialized for ${requestType}, processing SSE data`);

        // EventSource로 스트림 데이터 수신
        let buffer = '';
        let dataCount = 0;

        // EventSource 스트림 처리
        for await (const chunk of initResponse.data.split('\n\n')) {
          if (!userSessions.has(userId) || userSessions.get(userId).socketId !== socket.id) {
            console.log('User session no longer active');
            break;
          }

          if (chunk.startsWith('data: ')) {
            try {
              const jsonData = JSON.parse(chunk.substring(6));

              // 디버깅을 위한 로깅
              dataCount++;
              if (dataCount % 10 === 0) {
                console.log(`Processed ${dataCount} data chunks for ${requestType}`);
              }

              // 첫 실제 텍스트 응답을 받으면 첫 응답 시간 기록
              if (!userSessions.get(userId).firstResponseReceived && jsonData.text &&
                  jsonData.text !== '처리 중입니다...' && jsonData.text.trim() !== '') {
                const firstResponseTime = Date.now();
                const timeToFirstResponse = firstResponseTime - userSessions.get(userId).startTime;
                console.log(`Time to first response for user ${userId} (${requestType}): ${timeToFirstResponse}ms`);

                // 세션 업데이트
                userSessions.set(userId, {
                  ...userSessions.get(userId),
                  firstResponseReceived: true,
                  firstResponseTime: firstResponseTime,
                  timeToFirstResponse: timeToFirstResponse
                });

                // 클라이언트에 첫 응답 시간 정보 전송
                socket.emit('responseTiming', {
                  timeToFirstResponseMs: timeToFirstResponse,
                  timeToFirstResponseSeconds: (timeToFirstResponse / 1000).toFixed(2),
                  requestType: requestType
                });
              }

              if (jsonData.done) {
                console.log(`Stream completed normally for ${requestType}`);

                // 완료 시간 측정 및 통계 업데이트
                const endTime = Date.now();
                const session = userSessions.get(userId);
                const totalResponseTime = endTime - session.startTime;

                console.log(`Total response time for user ${userId} (${requestType}): ${totalResponseTime}ms`);
                updateResponseTimeStats(totalResponseTime, requestType);

                // 클라이언트에 완료 및 응답 시간 정보 전송
                socket.emit('streamData', {
                  text: '',
                  isDone: true,
                  requestType: requestType,
                  responseTiming: {
                    totalTimeMs: totalResponseTime,
                    totalTimeSeconds: (totalResponseTime / 1000).toFixed(2),
                    timeToFirstResponseMs: session.timeToFirstResponse || null,
                    timeToFirstResponseSeconds: session.timeToFirstResponse ? (session.timeToFirstResponse / 1000).toFixed(2) : null
                  }
                });

                // 세션 업데이트
                userSessions.set(userId, {
                  ...userSessions.get(userId),
                  completed: true,
                  endTime: endTime,
                  totalResponseTime: totalResponseTime
                });

                break;
              } else if (jsonData.text) {
                buffer += jsonData.text;
                socket.emit('streamData', {
                  text: jsonData.text,
                  isDone: false,
                  requestType: requestType
                });
              } else if (jsonData.error) {
                throw new Error(jsonData.error);
              }
            } catch (parseError) {
              console.warn('Error parsing data:', parseError, 'Raw chunk:', chunk);
              // 파싱 에러가 발생해도 계속 진행
            }
          }
        }

        // 스트림이 정상적으로 끝나지 않았지만 데이터를 받은 경우 완료 처리
        if (userSessions.has(userId) &&
            userSessions.get(userId).socketId === socket.id &&
            !userSessions.get(userId).completed &&
            userSessions.get(userId).firstResponseReceived) {

          const endTime = Date.now();
          const session = userSessions.get(userId);
          const totalResponseTime = endTime - session.startTime;

          console.log(`Stream ended without done signal. Total time for user ${userId} (${requestType}): ${totalResponseTime}ms`);
          updateResponseTimeStats(totalResponseTime, requestType);

          socket.emit('streamData', {
            text: '',
            isDone: true,
            requestType: requestType,
            responseTiming: {
              totalTimeMs: totalResponseTime,
              totalTimeSeconds: (totalResponseTime / 1000).toFixed(2),
              timeToFirstResponseMs: session.timeToFirstResponse || null,
              timeToFirstResponseSeconds: session.timeToFirstResponse ? (session.timeToFirstResponse / 1000).toFixed(2) : null
            }
          });
        }
        // 스트림이 정상적으로 끝나지 않았고 데이터도 받지 못한 경우
        else if (userSessions.has(userId) &&
                userSessions.get(userId).socketId === socket.id &&
                !userSessions.get(userId).completed) {
          socket.emit('streamData', {
            text: '',
            isDone: true,
            requestType: requestType
          });
        }
      } catch (error) {
        console.error(`Stream error (${requestType}):`, error);
        console.log('Error details:', error.response?.data || error.message);

        if (userSessions.has(userId)) {
          socket.emit('streamError', {
            message: error.message || 'Error in stream processing',
            requestType: requestType
          });
        }
      } finally {
        // 타임아웃 정리 및 세션 정리
        clearTimeout(streamTimeout);

        if (userSessions.has(userId)) {
          const session = userSessions.get(userId);
          if (session.eventSource) {
            session.eventSource.close();
          }

          // 응답 시간 로깅 (아직 완료되지 않은 경우)
          if (!session.completed) {
            const endTime = Date.now();
            const totalTime = endTime - session.startTime;
            console.log(`Session cleaned up for user ${userId} (${requestType}). Total time: ${totalTime}ms`);
          }

          userSessions.delete(userId);
        }
      }
    });

    socket.on('disconnect', () => {
      console.log('Client disconnected:', socket.id);
      // 세션 정리
      for (const [userId, session] of userSessions.entries()) {
        if (session.socketId === socket.id) {
          if (session.eventSource) {
            session.eventSource.close();
          }

          // 응답 시간 로깅 (아직 완료되지 않은 경우)
          if (session.startTime && !session.completed) {
            const endTime = Date.now();
            const totalTime = endTime - session.startTime;
            const requestType = session.requestType || 'qna';
            console.log(`Client disconnected for user ${userId} (${requestType}). Total session time: ${totalTime}ms`);
          }

          userSessions.delete(userId);
          console.log('Cleaned up session for user:', userId);
        }
      }
    });

    socket.on('error', (error) => {
      console.error('Socket error:', error);
      // 세션 정리
      for (const [userId, session] of userSessions.entries()) {
        if (session.socketId === socket.id) {
          if (session.eventSource) {
            session.eventSource.close();
          }
          userSessions.delete(userId);
          console.log('Cleaned up session after error for user:', userId);
        }
      }
    });
});

// 응답 시간 통계 엔드포인트
app.get('/stats/response-time', (req, res) => {
  // 현재 응답 시간 통계에 가공된 정보를 추가
  const formattedStats = {
    ...responseTimeStats,
    // 밀리초 단위 정보
    averageResponseTimeFormatted: responseTimeStats.averageResponseTime.toFixed(2) + 'ms',
    minResponseTimeFormatted: responseTimeStats.minResponseTime === Number.MAX_SAFE_INTEGER ? 'N/A' : responseTimeStats.minResponseTime + 'ms',
    maxResponseTimeFormatted: responseTimeStats.maxResponseTime + 'ms',
    // 초 단위 정보
    averageResponseTimeSecondsFormatted: responseTimeStats.averageResponseTimeSeconds.toFixed(2) + 's',
    minResponseTimeSecondsFormatted: responseTimeStats.minResponseTime === Number.MAX_SAFE_INTEGER ? 'N/A' : responseTimeStats.minResponseTimeSeconds.toFixed(2) + 's',
    maxResponseTimeSecondsFormatted: responseTimeStats.maxResponseTimeSeconds.toFixed(2) + 's',
    // 요청 유형별 통계 추가
    requestTypeStats: requestTypeStats
  };

  res.status(200).json({
    stats: formattedStats
  });
});

// 서버 상태 확인 엔드포인트
app.get('/health', (req, res) => {
  res.status(200).json({
    status: 'healthy',
    socketConnections: io.engine.clientsCount,
    activeSessions: userSessions.size,
    cloudFunctionUrl: CLOUD_FUNCTION_URL,
    responseTimeStats: {
      // 밀리초 단위
      averageResponseTimeMs: responseTimeStats.averageResponseTime.toFixed(2) + 'ms',
      minResponseTimeMs: responseTimeStats.minResponseTime === Number.MAX_SAFE_INTEGER ? 'N/A' : responseTimeStats.minResponseTime + 'ms',
      maxResponseTimeMs: responseTimeStats.maxResponseTime + 'ms',
      // 초 단위
      averageResponseTimeSeconds: responseTimeStats.averageResponseTimeSeconds.toFixed(2) + 's',
      minResponseTimeSeconds: responseTimeStats.minResponseTime === Number.MAX_SAFE_INTEGER ? 'N/A' : responseTimeStats.minResponseTimeSeconds.toFixed(2) + 's',
      maxResponseTimeSeconds: responseTimeStats.maxResponseTimeSeconds.toFixed(2) + 's',
      // 기타 정보
      totalRequests: responseTimeStats.totalRequests,
      // 요청 유형별 통계
      byRequestType: {
        codeFeedback: {
          requests: requestTypeStats.codeFeedback.totalRequests,
          avgResponseTime: requestTypeStats.codeFeedback.averageResponseTime.toFixed(2) + 'ms'
        },
        codeGeneration: {
          requests: requestTypeStats.codeGeneration.totalRequests,
          avgResponseTime: requestTypeStats.codeGeneration.averageResponseTime.toFixed(2) + 'ms'
        },
        qna: {
          requests: requestTypeStats.qna.totalRequests,
          avgResponseTime: requestTypeStats.qna.averageResponseTime.toFixed(2) + 'ms'
        }
      }
    }
  });
});

// 오류 처리 미들웨어
app.use((err, req, res, next) => {
  console.error('Server error:', err);
  res.status(500).json({ error: 'Internal server error' });
});

const PORT = process.env.PORT || 3001;
server.listen(PORT, () => {
  console.log(`Stream server running on port ${PORT}`);
  console.log(`Using Cloud Function URL: ${CLOUD_FUNCTION_URL}`);
});

// 정상 종료 처리
process.on('SIGTERM', () => {
  console.log('SIGTERM received. Cleaning up...');
  server.close(() => {
    console.log('Server closed');
    process.exit(0);
  });
});

process.on('SIGINT', () => {
  console.log('SIGINT received. Cleaning up...');
  server.close(() => {
    console.log('Server closed');
    process.exit(0);
  });
});