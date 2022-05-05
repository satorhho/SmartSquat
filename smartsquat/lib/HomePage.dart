import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'about.dart';
import 'posecamera.dart';

class HomePage extends StatelessWidget {
  String page_title = "SmartSquat";
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          children: [
            Container(
              margin: const EdgeInsets.only(
                  top: 100, bottom: 200, left: 30, right: 30),
              child: Text(
                "${page_title}",
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontStyle: FontStyle.italic,
                  fontSize: 35,
                  fontFamily: "Raleway",
                ),
              ),
            ),
            OutlinedButton(
              style: OutlinedButton.styleFrom(
                  shape: StadiumBorder(),
                  minimumSize: Size(180, 40),
                  primary: Colors.lightBlue,
                  side: BorderSide(color: Colors.lightBlue)),
              // highlightColor: Colors.white38,
              child: Text("Start"),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => Posecamera()),
                );
              },
            ),
            OutlinedButton(
              style: OutlinedButton.styleFrom(
                  shape: StadiumBorder(),
                  minimumSize: Size(180, 40),
                  primary: Colors.lightBlue,
                  side: BorderSide(color: Colors.lightBlue)),
              // highlightColor: Colors.white38,
              child: Text("About"),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => Instructions()),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
