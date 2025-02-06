/*
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:ui';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:retry/retry.dart';

/// WebSocket 연결 상태를 나타내는 열거형
enum ConnectionState {
  disconnected,    // 연결이 끊어진 상태
  connecting,      // 연결을 시도하는 중
  waitingReady,    // 서버 준비를 기다리는 중
  authenticating,  // 인증 진행 중
  connected,       // 연결된 상태
  reconnecting     // 재연결을 시도하는 중
}

/// 연결 메타데이터를 관리하는 클래스
class ConnectionMetadata {
  final DateTime connectionStartTime;
  DateTime lastMessageTime;
  int messageCount;
  int reconnectAttempts;
  final String connectionId;
  final Map<String, dynamic> _debugInfo = {};

  ConnectionMetadata({
    DateTime? connectionStartTime,
    DateTime? lastMessageTime,
    this.messageCount = 0,
    this.reconnectAttempts = 0,
    String? connectionId,
  }) :
        connectionStartTime = connectionStartTime ?? DateTime.now(),
        lastMessageTime = lastMessageTime ?? DateTime.now(),
        connectionId = connectionId ?? DateTime.now().millisecondsSinceEpoch.toString();

  /// 디버깅 정보 추가
  void addDebugInfo(String key, Map<String, dynamic> info) {
    _debugInfo[key] = Map<String, dynamic>.from(info)
      ..addAll({'timestamp': DateTime.now().toIso8601String()});
  }

  /// 메타데이터를 JSON으로 변환
  Map<String, dynamic> toJson() {
    return {
      'connectionDuration': DateTime.now().difference(connectionStartTime).toString(),
      'timeSinceLastMessage': DateTime.now().difference(lastMessageTime).toString(),
      'messageCount': messageCount,
      'reconnectAttempts': reconnectAttempts,
      'connectionId': connectionId,
      'debugInfo': Map<String, dynamic>.from(_debugInfo),
    };
  }
}

/// 서비스 관련 예외를 처리하는 클래스
class ServiceException implements Exception {
  final String message;
  final String? connectionId;
  final ConnectionState? connectionState;
  final DateTime timestamp;

  ServiceException(
      this.message, {
        this.connectionId,
        this.connectionState,
      }) : timestamp = DateTime.now();

  Map<String, dynamic> toJson() => {
    'message': message,
    'connectionId': connectionId,
    'connectionState': connectionState?.toString(),
    'timestamp': timestamp.toIso8601String(),
  };

  @override
  String toString() => message;
}

/// WebSocket을 통한 스트리밍 서비스를 관리하는 클래스
class StreamingService {
  // 내부 상태 관리
  WebSocketChannel? _channel;
  ConnectionState _connectionState = ConnectionState.disconnected;
  ConnectionMetadata? _metadata;

  // 타이머 관리
  Timer? _reconnectionTimer;
  Timer? _connectionTimer;
  Timer? _monitoringTimer;

  // 설정 상수
  static const int _maxReconnectAttempts = 3;
  static const Duration _reconnectDelay = Duration(seconds: 2);
  static const Duration _connectionTimeout = Duration(seconds: 30);
  static const Duration _monitoringInterval = Duration(seconds: 5);

  // 활성 스트림 관리
  final Map<String, StreamController<String>> _activeStreams = {};

  /// 플랫폼에 따른 WebSocket URL 반환
  String _getBaseUrl() {
    final wsProtocol = kDebugMode ? 'ws' : 'wss';
    final baseUrl = kDebugMode
        ? (!kIsWeb
        ? (Platform.isAndroid ? '10.0.2.2:5001' : 'localhost:5001')
        : 'localhost:5001')
        : 'your-production-url.cloudfunctions.net';

    // 함수 경로를 baseUrl에 포함하지 않고 별도로 처리
    return '$wsProtocol://$baseUrl';
  }

// WebSocket 연결 시 전체 URL 구성
  //final wsUrl = '${_getBaseUrl()}/ai-project-738a2/us-central1/aiCodeFeedbackStream';

  /// WebSocket 스트림 연결 설정
  /// WebSocket 스트림 연결 설정
  Future<Stream<String>> connectToStream(String question) async {
    final streamController = StreamController<String>();
    final connectionId = DateTime.now().millisecondsSinceEpoch.toString();
    final connectionCompleter = Completer<void>();

    final retry = RetryOptions(
      maxAttempts: 5,
      delayFactor: const Duration(seconds: 2),
    );

    try {
      await retry.retry(
            () async {
          _metadata = ConnectionMetadata(connectionId: connectionId);
          _connectionState = ConnectionState.connecting;

          // 인증 확인
          final user = FirebaseAuth.instance.currentUser;
          if (user == null) {
            throw _createServiceException('User not authenticated');
          }

          // 인증 토큰 획득
          final token = await user.getIdToken();

          // WebSocket URL 구성
          final wsProtocol = kDebugMode ? 'ws' : 'wss';
          final baseUrl = kDebugMode
              ? (!kIsWeb
              ? (Platform.isAndroid ? '10.0.2.2:5001' : 'localhost:5001')
              : 'localhost:5001')
              : 'your-production-url.cloudfunctions.net';

          final wsUrl = '$wsProtocol://$baseUrl/ai-project-738a2/us-central1/aiCodeFeedbackStream';

          print('Request Url : $wsUrl');

          _logInfo('WebSocket connection attempt details', {
            'url': wsUrl,
            'connectionId': connectionId,
            'authStatus': 'token_acquired',
            'timestamp': DateTime.now().toIso8601String(),
          });

          try {
            // WebSocket 연결 시도
            _channel = WebSocketChannel.connect(
              Uri.parse(wsUrl),
              protocols: ['websocket'],
            );

            // 연결 상태 모니터링 설정
            _monitoringTimer?.cancel();
            _monitoringTimer = Timer.periodic(
              const Duration(seconds: 2),
                  (timer) => _checkConnectionStatus(),
            );

            // 연결 타임아웃 설정
            _connectionTimer = Timer(_connectionTimeout, () {
              if (!connectionCompleter.isCompleted) {
                _logError('Connection timeout', {
                  'connectionId': connectionId,
                  'timeout': _connectionTimeout.inSeconds,
                  'state': _connectionState.toString(),
                });
                connectionCompleter.completeError(
                  _createServiceException('Connection timeout'),
                );
              }
            });

            // 메시지 리스너 설정
            _setupMessageListener(
              streamController,
              question,
              connectionId,
              connectionCompleter,
              token!,
            );

          } catch (e, stack) {
            _logError('WebSocket connection setup error', {
              'error': e.toString(),
              'stack': stack.toString(),
              'connectionId': connectionId,
              'url': wsUrl,
              'state': _connectionState.toString(),
            });
            rethrow;
          }

          // 연결 완료 대기
          await connectionCompleter.future;
          _activeStreams[connectionId] = streamController;
        },
        retryIf: (e) => e is WebSocketChannelException || e is ServiceException,
        onRetry: (e) {
          _logWarning('Retrying connection', {
            'error': e.toString(),
            'connectionId': connectionId,
            'attempt': (_metadata?.reconnectAttempts ?? 0) + 1,
            'timestamp': DateTime.now().toIso8601String(),
          });
          _metadata?.reconnectAttempts = (_metadata?.reconnectAttempts ?? 0) + 1;
          return _cleanupConnection();
        },
      );

    } catch (e, stack) {
      _logError('Connection establishment failed', {
        'error': e.toString(),
        'stack': stack.toString(),
        'connectionId': connectionId,
        'state': _connectionState.toString(),
        'attempts': _metadata?.reconnectAttempts ?? 0,
      });

      await _cleanupConnection();
      streamController.addError(_createServiceException(e.toString()));
      await streamController.close();
      rethrow;
    }

    // 스트림 변환기 설정
    final transformedStream = streamController.stream.transform(
      StreamTransformer<String, String>.fromHandlers(
        handleError: (error, stackTrace, sink) {
          _logError('Stream transformation error', {
            'error': error.toString(),
            'stack': stackTrace.toString(),
            'connectionId': connectionId,
          });
          sink.addError(error);
        },
        handleDone: (sink) async {
          _logInfo('Stream completed', {
            'connectionId': connectionId,
            'state': _connectionState.toString(),
            'timestamp': DateTime.now().toIso8601String(),
          });
          await _cleanupConnection();
          sink.close();
        },
      ),
    );

    return transformedStream;
  }

  /// 연결 상태 체크
  void _checkConnectionStatus() {
    if (_channel != null) {
      _logInfo('Connection status check', {
        'state': _connectionState.toString(),
        'channelState': _channel?.sink.done != null ? 'active' : 'closed',
        'lastMessageTime': _metadata?.lastMessageTime.toIso8601String(),
        'reconnectAttempts': _metadata?.reconnectAttempts,
        'connectionId': _metadata?.connectionId,
        'timestamp': DateTime.now().toIso8601String(),
      });
    }
  }

  /// 메시지 리스너 설정
  void _setupMessageListener(
      StreamController<String> streamController,
      String question,
      String connectionId,
      Completer<void> connectionCompleter,
      String token,
      ) {
    _channel!.stream.listen(
          (message) {
        try {
          _logInfo('Message received', {
            'raw': message.toString(),
            'connectionId': connectionId,
          });

          final data = jsonDecode(message.toString());

          switch (data['type']) {
            case 'status':
              if (data['status'] == 'authenticated') {
                _connectionState = ConnectionState.connected;
                _connectionTimer?.cancel();

                if (!connectionCompleter.isCompleted) {
                  connectionCompleter.complete();
                }

                // 질문 전송
                _channel!.sink.add(jsonEncode({
                  'type': 'question',
                  'question': question,
                  'timestamp': DateTime.now().toIso8601String(),
                }));
              }
              break;

            case 'chunk':
              if (data['content'] != null) {
                streamController.add(data['content']);
              }
              break;

            case 'complete':
              _cleanupConnection();
              streamController.close();
              break;

            case 'error':
              throw _createServiceException(data['error']);
          }
        } catch (e) {
          _handleConnectionError(e.toString(), streamController);
        }
      },
      onError: (error) {
        _logError('WebSocket error', {
          'error': error.toString(),
          'connectionId': connectionId,
        });
        _handleConnectionError(error.toString(), streamController);
      },
      onDone: () {
        _logInfo('WebSocket connection closed', {
          'connectionId': connectionId,
          'state': _connectionState.toString(),
        });
        _handleConnectionClosed(streamController);
      },
      cancelOnError: false,
    );

    // 초기 인증 메시지 전송
    _channel!.sink.add(jsonEncode({
      'type': 'auth',
      'token': token,
      'timestamp': DateTime.now().toIso8601String(),
    }));
  }

  /// 연결 에러 처리
  Future<void> _handleConnectionError(String error, StreamController<String> streamController) async {
    _logError('Connection error occurred', {
      'error': error,
      'connectionId': _metadata?.connectionId,
      'state': _connectionState.toString()
    });

    if (!streamController.isClosed) {
      streamController.addError(error);
      await streamController.close();  // StreamController.close()는 Future를 반환합니다
    }

    await _cleanupConnection();  // 정리 작업도 비동기로 처리
  }

  /// 연결 종료 처리
  void _handleConnectionClosed(StreamController<String> streamController) {
    _logInfo('Connection closed handler', {
      'connectionId': _metadata?.connectionId,
      'state': _connectionState.toString(),
      'reconnectAttempts': _metadata?.reconnectAttempts
    });

    if (_connectionState != ConnectionState.connected) {
      _handleReconnect(streamController);
    } else {
      _cleanupConnection();
    }
  }

  /// 재연결 처리
  void _handleReconnect(StreamController<String> streamController) {
    if ((_metadata?.reconnectAttempts ?? 0) >= _maxReconnectAttempts) {
      _logWarning('Max reconnection attempts reached', {
        'attempts': _metadata?.reconnectAttempts,
        'connectionId': _metadata?.connectionId
      });
      _handleConnectionError('Max reconnection attempts reached', streamController);
      return;
    }

    _connectionState = ConnectionState.reconnecting;
    _metadata?.reconnectAttempts = (_metadata?.reconnectAttempts ?? 0) + 1;

    _logInfo('Attempting to reconnect', {
      'attempt': _metadata?.reconnectAttempts,
      'connectionId': _metadata?.connectionId,
      'delay': _reconnectDelay.inSeconds
    });

    _reconnectionTimer = Timer(_reconnectDelay, () {
      // 재연결 시도는 connectToStream을 통해 처리됨
    });
  }

  /// 연결 정리
  Future<void> _cleanupConnection() async {
    _logInfo('Cleaning up connection', {
      'connectionId': _metadata?.connectionId,
      'state': _connectionState.toString()
    });

    _connectionTimer?.cancel();
    _reconnectionTimer?.cancel();
    _monitoringTimer?.cancel();

    if (_channel != null) {
      await _channel!.sink.close();  // WebSocketSink.close()는 Future를 반환합니다
      _channel = null;
    }

    _connectionState = ConnectionState.disconnected;
    _metadata = null;
  }

  /// 서비스 예외 생성
  ServiceException _createServiceException(String message) {
    return ServiceException(
      message,
      connectionId: _metadata?.connectionId,
      connectionState: _connectionState,
    );
  }

  /// 정보 로깅
  void _logInfo(String message, Map<String, dynamic> data) {
    if (kDebugMode) {
      final logData = Map<String, dynamic>.from(data)
        ..addAll({
          'timestamp': DateTime.now().toIso8601String(),
          if (_metadata?.connectionId != null) 'connectionId': _metadata!.connectionId,
        });

      if (_metadata != null) {
        _metadata!.addDebugInfo(message, logData);
      }

      print('StreamingService - $message: ${jsonEncode(logData)}');
    }
  }

  /// 경고 로깅
  void _logWarning(String message, Map<String, dynamic> data) {
    if (kDebugMode) {
      final logData = {
        ...data,
        'timestamp': DateTime.now().toIso8601String(),
        if (_metadata?.connectionId != null) 'connectionId': _metadata!.connectionId,
      };
      print('StreamingService WARNING - $message: ${jsonEncode(logData)}');
      _metadata?.addDebugInfo('WARNING: $message', logData);
    }
  }

  /// 에러 로깅
  void _logError(String message, Map<String, dynamic> data) {
    if (kDebugMode) {
      final logData = {
        ...data,
        'timestamp': DateTime.now().toIso8601String(),
        if (_metadata?.connectionId != null) 'connectionId': _metadata!.connectionId,
      };
      print('StreamingService ERROR - $message: ${jsonEncode(logData)}');
      _metadata?.addDebugInfo('ERROR: $message', logData);
    }
  }

  /// 서비스 정리
  void dispose() {
    _logInfo('Disposing StreamingService', {
      'activeStreams': _activeStreams.length,
      'connectionState': _connectionState.toString()
    });
    _cleanupConnection();
  }
}*/
