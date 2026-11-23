import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

/// Run with `--dart-define=DEMO=true` to drive the UI with simulated peers
/// and ranging (useful in the iOS Simulator, which has no UWB).
const bool kDemoMode = bool.fromEnvironment('DEMO');

/// Demo only: jump straight to a screen ('search' or 'range') for review.
const String kDemoScene = String.fromEnvironment('DEMO_SCENE');

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.light);
  runApp(const UwbLocatorApp());
}

// ---------------------------------------------------------------------------
// Design tokens: dark neumorphism. One surface; depth comes from light.
// ---------------------------------------------------------------------------

abstract final class Palette {
  static const surface = Color(0xFF1E2230);
  static const shade = Color(0xFF141720); // shadow, bottom-right
  static const light = Color(0xFF2A2F40); // highlight, top-left
  static const far = Color(0xFF6A78FF); // glow when your friend is far
  static const near = Color(0xFF5FF0D2); // glow when they're close
  static const text = Color(0xFFE9ECF5);
  static const muted = Color(0xFF8A90A6);
  static const warn = Color(0xFFFF9C8A);
}

abstract final class Txt {
  static const _display = 'Avenir Next';

  static const distance = TextStyle(
    fontFamily: _display,
    fontWeight: FontWeight.w200,
    fontSize: 88,
    height: 1,
    letterSpacing: -2,
    color: Palette.text,
    fontFeatures: [FontFeature.tabularFigures()],
  );

  static const unit = TextStyle(
    fontFamily: _display,
    fontWeight: FontWeight.w300,
    fontSize: 30,
    height: 1,
    color: Palette.muted,
  );

  static const headline = TextStyle(
    fontFamily: _display,
    fontWeight: FontWeight.w500,
    fontSize: 24,
    height: 1.2,
    letterSpacing: -0.2,
    color: Palette.text,
  );

  static const name = TextStyle(
    fontSize: 17,
    fontWeight: FontWeight.w600,
    height: 1.25,
    color: Palette.text,
  );

  static const body = TextStyle(
    fontSize: 16,
    height: 1.4,
    color: Palette.text,
  );

  static const caption = TextStyle(
    fontSize: 15,
    height: 1.4,
    color: Palette.muted,
  );
}

abstract final class Space {
  static const xs = 6.0;
  static const s = 12.0;
  static const m = 20.0;
  static const l = 32.0;
  static const xl = 44.0;
}

// ---------------------------------------------------------------------------
// App
// ---------------------------------------------------------------------------

class UwbLocatorApp extends StatelessWidget {
  const UwbLocatorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Find My Friend',
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: Palette.surface,
        colorScheme: const ColorScheme.dark(
          primary: Palette.near,
          surface: Palette.surface,
          onSurface: Palette.text,
          error: Palette.warn,
        ),
      ),
      home: const SplashGate(),
    );
  }
}

/// Shows the splash once, then hands over to the locator.
class SplashGate extends StatefulWidget {
  const SplashGate({super.key});

  @override
  State<SplashGate> createState() => _SplashGateState();
}

class _SplashGateState extends State<SplashGate> {
  bool _done = false;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 500),
      switchInCurve: Curves.easeOutCubic,
      child: _done
          ? const LocatorPage(key: ValueKey('app'))
          : SplashScreen(
              key: const ValueKey('splash'),
              onFinished: () => setState(() => _done = true),
            ),
    );
  }
}


// ---------------------------------------------------------------------------
// Backend: native channels, or a simulated one for demo mode.
// ---------------------------------------------------------------------------

abstract class LocatorBackend {
  Stream<Map<dynamic, dynamic>> get events;
  Future<void> startDiscovery();
  Future<void> stopDiscovery();
  Future<void> connect(String peerId);
  Future<void> disconnect();
}

class ChannelBackend implements LocatorBackend {
  static const _methods = MethodChannel('uwb_locator/methods');
  static const _events = EventChannel('uwb_locator/events');

  @override
  Stream<Map<dynamic, dynamic>> get events => _events
      .receiveBroadcastStream()
      .where((e) => e is Map)
      .cast<Map<dynamic, dynamic>>();

  @override
  Future<void> startDiscovery() => _methods.invokeMethod('startDiscovery');

  @override
  Future<void> stopDiscovery() => _methods.invokeMethod('stopDiscovery');

  @override
  Future<void> connect(String peerId) =>
      _methods.invokeMethod('connect', {'peerId': peerId});

  @override
  Future<void> disconnect() => _methods.invokeMethod('disconnect');
}

