import 'dart:io';
import 'dart:math';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:genkit_ex/stream_feedback_page.dart';
import 'auth_page.dart';
import 'firebase_options.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'package:flutter/material.dart';
import 'dart:async';

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

      FirebaseFunctions.instance.useFunctionsEmulator(host, 5001);

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
            return const StreamFeedbackPage(title: 'AI Code Feedback');
          }

          return const AuthPage();
        },
      ),
    );
  }
}