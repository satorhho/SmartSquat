import 'package:flutter/material.dart';

class Instructions extends StatelessWidget {
  Widget get _text => SingleChildScrollView(
        child: Column(
          children: <Widget>[
            Text("ABOUT",
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 25.0, fontWeight: FontWeight.bold)),
            Text(
                "Smartsquat is an application developed by Briones et al. to aid new lifters in performing the high bar back squat (HBBS) in near real time (after each rep). The app is a means of presenting the system written within the paper.",
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 15.0,
                ),
              ),
            Text(
              "\nHow to use the application?",
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16.0,
                fontStyle: FontStyle.italic,
              ),
            ),
            Text(
                " 1) Press Start.\n 2) Press Video Capture.\n 3) Enable Pose Estimation (powered by MLKit).\n 4) Face your body to the camera and turn 45° right wards (diagonal).\n 5) To prompt the squat, stay still for 3 seconds.\n 6) Squat as the text-to-speech instructs.\n 7) Wait for feedback.\n 8) Follow feedback.",
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 15.0,
                ),
              ),
          ],
        ),
      );
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: ThemeData(
        brightness: Brightness.light,
        primaryColor: Colors.white,
      ),
      home: Scaffold(
        appBar: AppBar(
          title: const Text('SmartSquat'),
        ),
        body: _text,
      ),
    );
  }
}

  // @override
  // Widget build(BuildContext context) {
  //   return Scaffold(body: _text);
  // }