class DemoBackend implements LocatorBackend {
  final _controller = StreamController<Map<dynamic, dynamic>>.broadcast();
  final List<Timer> _timers = [];
  Timer? _ranging;

  @override
  Stream<Map<dynamic, dynamic>> get events => _controller.stream;

  void _later(int ms, Map<String, dynamic> event) {
    _timers.add(Timer(Duration(milliseconds: ms), () => _controller.add(event)));
  }

  void _cancelAll() {
    for (final t in _timers) {
      t.cancel();
    }
    _timers.clear();
    _ranging?.cancel();
  }

  @override
  Future<void> startDiscovery() async {
    _later(1400, {'type': 'peerFound', 'peerId': 'iPhone-60AF9'});
    _later(2600, {'type': 'peerFound', 'peerId': 'iPhone-7DCEC'});
  }

  @override
  Future<void> stopDiscovery() async => _cancelAll();

  @override
  Future<void> connect(String peerId) async {
    _later(900, {'type': 'connected', 'peerId': peerId});
    var t = 0.0;
    _timers.add(Timer(const Duration(milliseconds: 1600), () {
      _ranging = Timer.periodic(const Duration(milliseconds: 250), (_) {
        t += 0.25;
        final distance = math.max(0.3, 7.5 - t * 0.35) +
            0.08 * math.sin(t * 3);
        final angle = 0.9 * math.sin(t * 0.6);
        _controller.add({
          'type': 'ranging',
          'distance': distance,
          if (t > 2) 'horizontalAngle': angle,
        });
      });
    }));
  }

  @override
  Future<void> disconnect() async {
    _cancelAll();
    _controller.add({'type': 'disconnected'});
  }
}

// ---------------------------------------------------------------------------
// State
// ---------------------------------------------------------------------------

enum Phase { idle, searching, connecting, ranging }

class LocatorPage extends StatefulWidget {
  const LocatorPage({super.key});

  @override
  State<LocatorPage> createState() => _LocatorPageState();
}

class _LocatorPageState extends State<LocatorPage> {
  final LocatorBackend _backend = kDemoMode ? DemoBackend() : ChannelBackend();
  StreamSubscription<Map<dynamic, dynamic>>? _subscription;

  final List<String> _peers = [];
  Phase _phase = Phase.idle;
  String? _peer;
  String? _connectingTo;

  /// One-line note from the native side (progress or a problem).
  String? _note;
  bool _noteIsProblem = false;

  double? _distance;
  double? _angle; // radians, 0 = straight ahead, positive = to the right
  double? _trend; // metres per second, negative = getting closer
  DateTime? _lastSample;
  bool _arrivedBuzzed = false;

  @override
  void initState() {
    super.initState();
    _subscription = _backend.events.listen(
      _handleEvent,
      onError: (Object error) => _setNote('Lost contact with the radio: $error',
          problem: true),
    );

    if (kDemoMode && kDemoScene.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        await _startSearching();
        if (kDemoScene == 'range') {
          await Future<void>.delayed(const Duration(milliseconds: 3000));
          if (_peers.isNotEmpty) _connect(_peers.first);
        }
      });
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  void _setNote(String? note, {bool problem = false}) {
    if (!mounted) return;
    setState(() {
      _note = note;
      _noteIsProblem = problem;
    });
  }

  void _resetRanging() {
    _distance = null;
    _angle = null;
    _trend = null;
    _lastSample = null;
    _arrivedBuzzed = false;
  }

  void _handleEvent(Map<dynamic, dynamic> event) {
    if (!mounted) return;
    final type = event['type']?.toString();

    setState(() {
      switch (type) {
        case 'status':
          _note = event['message']?.toString();
          _noteIsProblem = false;
        case 'error':
          _note = event['message']?.toString() ?? 'Something went wrong.';
          _noteIsProblem = true;
          _connectingTo = null;
          if (_phase == Phase.connecting) _phase = Phase.searching;
        case 'peerFound':
          final peer = event['peerId']?.toString();
          if (peer != null && !_peers.contains(peer)) _peers.add(peer);
        case 'peerLost':
          _peers.remove(event['peerId']?.toString());
        case 'connected':
          _peer = event['peerId']?.toString();
          _connectingTo = null;
          _phase = Phase.ranging;
          _note = null;
          _resetRanging();
          HapticFeedback.mediumImpact();
        case 'ranging':
          _applySample(event);
        case 'disconnected':
          final wasRanging = _phase == Phase.ranging;
          _phase = Phase.idle;
          _peer = null;
          _connectingTo = null;
          _peers.clear();
          _resetRanging();
          if (wasRanging) {
            _note = 'Disconnected.';
            _noteIsProblem = false;
          }
      }
    });
  }

