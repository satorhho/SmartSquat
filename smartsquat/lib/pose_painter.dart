import 'dart:io';
import 'dart:ui';
import 'dart:typed_data';
import 'package:tuple/tuple.dart';
import 'package:flutter/widgets.dart';
import 'package:body_detection/models/pose.dart';
import 'package:body_detection/models/pose_landmark.dart';
import 'package:body_detection/models/pose_landmark_type.dart';



class PosePainter extends CustomPainter {
  PosePainter({
    required this.pose,
    required this.imageSize,
  });

  final Pose? pose;
  final Size imageSize;
  final pointPaint = Paint()..color = const Color.fromRGBO(255, 255, 255, 0.8);
  final leftPointPaint = Paint()..color = const Color.fromRGBO(223, 157, 80, 1);
  final rightPointPaint = Paint()..color = const Color.fromRGBO(100, 208, 218, 1);
  final linePaint = Paint()..color = const Color.fromRGBO(255, 255, 255, 0.9)..strokeWidth = 3;

  final Future<Directory> path = Directory('cnn_inputs').create(recursive: true); 
  final int counter = 0; 

  List<Uint8List> segments = [];
  List<Tuple2<Uint8List, double>> recording = [];              //saves a list of tuple. Use recording[].item1 to get the image (which is in bytes), and recording[].item2 to get Y Coordinate
  
  @override
  void paint(Canvas canvas, Size size) {
    _paintPose(canvas, size);
  }

  
  
  void _paintPose(Canvas canvas, Size size) {
    //Recording ulitilites
    List<Tuple2<Uint8List, double>> recording = [];

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


    if (pose == null) return;

    final double hRatio =
        imageSize.width == 0 ? 1 : size.width / imageSize.width;
    final double vRatio =
        imageSize.height == 0 ? 1 : size.height / imageSize.height;

    offsetForPart(PoseLandmark part) =>
        Offset(part.position.x * hRatio, part.position.y * vRatio);

    // Landmark connections
    final landmarksByType = {for (final it in pose!.landmarks) it.type: it};
    for (final connection in connections) {
      final point1 = offsetForPart(landmarksByType[connection[0]]!);
      final point2 = offsetForPart(landmarksByType[connection[1]]!);
      canvas.drawLine(point1, point2, linePaint);
    }

    for (final part in pose!.landmarks) {
      // Landmark points
      canvas.drawCircle(offsetForPart(part), 5, pointPaint);
      if (part.type.isLeftSide) {
        canvas.drawCircle(offsetForPart(part), 3, leftPointPaint);
      } else if (part.type.isRightSide) {
        canvas.drawCircle(offsetForPart(part), 3, rightPointPaint);
      }
    }

    

    for (final lm in pose!.landmarks) { //lm is landmark

      // One of the 33 detectable body landmarks.
      int id = lm.type.index;

      if(id == 11){
        tmpLmVal = double.parse(lm.position.x.toStringAsFixed(1));  //if shoulder, take x val
      }

                                //Set timer for 2 seconds
      if(!isTimed){             // if not timed, 
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
          saveRecords(canvas, size, recording, pose);
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
            saveRecords(canvas, size, recording, pose);
            segments.add(recording[(recording.length)-1].item1);
            saveImgs(recording, segments);
            isRecording = false;
            isTimed = false;
            initialTime = now.millisecondsSinceEpoch/1000;
            initialTime2 = now.millisecondsSinceEpoch/1000;
            monitorVal = 0.01;
            Paragraph se= "Squat Ended" as Paragraph;
            canvas.drawParagraph(se , const Offset(0.0, 0.0));
          }
        }
      }
    }

    
  }

  Future<void> saveRecords(Canvas canvas, Size size, List<Tuple2< Uint8List, double>> recording, Pose? pose) async {
    
    final recorder = PictureRecorder();
    Canvas newcanvas = canvas;
    newcanvas = Canvas(
            recorder,
            Rect.fromPoints(const Offset(0.0, 0.0),
                Offset(size.width, size.height)));
    final picture = recorder.endRecording();

    final image = await picture.toImage(size.width.toInt(), size.height.toInt());
    final dataBytes =  await image.toByteData(format: ImageByteFormat.png);
    final list = dataBytes!.buffer.asUint8List();
    Tuple2<Uint8List, double> tmp = Tuple2(list, double.parse(pose!.landmarks[11].position.y.toStringAsFixed(1)));
    recording.add(tmp);

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
    
    final result = File('$path/input$counter.png')
      .writeAsBytesSync(segment.buffer.asInt8List());

    counter++;
    

    }
    segments.clear();
    recordingArr.clear();
    
  }


  @override
  bool shouldRepaint(PosePainter oldDelegate) {
    return oldDelegate.pose != pose ||
        oldDelegate.imageSize != imageSize;
  }
  

   

