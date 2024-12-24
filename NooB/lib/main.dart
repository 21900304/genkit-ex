import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';
import 'package:noob/screens/addquestion/AddQuestionPage.dart';
import 'package:noob/screens/home/home.dart';
import 'package:noob/screens/notification/NotificationPage.dart';
import 'package:noob/screens/onboarding/OnboardingPage_Car.dart';
import 'package:noob/screens/onboarding/OnboardingPage_Pro.dart';
import 'package:noob/screens/onboarding/OnboardingPage_Top.dart';
import 'package:noob/screens/onboarding/OnboardingPage_Uni.dart';
import 'package:noob/screens/onboarding/OnboardingPage_User.dart';
import 'package:noob/screens/login/LoginPage.dart';
import 'package:noob/screens/profile/profile.dart';
import 'package:noob/screens/splash/SplashPage.dart';
import 'MainPage.dart';
import 'firebase_options.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ScreenUtilInit(
      designSize: const Size(430, 932),
      builder: (_, child) {
        return GetMaterialApp(
          initialBinding: BindingsBuilder(() {
            Get.lazyPut<HomeController>(() => HomeController(), fenix: true);
          }),
          home: InitialRouter(), // 초기 라우팅 페이지로 InitialRouter 사용
          getPages: [
            GetPage(name: '/splash', page: () => SplashPage(),),
            GetPage(name: '/onboarding_car', page: () => OnboardingPageCar(),),
            GetPage(name: '/onboarding_user', page: () => OnboardingPageUser(),),
            GetPage(name: '/onboarding_uni', page: () => OnboardingPageUni(),),
            GetPage(name: '/onboarding_pro', page: () => OnboardingPagePro(),),
            GetPage(name: '/onboarding_top', page: () => OnboardingPageTop(),),
            GetPage(name: '/login', page: () => LoginPage(),),
            GetPage(name: '/main', page: () => MainPage(),),
            GetPage(name: '/home', page: () => HomePage(),),
            GetPage(name: '/addQ', page: () => AddQuestionPage(),),
            GetPage(name: '/notifications', page: () => NotificationPage(),),

            // 기본 이동 : Get.to(() => NextPage());
            // 기본 이동 : Get.to(() => NextPage(), arguments: value);
            // 이전 페이지 1개만 삭제 후 이동 : Get.off(() => NextPage());
            // 이전 페이지 모두 삭제 후 이동 : Get.offAll(() => NextPage());
            // NamedRoute 이동 : Get.toNamed('/a/b/c1');
            // 뒤로 가기 : Get.back();
          ],
        );
      },
    );
  }
}

class InitialRouter extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    // FirebaseAuth의 authStateChanges() 스트림을 사용하여 로그인 상태를 실시간으로 확인
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        // Firebase 초기화 중
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Scaffold(
            body: Center(child: CircularProgressIndicator()), // 로딩 중일 때
          );
        }

        // 로그인이 되어 있으면 MainPage로, 아니면 LoginPage로 이동
        if (snapshot.hasData) {
          return MainPage();  // 로그인된 상태
        } else {
          return LoginPage();  // 로그인되지 않은 상태
        }
      },
    );
  }
}


// 기본 이동 : Get.to(() => NextPage());
// 기본 이동 : Get.to(() => NextPage(), arguments: value);
// 이전 페이지 1개만 삭제 후 이동 : Get.off(() => NextPage());
// 이전 페이지 모두 삭제 후 이동 : Get.offAll(() => NextPage());
// NamedRoute 이동 : Get.toNamed('/a/b/c1');
// 뒤로 가기 : Get.back();
