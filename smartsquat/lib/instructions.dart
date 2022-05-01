import 'package:flutter/material.dart';

class Instructions extends StatelessWidget {
  Widget get _text => SingleChildScrollView(
        child: Column(
          children: [
            ClipRect(),
            Center(child: Text("")),
            Text("INSTRUCTIONS",
                style: TextStyle(
                  fontSize: 20.0,
                )),
            Text("Steps in how to use the app:",
                style: TextStyle(
                  fontSize: 15.0,
                )),
            Text("1. click the start"),
            Text("2. click the Start Camera"),
            Text("3. Turn on the pose estimation by clicking it"),
            Text("4. Face your body to the camera while in your right side"),
            Text("5. Stay still for a few seconds until you heard a prompt"),
            Text("6. Squat after you hear a prompt telling you to squat"),
            Text("7. Wait until you heard some feedbacking prompt"),
            Text("8. Repeat step 4-7 until you don't want to squat"),
          ],
        ),
      );
  @override
  Widget build(BuildContext context) {
    return Scaffold(body: _text);
  }
}
