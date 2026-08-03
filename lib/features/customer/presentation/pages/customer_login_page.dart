import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/widgets/custom_button.dart';
import '../../../../core/widgets/custom_text_field.dart';

class CustomerLoginPage extends StatefulWidget {
  const CustomerLoginPage({super.key});

  @override
  State<CustomerLoginPage> createState() => _CustomerLoginPageState();
}

class _CustomerLoginPageState extends State<CustomerLoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  
  bool _isLoading = false;
  bool _isSignUp = true;

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);

    try {
      if (_isSignUp) {
        // Sign Up Flow
        await Supabase.instance.client.auth.signUp(
          email: _emailController.text.trim(),
          password: _passwordController.text.trim(),
          data: {
            'full_name': _nameController.text.trim(),
            'phone': _phoneController.text.trim(),
            'role': 'customer',
          },
        );
        
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Registration successful!'),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        // Log In Flow
        await Supabase.instance.client.auth.signInWithPassword(
          email: _emailController.text.trim(),
          password: _passwordController.text.trim(),
        );
        
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Login successful!'),
            backgroundColor: Colors.green,
          ),
        );
      }
      
      if (!mounted) return;
      
      final user = Supabase.instance.client.auth.currentUser;
      if (user != null) {
        final role = user.userMetadata?['role'] as String?;
        if (role == 'driver') {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Driver account detected. Routing to Driver Dashboard.'),
              backgroundColor: Colors.green,
            ),
          );
          
          final driverRow = await Supabase.instance.client
              .from('drivers')
              .select('status')
              .eq('user_id', user.id)
              .maybeSingle();
              
          if (!mounted) return;
          if (driverRow != null) {
            final status = driverRow['status'] as String? ?? 'pending_approval';
            if (status == 'approved') {
              Navigator.pushNamedAndRemoveUntil(context, '/driver_home', (r) => false);
            } else {
              Navigator.pushNamedAndRemoveUntil(context, '/driver_pending', (r) => false);
            }
          } else {
             await Supabase.instance.client.auth.signOut();
             ScaffoldMessenger.of(context).showSnackBar(
               const SnackBar(content: Text('No driver profile found. Please register.'), backgroundColor: Colors.orange),
             );
          }
          return;
        }
      }

      Navigator.pushNamedAndRemoveUntil(context, '/customer_home', (r) => false);
    } on AuthException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message), backgroundColor: Colors.red),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _toggleMode() {
    setState(() {
      _isSignUp = !_isSignUp;
      // Clear forms when switching modes
      _formKey.currentState?.reset();
    });
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
                // ── Header
                Stack(
                  alignment: Alignment.center,
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: IconButton(
                        icon: const Icon(Icons.arrow_back, color: AppColors.textDark),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ),
                    Text(
                      'Taxi Go',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            color: AppColors.primaryYellow,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.0,
                          ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),

                // ── Hero icon
                Container(
                  width: 90,
                  height: 90,
                  decoration: BoxDecoration(
                    color: AppColors.primaryYellow.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.primaryYellow.withValues(alpha: 0.25),
                        blurRadius: 20,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Icon(
                    _isSignUp ? Icons.person_add_rounded : Icons.login_rounded,
                    size: 42,
                    color: AppColors.primaryYellow,
                  ),
                ),
                const SizedBox(height: 24),

                // ── Titles
                Text(
                  _isSignUp ? 'Create Account' : 'Welcome Back!',
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                      ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  _isSignUp ? 'Join Taxi Go as a Passenger' : 'Sign in to your Passenger account',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppColors.textGrey, fontSize: 14),
                ),
                const SizedBox(height: 32),

                // ── Full Name (Sign Up Only)
                if (_isSignUp) ...[
                  CustomTextField(
                    label: 'Full Name',
                    hintText: 'John Doe',
                    prefixIcon: Icons.person_outline,
                    controller: _nameController,
                    validator: (value) =>
                        value == null || value.trim().isEmpty ? 'Please enter your full name' : null,
                  ),
                  const SizedBox(height: 16),
                ],

                // ── Phone Number (Sign Up Only)
                if (_isSignUp) ...[
                  CustomTextField(
                    label: 'Phone Number',
                    hintText: '+94 77 123 4567',
                    prefixIcon: Icons.phone_outlined,
                    keyboardType: TextInputType.phone,
                    controller: _phoneController,
                    validator: (value) =>
                        value == null || value.trim().isEmpty ? 'Please enter your phone number' : null,
                  ),
                  const SizedBox(height: 16),
                ],

                // ── Email field (Both)
                CustomTextField(
                  label: 'Email Address',
                  hintText: 'you@example.com',
                  prefixIcon: Icons.email_outlined,
                  keyboardType: TextInputType.emailAddress,
                  controller: _emailController,
                  validator: (value) {
                    final trimmed = value?.trim() ?? '';
                    if (trimmed.isEmpty) return 'Please enter your email';
                    if (!RegExp(r'^[\w\.\-]+@[\w\-]+\.[a-zA-Z]{2,}$').hasMatch(trimmed)) {
                      return 'Please enter a valid email address';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),

                // ── Password (Both)
                CustomTextField(
                  label: 'Password',
                  hintText: _isSignUp ? 'Create a password' : 'Enter your password',
                  prefixIcon: Icons.lock_outline,
                  isPassword: true,
                  controller: _passwordController,
                  validator: (value) =>
                      value == null || value.length < 6 ? 'Password must be at least 6 characters' : null,
                ),
                const SizedBox(height: 16),

                // ── Confirm Password (Sign Up Only)
                if (_isSignUp) ...[
                  CustomTextField(
                    label: 'Confirm Password',
                    hintText: 'Re-enter your password',
                    prefixIcon: Icons.lock_outline,
                    isPassword: true,
                    controller: _confirmPasswordController,
                    validator: (value) {
                      if (value == null || value.isEmpty) return 'Please confirm your password';
                      if (value != _passwordController.text) return 'Passwords do not match';
                      return null;
                    },
                  ),
                  const SizedBox(height: 32),
                ] else ...[
                  const SizedBox(height: 16), // Padding for login
                ],

                // ── Submit button
                CustomButton(
                  text: _isSignUp ? 'Register' : 'Sign In',
                  isLoading: _isLoading,
                  onPressed: _submit,
                ),
                const SizedBox(height: 24),

                // ── Toggle Login / Sign Up
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      _isSignUp ? "Already have an account? " : "Don't have an account? ",
                      style: TextStyle(
                        color: AppColors.textGrey.withValues(alpha: 0.8),
                        fontSize: 14,
                      ),
                    ),
                    GestureDetector(
                      onTap: _toggleMode,
                      child: Text(
                        _isSignUp ? 'Login' : 'Create one',
                        style: const TextStyle(
                          color: AppColors.textYellow,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                          decoration: TextDecoration.underline,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 32),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