  void _applySample(Map<dynamic, dynamic> event) {
    final d = event['distance'];
    final h = event['horizontalAngle'];
    final x = event['directionX'];

    final now = DateTime.now();
    if (d is num) {
      final next = d.toDouble();
      if (_distance != null && _lastSample != null) {
        final dt = now.difference(_lastSample!).inMilliseconds / 1000;
        if (dt > 0) {
          final rate = (next - _distance!) / dt;
          // Smooth heavily: we only want the drift, not the jitter.
          _trend = _trend == null ? rate : _trend! * 0.85 + rate * 0.15;
        }
      }
      _distance = next;
      _lastSample = now;

      if (next < 0.5 && !_arrivedBuzzed) {
        _arrivedBuzzed = true;
        HapticFeedback.heavyImpact();
      } else if (next > 0.8) {
        _arrivedBuzzed = false;
      }
    }

    if (h is num) {
      _angle = h.toDouble();
    } else if (x is num) {
      _angle = math.asin(x.toDouble().clamp(-1.0, 1.0));
    } else {
      _angle = null;
    }
  }

  Future<void> _startSearching() async {
    HapticFeedback.selectionClick();
    setState(() {
      _peers.clear();
      _phase = Phase.searching;
      _note = null;
    });
    try {
      await _backend.startDiscovery();
    } on PlatformException catch (e) {
      _setNote(e.message ?? 'Couldn\'t start looking for friends.',
          problem: true);
      if (mounted) setState(() => _phase = Phase.idle);
    }
  }

  Future<void> _stopSearching() async {
    setState(() {
      _phase = Phase.idle;
      _connectingTo = null;
      _note = null;
    });
    try {
      await _backend.stopDiscovery();
    } on PlatformException catch (_) {}
  }

  Future<void> _connect(String peer) async {
    HapticFeedback.selectionClick();
    setState(() {
      _phase = Phase.connecting;
      _connectingTo = peer;
      _note = null;
    });
    try {
      await _backend.connect(peer);
    } on PlatformException catch (e) {
      if (!mounted) return;
      setState(() {
        _phase = Phase.searching;
        _connectingTo = null;
        _note = e.message ?? 'Couldn\'t connect.';
        _noteIsProblem = true;
      });
    }
  }

  Future<void> _disconnect() async {
    try {
      await _backend.disconnect();
    } on PlatformException catch (_) {}
    if (!mounted) return;
    setState(() {
      _phase = Phase.idle;
      _peer = null;
      _peers.clear();
      _resetRanging();
    });
  }

