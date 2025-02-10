import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'package:http/http.dart' as http;

class FeedbackData {
  final String question;
  final String feedback;

  FeedbackData({
    required this.question,
    required this.feedback,
  });

  factory FeedbackData.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return FeedbackData(
      question: data['question'] ?? '',
      feedback: data['feedback'] ?? '',
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

  @override
  void initState() {
    super.initState();
    _initializeSocket();
    _loadPreviousFeedbacks();
  }

  Future<void> _loadPreviousFeedbacks() async {
    if (!mounted) return;

    setState(() {
      _isLoading = true;
    });

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final querySnapshot = await FirebaseFirestore.instance
          .collection('streaming_feedback')
          .where('userId', isEqualTo: user.uid)
          .orderBy('timestamp', descending: true)
          .limit(10)
          .get();

      if (!mounted) return;

      setState(() {
        previousFeedbacks = querySnapshot.docs
            .map((doc) => FeedbackData.fromFirestore(doc))
            .toList();
        _isLoading = false;
      });
    } catch (e) {
      if (kDebugMode) {
        print('Error loading previous feedbacks: $e');
      }
      if (!mounted) return;

      setState(() {
        _isLoading = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to load previous feedbacks: ${e.toString()}')),
      );
    }
  }

  void _initializeSocket() {
    final serverUrl = const bool.fromEnvironment('USE_FIREBASE_EMULATOR', defaultValue: false)
        ? 'http://localhost:3001'
        : 'https://your-production-domain.com';

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
    if (user == null) return;

    try {
      // WebSocket 스트림 시작
      socket.emit('startStream', {
        'question': _questionController.text,
        'userId': user.uid,
      });

      // Cloud Function 호출
      final idToken = await user.getIdToken();
      final functionUrl = const bool.fromEnvironment('USE_FIREBASE_EMULATOR', defaultValue: false)
          ? 'http://localhost:5001/ai-project-738a2/us-central1/aiStreamingFeedback'
          : 'https://your-production-function-url.com';

      final response = await http.post(
        Uri.parse(functionUrl),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $idToken',
        },
        body: json.encode({
          'question': _questionController.text,
        }),
      );

      if (response.statusCode == 200) {
        final stream = response.body.split('\n\n');
        for (var data in stream) {
          if (data.startsWith('data: ')) {
            final jsonData = json.decode(data.substring(6));
            if (jsonData['done'] == true) {
              setState(() {
                _isProcessing = false;
              });
              break;
            }
            setState(() {
              _streamResponse += jsonData['text'] ?? '';
            });
          }
        }
      } else {
        throw Exception('Failed to connect to Cloud Function: ${response.statusCode}');
      }
    } catch (error) {
      if (kDebugMode) {
        print('Error during stream processing: $error');
      }
      setState(() {
        _isStreaming = false;
        _isProcessing = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: ${error.toString()}')),
      );
    }
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
            onPressed: _loadPreviousFeedbacks,
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
                  TextField(
                    controller: _questionController,
                    maxLines: 3,
                    decoration: InputDecoration(
                      border: const OutlineInputBorder(),
                      labelText: 'Your Question',
                      hintText: 'Type your question here...',
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

  Widget _buildHistoryTab() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (previousFeedbacks.isEmpty) {
      return const Center(
        child: Text('No previous feedbacks available'),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16.0),
      itemCount: previousFeedbacks.length,
      itemBuilder: (context, index) {
        final feedback = previousFeedbacks[index];
        return Card(
          margin: const EdgeInsets.only(bottom: 16.0),
          child: ExpansionTile(
            title: Text(
              feedback.question,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            children: [
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: SelectableText(feedback.feedback),
              ),
            ],
          ),
        );
      },
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