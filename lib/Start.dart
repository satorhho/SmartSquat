import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

class Start extends StatefulWidget {
  @override
  _StartState createState() => _StartState();

}

class _StartState extends State<Start> {
  File? _image;
  final image_picker = ImagePicker();

  Future getImage() async {
    final image = await image_picker.getImage(
        source: ImageSource.camera
    );

    setState(() {
      _image = File(image!.path);
    });
  }
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: _image == null ? Text("No Image Selected") : Image.file(_image!),
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: Colors.blue,
        child: Icon(Icons.camera_alt),
        onPressed: getImage,
      ),
    );
  }

}