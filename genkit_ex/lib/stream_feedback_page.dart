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
import 'package:shared_preferences/shared_preferences.dart'; // 로컬 저장소를 위해 추가

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

// 프롬프트 템플릿 관리를 위한 클래스 추가
class PromptTemplates {
  String codeFeedback;
  String codeGeneration;
  String qna;

  PromptTemplates({
    required this.codeFeedback,
    required this.codeGeneration,
    required this.qna,
  });

  // JSON으로 변환
  Map<String, dynamic> toJson() {
    return {
      'codeFeedback': codeFeedback,
      'codeGeneration': codeGeneration,
      'qna': qna,
    };
  }

  // JSON에서 객체로 변환
  factory PromptTemplates.fromJson(Map<String, dynamic> json) {
    return PromptTemplates(
      codeFeedback: json['codeFeedback'] ?? '',
      codeGeneration: json['codeGeneration'] ?? '',
      qna: json['qna'] ?? '',
    );
  }

  // 기본 템플릿 제공
  factory PromptTemplates.defaults() {
    return PromptTemplates(
      codeFeedback: "I will provide you with Flutter code and specific requirements. " +
          "Please analyze the code and provide suggestions based on the requirements.\n\n" +
          "Flutter Code:\n" +
          "\${code}\n\n" +
          "Requirements:\n" +
          "\${requirements}\n\n" +
          "Please provide:\n" +
          "1. Analysis of how well the code meets the requirements\n" +
          "2. Specific suggestions for improvements or modifications\n" +
          "3. Code examples for suggested changes if necessary\n" +
          "4. Best practices and optimization recommendations",
      codeGeneration: "Please generate a coding problem based on the following specifications." +
          "The problem should be challenging but solvable, and include:\n" +
          "1. A clear problem statement\n" +
          "2. Input and output specifications\n" +
          "3. Example inputs and expected outputs\n" +
          "4. Constraints or limitations\n" +
          "5. Hints for solving (optional)\n\n" +
          "Specifications: \${specifications}",
      qna: "Please provide a detailed and accurate answer to the following question:\n\n\${question}",
    );
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

  // 프롬프트 템플릿 관리
  late PromptTemplates _promptTemplates;
  bool _isPromptTemplatesLoaded = false;

  // 템플릿 편집을 위한 컨트롤러
  final TextEditingController _codeFeedbackController = TextEditingController();
  final TextEditingController _codeGenerationController = TextEditingController();
  final TextEditingController _qnaController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadPromptTemplates();
    _initializeSocket();
  }

