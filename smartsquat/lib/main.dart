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
  double initialTime = (DateTime.now().millisecondsSinceEpoch/1000); 
  double initialTime2 = 0;
  double initLmPos = 0.01;
  double tmpLmVal =  0.1;
  double monitorVal = 0.01;
  double recThis = 0;
  bool isTimed = false;
  bool isRecording = false;
  bool isTracking = false;

  Future<void> _startCameraStream() async {
    final request = await Permission.camera.request();
    final request2 = await Permission.storage.request();

    if (request.isGranted) {
      await BodyDetection.startCameraStream(
        onFrameAvailable: _handleCameraImage,
        onPoseAvailable: (pose) {
          if (!_isDetectingPose) return;
          _handlePose(pose);
          segmentation(pose);
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

  void segmentation(Pose? pose) {
    
    for(PoseLandmark lm in pose!.landmarks){

      int id = lm.type.index;

      if(id == 11){
        tmpLmVal = double.parse(lm.position.x.toStringAsFixed(1));  //if shoulder, take x val
      }
      //Set timer for 2 seconds
      if(isTimed == false){             // if not timed, 
        initialTime = (DateTime.now().millisecondsSinceEpoch/1000);
        if(id == 11){
          initLmPos = double.parse(lm.position.x.toStringAsFixed(1));
        }
      } else if(isTimed){
        double currTime = (DateTime.now().millisecondsSinceEpoch/1000);
        if( currTime >= (initialTime + 1.5) ){
          isRecording = true;
        }
      }

      if((tmpLmVal <= (initLmPos + 5)) && (tmpLmVal >= (initLmPos - 5))){ 
        isTimed = true;
      }
      else{
        isTimed = false;
      }

      if(isRecording){
        if( id == 11){
          record();
          recThis = double.parse(lm.position.y.toStringAsFixed(1));
          
          if((monitorVal + 20) < recThis ){
            isRecording = false;
            isTracking = segmentize();
            monitorVal = 0.01;
            isTimed = false;
            initialTime = (DateTime.now().millisecondsSinceEpoch/1000);
            initialTime2 = (DateTime.now().millisecondsSinceEpoch/1000);
          }
        }    
        monitorVal = double.parse(lm.position.y.toStringAsFixed(1));
      }

      if (isTracking){
        if(id == 11){

          double currLm = double.parse(lm.position.y.toStringAsFixed(1));
          bool offset = ((recording[0].item2 >= currLm -1) && (recording[0].item2 <= currLm + 1 ) );
          // (recording[0].item2 == currLm )
          
          if( ( (monitorVal ) > currLm ) || (recording[0].item2 == currLm ) ){
            isTracking = false;
            record();
            segments.add(recording[(recording.length)-1].item1); //top_2
            saveImgs();
            isRecording = false;
            isTimed = false;
            initialTime = (DateTime.now().millisecondsSinceEpoch/1000);
            initialTime2 = (DateTime.now().millisecondsSinceEpoch/1000);
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

    Tuple2<Uint8List, double> tmp = Tuple2(pngBytes, double.parse(_detectedPose!.landmarks[11].position.y.toStringAsFixed(1)));
    recording.add(tmp);

  }

  bool segmentize(){

    segments.add(recording[0].item1);         
    double initialYval = recording[0].item2;
    int startIdx = 0;
    for(int i = 0; i < (recording.length); i++ ){          
      if(recording[i].item2 > initialYval){
          startIdx = i;
          break;
      }
    }
    segments.add(recording[ (((recording.length)+startIdx)/2).ceil() ].item1); //mid_1
    segments.add(recording[ (recording.length)-2 ].item1); // bot_1
    
    return true;
  }

  void saveImgs() async {

    int counter = 0;
    for(Uint8List segment in segments){ 
    
      final result = await ImageGallerySaver.saveImage(
        Uint8List.fromList(segment),
        quality: 60,
        name: "input${counter.toString()}");
        
      counter+=1;
    }
    segments.clear();
    recording.clear();
    
  }

   Future<void> sav() async {
    
    RenderRepaintBoundary boundary = globalKey.currentContext?.findRenderObject() as RenderRepaintBoundary;

    final image = await boundary.toImage();
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    Uint8List pngBytes = byteData!.buffer.asUint8List();

    final result = await ImageGallerySaver.saveImage(
        Uint8List.fromList(pngBytes),
        quality: 60,
        name: "input");
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
