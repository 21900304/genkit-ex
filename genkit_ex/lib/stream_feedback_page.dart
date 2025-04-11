import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'package:http/http.dart' as http;

// 요청 유형 정의
enum RequestType {
  codeFeedback,
  codeGeneration,
  qna
}

extension RequestTypeExtension on RequestType {
  String get value {
    switch (this) {
      case RequestType.codeFeedback:
        return 'codeFeedback';
      case RequestType.codeGeneration:
        return 'codeGeneration';
      case RequestType.qna:
        return 'qna';
    }
  }

  String get displayName {
    switch (this) {
      case RequestType.codeFeedback:
        return '코드 피드백';
      case RequestType.codeGeneration:
        return '문제 생성';
      case RequestType.qna:
        return '질의 응답';
    }
  }
}

class FeedbackData {
  final String question;
  final String feedback;
  final String requestType;

  FeedbackData({
    required this.question,
    required this.feedback,
    this.requestType = 'qna',
  });

  factory FeedbackData.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return FeedbackData(
      question: data['question'] ?? '',
      feedback: data['feedback'] ?? '',
      requestType: data['requestType'] ?? 'qna',
    );
  }
}

class StreamFeedbackPage extends StatefulWidget {
  const StreamFeedbackPage({super.key, required this.title});
  final String title;

  @override
  State<StreamFeedbackPage> createState() => _StreamFeedbackPageState();
}

class _StreamFeedbackPageState extends State<StreamFeedbackPage> {
  final TextEditingController _questionController = TextEditingController();
  String _streamResponse = '';
  bool _isStreaming = false;
  bool _isProcessing = false;
  late IO.Socket socket;
  List<FeedbackData> previousFeedbacks = [];
  bool _isLoading = false;
  StreamSubscription? _sseSubscription;

  // 선택된 요청 유형
  RequestType _selectedRequestType = RequestType.qna;

  @override
  void initState() {
    super.initState();
    _initializeSocket();
  }


  void _initializeSocket() {
    final serverUrl = const bool.fromEnvironment('USE_FIREBASE_EMULATOR', defaultValue: false)
        ? 'http://localhost:3001'
        : 'http://localhost:3001';

    if (kDebugMode) {
      print('Platform: ${kIsWeb ? 'Web' : Platform.operatingSystem}');
      print('Connecting to socket server at: $serverUrl');
    }

    socket = IO.io(serverUrl, IO.OptionBuilder()
        .setTransports(['websocket', 'polling'])
        .enableForceNew()
        .enableReconnection()
        .setReconnectionAttempts(5)
        .setReconnectionDelay(2000)
        .setTimeout(20000)
        .build());

    socket.onConnect((_) {
      if (kDebugMode) {
        print('Socket connected successfully');
        print('Socket ID: ${socket.id}');
      }
    });

    socket.on('streamData', (data) {
      if (mounted) {
        if (data is Map<String, dynamic>) {
          setState(() {
            if (data['isDone'] == true) {
              _isStreaming = false;
              _isProcessing = false;
            } else {
              final text = data['text'];
              if (text != null) {
                _streamResponse += text.toString();
              }
            }
          });
        }
      }
    });

    socket.on('streamError', (data) {
      if (mounted) {
        setState(() {
          _isStreaming = false;
          _isProcessing = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(data['message'] ?? 'Stream error occurred')),
        );
      }
    });

    socket.onError((error) {
      if (kDebugMode) {
        print('Socket error details:');
        print(error);
      }
      if (mounted) {
        setState(() {
          _isStreaming = false;
          _isProcessing = false;
        });
      }
    });

    socket.onDisconnect((_) {
      if (kDebugMode) {
        print('Socket disconnected');
        print('Attempting to reconnect...');
      }
      if (!socket.connected) {
        socket.connect();
      }
    });

    socket.connect();
  }

  Future<void> _startStream() async {
    if (_questionController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter your question first')),
      );
      return;
    }

