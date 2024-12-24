import 'dart:math';

import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'firebase_options.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

const String FEEDBACK_COLLECTION = 'code_feedback';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter AI Code Feedback',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: StreamBuilder<User?>(
        stream: FirebaseAuth.instance.authStateChanges(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          }

          if (snapshot.hasData && snapshot.data!.emailVerified) {
            return const CodeFeedbackPage(title: 'AI Code Feedback');
          }

          return const AuthPage();
        },
      ),
    );
  }
}

class AuthPage extends StatefulWidget {
  const AuthPage({super.key});

  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLogin = true;
  bool _isLoading = false;

  Future<void> _submitForm() async {
    if (_emailController.text.isEmpty || _passwordController.text.isEmpty) {
      _showError('Please fill in all fields');
      return;
    }

    setState(() => _isLoading = true);

    try {
      if (_isLogin) {
        final credential = await FirebaseAuth.instance.signInWithEmailAndPassword(
          email: _emailController.text.trim(),
          password: _passwordController.text.trim(),
        );

        if (!credential.user!.emailVerified) {
          await FirebaseAuth.instance.signOut();
          _showError('Please verify your email first');
        } else {
          // 이메일이 인증되었다면 CodeFeedbackPage로 이동
          if (mounted) {
            Navigator.of(context).pushReplacement(
              MaterialPageRoute(
                builder: (context) => const CodeFeedbackPage(title: 'AI Code Feedback'),
              ),
            );
          }
        }
      } else {
        final credential = await FirebaseAuth.instance.createUserWithEmailAndPassword(
          email: _emailController.text.trim(),
          password: _passwordController.text.trim(),
        );
        await credential.user!.sendEmailVerification();
        _showMessage('Verification email sent. Please check your inbox.');
      }
    } on FirebaseAuthException catch (e) {
      _showError(_getErrorMessage(e.code));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String _getErrorMessage(String code) {
    switch (code) {
      case 'email-already-in-use':
        return 'This email is already registered';
      case 'invalid-email':
        return 'Invalid email address';
      case 'weak-password':
        return 'Password is too weak';
      case 'user-not-found':
        return 'No user found with this email';
      case 'wrong-password':
        return 'Wrong password';
      default:
        return 'An error occurred: $code';
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isLogin ? 'Login' : 'Sign Up'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _emailController,
              decoration: const InputDecoration(
                labelText: 'Email',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.emailAddress,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _passwordController,
              decoration: const InputDecoration(
                labelText: 'Password',
                border: OutlineInputBorder(),
              ),
              obscureText: true,
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _isLoading ? null : _submitForm,
              child: _isLoading
                  ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
                  : Text(_isLogin ? 'Login' : 'Sign Up'),
            ),
            TextButton(
              onPressed: () => setState(() => _isLogin = !_isLogin),
              child: Text(_isLogin
                  ? 'Don\'t have an account? Sign Up'
                  : 'Already have an account? Login'),
            ),
          ],
        ),
      ),
    );
  }
}

class CodeFeedbackPage extends StatefulWidget {
  const CodeFeedbackPage({super.key, required this.title});
  final String title;

  @override
  State<CodeFeedbackPage> createState() => _CodeFeedbackPageState();
}

class _CodeFeedbackPageState extends State<CodeFeedbackPage> {
  final TextEditingController _codeController = TextEditingController();
  String _aiFeedback = '';
  bool _isLoading = false;
  List<Map<String, dynamic>> _feedbackHistory = [];
  http.Client? _client;

  @override
  void initState() {
    super.initState();
    _loadFeedbackHistory();
  }

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
          'code': doc.data()['code'] as String,
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

