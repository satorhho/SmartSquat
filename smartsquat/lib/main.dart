import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:tflite/tflite.dart';
import 'package:tuple/tuple.dart';
import 'package:permission_handler/permission_handler.dart';

import 'package:body_detection/body_detection.dart';
import 'package:body_detection/models/pose_landmark.dart';
import 'package:body_detection/models/image_result.dart';
import 'package:body_detection/models/pose.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;

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

  // Utilities
  // ~ Text
    List<String> out = ["a", "b", "c", "d"];
    String squatPrompt = "";
    String pass = "";
    
  // ~ Recording Segments
  late Uint8List list;
  List<Uint8List> segments = [];
  List<Tuple2<Uint8List, double>> recording = [];
  late Pose recPose; 

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

  // ~ folder Directory
  var systemTempDir = Directory.systemTemp;

  // ~ CNN
  bool _loading = true;
  late List _output;
  

  Future<void> _startCameraStream() async {
    final request = await Permission.camera.request();

    if (request.isGranted) {
      final request2 = await Permission.storage.request();
      if (request2.isGranted){
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


  // *********** Segmentation Functions   ****************** //

  void segmentation() {

    for(PoseLandmark lm in _detectedPose!.landmarks){
      
      int id = lm.type.index;
      if(id == 12){
        tmpLmVal = double.parse(lm.position.x.toStringAsFixed(1));    //if shoulder, take x val
      }

      // Left shoulder is timed for 2 seconds, if landmark is within range of previous frame, start
      
      if(isTimed == false){             
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

      //Records the downwards squat of the user
      if(isRecording){
        if(id == 12){
          record(lm.position.y);
          
          recThis = double.parse(lm.position.y.toStringAsFixed(1));
         
          if(monitorVal - 3 > recThis ){
            
            isRecording = false;
            isTracking = saveSegments();
            monitorVal = 1000;
            isTimed = false;
            initialTime = (DateTime.now().millisecondsSinceEpoch/1000);
            initialTime2 = (DateTime.now().millisecondsSinceEpoch/1000);
          }
          monitorVal = double.parse(lm.position.y.toStringAsFixed(1));
        }    
        
      }
      
      // Tracks the user if the downward squat is over

      if (isTracking){
        if(id == 12){

          double currLm = double.parse(lm.position.y.toStringAsFixed(1));
          
          if(currLm <= recording[0].item2 +3) {
            isTracking = false;
            record(currLm);
            
            segments.add(recording[(recording.length)-1].item1); //top_2
            ctr++;
            
            // seg = seg + "\n Current " + ctr.toString();
            squatPrompt = "Recording Done";
            predictImages();
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
 
 
  // ****************** Recording Segments ****************** //

  void record(double lm) {
    recPose = _detectedPose!;
    Tuple2<Uint8List, double> tmp = Tuple2(list, lm);
    recording.add(tmp);
    
  }

  bool saveSegments(){
    segments.add(recording[0].item1); // top_1

    double prevFrameYval = recording[0].item2; // NOTE: The 2 index here is he 2nd decimal place
    int changeIdx = 0;

    double nextFrameYval = recording[recording.length-2].item2;
    int changeIdxBot = 0;

    for (int i= 0; i <recording.length-1; i++){
      if( recording[i].item2 - 3 > prevFrameYval) {   //This is where the change starts from top_1 
          changeIdx = i;
          break;
      }
    }
            
    for(int j = 0; j < recording.length-1; j++){
      if( (recording[j].item2 <= (nextFrameYval +1)) && ( recording[j].item2 >= (nextFrameYval-1)) ){ // This is where the change starts to bot_1
          changeIdxBot = j;
          break;
          }
    }
    segments.add(recording[((changeIdx + changeIdxBot)~/2.0)].item1);
    ctr++;
    segments.add(recording[(recording.length)-2].item1); // bot_1
    ctr++;

    return true;
  }



// **************  CNN Model  ******************* //

  // Runs the model
  void predictImages() async {
    
    for(int i=0; i<=3; i++){  
      await recognizeImageBinary(segments[i], i);
    }

    segments.clear();
    recording.clear();
  }

  //loads the model
  recognizeImageBinary(Uint8List image, int i) async {
    
    img.Image? oriImage = img.decodeJpg(image);
    img.Image resizedImage = img.copyResize(oriImage!, height: 224, width: 224);
    var output = await Tflite.runModelOnBinary(
      binary: imageToByteListFloat32(resizedImage, 224, 127.5, 127.5),
      numResults: 8,
      threshold: 0.05,
    );
    setState(() {
      _output = output!;
      out[i] = "${output[0]['label']}";
    });
  }

  //Processes image for binary input
   Uint8List imageToByteListFloat32(
      img.Image image, int inputSize, double mean, double std) {
    var convertedBytes = Float32List(1 * inputSize * inputSize * 3);
    var buffer = Float32List.view(convertedBytes.buffer);
    int pixelIndex = 0;
    for (var i = 0; i < inputSize; i++) {
      for (var j = 0; j < inputSize; j++) {
        var pixel = image.getPixel(j, i);
        buffer[pixelIndex++] = (img.getRed(pixel) - mean) / std;
        buffer[pixelIndex++] = (img.getGreen(pixel) - mean) / std;
        buffer[pixelIndex++] = (img.getBlue(pixel) - mean) / std;
      }
    }
    return convertedBytes.buffer.asUint8List();
  }

    @override
  void initState() {
    //initState is the first function that is executed by default when this class is called
    super.initState();
    loadModel().then((value) {
      setState(() {});
    });
  }

  @override
  void dispose() {
    //dispose function disposes and clears our memory
    super.dispose();
    Tflite.close();
  }

   classifyImage(File image, int i) async {
    
    pass = "Classify Image";
    //this function runs the model on the image
    _output = (await Tflite.runModelOnImage(
      path: image.path,
      numResults:8, 

    ))!;

    _loading = false;   
    out[i] = "${_output[0]['label']}";   
    
  }

  loadModel() async {
    //this function loads our model
    await Tflite.loadModel(
      model: 'assets/smartsquat.tflite',
      labels: 'assets/labels.txt',
    );
  }

  // *************** Feedbacking ************** //

  //use recPose for PoseEstimation
  


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
          Text(out[0]),
          Text(out[1]),
          Text(out[2]),
          Text(out[3]),
          Center(
            child: Text(pass)
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