//*****Landmarks

  List<List<PoseLandmarkType>> get connections => [
        [PoseLandmarkType.leftEar, PoseLandmarkType.leftEyeOuter],
        [PoseLandmarkType.leftEyeOuter, PoseLandmarkType.leftEye],
        [PoseLandmarkType.leftEye, PoseLandmarkType.leftEyeInner],
        [PoseLandmarkType.leftEyeInner, PoseLandmarkType.nose],
        [PoseLandmarkType.nose, PoseLandmarkType.rightEyeInner],
        [PoseLandmarkType.rightEyeInner, PoseLandmarkType.rightEye],
        [PoseLandmarkType.rightEye, PoseLandmarkType.rightEyeOuter],
        [PoseLandmarkType.rightEyeOuter, PoseLandmarkType.rightEar],
        [PoseLandmarkType.mouthLeft, PoseLandmarkType.mouthRight],
        [PoseLandmarkType.leftShoulder, PoseLandmarkType.rightShoulder],
        [PoseLandmarkType.leftShoulder, PoseLandmarkType.leftHip],
        [PoseLandmarkType.rightShoulder, PoseLandmarkType.rightHip],
        [PoseLandmarkType.rightShoulder, PoseLandmarkType.rightElbow],
        [PoseLandmarkType.rightWrist, PoseLandmarkType.rightElbow],
        [PoseLandmarkType.rightWrist, PoseLandmarkType.rightThumb],
        [PoseLandmarkType.rightWrist, PoseLandmarkType.rightIndexFinger],
        [PoseLandmarkType.rightWrist, PoseLandmarkType.rightPinkyFinger],
        [PoseLandmarkType.leftHip, PoseLandmarkType.rightHip],
        [PoseLandmarkType.leftHip, PoseLandmarkType.leftKnee],
        [PoseLandmarkType.rightHip, PoseLandmarkType.rightKnee],
        [PoseLandmarkType.rightKnee, PoseLandmarkType.rightAnkle],
        [PoseLandmarkType.leftKnee, PoseLandmarkType.leftAnkle],
        [PoseLandmarkType.leftElbow, PoseLandmarkType.leftShoulder],
        [PoseLandmarkType.leftWrist, PoseLandmarkType.leftElbow],
        [PoseLandmarkType.leftWrist, PoseLandmarkType.leftThumb],
        [PoseLandmarkType.leftWrist, PoseLandmarkType.leftIndexFinger],
        [PoseLandmarkType.leftWrist, PoseLandmarkType.leftPinkyFinger],
        [PoseLandmarkType.leftAnkle, PoseLandmarkType.leftHeel],
        [PoseLandmarkType.leftAnkle, PoseLandmarkType.leftToe],
        [PoseLandmarkType.rightAnkle, PoseLandmarkType.rightHeel],
        [PoseLandmarkType.rightAnkle, PoseLandmarkType.rightToe],
        [PoseLandmarkType.rightHeel, PoseLandmarkType.rightToe],
        [PoseLandmarkType.leftHeel, PoseLandmarkType.leftToe],
        [PoseLandmarkType.rightIndexFinger, PoseLandmarkType.rightPinkyFinger],
        [PoseLandmarkType.leftIndexFinger, PoseLandmarkType.leftPinkyFinger],
      ];
}
