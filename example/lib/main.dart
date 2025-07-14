import 'package:cubixd/cubixd.dart';
import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:math' show pi;
import 'package:vector_math/vector_math_64.dart' show Matrix4, Vector2, Vector3;
import 'package:motion_core/motion_core.dart';

void main() => runApp(const MotionVisualizerApp());

class MotionVisualizerApp extends StatelessWidget {
  const MotionVisualizerApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Motion Visualizer',
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
    _motionSubscription = MotionCore.motionStream.listen((data) {
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
      appBar: AppBar(title: const Text('Motion Visualizer')),
      backgroundColor: Colors.black,
      body: !_isAvailable
          ? const Center(child: Text('Motion sensors not available'))
          : _motionData == null
              ? const Center(child: CircularProgressIndicator())
              : Column(
                  children: [
                    const SizedBox(height: 16),
                    Expanded(child: _buildRubikCube()),
                    const SizedBox(height: 16),
                    _buildGravityCompass(),
                    const SizedBox(height: 16),
                    _buildAccelerationIndicator(),
                    const SizedBox(height: 16),
                    _buildDataTable(),
                    const SizedBox(height: 16),
                  ],
                ),
    );
  }

  Widget _buildRubikCube() {
    final Vector3 euler = _motionData!.eulerAngles;
    return Center(
      child: CubixD(
        size: 180,
        delta: Vector2(-euler.x, -euler.y),
        onSelected: (opt, delta) {
          print('here');
        },
        front: _face(Colors.yellow),
        back: _face(Colors.pink),
        left: _face(Colors.blue),
        right: _face(Colors.green),
        top: _face(Colors.red),
        bottom: _face(Colors.orange),
      ),
    );
  }

  Widget _face(Color color) => Container(
        margin: const EdgeInsets.all(1.5),
        child: Container(
          color: color.withValues(alpha: .7),
        ),
      );

  Widget _buildGravityCompass() {
    final Vector3 g = _motionData!.gravity.normalized();
    return SizedBox(
      height: 100,
      child: CustomPaint(
        painter: _VectorArrowPainter(vector: g, color: Colors.purple),
        child: const Center(child: Text('Gravity Direction')),
      ),
    );
  }

  Widget _buildAccelerationIndicator() {
    final Vector3 acc = _motionData!.userAcceleration;
    final double intensity = acc.length.clamp(0.0, 2.0);
    return Center(
      child: Container(
        width: 80 + intensity * 40,
        height: 80 + intensity * 40,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.teal.withOpacity(0.5 + 0.2 * intensity),
        ),
        child: const Center(child: Text('ACC')),
      ),
    );
  }

  Widget _buildDataTable() {
    final d = _motionData!;
    final deg = (double r) => '${(r * 180 / pi).toStringAsFixed(1)}°';
    final heading = d.headingAccuracy < 0 ? 'N/A' : deg(d.headingAccuracy);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Table(
        columnWidths: const {0: IntrinsicColumnWidth()},
        children: [
          _row('Pitch', deg(d.pitch)),
          _row('Roll', deg(d.roll)),
          _row('Yaw', deg(d.yaw)),
          _row('Heading Acc', heading),
          _row('Gravity', _vec(d.gravity)),
          _row('User Acc', _vec(d.userAcceleration)),
        ],
      ),
    );
  }

  TableRow _row(String label, String val) => TableRow(children: [
        Padding(
            padding: const EdgeInsets.all(6),
            child: Text(label,
                style: const TextStyle(fontWeight: FontWeight.bold))),
        Padding(padding: const EdgeInsets.all(6), child: Text(val)),
      ]);

  String _vec(Vector3 v) =>
      'X:${v.x.toStringAsFixed(2)}, Y:${v.y.toStringAsFixed(2)}, Z:${v.z.toStringAsFixed(2)}';
}

class _VectorArrowPainter extends CustomPainter {
  final Vector3 vector;
  final Color color;

  _VectorArrowPainter({required this.vector, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = color
      ..strokeWidth = 4
      ..style = PaintingStyle.stroke;

    final center = Offset(size.width / 2, size.height / 2);
    final dx = vector.x * size.width / 2;
    final dy = -vector.y * size.height / 2; // invert y for screen coords
    final end = Offset(center.dx + dx, center.dy + dy);

    canvas.drawLine(center, end, paint);
    canvas.drawCircle(end, 6, paint);
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => true;
}
