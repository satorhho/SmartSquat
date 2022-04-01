import 'dart:async';
import 'dart:typed_data';
import 'package:tuple/tuple.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:image_gallery_saver/image_gallery_saver.dart';

import 'package:body_detection/body_detection.dart';
import 'package:body_detection/models/pose_landmark.dart';
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
  // ~ Text
    String squatPrompt = "";
    String getLM = "";
    String seg = "";
  // ~ Recording
  Uint8List list = Uint8List.fromList([0, 2, 5, 7, 42, 255]);
  List<Uint8List> segments = [];
  List<Tuple2<Uint8List, double>> recording = [];

  // ~ Timer 
  double initialTime = (DateTime.now().millisecondsSinceEpoch/1000); 
  double initialTime2 = 0;
  double initLmPos = 0.01;
  double initYpos = 0;
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
          segmentation();
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
    list = result.bytes;
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
  int ctr = 0;
  String land = "";
  void segmentation() {
    // land = "";
    // ctr = 0;
    for(PoseLandmark lm in _detectedPose!.landmarks){
      
      int id = lm.type.index;
      // land = land + ctr.toString() + lm.type.toString() + "\n";
      // ctr++;
      if(id == 12){
        land = lm.type.toString();
        tmpLmVal = double.parse(lm.position.x.toStringAsFixed(1));    //if shoulder, take x val
      }
      //Set timer for 2 seconds
      if(isTimed == false){             // if not timed, 
        initialTime = (DateTime.now().millisecondsSinceEpoch/1000);
        if(id == 12){
          initLmPos = double.parse(lm.position.x.toStringAsFixed(1));
        }
      } else if(isTimed){
        double currTime = (DateTime.now().millisecondsSinceEpoch/1000); 
        if( currTime >= (initialTime + 2) ){
          isRecording = true;
          squatPrompt = "Recording, Please Squat now";
        }
      }
      
      if((tmpLmVal <= (initLmPos + 5)) && (tmpLmVal >= (initLmPos - 5))){ 
        isTimed = true;
      }
      else{
        isTimed = false;
      }

      if(isRecording){
        if( id == 12){
          record(lm.position.y);

          recThis = double.parse(lm.position.y.toStringAsFixed(1));
         
          if(monitorVal - 3 > recThis ){
            getLM = "Tracking \nCurrent = " + monitorVal.toString() + " Prev " + recThis.toString() ;
            isRecording = false;
            isTracking = segmentize();
            seg = "Past count = " + ctr.toString();
            monitorVal = 1000;
            isTimed = false;
            initialTime = (DateTime.now().millisecondsSinceEpoch/1000);
            initialTime2 = (DateTime.now().millisecondsSinceEpoch/1000);
          }
          monitorVal = double.parse(lm.position.y.toStringAsFixed(1));
        }    
        
      }

      if (isTracking){
        if(id == 12){

          double currLm = double.parse(lm.position.y.toStringAsFixed(1));
          // (recording[0].item2 == currLm )
          
          if( recording[0].item2 +3 >= currLm) {
            isTracking = false;
            record(currLm);
            
            segments.add(recording[(recording.length)-1].item1); //top_2
            ctr++;
            seg = seg + "\n Current " + ctr.toString();
            squatPrompt = "Recording Done";
            saveImgs();
            isRecording = false;
            isTimed = false;
            initialTime = (DateTime.now().millisecondsSinceEpoch/1000);
            initialTime2 = (DateTime.now().millisecondsSinceEpoch/1000);
            monitorVal = 0.01;
          }
        }
      }
      if(id== 12){
      }
    }
  }
  int ctr1 = 0;

  Future<void> save() async {

    await ImageGallerySaver.saveImage(
        Uint8List.fromList(list),
        name: "input${ctr1.toString()}");
        
      ctr1++;
  }

  void record(double lm) {

    
    // RenderRepaintBoundary boundary = globalKey.currentContext?.findRenderObject() as RenderRepaintBoundary;
    // boundary. markNeedsCompositingBitsUpdate();
    // final image = await boundary.toImage();
    // final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    // final pngBytes = byteData!.buffer.asUint8List();

    Tuple2<Uint8List, double> tmp = Tuple2(list, lm);
    recording.add(tmp);
    
  }

  bool segmentize(){

    segments.add(recording[0].item1);         
    ctr++;
    double initialYval = recording[0].item2;
    int startIdx = 0;
    for(int i = 0; i < (recording.length); i++ ){          
      if(recording[i].item2 > initialYval){
          startIdx = i;
          break;
      }
    }
    segments.add(recording[ (((recording.length)+startIdx)/2).ceil() ].item1); //mid_1
    ctr++;
    segments.add(recording[ (recording.length)-2 ].item1); // bot_1
    ctr++;
    
    return true;
  }

  void saveImgs()  {

    int counter = 0;
    for(Uint8List segment in segments){ 
    
      ImageGallerySaver.saveImage(
        Uint8List.fromList(segment),
        name: "input${counter.toString()}");
        
      counter+=1;
    }
    segments.clear();
    recording.clear();
  }

  Widget? get _selectedTab => _selectedTabIndex == 0
      ? _cameraDetectionView
      : null;

  Widget get _cameraDetectionView => SingleChildScrollView(
        child: Center(
          child: Column(
            children: [
              ClipRect(                  
                  child: CustomPaint(
                    child: _cameraImage,
                    foregroundPainter: PosePainter(
                      pose: _detectedPose,
                      imageSize: _imageSize,
                    ),
                  ),
                ),
              OutlinedButton(
                onPressed: _toggleDetectPose,
                child: _isDetectingPose
                    ? const Text('Turn off pose detection')
                    : const Text('Turn on pose detection'),
              ),
              Center(
                child: Text(squatPrompt),
              ),
              Text(land),
              Text(getLM),
              Text(seg),
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