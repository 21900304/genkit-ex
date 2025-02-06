/*
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'auth_page.dart';
import 'code_feedback_page.dart';
import 'firebase_options.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

/// Firestore 컬렉션 상수 정의
const String FEEDBACK_COLLECTION = 'code_feedback';

/// Firebase Emulator 설정을 위한 환경 변수와 호스트 설정
/// `flutter run --dart-define=USE_FIREBASE_EMULATOR=true` 명령으로 실행할 때 활성화됩니다.
const bool useEmulator = bool.fromEnvironment('USE_FIREBASE_EMULATOR', defaultValue: false);

/// 플랫폼별 에뮬레이터 호스트 설정
/// Android 에뮬레이터에서는 10.0.2.2를 사용하고, 다른 환경에서는 localhost를 사용합니다.
final host = kIsWeb ? 'localhost' : (Platform.isAndroid ? '10.0.2.2' : 'localhost');

/// 앱의 진입점입니다. Firebase 초기화와 에뮬레이터 설정을 수행합니다.
Future<void> main() async {
  // Flutter 바인딩 초기화
  WidgetsFlutterBinding.ensureInitialized();

  // Firebase 코어 초기화
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // 에뮬레이터 모드가 활성화된 경우 Firebase 에뮬레이터 설정
  if (useEmulator) {
    try {
      if (kDebugMode) {
        print('Firebase Emulator 연결 시작...');
        print('Auth Emulator: $host:9099');
        print('Firestore Emulator: $host:8080');
        print('Functions Emulator: $host:5001');
      }

      // Firebase Auth 에뮬레이터 설정
      await FirebaseAuth.instance.useAuthEmulator(host, 9099);

      // Firestore 에뮬레이터 설정
      FirebaseFirestore.instance.settings = Settings(
        host: '$host:8080',
        sslEnabled: false,
        persistenceEnabled: false,
      );

      // 에뮬레이터 연결 상태 확인을 위한 로그
      if (kDebugMode) {
        print('Firebase Emulator 연결 성공');

        // 현재 인증된 사용자가 있다면 정보 출력
        final currentUser = FirebaseAuth.instance.currentUser;
        if (currentUser != null) {
          print('현재 인증된 사용자: ${currentUser.email}');
        } else {
          print('인증된 사용자 없음');
        }
      }
    } catch (e) {
      // 에뮬레이터 연결 실패 시 에러 로깅
      if (kDebugMode) {
        print('Firebase Emulator 연결 실패: $e');
        print('스택 트레이스:');
        print(e is Error ? e.stackTrace : null);
      }
    }
  }

  // MyApp 위젯으로 앱 실행 시작
  runApp(const MyApp());
}

/// 앱의 루트 위젯입니다.
/// Material Design을 사용하며, 인증 상태에 따라 적절한 페이지를 표시합니다.
class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      // 앱의 제목 설정
      title: 'Flutter AI Code Feedback',

      // 앱의 테마 설정
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),

      // StreamBuilder를 사용하여 인증 상태 변화를 감지하고 적절한 페이지를 표시
      home: StreamBuilder<User?>(
        // Firebase Auth의 인증 상태 변화를 구독
        stream: FirebaseAuth.instance.authStateChanges(),
        builder: (context, snapshot) {
          // 연결 상태 확인 중일 때 로딩 인디케이터 표시
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          }

          // 인증된 사용자가 있고 이메일이 인증되었다면 메인 페이지로 이동
          if (snapshot.hasData && snapshot.data!.emailVerified) {
            return const CodeFeedbackPage(title: 'AI Code Feedback');
          }

          // 인증되지 않은 상태라면 인증 페이지로 이동
          return const AuthPage();
        },
      ),
    );
  }
}*/
