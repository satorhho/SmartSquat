

import 'dart:io';
import 'dart:ui' as ui;
import 'dart:typed_data';
import 'package:body_detection/models/pose_landmark.dart';
import 'package:tuple/tuple.dart';
import 'package:flutter/rendering.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:image_gallery_saver/image_gallery_saver.dart';

import 'package:body_detection/body_detection.dart';

import 'package:body_detection/models/image_result.dart';
import 'package:body_detection/models/pose.dart';
import 'package:flutter/material.dart';




import 'pose_painter.dart';


void main() {
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {

  GlobalKey globalKey = GlobalKey();

  int _selectedTabIndex = 0;

  bool _isDetectingPose = false;
  Pose? _detectedPose;
  Image? _cameraImage;
  Size _imageSize = Size.zero;
  //Utilities
  
  
  //Recording ulitilites
  List<Uint8List> segments = [];
  List<Tuple2<Uint8List, double>> recording = [];              //saves a list of tuple. Use recording[].item1 to get the image (which is in bytes), and recording[].item2 to get Y Coordinate

  //timer utilities
  DateTime now = DateTime.now();
  double initialTime = 0; 
  double initialTime2 = 0;
  double initialAnklePos = 0.01;
  bool isTimed = false;
  bool isRecording = false;
  double tmpLmVal =  0.1;

  double monitorVal = 0.01;
  bool isTracking = false;
  double recThis = 0;

  Future<void> _startCameraStream() async {
    final request = await Permission.camera.request();
    if (request.isGranted) {
      await BodyDetection.startCameraStream(
        onFrameAvailable: _handleCameraImage,
        onPoseAvailable: (pose) {
          if (!_isDetectingPose) return;
          _handlePose(pose);
          record();
        },
      );
    }
  }

  Future<void> _stopCameraStream() async {
    await BodyDetection.stopCameraStream();

    setState(() {
      _cameraImage = null;
      _imageSize = Size.zero;
    });
  }

  void _handleCameraImage(ImageResult result) {
    // Ignore callback if navigated out of the page.
    if (!mounted) return;

    // To avoid a memory leak issue.
    // https://github.com/flutter/flutter/issues/60160
    PaintingBinding.instance?.imageCache?.clear();
    PaintingBinding.instance?.imageCache?.clearLiveImages();

    final image = Image.memory(
      result.bytes,
      gaplessPlayback: true,
      fit: BoxFit.contain,
    );

    setState(() {
      _cameraImage = image;
      _imageSize = result.size;
    });
  }

  void _handlePose(Pose? pose) {
    // Ignore if navigated out of the page.
    if (!mounted) return;
    
    setState(() {
      _detectedPose = pose;
    });
  }

  Future<void> _toggleDetectPose() async {
    if (_isDetectingPose) {
      await BodyDetection.disablePoseDetection();
    } else {
      await BodyDetection.enablePoseDetection();
    }

    setState(() {
      _isDetectingPose = !_isDetectingPose;
      _detectedPose = null;
    });
    record();
  }


  void _onTabEnter(int index) {
    // Camera tab
    if (index == 0) {
      _startCameraStream();
    }
  }

  void _onTabExit(int index) {
    // Camera tab
    if (index == 1) {
      _stopCameraStream();
    }
  }

  void _onTabSelectTapped(int index) {
    _onTabExit(_selectedTabIndex);
    _onTabEnter(index);

    setState(() {
      _selectedTabIndex = index;
    });
  }

  Future<void> segmentation(Pose? pose) async {

    if (!(await Permission.storage.status.isGranted)) {
      await Permission.storage.request();
    }
    
    for (PoseLandmark lm in pose!.landmarks) { //lm is landmark

      // One of the 33 detectable body landmarks.
      int id = lm.type.index;

      if(id == 11){
        tmpLmVal = double.parse(lm.position.x.toStringAsFixed(1));  //if shoulder, take x val
      }

                                //Set timer for 2 seconds
      if(isTimed == false){             // if not timed, 
        initialTime = (now.millisecondsSinceEpoch/1000);
        if(id == 11){
          initialAnklePos = double.parse(lm.position.x.toStringAsFixed(1));
        }
      }
      else{
        if( (now.millisecondsSinceEpoch/1000) >= (initialTime + 2) ){
            isRecording = true;
        }
      }

      if(tmpLmVal == initialAnklePos){ 
        isTimed = true;
      }
      else{
        isTimed = false;
      }

      if(isRecording){
        if( id == 11){
          record();
          recThis = double.parse(lm.position.y.toStringAsFixed(1));
          
          if(monitorVal > recThis){
            isRecording = false;
            isTracking = segmentize(recording, segments);
            monitorVal = 0.01;
            isTimed = false;
            initialTime = now.millisecondsSinceEpoch/1000;
            initialTime2 = now.millisecondsSinceEpoch/1000;
          }
        }    
        monitorVal = double.parse(lm.position.y.toStringAsFixed(1));
      }

      if (isTracking){
        if(id == 11){
        
          if(monitorVal < double.parse(lm.position.y.toStringAsFixed(1)) || recording[0].item2 == double.parse(lm.position.y.toStringAsFixed(1))){
            isTracking = false;
            record();
            segments.add(recording[(recording.length)-1].item1);
            saveImgs(recording, segments);
            isRecording = false;
            isTimed = false;
            initialTime = now.millisecondsSinceEpoch/1000;
            initialTime2 = now.millisecondsSinceEpoch/1000;
            monitorVal = 0.01;
          }
        }
      }
    }
  }

  Future<void> record() async {
    
    RenderRepaintBoundary boundary = globalKey.currentContext?.findRenderObject() as RenderRepaintBoundary;

    final image = await boundary.toImage();
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    Uint8List pngBytes = byteData!.buffer.asUint8List();

    final result = await ImageGallerySaver.saveImage(
        Uint8List.fromList(pngBytes),
        quality: 60,
        name: "testing");
    result;

  }

  bool segmentize(List<Tuple2< Uint8List, double>> recordingArr, List<Uint8List> segments){

    segments.add(recordingArr[0].item1);         
    double initialYval = recordingArr[0].item2;
    int startIdx = 0;
    for(int i = 0; i < (recordingArr.length); i++ ){          
      if(recordingArr[i].item2 > initialYval){
          startIdx = i;
          break;
      }
    }
    segments.add(recordingArr[ (((recordingArr.length)+startIdx)/2).ceil() ].item1); //mid_1
    segments.add(recordingArr[ (recordingArr.length)-2 ].item1); // bot_1
    return true;
  }

  void saveImgs(List<Tuple2< Uint8List, double>> recordingArr, List<Uint8List> segments) async {

    int counter = 0;
    for(Uint8List segment in segments){ 
    
      final result = await ImageGallerySaver.saveImage(
        Uint8List.fromList(segment),
        quality: 80,
        name: "input$counter");

      result;
      counter++;
    }
    segments.clear();
    recordingArr.clear();
    
  }

  Widget? get _selectedTab => _selectedTabIndex == 0
      ? _cameraDetectionView
      : null;

  Widget get _cameraDetectionView => SingleChildScrollView(
        child: Center(
          child: Column(
            children: [
              ClipRect(
                child: RepaintBoundary(
                  key: globalKey,
                  child: CustomPaint(
                    child: _cameraImage,
                    foregroundPainter: PosePainter(
                      pose: _detectedPose,
                      imageSize: _imageSize,
                    ),
                  ),
                ),
              ),
              OutlinedButton(
                onPressed: _toggleDetectPose,
                child: _isDetectingPose
                    ? const Text('Turn off pose detection')
                    : const Text('Turn on pose detection'),
              ),
            ],
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(
          title: const Text('Smart Squat v2'),
        ),
        bottomNavigationBar: BottomNavigationBar(
          items: const <BottomNavigationBarItem>[
            BottomNavigationBarItem(
              icon: Icon(Icons.camera), 
              label: 'Camera',
            ),
          ],
          onTap: _onTabSelectTapped,
        ),
        body: _selectedTab,
      ),
    );
  }
}
