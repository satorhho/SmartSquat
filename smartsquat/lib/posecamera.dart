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

class Posecamera extends StatefulWidget {
  const Posecamera({Key? key}) : super(key: key);
  @override
  _PosecameraState createState() => _PosecameraState();
}

class _PosecameraState extends State<Posecamera> {
  GlobalKey globalKey = GlobalKey();

  FlutterTts flutterTts = FlutterTts();

  int _selectedTabIndex = 0;

  bool _screen = true;
  bool _isDetectingPose = false;
  Pose? _detectedPose;
  Image? _cameraImage;
  Size _imageSize = Size.zero;

  // Utilities
  // ~ Text
  List<String> prediction_out = ["a", "b", "c", "d"];
  List<String> correct_output = ["c_top_1", "c_mid_1", "c_bot_1", "c_top_2"];
  String squatPrompt = "";
  String result_feedback = "";

  // checker
  List<bool> check = [false, false, false, false, false];

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
  double initialTime2 = (DateTime.now().millisecondsSinceEpoch / 1000);
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
      // final request2 = await Permission.storage.request();
      // if (request2.isGranted) {
      await BodyDetection.startCameraStream(
        onFrameAvailable: _handleCameraImage,
        onPoseAvailable: (pose) {
          if (!_isDetectingPose) return;
          _handlePose(pose);
          segmentation();
        },
      );
      // }
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

  int nspeech = 0;

  // *********** Segmentation Functions   ****************** //

