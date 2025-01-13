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
    apiKey: 'AIzaSyDc6IoTlSIm193KR9pDW0oG1Eoyvf0UAIc',
    appId: '1:12376997928:web:d3c3498f89279b0b3b751d',
    messagingSenderId: '12376997928',
    projectId: 'emulators-ex',
    authDomain: 'emulators-ex.firebaseapp.com',
    databaseURL: 'https://emulators-ex-default-rtdb.firebaseio.com',
    storageBucket: 'emulators-ex.firebasestorage.app',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyC0NlB7H-yq17z4mrGU-AkqyE3PO659oow',
    appId: '1:12376997928:android:177281afa9b84a853b751d',
    messagingSenderId: '12376997928',
    projectId: 'emulators-ex',
    databaseURL: 'https://emulators-ex-default-rtdb.firebaseio.com',
    storageBucket: 'emulators-ex.firebasestorage.app',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyBpz90FaZkhezuze-SNUzHXYlrZQog8Mbk',
    appId: '1:12376997928:ios:297d1b09f90794193b751d',
    messagingSenderId: '12376997928',
    projectId: 'emulators-ex',
    databaseURL: 'https://emulators-ex-default-rtdb.firebaseio.com',
    storageBucket: 'emulators-ex.firebasestorage.app',
    iosBundleId: 'com.example.genkitEx',
  );

  static const FirebaseOptions macos = FirebaseOptions(
    apiKey: 'AIzaSyBpz90FaZkhezuze-SNUzHXYlrZQog8Mbk',
    appId: '1:12376997928:ios:297d1b09f90794193b751d',
    messagingSenderId: '12376997928',
    projectId: 'emulators-ex',
    databaseURL: 'https://emulators-ex-default-rtdb.firebaseio.com',
    storageBucket: 'emulators-ex.firebasestorage.app',
    iosBundleId: 'com.example.genkitEx',
  );

  static const FirebaseOptions windows = FirebaseOptions(
    apiKey: 'AIzaSyDc6IoTlSIm193KR9pDW0oG1Eoyvf0UAIc',
    appId: '1:12376997928:web:483219d125d6e3ff3b751d',
    messagingSenderId: '12376997928',
    projectId: 'emulators-ex',
    authDomain: 'emulators-ex.firebaseapp.com',
    databaseURL: 'https://emulators-ex-default-rtdb.firebaseio.com',
    storageBucket: 'emulators-ex.firebasestorage.app',
  );

}