    setState(() {
      _isStreaming = true;
      _isProcessing = true;
      _streamResponse = '';
    });

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      setState(() {
        _isStreaming = false;
        _isProcessing = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('로그인이 필요합니다')),
      );
      return;
    }

    try {
      // 사용자 인증 토큰 획득
      final idToken = await user.getIdToken();

      if (kDebugMode) {
        print('Starting stream with socket.io');
        print('User ID: ${user.uid}');
        print('Request Type: ${_selectedRequestType.value}');
        print('Question: ${_questionController.text.substring(0, min(50, _questionController.text.length))}...');
      }

      // 소켓 연결 확인
      if (!socket.connected) {
        if (kDebugMode) {
          print('Socket disconnected, attempting to reconnect...');
        }

        // 소켓 재연결 시도
        socket.connect();

        // 연결 대기
        await Future.delayed(const Duration(seconds: 2));

        if (!socket.connected) {
          throw Exception('Socket connection failed. Please try again later.');
        }
      }

      // 응답 처리를 위한 리스너 설정 (기존 리스너가 없을 경우에만)
      _setupSocketListeners();

      // 스트리밍 요청 전송 (요청 유형 포함)
      socket.emit('startStream', {
        'question': _questionController.text,
        'userId': user.uid,
        'idToken': idToken,
        'requestType': _selectedRequestType.value, // 요청 유형 추가
      });

      // 타임아웃 설정 (60초)
      Future.delayed(const Duration(seconds: 60), () {
        if (_isProcessing) {
          setState(() {
            _isProcessing = false;
            if (_streamResponse.isEmpty) {
              _streamResponse = '응답 시간이 초과되었습니다. 나중에 다시 시도해주세요.';
            }
          });
        }
      });

    } catch (error) {
      if (kDebugMode) {
        print('Error during stream processing: $error');
      }
      setState(() {
        _isStreaming = false;
        _isProcessing = false;
        if (_streamResponse.isEmpty) {
          _streamResponse = '오류가 발생했습니다: ${error.toString()}';
        }
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: ${error.toString()}')),
      );
    }
  }

  // 소켓 리스너 설정 메서드
  void _setupSocketListeners() {
    // 기존 리스너 제거
    socket.off('streamData');
    socket.off('streamError');

    // 데이터 수신 리스너
    socket.on('streamData', (data) {
      if (mounted) {
        if (data is Map<String, dynamic>) {
          setState(() {
            if (data['isDone'] == true) {
              _isStreaming = false;
              _isProcessing = false;
            } else {
              final text = data['text'];
              if (text != null && text.toString().isNotEmpty) {
                // '처리 중입니다...' 메시지를 받았을 때 초기화
                if (_streamResponse == '처리 중입니다...' && text.toString() != '처리 중입니다...') {
                  _streamResponse = text.toString();
                } else {
                  _streamResponse += text.toString();
                }
              }
            }
          });
        }
      }
    });

    // 오류 수신 리스너
    socket.on('streamError', (data) {
      if (mounted) {
        setState(() {
          _isStreaming = false;
          _isProcessing = false;

          // 오류 메시지가 있으면 표시
          if (data is Map<String, dynamic> && data['message'] != null) {
            _streamResponse += '\n\n오류: ${data['message']}';
          } else {
            _streamResponse += '\n\n알 수 없는 오류가 발생했습니다.';
          }
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: Text(widget.title),
        actions: [
          IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: (){}//_loadPreviousFeedbacks,
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: DefaultTabController(
              length: 2,
              child: Column(
                children: [
                  TabBar(
                    tabs: const [
                      Tab(text: 'New Question'),
                      Tab(text: 'History'),
                    ],
                    labelColor: Theme.of(context).primaryColor,
                  ),
                  Expanded(
                    child: TabBarView(
                      children: [
                        _buildNewQuestionTab(),
                        _buildHistoryTab(),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNewQuestionTab() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Card(
            elevation: 2,
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Ask a Question',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 16),
                  // 요청 유형 선택기 추가
                  DropdownButtonFormField<RequestType>(
                    value: _selectedRequestType,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      labelText: '요청 유형 선택',
                      filled: true,
                    ),
                    items: RequestType.values.map((type) {
                      return DropdownMenuItem<RequestType>(
                        value: type,
                        child: Text(type.displayName),
                      );
                    }).toList(),
                    onChanged: (RequestType? value) {
                      if (value != null) {
                        setState(() {
                          _selectedRequestType = value;
                        });
                      }
                    },
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _questionController,
                    maxLines: 3,
                    decoration: InputDecoration(
                      border: const OutlineInputBorder(),
                      labelText: _getQuestionLabel(),
                      hintText: _getQuestionHint(),
                      filled: true,
                      fillColor: Colors.grey[50],
                    ),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: (_isStreaming || _isProcessing) ? null : _startStream,
                    icon: (_isStreaming || _isProcessing)
                        ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                        : const Icon(Icons.send),
                    label: Text(
                      (_isStreaming || _isProcessing)
                          ? 'Processing...'
                          : 'Get Feedback',
                    ),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        vertical: 12,
                        horizontal: 24,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_streamResponse.isNotEmpty) ...[
            const SizedBox(height: 16),
            Expanded(
              child: Card(
                elevation: 2,
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Response',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 16),
                      Expanded(
                        child: SingleChildScrollView(
                          child: SelectableText(
                            _streamResponse,
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // 요청 유형에 따른 질문 라벨 반환
  String _getQuestionLabel() {
    switch (_selectedRequestType) {
      case RequestType.codeFeedback:
        return '코드와 요구사항';
      case RequestType.codeGeneration:
        return '문제 생성을 위한 조건';
      case RequestType.qna:
        return '질문';
    }
  }

  // 요청 유형에 따른 힌트 텍스트 반환
  String _getQuestionHint() {
    switch (_selectedRequestType) {
      case RequestType.codeFeedback:
        return '코드를 입력한 후, [요구사항] 형식으로 요구사항을 작성하세요';
      case RequestType.codeGeneration:
        return '문제 생성을 위한 조건을 입력하세요 (예: 난이도, 주제, 특정 개념 등)';
      case RequestType.qna:
        return '질문을 입력하세요';
    }
  }

  Widget _buildHistoryTab() {
    return const Center(
      child: Text('DB에 안 찍을 거지롱 >ㅁ<'),
    );
  }

  @override
  void dispose() {
    _sseSubscription?.cancel();
    socket.disconnect();
    _questionController.dispose();
    super.dispose();
  }
}