  Future<void> segmentation() async {
    double currTime = (DateTime.now().millisecondsSinceEpoch / 1000);
    if (currTime >= initialTime2) {
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
          currTime = (DateTime.now().millisecondsSinceEpoch / 1000);
          if (currTime >= (initialTime2 + 2)) {
            currTime = (DateTime.now().millisecondsSinceEpoch / 1000);
            if (currTime >= (initialTime + 3)) {
              isRecording = true;
              squatPrompt = "Recording, Please Squat now";
              if (nspeech == 0) {
                await speechnow("You may squat now");
                nspeech = 1;
              }
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

              _toggleDetectPose();
              squatPrompt = "Predicting";
              await speechnow("Please wait for evaluation");
              showscreen();
              await predictImages();
              squatPrompt = "Finish Predicting";
              nspeech = 0;
              isRecording = false;
              isTimed = false;
              initialTime = (DateTime.now().millisecondsSinceEpoch / 1000);
              initialTime2 = (DateTime.now().millisecondsSinceEpoch / 1000) + 5;
              // currTime = (DateTime.now().millisecondsSinceEpoch / 1000);
              monitorVal = 0.01;
              _toggleDetectPose();
            }
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

    segments.add(recording[(recording.length) - 2].item1); // bot_1
    segPose.add(recPose[(recPose.length) - 2].item2);

    return true;
  }

// **************  CNN Model  ******************* //
  double timepredicting = 0;

  // Runs model on each of the segments
  Future predictImages() async {
    int startTime = new DateTime.now().millisecondsSinceEpoch;
    for (int i = 0; i <= 3; i++) {
      await recognizeImageBinary(segments[i], i);
    }
    await Feedbacking(segPose);
    int endtime = new DateTime.now().millisecondsSinceEpoch;
    endtime = endtime - startTime;
    timepredicting = endtime / 1000;
    prediction_out = ["a", "b", "c", "d"];

    segPose.clear();
    recPose.clear();
    segments.clear();
    recording.clear();
    showscreen();
  }

  // showing squatting motion
  void showscreen() {
    setState(() {
      if (_screen == true) {
        _screen = false;
      } else {
        _screen = true;
      }
    });
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
      prediction_out[i] = "${output[0]['label']}";
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
    loadModel().then((val) {
      setState(() {});
    });
  }

  @override
  void dispose() {
    //dispose function disposes and clears our memory
    super.dispose();
    Tflite.close();
  }

  // classifyImage(File image, int i) async {
  //   pass = "Classify Image";
  //   //this function runs the model on the image
  //   _output = (await Tflite.runModelOnImage(
  //     path: image.path,
  //     numResults: 8,
  //   ))!;

  //   _loading = false;
  //   out[i] = "${_output[0]['label']}";
  // }

  Future loadModel() async {
    Tflite.close();
    //this function loads our model
    await Tflite.loadModel(
      model: 'assets/smartsquat.tflite',
      labels: 'assets/labels.txt',
    );
  }

  // *************** text to speech ************* //

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

  Feedbacking(List<Pose?> pose) async {
    bool flatfeet = false;
    bool head = false;
    bool torso = false;
    bool kneecaving = false;
    bool depth = false;
    for (int i = 0; i <= 3; i++) {
      if (prediction_out[i] != correct_output[i]) {
        head = (head || checkHeadAlignment(pose[i]));
        if (i >= 1 && i <= 3) {
          torso = (torso || checkTorsoAngle(pose[0], pose[i]));
        }
        if (i == 0 || i == 2) {
          flatfeet = (flatfeet || checkFlatFoot(pose[i], pose[i + 1]));
          if (i == 2) {
            depth = (depth || depths(pose[i]));
          }
        }
        if (i == 3) {
          kneecaving = (kneecaving || kneeCaveIn(pose[2], pose[i]));
        }
      }
    }
    result_feedback = "";
    textCheck(flatfeet, head, torso, kneecaving, depth);
    if (result_feedback.isEmpty) {
      result_feedback = "You have a correct posture";
    }
    await speechnow(result_feedback);
    check = [false, false, false, false, false];
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

  List<double> lmPosition(Pose? pose, int i) {
    double x = 0, y = 0;
    for (PoseLandmark lm in pose!.landmarks) {
      int id = lm.type.index;
      if (id == i) {
        x = double.parse(lm.position.x.toStringAsFixed(3));
        y = double.parse(lm.position.y.toStringAsFixed(3));
      }
    }
    return [x, y];
  }

  // half-check
  bool checkHeadAlignment(Pose? pose) {
    var righteyeouter = lmPosition(pose, 24);
    var rightear = lmPosition(pose, 20);

    if (righteyeouter[1] > rightear[1]) {
      check[0] = true;
    }
    return check[0];
  }

//
  bool checkFlatFoot(Pose? pose, Pose? midtop) {
    var rightHeel = lmPosition(pose, 25);
    var midtop_rightHeel = lmPosition(midtop, 25);
    var minus_right = rightHeel[1] - midtop_rightHeel[1];

    var leftHeel = lmPosition(pose, 7);
    var midtop_leftHeel = lmPosition(midtop, 7);
    var minus_left = rightHeel[1] - midtop_rightHeel[1];

    if (minus_right.abs() > 8.2 || minus_left.abs() > 8.2) {
      check[1] = true;
    }

    return check[1];
  }

  bool checkTorsoAngle(Pose? top1, Pose? pose) {
    var top1_leftShoulder = lmPosition(top1, 12);
    var leftShoulder = lmPosition(pose, 12);
    var minus_shoulder = top1_leftShoulder[0] - leftShoulder[0];
    if (minus_shoulder.abs() > 20) {
      check[2] = true;
    }
    return check[2];
  }

  // check
  bool kneeCaveIn(Pose? bot, Pose? pose) {
    var bot_leftKnee = lmPosition(bot, 10);
    var bot_rightKnee = lmPosition(bot, 28);
    var bot_disKnee = distance2d(
        bot_rightKnee[0], bot_rightKnee[1], bot_leftKnee[0], bot_leftKnee[1]);
    bot_disKnee = double.parse(bot_disKnee.toStringAsFixed(0));

    var leftKnee = lmPosition(pose, 10);
    var rightKnee = lmPosition(pose, 28);
    var disKnee =
        distance2d(rightKnee[0], rightKnee[1], leftKnee[0], leftKnee[1]);
    disKnee = double.parse(disKnee.toStringAsFixed(0));

    if (bot_disKnee < disKnee) {
      check[3] = true;
    }
    return check[3];
  }

  // check
  bool depths(Pose? pose) {
    var rightKnee = lmPosition(pose, 28);
    var rightHip = lmPosition(pose, 26);

    if (rightHip[1] < rightKnee[1]) {
      check[4] = true;
    }
    return check[4];
  }

  Widget? get _selectedTab =>
      _selectedTabIndex == 0 ? _cameraDetectionView : null;

  Widget get _cameraDetectionView => SingleChildScrollView(
        child: Center(
            child: _screen == true
                ? Column(
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
                      Text(result_feedback),
                      Text("time: " + timepredicting.toString() + "s"),
                    ],
                  )
                : Column(
                    children: [
                      ClipRect(
                        child: Image.asset(
                          'assets/images/gif-squating.gif',
                          fit: BoxFit.fill,
                          height: 450,
                          alignment: Alignment.center,
                        ),
                      ),
                      Center(
                        child: Text("PREDICTING . . ."),
                      ),
                    ],
                  )),
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
