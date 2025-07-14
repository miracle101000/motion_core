import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:math' show pi;
import 'package:vector_math/vector_math_64.dart' show Vector3,  Matrix4;
import 'package:motion_core/motion_core.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Motion Core Demo',
      theme: ThemeData.dark(),
      home: const MotionDemoScreen(),
    );
  }
}

class MotionDemoScreen extends StatefulWidget {
  const MotionDemoScreen({super.key});
  @override
  State<MotionDemoScreen> createState() => _MotionDemoScreenState();
}

class _MotionDemoScreenState extends State<MotionDemoScreen> {
  MotionData? _motionData;
  StreamSubscription? _motionSubscription;
  bool _isAvailable = false;

  @override
  void initState() {
    super.initState();
    _checkAvailabilityAndStart();
  }

  Future<void> _checkAvailabilityAndStart() async {
    bool available = await MotionCore.isAvailable();
    if (!mounted) return;
    setState(() => _isAvailable = available);
    if (_isAvailable) _startListening();
  }

  void _startListening() {
    _motionSubscription = MotionCore.motionStream.listen((MotionData data) {
      if (mounted) setState(() => _motionData = data);
    });
  }

  @override
  void dispose() {
    _motionSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Core Motion & Sensor Fusion')),
      body: Center(
        child: !_isAvailable
            ? const Text('Required motion sensors are not available.')
            : _motionData == null
                ? const CircularProgressIndicator()
                : Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _build3DBox(),
                        const SizedBox(height: 32),
                        _buildDataTable(),
                      ],
                    ),
                  ),
      ),
    );
  }

  Widget _build3DBox() {
    final quat = _motionData!.attitude;
    final matrix = Matrix4.compose(
      Vector3.zero(),   // no translation
      quat,             // rotation from quaternion
      Vector3.all(1),   // no scaling
    )..setEntry(3, 2, 0.001); // adds nice perspective

    return Transform(
      transform: matrix,
      alignment: Alignment.center,
      child: Container(
        width: 150,
        height: 150,
        decoration: BoxDecoration(
          color: Colors.blueAccent.withValues(alpha: .8),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white, width: 2),
        ),
        child: const Center(
          child: Text('FRONT', style: TextStyle(fontWeight: FontWeight.bold)),
        ),
      ),
    );
  }

  Widget _buildDataTable() {
    final data = _motionData!;
    final heading = data.headingAccuracy < 0
        ? 'N/A'
        : '${(data.headingAccuracy * 180/pi).toStringAsFixed(1)}°';

    return Table(
      columnWidths: const {0: IntrinsicColumnWidth()},
      children: [
        _buildTableRow('Pitch:', '${(data.pitch * 180/pi).toStringAsFixed(1)}°'),
        _buildTableRow('Roll:',  '${(data.roll * 180/pi).toStringAsFixed(1)}°'),
        _buildTableRow('Yaw:',   '${(data.yaw * 180/pi).toStringAsFixed(1)}°'),
        _buildTableRow('Heading Acc:', heading),
        _buildTableRow('Gravity:', _formatVector3(data.gravity)),
        _buildTableRow('User Acc:', _formatVector3(data.userAcceleration)),
      ],
    );
  }

  TableRow _buildTableRow(String label, String value) {
    return TableRow(children: [
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 4.0),
        child: Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 4.0),
        child: Text(value),
      ),
    ]);
  }

  String _formatVector3(Vector3 v) =>
      'X:${v.x.toStringAsFixed(2)}, Y:${v.y.toStringAsFixed(2)}, Z:${v.z.toStringAsFixed(2)}';
}
