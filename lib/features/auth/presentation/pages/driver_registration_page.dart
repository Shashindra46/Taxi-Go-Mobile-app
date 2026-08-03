import 'package:flutter/material.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/widgets/custom_button.dart';
import '../../../../core/widgets/custom_text_field.dart';
import '../widgets/registration_progress_bar.dart';

class DriverRegistrationPage extends StatefulWidget {
  const DriverRegistrationPage({super.key});

  @override
  State<DriverRegistrationPage> createState() => _DriverRegistrationPageState();
}

class _DriverRegistrationPageState extends State<DriverRegistrationPage> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _nicController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();


  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _nicController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _handleNext() async {
    if (!_formKey.currentState!.validate()) return;

    final email = _emailController.text.trim();

    // Do NOT call signUp here. Sending the OTP at Step 1 means the token will
    // expire long before the user finishes vehicle details + document upload.
    // The auth.signUp call is deferred to the final Submit step in
    // document_upload_page.dart so the OTP email arrives exactly on time.
    if (!mounted) return;
    Navigator.pushNamed(
      context,
      '/vehicle_details',
      arguments: {
        'email': email,
        'isSignUp': true,
        'pendingDriverArgs': {
          'name': _nameController.text.trim(),
          'phone': _phoneController.text.trim(),
          'nic': _nicController.text.trim(),
          'email': email,
          // Password is passed through so document_upload can call signUp
          'password': _passwordController.text,
        },
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // Custom Navigation Header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: IconButton(
                      icon: const Icon(Icons.arrow_back, color: AppColors.textDark),
                      onPressed: () {
                        Navigator.pop(context);
                      },
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
            ),

            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Page Titles
                      Text(
                        'Driver Registration',
                        style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                              fontSize: 26,
                              fontWeight: FontWeight.w800,
                            ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Fill in your details to start driving',
                        style: TextStyle(
                          color: AppColors.textGrey,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 20),

                      // Progress Bar
                      const RegistrationProgressBar(
                        currentStep: 1,
                        totalSteps: 3,
                        stepDescription: 'Personal Info',
                      ),
                      const SizedBox(height: 32),

                      // Form Inputs
                      CustomTextField(
                        label: 'Full Name',
                        hintText: 'Enter your full name',
                        prefixIcon: Icons.person_outline,
                        controller: _nameController,
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Please enter your full name';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 20),

                      PhoneInputField(
                        label: 'Phone Number',
                        hintText: '77 123 4567',
                        controller: _phoneController,
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Please enter your phone number';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 20),

                      CustomTextField(
                        label: 'NIC Number',
                        hintText: 'Enter your NIC number',
                        prefixIcon: Icons.badge_outlined,
                        controller: _nicController,
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Please enter your NIC number';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 20),

                      CustomTextField(
                        label: 'Email Address',
                        hintText: 'you@example.com',
                        prefixIcon: Icons.email_outlined,
                        keyboardType: TextInputType.emailAddress,
                        controller: _emailController,
                        validator: (value) {
                          final trimmed = value?.trim() ?? '';
                          if (trimmed.isEmpty) {
                            return 'Please enter your email address';
                          }
                          final emailRegex = RegExp(
                              r'^[\w\.\-]+@[\w\-]+\.[a-zA-Z]{2,}$');
                          if (!emailRegex.hasMatch(trimmed)) {
                            return 'Please enter a valid email address';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 20),

                      CustomTextField(
                        label: 'Password',
                        hintText: 'Create a password',
                        prefixIcon: Icons.lock_outline,
                        isPassword: true,
                        controller: _passwordController,
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Please enter a password';
                          }
                          if (value.length < 6) {
                            return 'Password must be at least 6 characters';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 20),

                      CustomTextField(
                        label: 'Confirm Password',
                        hintText: 'Re-enter your password',
                        prefixIcon: Icons.lock_person_outlined,
                        isPassword: true,
                        controller: _confirmPasswordController,
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Please confirm your password';
                          }
                          if (value != _passwordController.text) {
                            return 'Passwords do not match';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 32),

                      // Next Button
                      CustomButton(
                        text: 'Next →',
                        isLoading: false,
                        onPressed: _handleNext,
                      ),
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