  void _cancelRequest() {
    if (_client != null) {
      _client!.close();
      _client = null;
      setState(() {
        _isLoading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Request cancelled')),
      );
    }
  }

  Future<void> _getAiFeedback() async {
    // 이미 요청 중이면 취소
    if (_isLoading) {
      _cancelRequest();
      return;
    }

    if (_codeController.text.isEmpty) {
      _showError('Please enter some code first');
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception('User not authenticated');

      final idToken = await user.getIdToken();

      // API 요청 데이터 준비
      final requestBody = {
        'subject': _codeController.text,
        'auth': {'uid': user.uid, 'email_verified': true}
      };

      // 새로운 client 인스턴스 생성
      _client = http.Client();

      final response = await _client!.post(
        Uri.parse('https://aicodefeedback-mu5egjfopa-uc.a.run.app'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $idToken',
          'Accept': 'application/json',
        },
        body: json.encode(requestBody),
      );

      if (!mounted) return;

      if (response.statusCode == 200) {
        String responseBody = response.body.trim();

        // 응답이 직접적인 문자열인 경우 처리
        if (!responseBody.startsWith('{') && !responseBody.startsWith('[')) {
          setState(() {
            _aiFeedback = responseBody;
          });
          await _saveFeedback(_codeController.text, responseBody);
          return;
        }

        // JSON 응답 처리
        try {
          final jsonResponse = json.decode(responseBody);
          final feedback = jsonResponse['result'] ??
              jsonResponse['text'] ??
              jsonResponse['llmResponse.text'] ??
              responseBody;

          setState(() {
            _aiFeedback = feedback.toString();
          });
          await _saveFeedback(_codeController.text, feedback.toString());
        } catch (e) {
          debugPrint('JSON parse error: $e');
          debugPrint('Response body: $responseBody');

          setState(() {
            _aiFeedback = responseBody;
          });
          await _saveFeedback(_codeController.text, responseBody);
        }
      } else {
        _showError('Failed to get AI feedback. Status: ${response.statusCode}');
        debugPrint('Error response: ${response.body}');
      }
    } catch (e) {
      if (!mounted) return;
      if (e is http.ClientException) {
        _showError('Request cancelled');
      } else {
        _showError('Error: $e');
        debugPrint('Error details: $e');
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
      // client 정리
      _client?.close();
      _client = null;
    }
  }

  Future<void> _saveFeedback(String code, String feedback) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        _showError('Please sign in first');
        return;
      }

      await FirebaseFirestore.instance.collection(FEEDBACK_COLLECTION).add({
        'userId': user.uid,
        'code': code,
        'feedback': feedback,
        'timestamp': FieldValue.serverTimestamp(),
      });

      await _loadFeedbackHistory();
    } catch (e) {
      _showError('Error saving feedback: $e');
    }
  }

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
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _codeController,
              maxLines: 10,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'Enter your Flutter code',
                hintText: 'Paste your code here...',
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _getAiFeedback,
              child: _isLoading
                  ? Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(_isLoading ? 'Cancel' : 'Get AI Feedback'),
                ],
              )
                  : const Text('Get AI Feedback'),
            ),
            if (_aiFeedback.isNotEmpty) ...[
              const SizedBox(height: 16),
              const Text('AI Feedback:',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              Expanded(
                child: SingleChildScrollView(
                  child: Container(
                    padding: const EdgeInsets.all(8.0),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey.shade300),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: SelectableText(
                      _aiFeedback,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),
                ),
              ),
              const Divider(),
            ],
            const Text('Feedback History:',
                style: TextStyle(fontWeight: FontWeight.bold)),
            Expanded(
              child: ListView.builder(
                itemCount: _feedbackHistory.length,
                itemBuilder: (context, index) {
                  final feedback = _feedbackHistory[index];
                  return Card(
                    child: ExpansionTile(
                      title: Text('Feedback ${index + 1}'),
                      subtitle: Text('Time: ${feedback['timestamp'].toDate()}'),
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Code:',
                                  style: TextStyle(fontWeight: FontWeight.bold)),
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(8.0),
                                decoration: BoxDecoration(
                                  color: Colors.grey.shade100,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: SelectableText(
                                  feedback['code'],
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ),
                              const SizedBox(height: 8),
                              const Text('Feedback:',
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

  @override
  void dispose() {
    _codeController.dispose();
    _client?.close();
    super.dispose();
  }
}