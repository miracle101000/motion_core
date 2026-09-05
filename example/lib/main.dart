import 'dart:async';
import 'dart:math' show pi;

import 'package:cubixd/cubixd.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:motion_core/motion_core.dart';
import 'package:vector_math/vector_math_64.dart' show Vector2, Vector3;

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
  static const _rates = [15, 30, 60, 100];

  MotionData? _motionData;
  StreamSubscription<MotionData>? _subscription;

  /// `null` while availability is still being checked.
  bool? _isAvailable;
  List<AttitudeReferenceFrame> _availableFrames = const [];
  AttitudeReferenceFrame _frame = AttitudeReferenceFrame.magneticNorthZVertical;
  int _rateHz = 60;
  String? _error;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final available = await MotionCore.isAvailable();
    final frames = await MotionCore.availableReferenceFrames();
    if (!mounted) return;
    setState(() {
      _isAvailable = available;
      _availableFrames = frames;
    });
    if (available) {
      await _applyConfiguration();
      _startListening();
    }
  }

  Future<void> _applyConfiguration() {
    return MotionCore.configure(
      referenceFrame: _frame,
      updateInterval: Duration(microseconds: 1000000 ~/ _rateHz),
    );
  }

  void _startListening() {
    _subscription = MotionCore.motionStream.listen(
      (data) {
        if (!mounted) return;
        setState(() {
          _motionData = data;
          _error = null;
        });
      },
      onError: (Object error) {
        if (!mounted) return;
        setState(() {
          _error = error is PlatformException
              ? '${error.code}: ${error.message}'
              : '$error';
        });
      },
    );
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Motion Visualizer')),
      backgroundColor: Colors.black,
      body: switch (_isAvailable) {
        null => const Center(child: CircularProgressIndicator()),
        false => const Center(child: Text('Motion sensors not available')),
        true => _buildContent(),
      },
    );
  }

  Widget _buildContent() {
    final data = _motionData;
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 16),
      children: [
        _buildControls(),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(_error!, style: const TextStyle(color: Colors.redAccent)),
          ),
        if (data == null)
          const Padding(
            padding: EdgeInsets.all(48),
            child: Center(child: CircularProgressIndicator()),
          )
        else ...[
          const SizedBox(height: 16),
          SizedBox(height: 220, child: _buildCube(data)),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(child: _buildGravityCompass(data)),
              Expanded(child: _buildHeadingCompass(data)),
              Expanded(child: _buildAccelerationIndicator(data)),
            ],
          ),
          const SizedBox(height: 16),
          _buildDataTable(data),
        ],
      ],
    );
  }

  Widget _buildControls() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Expanded(
            child: DropdownButton<AttitudeReferenceFrame>(
              isExpanded: true,
              value: _frame,
              items: [
                for (final frame in AttitudeReferenceFrame.values)
                  DropdownMenuItem(
                    value: frame,
                    child: Text(
                      _availableFrames.contains(frame)
                          ? frame.name
                          : '${frame.name} (fallback)',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: (frame) async {
                if (frame == null) return;
                setState(() => _frame = frame);
                await _applyConfiguration();
              },
            ),
          ),
          const SizedBox(width: 16),
          DropdownButton<int>(
            value: _rateHz,
            items: [
              for (final hz in _rates)
                DropdownMenuItem(value: hz, child: Text('$hz Hz')),
            ],
            onChanged: (hz) async {
              if (hz == null) return;
              setState(() => _rateHz = hz);
              await _applyConfiguration();
            },
          ),
        ],
      ),
    );
  }

  Widget _buildCube(MotionData data) {
    final Vector3 euler = data.eulerAngles;
    return Center(
      child: CubixD(
        size: 180,
        delta: Vector2(-euler.x, -euler.y),
        onSelected: (_, __) {},
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
        child: Container(color: color.withValues(alpha: .7)),
      );

  Widget _buildGravityCompass(MotionData data) {
    final Vector3 g = data.gravity.normalized();
    return SizedBox(
      height: 100,
      child: CustomPaint(
        painter: _VectorArrowPainter(vector: g, color: Colors.purple),
        child: const Center(child: Text('Gravity')),
      ),
    );
  }

  Widget _buildHeadingCompass(MotionData data) {
    final heading = data.heading;
    return SizedBox(
      height: 100,
      child: heading == null
          ? const Center(child: Text('No heading'))
          : Transform.rotate(
              // Rotate the needle so it keeps pointing north on screen.
              angle: -heading * pi / 180,
              child: const Icon(Icons.navigation, size: 64, color: Colors.redAccent),
            ),
    );
  }

  Widget _buildAccelerationIndicator(MotionData data) {
    // userAcceleration is in m/s²; treat 1 g as "full" intensity.
    final double intensity = (data.userAcceleration.length / 9.81).clamp(0.0, 1.0);
    return Center(
      child: Container(
        width: 50 + intensity * 50,
        height: 50 + intensity * 50,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.teal.withValues(alpha: 0.4 + 0.6 * intensity),
        ),
        child: const Center(child: Text('ACC')),
      ),
    );
  }

  Widget _buildDataTable(MotionData d) {
    String deg(double r) => '${(r * 180 / pi).toStringAsFixed(1)}°';
    String optional(double? v, String Function(double) format) =>
        v == null ? 'N/A' : format(v);
    final magnetic = d.magneticField;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Table(
        columnWidths: const {0: IntrinsicColumnWidth()},
        children: [
          _row('Frame', d.referenceFrame.name),
          _row('Pitch', deg(d.pitch)),
          _row('Roll', deg(d.roll)),
          _row('Yaw', deg(d.yaw)),
          _row('Heading', optional(d.heading, (h) => '${h.toStringAsFixed(1)}°')),
          _row('Heading acc.', optional(d.headingAccuracy, deg)),
          _row('Gravity (m/s²)', _vec(d.gravity)),
          _row('User acc. (m/s²)', _vec(d.userAcceleration)),
          _row('Rotation (rad/s)',
              d.rotationRate == null ? 'N/A' : _vec(d.rotationRate!)),
          _row(
            'Magnetic (µT)',
            magnetic == null
                ? 'N/A'
                : '${_vec(magnetic.field)} (${magnetic.accuracy.name})',
          ),
          _row('Timestamp', '${d.timestamp.toStringAsFixed(3)} s'),
        ],
      ),
    );
  }

  TableRow _row(String label, String value) => TableRow(children: [
        Padding(
          padding: const EdgeInsets.all(6),
          child: Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
        ),
        Padding(padding: const EdgeInsets.all(6), child: Text(value)),
      ]);

  String _vec(Vector3 v) =>
      'X:${v.x.toStringAsFixed(2)}, Y:${v.y.toStringAsFixed(2)}, Z:${v.z.toStringAsFixed(2)}';
}

class _VectorArrowPainter extends CustomPainter {
  _VectorArrowPainter({required this.vector, required this.color});

  final Vector3 vector;
  final Color color;

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
  bool shouldRepaint(covariant _VectorArrowPainter oldDelegate) =>
      oldDelegate.vector != vector || oldDelegate.color != color;
}
