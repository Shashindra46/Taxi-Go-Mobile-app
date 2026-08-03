import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/widgets/custom_button.dart';

class DriverPendingPage extends StatefulWidget {
  const DriverPendingPage({super.key});

  @override
  State<DriverPendingPage> createState() => _DriverPendingPageState();
}

class _DriverPendingPageState extends State<DriverPendingPage>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;
  late Animation<double> _rotateAnimation;

  String get _driverEmail =>
      Supabase.instance.client.auth.currentUser?.email ?? 'your email';

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);

    _pulseAnimation =
        Tween<double>(begin: 0.88, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    _rotateAnimation =
        Tween<double>(begin: -0.05, end: 0.05).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _signOut() async {
    await Supabase.instance.client.auth.signOut();
    if (!mounted) return;
    Navigator.pushNamedAndRemoveUntil(context, '/login', (r) => false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
          child: Column(
            children: [
              // ── Brand header
              Text(
                'Taxi Go',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: AppColors.primaryYellow,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.0,
                    ),
              ),
              const Spacer(),

              // ── Animated icon
              AnimatedBuilder(
                animation: _pulseController,
                builder: (_, child) => Transform.scale(
                  scale: _pulseAnimation.value,
                  child: Transform.rotate(
                    angle: _rotateAnimation.value,
                    child: child,
                  ),
                ),
                child: Container(
                  width: 130,
                  height: 130,
                  decoration: BoxDecoration(
                    color: AppColors.primaryYellow.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.primaryYellow.withValues(alpha: 0.3),
                        blurRadius: 40,
                        spreadRadius: 8,
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.hourglass_top_rounded,
                    size: 64,
                    color: AppColors.primaryYellow,
                  ),
                ),
              ),
              const SizedBox(height: 36),

              // ── Heading
              Text(
                'Application Under Review',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                    ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Our admin team is verifying your submitted documents. '
                'You will be notified once your account is approved.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppColors.textGrey,
                  fontSize: 14,
                  height: 1.6,
                ),
              ),
              const SizedBox(height: 28),

              // ── Email badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                decoration: BoxDecoration(
                  color: AppColors.inputFocusedBg,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                      color: AppColors.primaryYellow.withValues(alpha: 0.4)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.email_outlined,
                        color: AppColors.primaryYellowDark, size: 18),
                    const SizedBox(width: 10),
                    Flexible(
                      child: Text(
                        _driverEmail,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                          color: AppColors.textDark,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 28),

              // ── Status steps
              _buildStatusStep(
                icon: Icons.check_circle_rounded,
                color: Colors.green,
                label: 'Account Created',
                done: true,
              ),
              _buildStatusStep(
                icon: Icons.mark_email_read_outlined,
                color: Colors.green,
                label: 'Email Verified',
                done: true,
              ),
              _buildStatusStep(
                icon: Icons.upload_file_rounded,
                color: Colors.green,
                label: 'Documents Submitted',
                done: true,
              ),
              _buildStatusStep(
                icon: Icons.admin_panel_settings_outlined,
                color: AppColors.primaryYellow,
                label: 'Admin Review — In Progress',
                done: false,
                isActive: true,
              ),
              _buildStatusStep(
                icon: Icons.verified_rounded,
                color: AppColors.borderGrey,
                label: 'Account Approved',
                done: false,
              ),
              const SizedBox(height: 36),

              // ── ETA note
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.cardLight,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.access_time_rounded,
                        color: AppColors.textGrey, size: 18),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Typical review time: 24–48 hours. '
                        'Check back after you receive an approval email.',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.textGrey.withValues(alpha: 0.9),
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const Spacer(),

              // ── Sign out button
              CustomButton(
                text: 'Sign Out',
                onPressed: _signOut,
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusStep({
    required IconData icon,
    required Color color,
    required String label,
    required bool done,
    bool isActive = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(width: 14),
          Text(
            label,
            style: TextStyle(
              fontSize: 14,
              fontWeight: isActive ? FontWeight.w800 : FontWeight.w500,
              color: isActive
                  ? AppColors.textDark
                  : done
                      ? AppColors.textDark
                      : AppColors.textGrey,
            ),
          ),
          if (isActive) ...[
            const SizedBox(width: 8),
            _PulsingDot(),
          ],
        ],
      ),
    );
  }
}

// ── Small inline pulsing dot widget
class _PulsingDot extends StatefulWidget {
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
        vsync: this, duration: const Duration(milliseconds: 700))
      ..repeat(reverse: true);
    _anim = Tween<double>(begin: 0.3, end: 1.0).animate(_ctrl);
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
      builder: (_, _) => Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: AppColors.primaryYellow.withValues(alpha: _anim.value),
        ),
      ),
    );
  }
}
