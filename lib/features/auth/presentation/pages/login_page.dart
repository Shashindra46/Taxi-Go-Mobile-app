import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_assets.dart';
import '../../../../core/widgets/custom_button.dart';
import '../../../../core/widgets/custom_text_field.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _handleSignIn() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);

    final email = _emailController.text.trim();
    final password = _passwordController.text;

    // ── Step 1: Authenticate ─────────────────────────────────────────────
    // Any failure here stops the flow entirely and shows the error.
    try {
      await Supabase.instance.client.auth.signInWithPassword(
        email: email,
        password: password,
      );
    } on AuthException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message), backgroundColor: Colors.red),
      );
      setState(() => _isLoading = false);
      return;
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Sign-in failed: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
      setState(() => _isLoading = false);
      return;
    }

    // ── Step 2: Auth succeeded — check driver status ─────────────────────
    // A failure here is non-fatal: the user IS signed in, so we navigate
    // them forward instead of showing a blocking error.
    if (!mounted) return;
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) throw Exception('User is null after login');
      final uid = user.id;
      final role = user.userMetadata?['role'] as String?;

      if (role == 'customer') {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Welcome back, Passenger!'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pushNamedAndRemoveUntil(context, '/customer_home', (r) => false);
        return;
      }

      final driverRow = await Supabase.instance.client
          .from('drivers')
          .select('status')
          .eq('user_id', uid)
          .maybeSingle();

      if (!mounted) return;

      if (driverRow != null) {
        final status = driverRow['status'] as String? ?? 'pending_approval';
        if (status == 'approved') {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Welcome back! Your account is approved.'),
              backgroundColor: Colors.green,
            ),
          );
          Navigator.pushNamedAndRemoveUntil(
              context, '/driver_home', (r) => false);
        } else {
          // pending_approval / rejected / suspended
          Navigator.pushNamedAndRemoveUntil(
              context, '/driver_pending', (r) => false);
        }
      } else {
        // No drivers row yet — registration was not completed.
        await Supabase.instance.client.auth.signOut();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No driver profile found. Please register.'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } catch (e) {
      // drivers query failed (RLS policy missing, network error, etc.)
      await Supabase.instance.client.auth.signOut();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content:
              Text('Could not load your profile. Please try again.'),
          backgroundColor: Colors.orange,
        ),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Header Brand Name
                Text(
                  'Taxi Go',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: AppColors.primaryYellow,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.0,
                      ),
                ),
                const SizedBox(height: 32),

                // Logo Container
                Container(
                  width: 140,
                  height: 140,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black12,
                        blurRadius: 10,
                        offset: Offset(0, 4),
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
                const SizedBox(height: 24),

                // Welcome Texts
                Text(
                  'Welcome!',
                  style: Theme.of(context).textTheme.displayLarge?.copyWith(
                        fontSize: 28,
                        fontWeight: FontWeight.w800,
                      ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Sign in to continue your journey',
                  textAlign: Alignment.center.x == 0.0 ? TextAlign.center : null,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 32),

                // Inputs
                CustomTextField(
                  label: 'Email Address',
                  hintText: 'you@example.com',
                  prefixIcon: Icons.email_outlined,
                  keyboardType: TextInputType.emailAddress,
                  controller: _emailController,
                  validator: (value) {
                    final trimmed = value?.trim() ?? '';
                    if (trimmed.isEmpty) return 'Please enter your email';
                    final emailRegex =
                        RegExp(r'^[\w\.\-]+@[\w\-]+\.[a-zA-Z]{2,}$');
                    if (!emailRegex.hasMatch(trimmed)) {
                      return 'Please enter a valid email address';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 20),
                CustomTextField(
                  label: 'Password',
                  hintText: 'Enter your password',
                  prefixIcon: Icons.lock_outline,
                  isPassword: true,
                  controller: _passwordController,
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Please enter your password';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),

                // Forgot Password link
                Align(
                  alignment: Alignment.centerRight,
                  child: GestureDetector(
                    onTap: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Forgot Password flow clicked')),
                      );
                    },
                    child: const Text(
                      'Forgot Password?',
                      style: TextStyle(
                        color: AppColors.textYellow,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 24),

                // Sign In Button
                CustomButton(
                  text: 'Sign In',
                  isLoading: _isLoading,
                  onPressed: _handleSignIn,
                ),
                const SizedBox(height: 24),

                // Or Divider
                Row(
                  children: [
                    Expanded(child: Divider(color: AppColors.borderGrey.withValues(alpha: 0.5))),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 16.0),
                      child: Text(
                        'or',
                        style: TextStyle(
                          color: AppColors.textGrey,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    Expanded(child: Divider(color: AppColors.borderGrey.withValues(alpha: 0.5))),
                  ],
                ),
                const SizedBox(height: 24),

                // Google Button
                SocialSignInButton(
                  text: 'Continue with Google',
                  onPressed: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Google Sign-In clicked')),
                    );
                  },
                ),
                const SizedBox(height: 32),

                // Footer
                Text(
                  "Don't have an account?",
                  style: TextStyle(
                    color: AppColors.textGrey.withValues(alpha: 0.8),
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 8),
                GestureDetector(
                  onTap: () {
                    Navigator.pushNamed(context, '/role_selection');
                  },
                  child: const Text(
                    'Create Account',
                    style: TextStyle(
                      color: AppColors.textYellow,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      decoration: TextDecoration.underline,
                    ),
                  ),
                ),

                if (kDebugMode) ...[
                  const SizedBox(height: 32),
                  const Divider(color: Colors.redAccent),
                  const SizedBox(height: 16),
                  TextButton.icon(
                    onPressed: () {
                      Navigator.pushNamed(context, '/admin_dashboard');
                    },
                    icon: const Icon(Icons.admin_panel_settings, color: Colors.redAccent),
                    label: const Text(
                      'Dev Admin Login (Debug Only)',
                      style: TextStyle(color: Colors.redAccent),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
