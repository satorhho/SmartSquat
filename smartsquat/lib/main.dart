
import 'package:body_detection/body_detection.dart';

import 'package:body_detection/models/image_result.dart';
import 'package:body_detection/models/pose.dart';
import 'package:flutter/material.dart';

import 'package:permission_handler/permission_handler.dart';

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
  int _selectedTabIndex = 0;

  bool _isDetectingPose = false;

  Pose? _detectedPose;
  Image? _cameraImage;
  Size _imageSize = Size.zero;


  Future<void> _startCameraStream() async {
    final request = await Permission.camera.request();
    if (request.isGranted) {
      await BodyDetection.startCameraStream(
        onFrameAvailable: _handleCameraImage,
        onPoseAvailable: (pose) {
          if (!_isDetectingPose) return;
          _handlePose(pose);
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
