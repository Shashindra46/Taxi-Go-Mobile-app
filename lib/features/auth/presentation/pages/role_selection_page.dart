import 'package:flutter/material.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_assets.dart';
import '../../../../core/widgets/custom_button.dart';
import '../widgets/role_card.dart';

class RoleSelectionPage extends StatefulWidget {
  const RoleSelectionPage({super.key});

  @override
  State<RoleSelectionPage> createState() => _RoleSelectionPageState();
}

class _RoleSelectionPageState extends State<RoleSelectionPage> {
  String _selectedRole = 'customer'; // Default is customer

  void _handleContinue() {
    if (_selectedRole == 'driver') {
      Navigator.pushNamed(context, '/driver_registration');
    } else {
      Navigator.pushNamed(context, '/customer_login');
    }
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
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // Brand Logo
                    Container(
                      width: 100,
                      height: 100,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black12,
                            blurRadius: 8,
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

                    // Titles
                    Text(
                      'Join Taxi Go',
                      style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                            fontSize: 26,
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Select how you want to register',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 32),

                    // Customer Selection Card
                    RoleCard(
                      title: "I'm a Customer",
                      icon: Icons.person_outline,
                      bulletPoints: const [
                        'Book rides easily',
                        'Track your driver live',
                        'Pay securely',
                      ],
                      isSelected: _selectedRole == 'customer',
                      onTap: () {
                        setState(() {
                          _selectedRole = 'customer';
                        });
                      },
                    ),

                    // Driver Selection Card
                    RoleCard(
                      title: "I'm a Driver",
                      icon: Icons.settings_outlined, // represents steering wheel / driver settings
                      bulletPoints: const [
                        'Earn money driving',
                        'Flexible working hours',
                        'Weekly payments',
                      ],
                      isSelected: _selectedRole == 'driver',
                      onTap: () {
                        setState(() {
                          _selectedRole = 'driver';
                        });
                      },
                    ),
                    const SizedBox(height: 24),

                    // Continue Button
                    CustomButton(
                      text: 'Continue',
                      onPressed: _handleContinue,
                    ),
                    const SizedBox(height: 24),

                    // Bottom Sign In Link
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          'Already have an account? ',
                          style: TextStyle(
                            color: AppColors.textGrey.withValues(alpha: 0.8),
                            fontSize: 14,
                          ),
                        ),
                        GestureDetector(
                          onTap: () {
                            // Go back to Welcome screen
                            Navigator.pushNamedAndRemoveUntil(context, '/login', (route) => false);
                          },
                          child: const Text(
                            'Sign In',
                            style: TextStyle(
                              color: AppColors.textYellow,
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
