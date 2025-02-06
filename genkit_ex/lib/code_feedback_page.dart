/*
// lib/pages/code_feedback_page.dart

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:genkit_ex/streaming_service.dart';

import 'auth_page.dart';
import 'main.dart';


class CodeFeedbackPage extends StatefulWidget {
  const CodeFeedbackPage({super.key, required this.title});
  final String title;

  @override
  State<CodeFeedbackPage> createState() => _CodeFeedbackPageState();
}

class _CodeFeedbackPageState extends State<CodeFeedbackPage> {
  // 필요한 서비스와 컨트롤러들을 초기화합니다
  final StreamingService _streamingService = StreamingService();
  final TextEditingController _questionController = TextEditingController();
  String _currentResponse = '';
  bool _isLoading = false;
  List<Map<String, dynamic>> _feedbackHistory = [];

  @override
  void initState() {
    super.initState();
    // 페이지가 생성될 때 피드백 히스토리를 불러옵니다
    _loadFeedbackHistory();
  }

  @override
  void dispose() {
    // 페이지가 제거될 때 리소스를 정리합니다
    _streamingService.dispose();
    _questionController.dispose();
    super.dispose();
  }

  // AI 응답을 스트리밍 방식으로 받아오는 메서드
  Future<void> _getStreamingResponse() async {
    if (_questionController.text.isEmpty) {
      _showError('Please enter your question first');
      return;
    }

    setState(() {
      _isLoading = true;
      _currentResponse = '';
    });

    try {
      // StreamingService를 통해 AI 응답을 스트리밍으로 받습니다
      await for (final chunk in await _streamingService.connectToStream(_questionController.text)) {
        setState(() {
          _currentResponse += chunk;
        });
      }

      // 응답이 완료되면 Firestore에 저장하고 히스토리를 갱신합니다
      await _saveFeedback(_questionController.text, _currentResponse);
      await _loadFeedbackHistory();
    } catch (e) {
      _showError('Error: $e');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  // Firestore에서 피드백 히스토리를 불러오는 메서드
  Future<void> _loadFeedbackHistory() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final snapshot = await FirebaseFirestore.instance
          .collection(FEEDBACK_COLLECTION)
          .where('userId', isEqualTo: user.uid)
          .orderBy('timestamp', descending: true)
          .get();

      if (!mounted) return;

      setState(() {
        _feedbackHistory = snapshot.docs
            .map((doc) => {
          'id': doc.id,
          'question': doc.data()['question'] as String,
          'feedback': doc.data()['feedback'] as String,
          'timestamp': doc.data()['timestamp'] as Timestamp,
        })
            .toList();
      });
    } catch (e) {
      if (!mounted) return;
      _showError('Error loading feedback history: $e');
    }
  }

  // 새로운 피드백을 Firestore에 저장하는 메서드
  Future<void> _saveFeedback(String question, String feedback) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        _showError('Please sign in first');
        return;
      }

      await FirebaseFirestore.instance.collection(FEEDBACK_COLLECTION).add({
        'userId': user.uid,
        'question': question,
        'feedback': feedback,
        'timestamp': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      _showError('Error saving feedback: $e');
    }
  }

  // 에러 메시지를 표시하는 헬퍼 메서드
  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: Text(widget.title),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              await FirebaseAuth.instance.signOut();
              if (!mounted) return;
              Navigator.of(context).pushReplacement(
                MaterialPageRoute(builder: (context) => const AuthPage()),
              );
            },
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 질문 입력 필드
            TextField(
              controller: _questionController,
              maxLines: 3,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'Enter your question',
                hintText: 'Type your question here...',
              ),
            ),
            const SizedBox(height: 16),
            // 응답 생성 버튼
            ElevatedButton(
              onPressed: _isLoading ? null : _getStreamingResponse,
              child: _isLoading
                  ? const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  SizedBox(width: 8),
                  Text('Generating...'),
                ],
              )
                  : const Text('Get Answer'),
            ),
            // 현재 응답 표시
            if (_currentResponse.isNotEmpty) ...[
              const SizedBox(height: 16),
              const Text('AI Response:', style: TextStyle(fontWeight: FontWeight.bold)),
              Expanded(
                flex: 2,
                child: Container(
                  padding: const EdgeInsets.all(8.0),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey.shade300),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: SingleChildScrollView(
                    child: SelectableText(
                      _currentResponse,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),
                ),
              ),
              const Divider(),
            ],
            // 질문 히스토리 표시
            const Text('Question History:', style: TextStyle(fontWeight: FontWeight.bold)),
            Expanded(
              child: ListView.builder(
                itemCount: _feedbackHistory.length,
                itemBuilder: (context, index) {
                  final feedback = _feedbackHistory[index];
                  return Card(
                    child: ExpansionTile(
                      title: Text(
                        feedback['question'].toString().length > 50
                            ? '${feedback['question'].toString().substring(0, 50)}...'
                            : feedback['question'].toString(),
                      ),
                      subtitle: Text(
                        'Asked on: ${feedback['timestamp'].toDate().toString().split('.')[0]}',
                      ),
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Full Question:',
                                  style: TextStyle(fontWeight: FontWeight.bold)),
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(8.0),
                                decoration: BoxDecoration(
                                  color: Colors.grey.shade100,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: SelectableText(
                                  feedback['question'],
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ),
                              const SizedBox(height: 8),
                              const Text('Answer:',
                                  style: TextStyle(fontWeight: FontWeight.bold)),
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(8.0),
                                decoration: BoxDecoration(
                                  color: Colors.grey.shade100,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: SelectableText(
                                  feedback['feedback'],
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
*/
