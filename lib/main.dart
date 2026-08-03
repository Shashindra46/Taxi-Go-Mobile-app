import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'core/services/supabase_config.dart';
import 'core/theme/app_theme.dart';
import 'features/auth/presentation/pages/splash_page.dart';
import 'features/auth/presentation/pages/login_page.dart';
import 'features/auth/presentation/pages/role_selection_page.dart';
import 'features/auth/presentation/pages/driver_registration_page.dart';
import 'features/auth/presentation/pages/vehicle_details_page.dart';
import 'features/auth/presentation/pages/document_upload_page.dart';
import 'features/auth/presentation/pages/otp_verification_page.dart';
import 'features/auth/presentation/pages/driver_pending_page.dart';
import 'features/driver/presentation/pages/driver_home_page.dart';
import 'features/admin/presentation/pages/admin_login_page.dart';
import 'features/admin/presentation/pages/admin_dashboard_page.dart';
import 'features/customer/presentation/pages/customer_login_page.dart';
import 'features/customer/presentation/pages/customer_home_page.dart';
import 'features/customer/presentation/pages/customer_profile_page.dart';
import 'features/customer/presentation/pages/booking_status_page.dart';
import 'features/driver/presentation/pages/driver_profile_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: SupabaseConfig.supabaseUrl,
    publishableKey: SupabaseConfig.supabaseAnonKey,
  );

  runApp(const TaxiGoApp());
}

class TaxiGoApp extends StatelessWidget {
  const TaxiGoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TaxiGo',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      initialRoute: '/',
      routes: {
        '/': (context) => const SplashPage(),
        '/login': (context) => const LoginPage(),
        '/role_selection': (context) => const RoleSelectionPage(),
        '/driver_registration': (context) => const DriverRegistrationPage(),
        '/vehicle_details': (context) => const VehicleDetailsPage(),
        '/document_upload': (context) => const DocumentUploadPage(),
        '/otp_verification': (context) => const OtpVerificationPage(),
        '/driver_pending': (context) => const DriverPendingPage(),
        '/driver_home': (context) => const DriverHomePage(),
        '/admin_login': (context) => const AdminLoginPage(),
        '/admin_dashboard': (context) => const AdminDashboardPage(),
        '/customer_login': (context) => const CustomerLoginPage(),
        '/customer_home':     (context) => const CustomerHomePage(),
        '/customer_profile':  (context) => const CustomerProfilePage(),
        '/booking_status':    (context) => const BookingStatusPage(),
        '/driver_profile':    (context) => const DriverProfilePage(),
      },
    );
  }
}