  /// 0 when far (or unknown), 1 when you're on top of each other.
  double get _proximity {
    final d = _distance;
    if (_phase != Phase.ranging || d == null) return 0;
    return (1 - math.log(d + 1) / math.log(16)).clamp(0.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    final ranging = _phase == Phase.ranging;

    return Scaffold(
      body: SafeArea(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 400),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          child: ranging
              ? RangingView(
                  key: const ValueKey('ranging'),
                  peer: _peer ?? 'Your friend',
                  distance: _distance,
                  angle: _angle,
                  trend: _trend,
                  proximity: _proximity,
                  note: _note,
                  noteIsProblem: _noteIsProblem,
                  onDisconnect: _disconnect,
                )
              : DiscoveryView(
                  key: const ValueKey('discovery'),
                  phase: _phase,
                  peers: _peers,
                  connectingTo: _connectingTo,
                  note: _note,
                  noteIsProblem: _noteIsProblem,
                  onStart: _startSearching,
                  onStop: _stopSearching,
                  onConnect: _connect,
                ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Peer names arrive as `<device name>-<5 char id>`.
({String name, String? tag}) splitPeerName(String raw) {
  final i = raw.lastIndexOf('-');
  if (i > 0 && raw.length - i - 1 == 5) {
    return (name: raw.substring(0, i), tag: raw.substring(i + 1));
  }
  return (name: raw, tag: null);
}

bool reduceMotion(BuildContext context) =>
    MediaQuery.maybeDisableAnimationsOf(context) ?? false;

double dialSize(BuildContext context) {
  final size = MediaQuery.sizeOf(context);
  return math.min(math.min(size.width - 72, size.height * 0.36), 300);
}

// ---------------------------------------------------------------------------
// Neumorphic primitives
// ---------------------------------------------------------------------------

/// A shape moulded from the surface. [level] 1 = raised, 0 = flush,
/// -1 = pressed in. Changes animate, so buttons visibly sink and rise.
class NeuSurface extends StatelessWidget {
  const NeuSurface({
    super.key,
    required this.child,
    this.level = 1,
    this.radius = 20,
    this.circle = false,
    this.depth = 7,
    this.padding = EdgeInsets.zero,
  });

  final Widget child;
  final double level;
  final double radius;
  final bool circle;
  final double depth;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(end: level),
      duration: Duration(milliseconds: reduceMotion(context) ? 0 : 160),
      curve: Curves.easeOut,
      builder: (context, v, child) {
        final raised = v.clamp(0.0, 1.0);
        final inset = (-v).clamp(0.0, 1.0);
        final d = depth * raised;
        final shape = circle
            ? const CircleBorder()
            : RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius));

        return DecoratedBox(
          decoration: ShapeDecoration(
            shape: shape,
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color.lerp(Palette.surface, Palette.light, 0.35 * raised)!,
                Color.lerp(Palette.surface, Palette.shade, 0.25 * raised)!,
              ],
            ),
            shadows: [
              if (d > 0.1) ...[
                BoxShadow(
                  color: Palette.shade,
                  offset: Offset(d, d),
                  blurRadius: d * 2.2,
                ),
                BoxShadow(
                  color: Palette.light.withValues(alpha: 0.9),
                  offset: Offset(-d, -d),
                  blurRadius: d * 2.2,
                ),
              ],
            ],
          ),
          child: CustomPaint(
            foregroundPainter: inset > 0.01
                ? InsetPainter(
                    amount: inset,
                    radius: radius,
                    circle: circle,
                    depth: depth * 0.8,
                  )
                : null,
            child: Padding(padding: padding, child: child),
          ),
        );
      },
      child: child,
    );
  }
}

/// Inner shadows for recessed shapes: dark along the top-left inner edge,
/// light along the bottom-right, as if lit from the top-left.
class InsetPainter extends CustomPainter {
  InsetPainter({
    required this.amount,
    required this.radius,
    required this.depth,
    this.circle = false,
  });

  final double amount;
  final double radius;
  final double depth;
  final bool circle;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final rrect = circle
        ? RRect.fromRectAndRadius(rect, Radius.circular(size.shortestSide / 2))
        : RRect.fromRectAndRadius(rect, Radius.circular(radius));
    final d = depth * amount;

    canvas.save();
    canvas.clipRRect(rrect);
    Path ring(Offset shift) => (Path()
          ..fillType = PathFillType.evenOdd
          ..addRect(rect.inflate(depth * 4))
          ..addRRect(rrect.shift(shift)));

    canvas.drawPath(
      ring(Offset(d, d)),
      Paint()
        ..color = Palette.shade
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, d * 1.2),
    );
    canvas.drawPath(
      ring(Offset(-d, -d)),
      Paint()
        ..color = Palette.light.withValues(alpha: 0.8)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, d * 1.2),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(InsetPainter old) =>
      old.amount != amount || old.radius != radius || old.depth != depth;
}

/// A raised control that sinks while held, and stays sunk when [active].
class NeuButton extends StatefulWidget {
  const NeuButton({
    super.key,
    required this.child,
    required this.onPressed,
    required this.semanticLabel,
    this.active = false,
    this.radius = 28,
    this.circle = false,
    this.width,
    this.height = 56,
  });

  final Widget child;
  final VoidCallback onPressed;
  final String semanticLabel;
  final bool active;
  final double radius;
  final bool circle;
  final double? width;
  final double height;

  @override
  State<NeuButton> createState() => _NeuButtonState();
}

class _NeuButtonState extends State<NeuButton> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final pressed = _down || widget.active;
    return Semantics(
      button: true,
      label: widget.semanticLabel,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => setState(() => _down = true),
        onTapCancel: () => setState(() => _down = false),
        onTapUp: (_) => setState(() => _down = false),
        onTap: () {
          HapticFeedback.lightImpact();
          widget.onPressed();
        },
        child: SizedBox(
          width: widget.circle ? widget.height : widget.width,
          height: widget.height,
          child: NeuSurface(
            level: pressed ? -1 : 1,
            radius: widget.radius,
            circle: widget.circle,
            depth: 6,
            child: Center(child: widget.child),
          ),
        ),
      ),
    );
  }
}

class NoteLine extends StatelessWidget {
  const NoteLine({super.key, required this.text, required this.problem});

