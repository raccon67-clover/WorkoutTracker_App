

import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;


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
    apiKey: 'AIzaSyAd6YIHcQ86UWETBTyTrRXavuvRtdNyMB0',
    appId: '1:280561903262:web:bd13094a318a9ca7c2bd8f',
    messagingSenderId: '280561903262',
    projectId: 'fir-auth-5ec40',
    authDomain: 'fir-auth-5ec40.firebaseapp.com',
    storageBucket: 'fir-auth-5ec40.firebasestorage.app',
    measurementId: 'G-9X43BN0MEG',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyC-LJPFUsV2FT7Rj65hNrDJFXnBZGV9G48',
    appId: '1:280561903262:android:8bf605136adfd37bc2bd8f',
    messagingSenderId: '280561903262',
    projectId: 'fir-auth-5ec40',
    storageBucket: 'fir-auth-5ec40.firebasestorage.app',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyAgZZ2yXP-qzsKz4xjoab1l27zwHWWKdjA',
    appId: '1:280561903262:ios:e87d6471cd785c1dc2bd8f',
    messagingSenderId: '280561903262',
    projectId: 'fir-auth-5ec40',
    storageBucket: 'fir-auth-5ec40.firebasestorage.app',
    iosBundleId: 'com.example.workoutApp',
  );

  static const FirebaseOptions macos = FirebaseOptions(
    apiKey: 'AIzaSyAgZZ2yXP-qzsKz4xjoab1l27zwHWWKdjA',
    appId: '1:280561903262:ios:e87d6471cd785c1dc2bd8f',
    messagingSenderId: '280561903262',
    projectId: 'fir-auth-5ec40',
    storageBucket: 'fir-auth-5ec40.firebasestorage.app',
    iosBundleId: 'com.example.workoutApp',
  );

  static const FirebaseOptions windows = FirebaseOptions(
    apiKey: 'AIzaSyAd6YIHcQ86UWETBTyTrRXavuvRtdNyMB0',
    appId: '1:280561903262:web:24c4c625367c6101c2bd8f',
    messagingSenderId: '280561903262',
    projectId: 'fir-auth-5ec40',
    authDomain: 'fir-auth-5ec40.firebaseapp.com',
    storageBucket: 'fir-auth-5ec40.firebasestorage.app',
    measurementId: 'G-91V7E0EVVD',
  );
}
