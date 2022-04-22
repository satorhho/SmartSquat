import 'dart:math';
import 'package:vector_math/vector_math.dart' as math;
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
import 'package:flutter_tts/flutter_tts.dart';

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

  FlutterTts flutterTts = FlutterTts();

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
  late Uint8List _image;
  List<Uint8List> segments = [];
  List<Tuple2<Uint8List, double>> recording = [];
  List<Tuple2<Uint8List, Pose?>> recPose = [];
  List<Pose?> segPose = [];
  Uint8List list = Uint8List.fromList([0, 2, 5, 7, 42, 255]);
  // late List<Pose> recPose;

  // ~ Timer
  double initialTime = (DateTime.now().millisecondsSinceEpoch / 1000);
  double initLmPos = 0.01;
  double initYpos = 0;
  double tmpLmVal = 0.1;
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
      if (request2.isGranted) {
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
    _image = result.bytes;
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
  int nspeech = 0;

  // *********** Segmentation Functions   ****************** //

  Future<void> segmentation() async {
    for (PoseLandmark lm in _detectedPose!.landmarks) {
      int id = lm.type.index;
      if (id == 12) {
        tmpLmVal = double.parse(
            lm.position.x.toStringAsFixed(1)); //if shoulder, take x val
      }

      // Left shoulder is timed for 2 seconds, if landmark is within range of previous frame, start

      if (isTimed == false) {
        initialTime = (DateTime.now().millisecondsSinceEpoch / 1000);
        if (id == 12) {
          initLmPos = double.parse(lm.position.x.toStringAsFixed(1));
        }
      } else if (isTimed) {
        double currTime = (DateTime.now().millisecondsSinceEpoch / 1000);
        if (currTime >= (initialTime + 2)) {
          isRecording = true;
          squatPrompt = "Recording, Please Squat now";
          if (nspeech == 0) {
            await speechnow("You may squat now");
            nspeech = 1;
          }
        }
      }

      if ((tmpLmVal <= (initLmPos + 5)) && (tmpLmVal >= (initLmPos - 5))) {
        isTimed = true;
      } else {
        isTimed = false;
      }

      //Records the downwards squat of the user
      if (isRecording) {
        if (id == 12) {
          record(lm.position.y);

          recThis = double.parse(lm.position.y.toStringAsFixed(1));

          if (monitorVal - 3 > recThis) {
            isRecording = false;
            isTracking = saveSegments();
            monitorVal = 1000;
            isTimed = false;
            initialTime = (DateTime.now().millisecondsSinceEpoch / 1000);
          }
          monitorVal = double.parse(lm.position.y.toStringAsFixed(1));
        }
      }

      // Tracks the user and checks if the squat is now going upward

      if (isTracking) {
        if (id == 12) {
          double currLm = double.parse(lm.position.y.toStringAsFixed(1));

          if (currLm <= recording[0].item2 + 3) {
            isTracking = false;
            record(currLm);

            segments.add(recording[(recording.length) - 1].item1); //top_2
            segPose.add(recPose[(recPose.length) - 1].item2);
            ctr++;

            // _toggleDetectPose();
            await speechnow("Please wait for evaluation");
            squatPrompt = "Recording Done";
            predictImages();
            nspeech = 0;
            isRecording = false;
            isTimed = false;
            initialTime = (DateTime.now().millisecondsSinceEpoch / 1000);
            monitorVal = 0.01;
          }
        }
      }
    }
  }

  // ****************** Recording Segments ****************** //

  // ~ Saves the Image, Pose Estimation and lm(y-coordinate of shoulder)
  void record(double lm) {
    Tuple2<Uint8List, Pose?> forpose = Tuple2(list, _detectedPose);
    recPose.add(forpose);
    // recPose.add(_detectedPose!);
    Tuple2<Uint8List, double> tmp = Tuple2(_image, lm);
    recording.add(tmp);
  }

  // ~ Segmentizes the recorded squat and saves it in the list 'segments'
  bool saveSegments() {
    segments.add(recording[0].item1); // top_1
    segPose.add(recPose[0].item2);

    double prevFrameYval = recording[0].item2; //Top_1 y-coordinate
    int changeIdx = 0;

    double nextFrameYval =
        recording[recording.length - 2].item2; //Bot_1 y-coordinate
    int changeIdxBot = 0;

    for (int i = 0; i < recording.length - 1; i++) {
      if (recording[i].item2 >= prevFrameYval + 1) {
        //Captures the index where the user has started to descend
        changeIdx = i;
        break;
      }
    }

    for (int j = 0; j < recording.length - 1; j++) {
      if (recording[j].item2 >= (nextFrameYval - 2)) {
        // Captures the index of the user's squat where it first reach the bot
        changeIdxBot = j;
        break;
      }
    }
    segments.add(recording[((changeIdx + changeIdxBot) ~/ 2.0)].item1);
    segPose.add(recPose[((changeIdx + changeIdxBot) ~/ 2.0)].item2);
    ctr++;
    segments.add(recording[(recording.length) - 2].item1); // bot_1
    segPose.add(recPose[(recPose.length) - 2].item2);
    ctr++;

    return true;
  }

// **************  CNN Model  ******************* //

  // Runs model on each of the segments
  void predictImages() async {
    for (int i = 0; i <= 3; i++) {
      await recognizeImageBinary(segments[i], i);
      if (out[i][0] == 'i') {
        Feedbacking(segPose[i]);
        speechnow(result_feedback);
      }
    }

    segPose.clear();
    recPose.clear();
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
      numResults: 8,
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

  // *************** text to speech ************* //
  // bool tospeech() {
  //   bool textcheck = false;
  //   if (!result_feedback.isEmpty) {
  //     textcheck = true;
  //   }
  //   return textcheck;
  // }

  speechnow(String str_speech) async {
    await flutterTts.setLanguage("en-US");
    await flutterTts.setPitch(1);
    await flutterTts.speak(str_speech);
  }

  // *************** Feedbacking ************** //

  //use recPose for PoseEstimation

  // ****** 2D Calculation ****** //
  double calc2(double x1, double x2) {
    return ((x2 - x1) * (x2 - x1));
  }

  double slope(x1, y1, x2, y2) {
    double X = x2 - x1;
    double Y = y2 - y1;
    double resultXY = Y / X;

    return resultXY;
  }

  double anglecomputation(x1, y1, x2, y2, x3, y3) {
    double angle =
        math.degrees(atan2(y3 - y2, x3 - x2) - atan2(y1 - y2, x1 - x2));
    if (angle < 0) {
      angle += 180;
    }
    return angle;
  }

  double distance2d(x1, y1, x2, y2) {
    return sqrt(calc2(x1, x2) + calc2(y1, y2));
  }

  List<double> lmPosition(Pose? pose, int i) {
    return [
      pose!.landmarks[i].position.x,
      pose.landmarks[i].position.y,
      pose.landmarks[i].position.z
    ];
  }

  // segment counter
  int counter = 0;
  // result error
  String result_feedback = "";

  //checker
  bool flatfeet = false;
  bool head = false;
  bool torso = false;
  bool kneecaving = false;
  bool depth = false;
  List<bool> check = [false, false, false, false, false];

  void Feedbacking(Pose? pose) {
    result_feedback = "";

    flatfeet = (flatfeet || checkFlatFoot(pose));
    head = (head || checkHeadAlignment(pose));
    torso = (torso || checkTorsoAngle(pose));

    if (counter > 0 && counter < 4) {
      kneecaving = (kneecaving || kneeCaveIn(pose));
      depth = (depth || depths(pose));
      if (counter == 3) {
        textCheck(flatfeet, head, torso, kneecaving, depth);
        if (!result_feedback.isEmpty == "") {
          result_feedback = "You have a correct form";
        }
      }
    }

    counter++;

    if (counter > 3) {
      counter = 0;
      check = [false, false, false, false, false];
      flatfeet = false;
      head = false;
      torso = false;
      kneecaving = false;
      depth = false;
    }
  }

// function for printing errors in the body movement
  String textCheck(bool foot, bool head, bool torso, bool knee, bool _depth) {
    foot
        ? result_feedback += "Make sure your feet is flat on the floor! \n"
        : null;
    head
        ? result_feedback += "Avoid facing down. Instead, face forward! \n"
        : null;
    torso ? result_feedback += "Bring your torso upright! \n" : null;
    knee
        ? result_feedback +=
            "Avoid caving your knees!. Point your knees outward! \n"
        : null;
    _depth ? result_feedback += "Lower your squat." : null;

    return result_feedback;
  }

  var distanceknee = {};
  var distancetoe = {};
  var deptharr = {};
  var torsoarr = {};
  var headarr = {};
  bool checkHeadAlignment(Pose? pose) {
    var nose = lmPosition(pose, 18);
    var leftear = lmPosition(pose, 2);
    var headAllignment = slope(nose[0], nose[1], leftear[0], leftear[1]);

    headAllignment = double.parse(headAllignment.toStringAsFixed(3));

    headarr[counter] = headAllignment;
    if (counter == 2 && headarr[1] > headarr[0] && headarr[2] > headarr[1]) {
      check[0] = true;
    }
    return check[0];
  }

//
  bool checkFlatFoot(Pose? pose) {
    var rightHeel = lmPosition(pose, 25);
    var rightToe = lmPosition(pose, 32);
    var rfeet = slope(rightHeel[0], rightHeel[1], rightToe[0], rightToe[1]);
    rfeet = double.parse(rfeet.toStringAsFixed(3));

    var leftHeel = lmPosition(pose, 7);
    var leftToe = lmPosition(pose, 14);
    var lfeet = slope(leftHeel[0], leftHeel[1], leftToe[0], leftToe[1]);
    lfeet = double.parse(lfeet.toStringAsFixed(3));

    if (counter == 0 && lfeet < -0.8 || rfeet < -1.4) {
      check[1] = true;
    }

    return check[1];
  }

  bool checkTorsoAngle(Pose? pose) {
    var leftShoulder = lmPosition(pose, 12);
    var leftHip = lmPosition(pose, 8);
    var leftKnee = lmPosition(pose, 10);
    var torsoAngle = anglecomputation(leftKnee[0], leftKnee[1], leftHip[0],
        leftHip[1], leftShoulder[0], leftShoulder[1]);

    torsoAngle = double.parse(torsoAngle.toStringAsFixed(0));
    if (counter == 0) {
      torsoarr[0] = torsoAngle;
    }
    if (counter == 1) {
      torsoarr[1] = torsoAngle;
    }
    if (counter == 2) {
      torsoarr[2] = torsoAngle;
      var restorso = torsoarr[0] - torsoarr[1];
      var restorso2 = torsoarr[1] - torsoarr[2];
      if (restorso.abs() < 5 && (restorso2.abs() > 3 || restorso2.abs() == 0)) {
        check[2] = true;
      }
    }
    return check[2];
  }

  bool kneeCaveIn(Pose? pose) {
    var leftKnee = lmPosition(pose, 10);
    var rightKnee = lmPosition(pose, 28);
    var disKnee =
        distance2d(rightKnee[0], rightKnee[1], leftKnee[0], leftKnee[1]);
    disKnee = double.parse(disKnee.toStringAsFixed(0));

    var lefttoe = lmPosition(pose, 14);
    var righttoe = lmPosition(pose, 32);
    var distoe =
        distance2d(righttoe[0], rightKnee[1] - 1, lefttoe[0], leftKnee[1] - 1);
    distoe = double.parse(distoe.toStringAsFixed(0));

    if (counter == 1) {
      distanceknee[0] = disKnee;
      distancetoe[0] = distoe;
    }
    if (counter == 2) {
      distanceknee[1] = disKnee;
      distancetoe[1] = distoe;
      var disresmid = distanceknee[0] - distancetoe[0];
      var disresbot = distanceknee[1] - distancetoe[1];
      var disres = disresmid + disresbot;
      if (disres < 0) {
        check[3] = true;
      }
    }
    return check[3];
  }

  bool depths(Pose? pose) {
    var leftAnkle = lmPosition(pose, 1);
    var leftHip = lmPosition(pose, 8);
    var leftKnee = lmPosition(pose, 10);

    var depth = anglecomputation(leftAnkle[0], leftAnkle[1], leftKnee[0],
        leftKnee[1], leftHip[0], leftHip[1]);
    depth = double.parse(depth.toStringAsFixed(3));
    if (counter == 2 && (leftKnee[1] - leftHip[1]) <= 18) {
      check[4] = true;
    }
    return check[4];
  }

  Widget? get _selectedTab =>
      _selectedTabIndex == 0 ? _cameraDetectionView : null;

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
              Center(child: Text(pass)),
              Text(result_feedback),
            ],
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(
          title: const Text('Smart Squat'),
        ),
        bottomNavigationBar: BottomNavigationBar(
          items: const <BottomNavigationBarItem>[
            BottomNavigationBarItem(
              icon: Icon(Icons.camera),
              label: 'Start Camera',
            ),
          ],
          onTap: _onTabSelectTapped,
        ),
        body: _selectedTab,
      ),
    );
  }
}