  final String? text;
  final bool problem;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 250),
      child: text == null
          ? const SizedBox(key: ValueKey('none'), width: double.infinity)
          : Padding(
              key: ValueKey(text),
              padding: const EdgeInsets.only(top: Space.s),
              child: Text(
                text!,
                textAlign: TextAlign.center,
                style: Txt.caption.copyWith(
                  color: problem ? Palette.warn : Palette.muted,
                ),
              ),
            ),
    );
  }
}

// ---------------------------------------------------------------------------
// The dial: a raised disc with a recessed well. Inside the well, a soft
// glow (the only colour in the app) grows and shifts to aqua as you close in,
// and the arrow points to your friend.
// ---------------------------------------------------------------------------

enum PointerMode { idle, searching, unknown, arrow, arrived }

class Dial extends StatefulWidget {
  const Dial({
    super.key,
    required this.size,
    required this.mode,
    this.angle,
    this.intensity = 0.3,
    this.warmth = 0,
    this.pointerOpacity = 1,
    this.arrowTurns,
  });

  final double size;
  final PointerMode mode;
  final double? angle;
  final double intensity;
  final double warmth;
  final double pointerOpacity;

  /// Splash only: drive the arrow's rotation directly.
  final double? arrowTurns;

  @override
  State<Dial> createState() => _DialState();
}

