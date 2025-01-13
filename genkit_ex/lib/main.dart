import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'firebase_options.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

const String FEEDBACK_COLLECTION = 'code_feedback';

//flutter run --dart-define=USE_FIREBASE_EMULATOR=true

// Emulator 호스트 설정
const bool useEmulator = bool.fromEnvironment('USE_FIREBASE_EMULATOR', defaultValue: false);
const String androidEmulatorHost = '10.0.2.2';
const String iOSEmulatorHost = 'localhost';
const String emulatorHost = androidEmulatorHost; // 또는 iOSEmulatorHost

final host = kIsWeb ? 'localhost' : (Platform.isAndroid ? '10.0.2.2' : 'localhost');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  if (useEmulator) {
    try {
      // Auth Emulator 연결 시도 전 로그 추가
      if (kDebugMode) {
        print('Connecting to Auth Emulator at $host:9099');
      }

      // Auth Emulator 연결
      await FirebaseAuth.instance.useAuthEmulator(host, 9099);

      // Firestore Emulator 연결
      FirebaseFirestore.instance.settings = Settings(
        host: '$host:8080',
        sslEnabled: false,
        persistenceEnabled: false,
      );

      if (kDebugMode) {
        print('Successfully connected to Firebase Emulators');
      }
    } catch (e) {
      if (kDebugMode) {
        print('Failed to connect to emulators: $e');
      }
    }
  }

  runApp(const MyApp());
}

Future<void> _connectToEmulator() async {
  FirebaseFirestore.instance.settings = Settings(
    host: '$emulatorHost:8080',
    sslEnabled: false,
    persistenceEnabled: false,
  );

  await FirebaseAuth.instance.useAuthEmulator(emulatorHost, 9099);

  if (kDebugMode) {
    print('Connected to Firebase Emulator');
  }
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
        if (kDebugMode) {
          print('Attempting login with email: ${_emailController.text}');
        }
        final credential = await FirebaseAuth.instance.signInWithEmailAndPassword(
          email: _emailController.text.trim(),
          password: _passwordController.text.trim(),
        );
        if (kDebugMode) {
          print('Login successful: ${credential.user?.uid}');
        }

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
      if (kDebugMode) {
        print('Auth error: ${e.code} - ${e.message}');
      }
      print("${e.code}");
      _showError(_getErrorMessage(e.code));
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
              onTap: () {
                if (kIsWeb) {
                  _emailController.selection = TextSelection.fromPosition(
                    TextPosition(offset: _emailController.text.length),
                  );
                }
              },
              onTapOutside: (event) {
                FocusScope.of(context).unfocus();
              },
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
  final TextEditingController _questionController = TextEditingController();
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
          'question': doc.data()['question'] as String,
          'feedback': doc.data()['feedback'] as String,
          'timestamp': doc.data()['timestamp'] as Timestamp,
        })
            .toList();
      });
    } catch (e) {
      if (!mounted) return;
      _showError('Error loading feedback history: $e');
      print("Load Data Error : $e");
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
      print("Request cancelled");
    }
  }

  Future<void> _getAiFeedback() async {
    if (_isLoading) {
      _cancelRequest();
      return;
    }

    if (_questionController.text.isEmpty) {
      _showError('Please enter your question first');
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception('User not authenticated');

      final idToken = await user.getIdToken();

      final requestBody = {
        'question': _questionController.text,
        'auth': {'uid': user.uid, 'email_verified': true}
      };

      _client = http.Client();

      /*final functionUrl = const bool.fromEnvironment('USE_FIREBASE_EMULATOR', defaultValue: false)
          ? 'http://10.0.2.2:5001/your-project-id/us-central1/yourFunctionName'  // 에뮬레이터 URL
          : 'https://aicodefeedback-rm7c4usaqa-uc.a.run.app';

      final response = await _client!.post(
          Uri.parse('https://aicodefeedback-rm7c4usaqa-uc.a.run.app'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $idToken',
          'Accept': 'application/json',
        },
        body: json.encode(requestBody),
      );*/

      final functionUrl = useEmulator
          ? 'http://$emulatorHost:5001/emulators-ex/us-central1/aiCodeFeedback'
          : 'https://aicodefeedback-rm7c4usaqa-uc.a.run.app';

      final response = await _client!.post(
        Uri.parse('https://aicodefeedback-rm7c4usaqa-uc.a.run.app'),
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

        if (!responseBody.startsWith('{') && !responseBody.startsWith('[')) {
          setState(() {
            _aiFeedback = responseBody;
          });
          await _saveFeedback(_questionController.text, responseBody);
          return;
        }

        try {
          final jsonResponse = json.decode(responseBody);
          final feedback = jsonResponse['result'] ??
              jsonResponse['text'] ??
              jsonResponse['llmResponse.text'] ??
              responseBody;

          setState(() {
            _aiFeedback = feedback.toString();
          });
          await _saveFeedback(_questionController.text, feedback.toString());
        } catch (e) {
          debugPrint('JSON parse error: $e');
          debugPrint('Response body: $responseBody');

          setState(() {
            _aiFeedback = responseBody;
          });
          await _saveFeedback(_questionController.text, responseBody);
        }
      } else {
        _showError('Failed to get AI feedback. Status: ${response.statusCode}');
        print('Failed to get AI feedback. Status: ${response.statusCode}');
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
      _client?.close();
      _client = null;
    }
  }

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
                  Text(_isLoading ? 'Cancel' : 'Get Answer'),
                ],
              )
                  : const Text('Get Answer'),
            ),
            if (_aiFeedback.isNotEmpty) ...[
              const SizedBox(height: 16),
              const Text('Answer:', style: TextStyle(fontWeight: FontWeight.bold)),
              Container(
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
              const Divider(),
            ],
            const Text('Question History:',
                style: TextStyle(fontWeight: FontWeight.bold)),
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

  @override
  void dispose() {
    _questionController.dispose();
    _client?.close();
    super.dispose();
  }
}