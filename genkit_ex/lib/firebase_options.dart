// File generated by FlutterFire CLI.
// ignore_for_file: type=lint
import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

/// Default [FirebaseOptions] for use with your Firebase apps.
///
/// Example:
/// ```dart
/// import 'firebase_options.dart';
/// // ...
/// await Firebase.initializeApp(
///   options: DefaultFirebaseOptions.currentPlatform,
/// );
/// ```
class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      case TargetPlatform.macOS:
        return macos;
      case TargetPlatform.windows:
        return windows;
      case TargetPlatform.linux:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for linux - '
          'you can reconfigure this by running the FlutterFire CLI again.',
        );
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not supported for this platform.',
        );
    }
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyCx7hvDFerM6NZgHqBfvuJ_0uJlfGG_L24',
    appId: '1:589120315630:web:b2c1a660e1e879137193ff',
    messagingSenderId: '589120315630',
    projectId: 'genkit-ex',
    authDomain: 'genkit-ex.firebaseapp.com',
    storageBucket: 'genkit-ex.firebasestorage.app',
    measurementId: 'G-4N98RXSE5Q',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyDO7w5rp0nBqghOR0mhG6k5AK0g_JtYn3o',
    appId: '1:589120315630:android:3cd8df022611accc7193ff',
    messagingSenderId: '589120315630',
    projectId: 'genkit-ex',
    storageBucket: 'genkit-ex.firebasestorage.app',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyASVbxcNIH5lEtPI12uONR-Hmyc_4mbwn4',
    appId: '1:589120315630:ios:cc2b92236c51597c7193ff',
    messagingSenderId: '589120315630',
    projectId: 'genkit-ex',
    storageBucket: 'genkit-ex.firebasestorage.app',
    iosBundleId: 'com.example.genkitEx',
  );

  static const FirebaseOptions macos = FirebaseOptions(
    apiKey: 'AIzaSyASVbxcNIH5lEtPI12uONR-Hmyc_4mbwn4',
    appId: '1:589120315630:ios:cc2b92236c51597c7193ff',
    messagingSenderId: '589120315630',
    projectId: 'genkit-ex',
    storageBucket: 'genkit-ex.firebasestorage.app',
    iosBundleId: 'com.example.genkitEx',
  );

  static const FirebaseOptions windows = FirebaseOptions(
    apiKey: 'AIzaSyCx7hvDFerM6NZgHqBfvuJ_0uJlfGG_L24',
    appId: '1:589120315630:web:bb5c394ffaa01e1d7193ff',
    messagingSenderId: '589120315630',
    projectId: 'genkit-ex',
    authDomain: 'genkit-ex.firebaseapp.com',
    storageBucket: 'genkit-ex.firebasestorage.app',
    measurementId: 'G-6YSGWC64GP',
  );
}