class _DialState extends State<Dial> with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  final ValueNotifier<double> _phase = ValueNotifier(0);
  Duration _last = Duration.zero;
  double _turns = 0;

  bool get _breathing =>
      widget.mode == PointerMode.searching ||
      widget.mode == PointerMode.arrow ||
      widget.mode == PointerMode.unknown ||
      widget.mode == PointerMode.arrived;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((elapsed) {
      final dt = (elapsed - _last).inMicroseconds / 1e6;
      _last = elapsed;
      if (!_breathing) return;
      final hz = 0.35 + 0.65 * widget.warmth; // faster as you close in
      _phase.value = (_phase.value + dt * hz) % 1.0;
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (reduceMotion(context)) {
      _ticker.stop();
    } else if (!_ticker.isActive) {
      _last = Duration.zero;
      _ticker.start();
    }
  }

  @override
  void didUpdateWidget(Dial old) {
    super.didUpdateWidget(old);
    final a = widget.angle;
    if (a == null) return;
    final target = a / (2 * math.pi);
    var delta = (target - _turns) % 1.0;
    if (delta > 0.5) delta -= 1.0;
    _turns += delta;
  }

  @override
  void dispose() {
    _ticker.dispose();
    _phase.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.size;
    final well = s * 0.8;
    final motion = !reduceMotion(context);

    return SizedBox.square(
      dimension: s,
      child: NeuSurface(
        circle: true,
        depth: 14,
        child: Center(
          child: SizedBox.square(
            dimension: well,
            child: NeuSurface(
              circle: true,
              level: -1,
              depth: 12,
              child: TweenAnimationBuilder<Offset>(
                tween: Tween(end: Offset(widget.intensity, widget.warmth)),
                duration: Duration(milliseconds: motion ? 700 : 0),
                curve: Curves.easeOutCubic,
                builder: (context, v, child) => CustomPaint(
                  painter: _GlowPainter(
                    phase: _phase,
                    intensity: v.dx,
                    warmth: v.dy,
                    ripple: _breathing,
                  ),
                  child: child,
                ),
                child: Opacity(
                  opacity: widget.pointerOpacity,
                  child: Center(child: _pointer(well, motion)),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _pointer(double well, bool motion) {
    final arrowSize = well * 0.5;
    final Widget child = switch (widget.mode) {
      PointerMode.arrived => Container(
          key: const ValueKey('here'),
          width: well * 0.16,
          height: well * 0.16,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Palette.text,
            boxShadow: [
              BoxShadow(
                color: Palette.near.withValues(alpha: 0.7),
                blurRadius: 30,
                spreadRadius: 4,
              ),
            ],
          ),
        ),
      PointerMode.unknown || PointerMode.searching => Container(
          key: const ValueKey('ring'),
          width: well * 0.09,
          height: well * 0.09,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
                color: Palette.text.withValues(alpha: 0.75), width: 1.5),
          ),
        ),
      PointerMode.idle => CustomPaint(
          key: const ValueKey('idle'),
          size: Size.square(arrowSize),
          painter: _ArrowPainter(color: Palette.muted.withValues(alpha: 0.5)),
        ),
      PointerMode.arrow => widget.arrowTurns != null
          ? RotationTransition(
              key: const ValueKey('splash-arrow'),
              turns: AlwaysStoppedAnimation(widget.arrowTurns!),
              child: CustomPaint(
                size: Size.square(arrowSize),
                painter: _ArrowPainter(color: Palette.text),
              ),
            )
          : AnimatedRotation(
              key: const ValueKey('arrow'),
              turns: _turns,
              duration: Duration(milliseconds: motion ? 350 : 0),
              curve: Curves.easeOutCubic,
              child: CustomPaint(
                size: Size.square(arrowSize),
                painter: _ArrowPainter(color: Palette.text),
              ),
            ),
    };

    return AnimatedSwitcher(
      duration: Duration(milliseconds: motion ? 280 : 0),
      transitionBuilder: (c, a) => FadeTransition(
        opacity: a,
        child: ScaleTransition(scale: a, child: c),
      ),
      child: child,
    );
  }
}

class _GlowPainter extends CustomPainter {
  _GlowPainter({
    required this.phase,
    required this.intensity,
    required this.warmth,
    required this.ripple,
  }) : super(repaint: phase);

  final ValueNotifier<double> phase;
  final double intensity;
  final double warmth;
  final bool ripple;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final r = size.shortestSide / 2;
    final color = Color.lerp(Palette.far, Palette.near, warmth)!;
    final t = phase.value;
    final breathe = 1 + (ripple ? 0.05 * math.sin(t * 2 * math.pi) : 0);
    final glowR = r * (0.45 + 0.55 * intensity) * breathe;

    canvas.save();
    canvas.clipPath(Path()..addOval(Rect.fromCircle(center: center, radius: r)));
    canvas.drawCircle(
      center,
      glowR,
      Paint()
        ..shader = RadialGradient(
          colors: [
            color.withValues(alpha: 0.5 * intensity),
            color.withValues(alpha: 0.14 * intensity),
            color.withValues(alpha: 0),
          ],
          stops: const [0, 0.5, 1],
        ).createShader(Rect.fromCircle(center: center, radius: glowR)),
    );
    if (ripple) {
      canvas.drawCircle(
        center,
        r * (0.15 + 0.85 * t),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = color.withValues(alpha: 0.4 * (1 - t) * math.max(intensity, 0.4)),
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_GlowPainter old) =>
      old.intensity != intensity ||
      old.warmth != warmth ||
      old.ripple != ripple;
}

/// A clean location-style arrow with a notched tail.
class _ArrowPainter extends CustomPainter {
  _ArrowPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    final c = Offset(s / 2, s / 2);
    final path = Path()
      ..moveTo(c.dx, c.dy - s * 0.42)
      ..lineTo(c.dx + s * 0.27, c.dy + s * 0.34)
      ..lineTo(c.dx, c.dy + s * 0.19)
      ..lineTo(c.dx - s * 0.27, c.dy + s * 0.34)
      ..close();

    canvas.drawPath(
      path.shift(const Offset(3, 4)),
      Paint()
        ..color = Palette.shade.withValues(alpha: 0.8 * color.a)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_ArrowPainter old) => old.color != color;
}

// ---------------------------------------------------------------------------
// Splash: the dial rises out of the surface, the arrow swings to north,
// then the name appears.
// ---------------------------------------------------------------------------

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key, required this.onFinished});

  final VoidCallback onFinished;

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1500),
  );
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (reduceMotion(context)) {
      _c.value = 1;
      Timer(const Duration(milliseconds: 600), widget.onFinished);
    } else {
      _c.forward().then((_) {
        Timer(const Duration(milliseconds: 350), () {
          if (mounted) widget.onFinished();
        });
      });
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  double _seg(double from, double to, [Curve curve = Curves.easeOutCubic]) =>
      curve.transform(((_c.value - from) / (to - from)).clamp(0.0, 1.0));

  @override
  Widget build(BuildContext context) {
    final s = dialSize(context);

    return Scaffold(
      body: AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          final rise = _seg(0, 0.45);
          final swing = _seg(0.3, 0.8, Curves.easeOutBack);
          final words = _seg(0.6, 1);

          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Opacity(
                  opacity: rise,
                  child: Transform.scale(
                    scale: 0.9 + 0.1 * rise,
                    child: Dial(
                      size: s * 0.72,
                      mode: PointerMode.arrow,
                      intensity: 0.35 * swing,
                      pointerOpacity: swing.clamp(0.0, 1.0),
                      arrowTurns: -0.3 * (1 - swing),
                    ),
                  ),
                ),
                const SizedBox(height: Space.xl),
                Opacity(
                  opacity: words,
                  child: Transform.translate(
                    offset: Offset(0, 8 * (1 - words)),
                    child: const Column(
                      children: [
                        Text('Find My Friend', style: Txt.headline),
                        SizedBox(height: Space.xs),
                        Text('Close range, to the metre',
                            style: Txt.caption),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Discovery
// ---------------------------------------------------------------------------

class DiscoveryView extends StatelessWidget {
  const DiscoveryView({
    super.key,
    required this.phase,
    required this.peers,
    required this.connectingTo,
    required this.note,
    required this.noteIsProblem,
    required this.onStart,
    required this.onStop,
    required this.onConnect,
  });

  final Phase phase;
  final List<String> peers;
  final String? connectingTo;
  final String? note;
  final bool noteIsProblem;
  final VoidCallback onStart;
  final VoidCallback onStop;
  final ValueChanged<String> onConnect;

  bool get _looking => phase == Phase.searching || phase == Phase.connecting;

  @override
  Widget build(BuildContext context) {
    final String headline;
    final String caption;
    if (!_looking) {
      headline = 'Find a friend nearby';
      caption = 'See how far apart you are, and which way to go.';
    } else if (peers.isEmpty) {
      headline = 'Looking…';
      caption = 'Ask your friend to open the app and tap Start looking.';
    } else {
      headline = peers.length == 1 ? 'Found 1 phone' : 'Found ${peers.length} phones';
      caption = 'Tap the one you want to find.';
    }

    final hasList = _looking && peers.isNotEmpty;

    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.m + 4, Space.s, Space.m + 4, Space.m),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Find My Friend', style: Txt.name.copyWith(color: Palette.muted)),
          const Spacer(flex: 3),
          Center(
            child: AnimatedScale(
              scale: hasList ? 0.78 : 1,
              duration: const Duration(milliseconds: 350),
              curve: Curves.easeOutCubic,
              child: Dial(
                size: dialSize(context),
                mode: _looking ? PointerMode.searching : PointerMode.idle,
                intensity: _looking ? 0.45 : 0.15,
              ),
            ),
          ),
          const SizedBox(height: Space.l),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            child: Column(
              key: ValueKey(headline),
              children: [
                Text(headline, textAlign: TextAlign.center, style: Txt.headline),
                const SizedBox(height: Space.xs),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 300),
                  child: Text(caption,
                      textAlign: TextAlign.center, style: Txt.caption),
                ),
              ],
            ),
          ),
          NoteLine(text: note, problem: noteIsProblem),
          const Spacer(flex: 2),
          AnimatedSize(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOutCubic,
            alignment: Alignment.bottomCenter,
            child: hasList
                ? Padding(
                    padding: const EdgeInsets.only(bottom: Space.l - 4),
                    child: _PeerList(
                      peers: peers,
                      connectingTo: connectingTo,
                      onConnect: onConnect,
                    ),
                  )
                : const SizedBox(width: double.infinity),
          ),
          NeuButton(
            semanticLabel: _looking ? 'Stop looking' : 'Start looking',
            active: _looking,
            onPressed: _looking ? onStop : onStart,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: Text(
                _looking ? 'Stop looking' : 'Start looking',
                key: ValueKey(_looking),
                style: Txt.name.copyWith(
                  color: _looking ? Palette.muted : Palette.near,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PeerList extends StatelessWidget {
  const _PeerList({
    required this.peers,
    required this.connectingTo,
    required this.onConnect,
  });

  final List<String> peers;
  final String? connectingTo;
  final ValueChanged<String> onConnect;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 220),
      child: NeuSurface(
        radius: 22,
        depth: 6,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(22),
          child: ListView.separated(
            shrinkWrap: true,
            padding: const EdgeInsets.symmetric(vertical: 4),
            itemCount: peers.length,
            separatorBuilder: (_, _) => const Divider(
              height: 1,
              thickness: 1,
              indent: 70,
              endIndent: 16,
              color: Palette.shade,
            ),
            itemBuilder: (context, i) => _PeerRow(
              peer: peers[i],
              connecting: connectingTo == peers[i],
              disabled: connectingTo != null && connectingTo != peers[i],
              onTap: () => onConnect(peers[i]),
            ),
          ),
        ),
      ),
    );
  }
}

class _PeerRow extends StatelessWidget {
  const _PeerRow({
    required this.peer,
    required this.connecting,
    required this.disabled,
    required this.onTap,
  });

  final String peer;
  final bool connecting;
  final bool disabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final parts = splitPeerName(peer);

    return AnimatedOpacity(
      duration: const Duration(milliseconds: 200),
      opacity: disabled ? 0.4 : 1,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: (connecting || disabled) ? null : onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                const SizedBox.square(
                  dimension: 40,
                  child: NeuSurface(
                    circle: true,
                    level: -1,
                    depth: 4,
                    child: Icon(Icons.phone_iphone_rounded,
                        size: 19, color: Palette.muted),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(parts.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Txt.name),
                      if (parts.tag != null)
                        Text(parts.tag!,
                            style: Txt.caption.copyWith(fontSize: 13)),
                    ],
                  ),
                ),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  child: connecting
                      ? const SizedBox(
                          key: ValueKey('busy'),
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 1.8,
                            color: Palette.near,
                          ),
                        )
                      : Text(
                          'Connect',
                          key: const ValueKey('go'),
                          style: Txt.body.copyWith(
                            color: Palette.near,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Ranging
// ---------------------------------------------------------------------------

class RangingView extends StatelessWidget {
  const RangingView({
    super.key,
    required this.peer,
    required this.distance,
    required this.angle,
    required this.trend,
    required this.proximity,
    required this.note,
    required this.noteIsProblem,
    required this.onDisconnect,
  });

  final String peer;
  final double? distance;
  final double? angle;
  final double? trend;
  final double proximity;
  final String? note;
  final bool noteIsProblem;
  final VoidCallback onDisconnect;

  bool get _arrived => distance != null && distance! < 0.5;

  String get _status {
    final d = distance;
    if (d == null) return 'Measuring…';
    if (_arrived) return 'Right here';
    final t = trend;
    if (t != null && t < -0.12) return 'Getting closer';
    if (t != null && t > 0.12) return 'Moving apart';
    if (d < 1.5) return 'Within arm\'s reach';
    if (d < 5) return 'Very close';
    return 'Nearby';
  }

  PointerMode get _mode {
    if (_arrived) return PointerMode.arrived;
    if (angle == null) return PointerMode.unknown;
    return PointerMode.arrow;
  }

  @override
  Widget build(BuildContext context) {
    final name = splitPeerName(peer).name;

    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.m + 4, Space.s, Space.m + 4, Space.m),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Txt.name),
                    const Text('Connected', style: Txt.caption),
                  ],
                ),
              ),
              NeuButton(
                semanticLabel: 'Disconnect',
                circle: true,
                height: 46,
                onPressed: onDisconnect,
                child: const Icon(Icons.close_rounded,
                    size: 20, color: Palette.muted),
              ),
            ],
          ),
          const Spacer(flex: 2),
          Center(
            child: Dial(
              size: dialSize(context),
              mode: _mode,
              angle: angle,
              intensity: distance == null ? 0.35 : 0.4 + 0.6 * proximity,
              warmth: proximity,
            ),
          ),
          const SizedBox(height: Space.l),
          _DistanceReadout(distance: distance),
          const SizedBox(height: Space.xs),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 250),
            child: Text(
              _status,
              key: ValueKey(_status),
              textAlign: TextAlign.center,
              style: Txt.body.copyWith(
                color: _arrived ? Palette.near : Palette.muted,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          if (_mode == PointerMode.unknown && distance != null)
            const Padding(
              padding: EdgeInsets.only(top: Space.xs),
              child: Text(
                'Direction isn\'t available on this phone yet.',
                textAlign: TextAlign.center,
                style: Txt.caption,
              ),
            ),
          NoteLine(text: note, problem: noteIsProblem),
          const Spacer(flex: 3),
        ],
      ),
    );
  }
}

class _DistanceReadout extends StatelessWidget {
  const _DistanceReadout({required this.distance});

  final double? distance;

  @override
  Widget build(BuildContext context) {
    final d = distance;
    if (d == null) {
      return Text('–',
          textAlign: TextAlign.center,
          style: Txt.distance.copyWith(color: Palette.light));
    }

    return TweenAnimationBuilder<double>(
      tween: Tween(end: d),
      duration: reduceMotion(context)
          ? Duration.zero
          : const Duration(milliseconds: 300),
      curve: Curves.easeOut,
      builder: (context, value, _) {
        final text =
            value >= 10 ? value.toStringAsFixed(0) : value.toStringAsFixed(1);
        return Semantics(
          label: '$text metres',
          excludeSemantics: true,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(text, style: Txt.distance),
              const SizedBox(width: 4),
              const Text('m', style: Txt.unit),
            ],
          ),
        );
      },
    );
  }
}
