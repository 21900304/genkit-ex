import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:get/get_core/src/get_main.dart';
import 'package:noob/screens/addquestion/AddQuestionPage.dart';
import 'package:noob/screens/home/home.dart';
import 'package:noob/screens/profile/profile.dart';
import 'package:noob/utils/widget/appbar.dart';
import 'package:noob/utils/widget/bottombar.dart';
import 'package:noob/screens/onboarding/OnboardingPage_Pro.dart';
import 'package:noob/screens/onboarding/OnboardingPage_Uni.dart';
import 'package:noob/screens/onboarding/OnboardingPage_User.dart';


class MainPage extends StatefulWidget {
  @override
  _MainPageState createState() => _MainPageState();
}

class _MainPageState extends State<MainPage> {
  int _selectedIndex = 0;
  static List<Widget> _widgetOptions = <Widget>[
    HomePage(),
    AddQuestionPage(),
    ProfilePage(),
  ];

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
      if (index == 0) {
        Get.put(HomeController());
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: _widgetOptions.elementAt(_selectedIndex),
      ),
      bottomNavigationBar: bottomBar(currentIndex: _selectedIndex, onTap: _onItemTapped,
      ),
    );
  }
}