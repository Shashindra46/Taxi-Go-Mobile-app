import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_assets.dart';

/// SplashPage — the true app entry point (mounted at '/').
///
/// On init it:
///   1. Attempts to refresh the stored session so stale access tokens are
///      silently renewed before we make any routing decisions.
///   2. Reads the restored session; if none exists the user is sent to the
///      login page.
///   3. Inspects `userMetadata['role']` / `appMetadata['role']` and, for
///      drivers, additionally queries the `drivers` table for approval status.
///   4. Navigates with `pushNamedAndRemoveUntil` so the splash is removed from
///      the navigation stack.
///
/// Any error during session-check is treated as "not logged in" and the user
/// is safely redirected to the login page.
class SplashPage extends StatefulWidget {
  const SplashPage({super.key});

  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseController;
  late final Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();

    // Subtle pulsing animation for the logo while session is loading.
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 0.92, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    // Kick off session check after the first frame so the splash renders first.
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkSession());
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  // ─── Session resolution ────────────────────────────────────────────────────

  Future<void> _checkSession() async {
    // Small intentional delay so the splash is visible briefly even on
    // fast devices — avoids a jarring instant redirect.
    await Future.delayed(const Duration(milliseconds: 800));

    if (!mounted) return;

    try {
      final client = Supabase.instance.client;

      // Try to refresh the session. If the stored refresh token is still valid
      // this silently swaps in a fresh access token. If it fails (token revoked
      // / expired) we catch and fall through to the "no session" branch.
      Session? session = client.auth.currentSession;

      if (session != null) {
        try {
          final refreshed = await client.auth.refreshSession();
          session = refreshed.session;
        } catch (_) {
          // Refresh failed — treat the existing session as invalid.
          session = null;
        }
      }

      if (!mounted) return;

      if (session == null) {
        // No valid session — go to login.
        _navigateTo('/login');
        return;
      }

      // ── Determine role and route ──────────────────────────────────────────
      final user = session.user;

      // Role can live in userMetadata (set during sign-up) or appMetadata
      // (set server-side). Check both; appMetadata takes precedence.
      final metaRole = (user.appMetadata['role'] as String?)?.toLowerCase() ??
          (user.userMetadata?['role'] as String?)?.toLowerCase();

      if (metaRole == 'admin') {
        _navigateTo('/admin_dashboard');
        return;
      }

      if (metaRole == 'customer') {
        _navigateTo('/customer_home');
        return;
      }

      // Default: treat as driver — check approval status.
      final driverRow = await Supabase.instance.client
          .from('drivers')
          .select('status')
          .eq('user_id', user.id)
          .maybeSingle();

      if (!mounted) return;

      if (driverRow == null) {
        // No driver profile found — incomplete registration; sign them out
        // and send to login so they can re-register.
        await Supabase.instance.client.auth.signOut();
        _navigateTo('/login');
        return;
      }

      final status = driverRow['status'] as String? ?? 'pending_approval';
      if (status == 'approved') {
        _navigateTo('/driver_home');
      } else {
        _navigateTo('/driver_pending');
      }
    } catch (_) {
      // Any unexpected error — fail safe to login page.
      if (mounted) _navigateTo('/login');
    }
  }

  void _navigateTo(String route) {
    if (!mounted) return;
    Navigator.pushNamedAndRemoveUntil(context, route, (_) => false);
  }

  // ─── UI ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // ── Pulsing logo ────────────────────────────────────────────────
            ScaleTransition(
              scale: _pulseAnimation,
              child: Container(
                width: 130,
                height: 130,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.primaryYellow.withValues(alpha: 0.30),
                      blurRadius: 32,
                      spreadRadius: 6,
                    ),
                  ],
                ),
                child: ClipOval(
                  child: Image.asset(
                    AppAssets.logo,
                    fit: BoxFit.cover,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 28),

            // ── Brand name ──────────────────────────────────────────────────
            Text(
              'Taxi Go',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: AppColors.primaryYellow,
                    fontWeight: FontWeight.w800,
                    fontSize: 30,
                    letterSpacing: 1.2,
                  ),
            ),
            const SizedBox(height: 6),
            Text(
              'Your ride, your way',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppColors.textGrey,
                    fontSize: 13,
                    letterSpacing: 0.4,
                  ),
            ),
            const SizedBox(height: 52),

            // ── Loading indicator ───────────────────────────────────────────
            SizedBox(
              width: 26,
              height: 26,
              child: CircularProgressIndicator(
                strokeWidth: 2.8,
                valueColor: AlwaysStoppedAnimation<Color>(
                  AppColors.primaryYellow,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
