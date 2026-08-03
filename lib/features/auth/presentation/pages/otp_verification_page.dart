import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/widgets/custom_button.dart';

class OtpVerificationPage extends StatefulWidget {
  const OtpVerificationPage({super.key});

  @override
  State<OtpVerificationPage> createState() => _OtpVerificationPageState();
}

class _OtpVerificationPageState extends State<OtpVerificationPage>
    with SingleTickerProviderStateMixin {
  // ── OTP digit count ───────────────────────────────────────────────────
  // Supabase sends 6-digit OTPs by default. If your Supabase project
  // uses the "Email OTP" template and you have not customized the digit
  // count, this MUST be 6.
  static const int _otpLength = 8;

  // ── OTP input controllers (one per digit) ─────────────────────────────
  final List<TextEditingController> _controllers =
      List.generate(_otpLength, (_) => TextEditingController());
  final List<FocusNode> _focusNodes =
      List.generate(_otpLength, (_) => FocusNode());

  // ── State ─────────────────────────────────────────────────────────────
  bool _isVerifying = false;
  bool _isResending = false;
  int _secondsLeft = 60;
  Timer? _timer;

  // ── Route args ────────────────────────────────────────────────────────
  late String _email;
  bool _isSignUp = true;
  bool _argsLoaded = false;

  // ── Animation ─────────────────────────────────────────────────────────
  late AnimationController _shakeController;
  late Animation<double> _shakeAnimation;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_argsLoaded) {
      final args = ModalRoute.of(context)?.settings.arguments;
      if (args is Map) {
        _email = (args['email'] as String?) ?? '';
        _isSignUp = (args['isSignUp'] as bool?) ?? true;
      } else {
        _email = '';
      }
      _argsLoaded = true;
      _startTimer();
    }
  }

  @override
  void initState() {
    super.initState();
    _shakeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _shakeAnimation = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: -16.0), weight: 1),
      TweenSequenceItem(tween: Tween(begin: -16.0, end: 16.0), weight: 2),
      TweenSequenceItem(tween: Tween(begin: 16.0, end: -12.0), weight: 2),
      TweenSequenceItem(tween: Tween(begin: -12.0, end: 12.0), weight: 2),
      TweenSequenceItem(tween: Tween(begin: 12.0, end: 0.0), weight: 1),
    ]).animate(CurvedAnimation(parent: _shakeController, curve: Curves.easeOut));
  }

  @override
  void dispose() {
    _timer?.cancel();
    for (final c in _controllers) {
      c.dispose();
    }
    for (final f in _focusNodes) {
      f.dispose();
    }
    _shakeController.dispose();
    super.dispose();
  }

  // ── Timer ─────────────────────────────────────────────────────────────
  void _startTimer() {
    _timer?.cancel();
    setState(() => _secondsLeft = 60);
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      if (_secondsLeft == 0) {
        t.cancel();
      } else {
        setState(() => _secondsLeft--);
      }
    });
  }

  String get _timerLabel {
    final m = (_secondsLeft ~/ 60).toString().padLeft(2, '0');
    final s = (_secondsLeft % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  // ── Resend OTP ────────────────────────────────────────────────────────
  Future<void> _resendOtp() async {
    if (_isResending) return;
    setState(() => _isResending = true);

    // Clear existing input
    for (final c in _controllers) {
      c.clear();
    }
    if (mounted) _focusNodes.first.requestFocus();

    try {
      debugPrint('>>> [OTP] Resending OTP to $_email (isSignUp=$_isSignUp)');

      if (_isSignUp) {
        // Try resend first; if it fails fall back to signInWithOtp
        try {
          await Supabase.instance.client.auth.resend(
            type: OtpType.signup,
            email: _email,
          );
          debugPrint('>>> [OTP] Resend via resend(signup) succeeded');
        } on AuthException catch (resendErr) {
          // resend() can fail if the user is already confirmed or the token
          // is stale. Fall back to signInWithOtp which always sends a fresh OTP.
          debugPrint(
              '>>> [OTP] resend(signup) failed (${resendErr.message}), falling back to signInWithOtp');
          await Supabase.instance.client.auth.signInWithOtp(
            email: _email,
            shouldCreateUser: false,
          );
        }
      } else {
        await Supabase.instance.client.auth.signInWithOtp(
          email: _email,
          shouldCreateUser: false,
        );
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('A new OTP has been sent to your email.'),
          backgroundColor: Colors.green,
        ),
      );
      _startTimer();
    } on AuthException catch (e) {
      if (!mounted) return;
      debugPrint('>>> [OTP] Resend AuthException: ${e.message}');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Resend Failed: ${e.message}'),
          backgroundColor: Colors.red,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      debugPrint('>>> [OTP] Resend Unknown Error: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Resend Error: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _isResending = false);
    }
  }

  // ── Verify OTP ────────────────────────────────────────────────────────
  Future<void> _verifyOtp() async {
    // Guard against concurrent calls (e.g. auto-submit + button tap)
    if (_isVerifying) return;

    final token = _controllers.map((c) => c.text.trim()).join();
    if (token.length < _otpLength) {
      _shakeController.forward(from: 0);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Please enter all $_otpLength digits of the OTP.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() => _isVerifying = true);
    debugPrint(
        '>>> [OTP] Verifying token "$token" for email "$_email" (isSignUp=$_isSignUp)');

    try {
      // IMPORTANT: The token type must match what Supabase sent.
      //   - For email sign-up confirmation → OtpType.signup
      //   - For magic-link / sign-in OTP  → OtpType.email  (not magiclink)
      //
      // If you keep getting "Token has expired or is invalid", toggle the
      // type below between OtpType.signup and OtpType.email and retry.
      final otpType = _isSignUp ? OtpType.signup : OtpType.email;

      final response = await Supabase.instance.client.auth.verifyOTP(
        email: _email,
        token: token,
        type: otpType,
      );

      debugPrint(
          '>>> [OTP] Verification successful. Session: ${response.session?.accessToken != null}');

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Email verified! 🎉'),
          backgroundColor: Colors.green,
        ),
      );

      if (_isSignUp) {
        // Driver sign-up complete → go to Login screen so driver can sign in
        Navigator.pushNamedAndRemoveUntil(context, '/', (r) => false);
      } else {
        // Customer OTP login → go to customer home
        Navigator.pushNamedAndRemoveUntil(
            context, '/customer_home', (r) => false);
      }
    } on AuthException catch (e) {
      if (!mounted) return;
      debugPrint('>>> [OTP] Verification AuthException: ${e.message} | statusCode: ${e.statusCode}');

      _shakeController.forward(from: 0);
      for (final c in _controllers) {
        c.clear();
      }
      _focusNodes.first.requestFocus();

      // Provide a clear, actionable error message to the user
      String userMessage = e.message;
      if (e.message.toLowerCase().contains('expired') ||
          e.message.toLowerCase().contains('invalid')) {
        userMessage =
            'This code is invalid or has expired. Please request a new one.';
      } else if (e.message.toLowerCase().contains('rate')) {
        userMessage = 'Too many attempts. Please wait before trying again.';
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Verification Failed: $userMessage'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 5),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      debugPrint('>>> [OTP] Verification Unknown Error: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Unexpected Error: ${e.toString()}'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 5),
        ),
      );
    } finally {
      if (mounted) setState(() => _isVerifying = false);
    }
  }

  // ── OTP Box ───────────────────────────────────────────────────────────
  Widget _buildOtpBox(int index) {
    return SizedBox(
      width: 46,
      height: 56,
      child: TextFormField(
        controller: _controllers[index],
        focusNode: _focusNodes[index],
        textAlign: TextAlign.center,
        keyboardType: TextInputType.number,
        maxLength: 1,
        style: const TextStyle(
          fontSize: 24,
          fontWeight: FontWeight.w800,
          color: AppColors.textDark,
        ),
        decoration: InputDecoration(
          counterText: '',
          filled: true,
          fillColor: AppColors.inputUnfocusedBg,
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: AppColors.borderGrey, width: 1.5),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide:
                const BorderSide(color: AppColors.primaryYellow, width: 2.5),
          ),
          contentPadding: EdgeInsets.zero,
        ),
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        onChanged: (val) {
          if (val.isNotEmpty && index < _otpLength - 1) {
            _focusNodes[index + 1].requestFocus();
          } else if (val.isEmpty && index > 0) {
            _focusNodes[index - 1].requestFocus();
          }
          // Auto-submit when all digits are entered (guard prevents double-call)
          if (!_isVerifying &&
              _controllers.every((c) => c.text.isNotEmpty)) {
            _verifyOtp();
          }
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final maskedEmail = _maskEmail(_email);

    return Scaffold(
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding:
                const EdgeInsets.symmetric(horizontal: 28.0, vertical: 24.0),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight - 48),
              child: IntrinsicHeight(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
              // ── Back + brand header
              Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back,
                        color: AppColors.textDark),
                    onPressed: () => Navigator.pop(context),
                  ),
                  const Spacer(),
                  Text(
                    'Taxi Go',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          color: AppColors.primaryYellow,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.0,
                        ),
                  ),
                  const Spacer(),
                  const SizedBox(width: 48),
                ],
              ),
              const SizedBox(height: 36),

              // ── Hero icon
              Container(
                width: 96,
                height: 96,
                decoration: BoxDecoration(
                  color: AppColors.primaryYellow.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.mark_email_read_outlined,
                  size: 48,
                  color: AppColors.primaryYellow,
                ),
              ),
              const SizedBox(height: 28),

              // ── Title
              Text(
                'Verify Your Email',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                    ),
              ),
              const SizedBox(height: 10),
              Text(
                'We sent a $_otpLength-digit code to',
                style: const TextStyle(
                    color: AppColors.textGrey, fontSize: 14),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 4),
              Text(
                maskedEmail,
                style: const TextStyle(
                  color: AppColors.textDark,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              // Debug email display (only in debug builds)
              if (kDebugMode)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.blue.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.blue.withValues(alpha: 0.3)),
                  ),
                  child: Text(
                    '(Debug) Full email: $_email',
                    style: const TextStyle(color: Colors.blue, fontSize: 11),
                  ),
                ),
              const SizedBox(height: 28),

              // ── OTP input row (with shake animation on error)
              AnimatedBuilder(
                animation: _shakeAnimation,
                builder: (context, child) {
                  return Transform.translate(
                    offset: Offset(_shakeAnimation.value, 0),
                    child: child,
                  );
                },
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: List.generate(_otpLength, _buildOtpBox),
                ),
              ),
              const SizedBox(height: 36),

              // ── Verify button
              CustomButton(
                text: 'Verify & Register',
                isLoading: _isVerifying,
                onPressed: _verifyOtp,
              ),
              const SizedBox(height: 32),

              // ── Timer + resend
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    _secondsLeft > 0
                        ? 'Resend code in '
                        : 'Didn\'t receive the code?  ',
                    style: const TextStyle(
                        color: AppColors.textGrey, fontSize: 14),
                  ),
                  if (_secondsLeft > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.primaryYellow.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        _timerLabel,
                        style: const TextStyle(
                          color: AppColors.primaryYellowDark,
                          fontWeight: FontWeight.w800,
                          fontSize: 14,
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                      ),
                    )
                  else
                    GestureDetector(
                      onTap: _isResending ? null : _resendOtp,
                      child: _isResending
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                    AppColors.primaryYellow),
                              ),
                            )
                          : const Text(
                              'Resend OTP',
                              style: TextStyle(
                                color: AppColors.textYellow,
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                                decoration: TextDecoration.underline,
                              ),
                            ),
                    ),
                ],
              ),
              const SizedBox(height: 24),

              // ── Security note
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.inputFocusedBg,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                      color: AppColors.primaryYellow.withValues(alpha: 0.35)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.shield_outlined,
                        color: AppColors.primaryYellowDark, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'This code expires in 10 minutes. '
                        'Never share your OTP with anyone.',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.primaryYellowDark
                              .withValues(alpha: 0.9),
                          height: 1.5,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
                  ],       // Column children
                ),         // Column
              ),           // IntrinsicHeight
            ),             // ConstrainedBox
          ),               // SingleChildScrollView
        ),                 // LayoutBuilder
      ),                   // SafeArea
    );
  }

  /// Masks the email for privacy — e.g. dr****@gmail.com
  String _maskEmail(String email) {
    final parts = email.split('@');
    if (parts.length != 2) return email;
    final local = parts[0];
    final domain = parts[1];
    if (local.length <= 2) return '$local****@$domain';
    return '${local.substring(0, 2)}****@$domain';
  }
}
