import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'Start.dart';

class HomePage extends StatelessWidget{
  String page_title = "SmartSquat";
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          children: [
            Container(
              margin: const EdgeInsets.only(top: 100, bottom: 200, left: 30, right: 30),
              child: Text(
                "${page_title}",
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 35,
                  fontFamily: "Raleway",
                ),
              ),
            ),

            OutlineButton(
              child: Text("Start"),
              highlightColor: Colors.white38,
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => Start()),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

}