import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/widgets/custom_button.dart';

// ─── Mock driver data ──────────────────────────────────────────────────────
const _mockDrivers = [
  {
    'name': 'Kasun Perera',
    'rating': 4.9,
    'brand': 'Toyota',
    'model': 'Axio',
    'plate': 'WP-CAB-2341',
    'phone': '+94 77 123 4567',
  },
  {
    'name': 'Nuwan Silva',
    'rating': 4.8,
    'brand': 'Bajaj',
    'model': 'RE Three-Wheeler',
    'plate': 'NB-TUK-8812',
    'phone': '+94 71 987 6543',
  },
  {
    'name': 'Thilina Rathnayake',
    'rating': 4.7,
    'brand': 'Suzuki',
    'model': 'Alto',
    'plate': 'CP-CAR-5529',
    'phone': '+94 76 543 2109',
  },
];

// ─── Booking states ────────────────────────────────────────────────────────
enum _BookingState { searching, found }

class BookingStatusPage extends StatefulWidget {
  const BookingStatusPage({super.key});

  @override
  State<BookingStatusPage> createState() => _BookingStatusPageState();
}

class _BookingStatusPageState extends State<BookingStatusPage>
    with TickerProviderStateMixin {
  _BookingState _state = _BookingState.searching;
  Map<String, dynamic>? _driver;
  Timer? _searchTimer;

  // Radar animation
  late AnimationController _radarController;

  // Found card animation
  late AnimationController _foundController;
  late Animation<double> _foundSlide;
  late Animation<double> _foundFade;

  // Route args
  late Map<String, dynamic> _args;
  bool _argsLoaded = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_argsLoaded) {
      _args = (ModalRoute.of(context)?.settings.arguments
              as Map<String, dynamic>?) ??
          {};
      _argsLoaded = true;
      _startSearch();
    }
  }

  @override
  void initState() {
    super.initState();

    _radarController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat();

    _foundController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _foundSlide = Tween<double>(begin: 60, end: 0).animate(
      CurvedAnimation(parent: _foundController, curve: Curves.easeOutCubic),
    );
    _foundFade = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _foundController, curve: Curves.easeOut),
    );
  }

  @override
  void dispose() {
    _searchTimer?.cancel();
    _radarController.dispose();
    _foundController.dispose();
    super.dispose();
  }

  void _startSearch() {
    _searchTimer = Timer(const Duration(seconds: 5), () {
      if (!mounted) return;
      final driver =
          _mockDrivers[Random().nextInt(_mockDrivers.length)];
      setState(() {
        _state = _BookingState.found;
        _driver = Map<String, dynamic>.from(driver);
      });
      _radarController.stop();
      _foundController.forward();
    });
  }

  void _cancelRide() {
    _searchTimer?.cancel();
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // ── Header
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: _cancelRide,
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppColors.cardLight,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.close_rounded,
                          color: AppColors.textDark, size: 20),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Text(
                    _state == _BookingState.searching
                        ? 'Finding Your Ride'
                        : 'Driver Found!',
                    style:
                        Theme.of(context).textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                  ),
                ],
              ),
            ),

            Expanded(
              child: _state == _BookingState.searching
                  ? _buildSearchingView()
                  : _buildFoundView(),
            ),

            // ── Cancel button
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
              child: _state == _BookingState.searching
                  ? OutlinedButton(
                      onPressed: _cancelRide,
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(
                            color: AppColors.borderGrey, width: 1.5),
                        minimumSize: const Size(double.infinity, 56),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16)),
                      ),
                      child: const Text(
                        'Cancel Ride',
                        style: TextStyle(
                            color: AppColors.textDark,
                            fontWeight: FontWeight.w700),
                      ),
                    )
                  : CustomButton(
                      text: 'Track My Ride  📍',
                      onPressed: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                              content: Text(
                                  'Live tracking coming soon!')),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Searching UI ─────────────────────────────────────────────────────────
  Widget _buildSearchingView() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // Radar
        AnimatedBuilder(
          animation: _radarController,
          builder: (context, child) {
            return CustomPaint(
              size: const Size(240, 240),
              painter: _RadarPainter(_radarController.value),
            );
          },
        ),
        const SizedBox(height: 36),

        const Text(
          'Searching for nearby drivers...',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: AppColors.textDark,
          ),
        ),
        const SizedBox(height: 10),
        const Text(
          'Please wait a moment',
          style: TextStyle(color: AppColors.textGrey, fontSize: 14),
        ),
        const SizedBox(height: 28),

        // Destination chip
        if (_args['destination'] != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.inputFocusedBg,
              borderRadius: BorderRadius.circular(30),
              border: Border.all(
                  color: AppColors.primaryYellow.withValues(alpha: 0.4)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.location_on_outlined,
                    color: AppColors.primaryYellowDark, size: 16),
                const SizedBox(width: 6),
                Text(
                  _args['destination'] as String,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    color: AppColors.textDark,
                  ),
                ),
              ],
            ),
          ),

        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(
            3,
            (i) => _PulsingDot(delay: Duration(milliseconds: i * 200)),
          ),
        ),
      ],
    );
  }

  // ── Driver Found UI ──────────────────────────────────────────────────────
  Widget _buildFoundView() {
    final driver = _driver!;

    return AnimatedBuilder(
      animation: _foundController,
      builder: (context, child) => Transform.translate(
        offset: Offset(0, _foundSlide.value),
        child: Opacity(opacity: _foundFade.value, child: child),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          children: [
            // Success badge
            Container(
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                color: AppColors.primaryYellow.withValues(alpha: 0.12),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primaryYellow.withValues(alpha: 0.3),
                    blurRadius: 30,
                    spreadRadius: 4,
                  ),
                ],
              ),
              child: const Icon(Icons.check_circle_rounded,
                  color: AppColors.primaryYellow, size: 60),
            ),
            const SizedBox(height: 16),

            const Text(
              'Your driver is on the way!',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: AppColors.textDark,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              'ETA: ~3 minutes',
              style: TextStyle(
                  color: AppColors.textGrey.withValues(alpha: 0.8),
                  fontSize: 13),
            ),
            const SizedBox(height: 28),

            // Driver card
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppColors.cardLight,
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.06),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Column(
                children: [
                  // Avatar + name + rating
                  Row(
                    children: [
                      Container(
                        width: 56,
                        height: 56,
                        decoration: const BoxDecoration(
                          color: AppColors.cardDark,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.person_rounded,
                            color: AppColors.primaryYellow, size: 30),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              driver['name'] as String,
                              style: const TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w800,
                                color: AppColors.textDark,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                const Icon(Icons.star_rounded,
                                    color: AppColors.primaryYellow,
                                    size: 16),
                                const SizedBox(width: 3),
                                Text(
                                  '${driver['rating']}  •  Professional Driver',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: AppColors.textGrey,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  const Divider(color: AppColors.borderGrey),
                  const SizedBox(height: 16),

                  // Vehicle details
                  _buildDriverDetailRow(
                    Icons.directions_car_outlined,
                    'Vehicle',
                    '${driver['brand']} ${driver['model']}',
                  ),
                  const SizedBox(height: 12),
                  _buildDriverDetailRow(
                    Icons.confirmation_number_outlined,
                    'Plate Number',
                    driver['plate'] as String,
                    highlight: true,
                  ),
                  const SizedBox(height: 12),
                  _buildDriverDetailRow(
                    Icons.receipt_long_outlined,
                    'Destination',
                    (_args['destination'] as String?) ?? '—',
                  ),
                  const SizedBox(height: 20),

                  // Call Driver button
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                                'Calling ${driver['name']} at ${driver['phone']}'),
                          ),
                        );
                      },
                      icon: const Icon(Icons.call_rounded,
                          color: AppColors.primaryYellow, size: 20),
                      label: const Text(
                        'Call Driver',
                        style: TextStyle(
                          color: AppColors.primaryYellow,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(
                            color: AppColors.primaryYellow, width: 1.5),
                        minimumSize: const Size(double.infinity, 50),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildDriverDetailRow(IconData icon, String label, String value,
      {bool highlight = false}) {
    return Row(
      children: [
        Icon(icon, color: AppColors.textGrey, size: 18),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: const TextStyle(
                    color: AppColors.textGrey,
                    fontSize: 11,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 2),
            Text(
              value,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: highlight
                    ? AppColors.primaryYellowDark
                    : AppColors.textDark,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// ─── Radar painter ─────────────────────────────────────────────────────────
class _RadarPainter extends CustomPainter {
  final double progress;
  _RadarPainter(this.progress);

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final maxRadius = size.width / 2;

    // Static rings
    for (int i = 1; i <= 3; i++) {
      final ringPaint = Paint()
        ..color =
            AppColors.primaryYellow.withValues(alpha: 0.08 + 0.04 * i)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5;
      canvas.drawCircle(center, maxRadius * (i / 3), ringPaint);
    }

    // Sweeping arc
    final sweepPaint = Paint()
      ..shader = SweepGradient(
        startAngle: -pi / 2,
        endAngle: -pi / 2 + 2 * pi * progress,
        colors: [
          AppColors.primaryYellow.withValues(alpha: 0),
          AppColors.primaryYellow.withValues(alpha: 0.35),
        ],
      ).createShader(Rect.fromCircle(center: center, radius: maxRadius))
      ..style = PaintingStyle.fill;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: maxRadius),
      -pi / 2,
      2 * pi * progress,
      true,
      sweepPaint,
    );

    // Sweeping line
    final lineAngle = -pi / 2 + 2 * pi * progress;
    final linePaint = Paint()
      ..color = AppColors.primaryYellow.withValues(alpha: 0.8)
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
      center,
      Offset(center.dx + maxRadius * cos(lineAngle),
          center.dy + maxRadius * sin(lineAngle)),
      linePaint,
    );

    // Center dot
    canvas.drawCircle(
      center,
      8,
      Paint()..color = AppColors.primaryYellow,
    );
  }

  @override
  bool shouldRepaint(_RadarPainter old) => old.progress != progress;
}

// ─── Pulsing loading dot ───────────────────────────────────────────────────
class _PulsingDot extends StatefulWidget {
  final Duration delay;
  const _PulsingDot({required this.delay});

  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _anim = Tween<double>(begin: 0.4, end: 1.0).animate(
        CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
    Future.delayed(widget.delay, () {
      if (mounted) _ctrl.repeat(reverse: true);
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (context, _) => Container(
        width: 10,
        height: 10,
        margin: const EdgeInsets.symmetric(horizontal: 4),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: AppColors.primaryYellow.withValues(alpha: _anim.value),
        ),
      ),
    );
  }
}