  // 프롬프트 템플릿 로드
  Future<void> _loadPromptTemplates() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        // 로그인하지 않은 경우 로컬 저장소에서 로드
        _loadLocalPromptTemplates();
        return;
      }

      // Firestore에서 사용자별 프롬프트 템플릿 로드
      final docSnapshot = await FirebaseFirestore.instance
          .collection('user_prompt_templates')
          .doc(user.uid)
          .get();

      if (docSnapshot.exists) {
        final data = docSnapshot.data() as Map<String, dynamic>;
        _promptTemplates = PromptTemplates.fromJson(data);
      } else {
        // 템플릿이 없으면 기본값 설정 후 저장
        _promptTemplates = PromptTemplates.defaults();
        _savePromptTemplates();
      }

      // 컨트롤러 초기화
      _initializeControllers();
    } catch (e) {
      if (kDebugMode) {
        print('Error loading prompt templates: $e');
      }
      // 오류 발생 시 로컬 저장소에서 로드
      _loadLocalPromptTemplates();
    } finally {
      setState(() {
        _isPromptTemplatesLoaded = true;
        _isLoading = false;
      });
    }
  }

  // 로컬 저장소에서 프롬프트 템플릿 로드
  Future<void> _loadLocalPromptTemplates() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final templatesJson = prefs.getString('prompt_templates');

      if (templatesJson != null) {
        _promptTemplates = PromptTemplates.fromJson(jsonDecode(templatesJson));
      } else {
        _promptTemplates = PromptTemplates.defaults();
      }

      // 컨트롤러 초기화
      _initializeControllers();
    } catch (e) {
      if (kDebugMode) {
        print('Error loading local prompt templates: $e');
      }
      // 오류 발생 시 기본값 사용
      _promptTemplates = PromptTemplates.defaults();
      _initializeControllers();
    } finally {
      setState(() {
        _isPromptTemplatesLoaded = true;
        _isLoading = false;
      });
    }
  }

  // 컨트롤러 초기화
  void _initializeControllers() {
    _codeFeedbackController.text = _promptTemplates.codeFeedback;
    _codeGenerationController.text = _promptTemplates.codeGeneration;
    _qnaController.text = _promptTemplates.qna;
  }

  // 프롬프트 템플릿 저장
  Future<void> _savePromptTemplates() async {
    try {
      // 현재 컨트롤러 값으로 템플릿 업데이트
      _promptTemplates = PromptTemplates(
        codeFeedback: _codeFeedbackController.text,
        codeGeneration: _codeGenerationController.text,
        qna: _qnaController.text,
      );

      // 로컬 저장소에 저장
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('prompt_templates', jsonEncode(_promptTemplates.toJson()));

      // 로그인한 사용자면 Firestore에도 저장
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        await FirebaseFirestore.instance
            .collection('user_prompt_templates')
            .doc(user.uid)
            .set(_promptTemplates.toJson());
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('템플릿이 저장되었습니다')),
      );
    } catch (e) {
      if (kDebugMode) {
        print('Error saving prompt templates: $e');
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('템플릿 저장 중 오류가 발생했습니다: ${e.toString()}')),
      );
    }
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

      // 스트리밍 요청 전송 (요청 유형 및 커스텀 템플릿 포함)
      socket.emit('startStream', {
        'question': _questionController.text,
        'userId': user.uid,
        'idToken': idToken,
        'requestType': _selectedRequestType.value,
        'customTemplate': _getCurrentTemplate(), // 현재 선택된 유형의 커스텀 템플릿 전송
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

  // 현재 선택된 요청 유형에 따른 템플릿 반환
  String _getCurrentTemplate() {
    if (!_isPromptTemplatesLoaded) {
      return '';
    }

    switch (_selectedRequestType) {
      case RequestType.codeFeedback:
        return _promptTemplates.codeFeedback;
      case RequestType.codeGeneration:
        return _promptTemplates.codeGeneration;
      case RequestType.qna:
        return _promptTemplates.qna;
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
            icon: const Icon(Icons.settings),
            onPressed: () => _showTemplateSettingsDialog(),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
        children: [
          Expanded(
            child: DefaultTabController(
              length: 1,
              child: Column(
                children: [
                  TabBar(
                    tabs: const [
                      Tab(text: 'New Question'),
                    ],
                    labelColor: Theme.of(context).primaryColor,
                  ),
                  Expanded(
                    child: TabBarView(
                      children: [
                        _buildNewQuestionTab(),
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

  // 템플릿 설정 다이얼로그 표시
  void _showTemplateSettingsDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('프롬프트 템플릿 설정'),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('각 요청 타입에 대한 커스텀 프롬프트 템플릿을 설정하세요.'),
                const SizedBox(height: 16),

                // 코드 피드백 템플릿
                const Text('코드 피드백 템플릿:', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                TextField(
                  controller: _codeFeedbackController,
                  maxLines: 6,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    hintText: '코드 피드백을 위한 프롬프트 템플릿',
                    filled: true,
                  ),
                ),
                const SizedBox(height: 16),

                // 코드 생성 템플릿
                const Text('문제 생성 템플릿:', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                TextField(
                  controller: _codeGenerationController,
                  maxLines: 6,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    hintText: '문제 생성을 위한 프롬프트 템플릿',
                    filled: true,
                  ),
                ),
                const SizedBox(height: 16),

                // 질의응답 템플릿
                const Text('질의응답 템플릿:', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                TextField(
                  controller: _qnaController,
                  maxLines: 6,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    hintText: '질의응답을 위한 프롬프트 템플릿',
                    filled: true,
                  ),
                ),

                const SizedBox(height: 8),
                Text(
                  '변수는 \${code}, \${requirements}, \${specifications}, \${question} 등으로 사용할 수 있습니다.',
                  style: TextStyle(color: Colors.grey[700], fontSize: 12),
                )
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              // 기본값으로 리셋
              _codeFeedbackController.text = PromptTemplates.defaults().codeFeedback;
              _codeGenerationController.text = PromptTemplates.defaults().codeGeneration;
              _qnaController.text = PromptTemplates.defaults().qna;
            },
            child: const Text('기본값으로 리셋'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('취소'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _savePromptTemplates();
            },
            child: const Text('저장'),
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

  /*Widget _buildHistoryTab() {
    return const Center(
      child: Text('DB에 안 찍을 거지롱 >ㅁ<'),
    );
  }*/

  @override
  void dispose() {
    _sseSubscription?.cancel();
    socket.disconnect();
    _questionController.dispose();
    _codeFeedbackController.dispose();
    _codeGenerationController.dispose();
    _qnaController.dispose();
    super.dispose();
  }
}