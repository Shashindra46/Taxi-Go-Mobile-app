import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/models/driver_model.dart';
import '../../../../core/models/vehicle_model.dart';
import '../../../../core/services/supabase_service.dart';
import '../../../../core/widgets/custom_button.dart';
import '../widgets/document_upload_card.dart';
import '../widgets/registration_progress_bar.dart';

// ─── Document slot definition ─────────────────────────────────────────────
class _DocSlot {
  final String id;
  final String label;
  final String subtitle;
  final IconData icon;

  const _DocSlot(this.id, this.label, this.subtitle, this.icon);
}

const _slots = [
  _DocSlot('license_front', 'Driving License (Front)',
      'Clear photo of front side', Icons.credit_card),
  _DocSlot('license_back', 'Driving License (Back)',
      'Clear photo of back side', Icons.credit_card_off_outlined),
  _DocSlot('nic', 'National ID (NIC)',
      'Front side of your NIC card', Icons.badge_outlined),
  _DocSlot('revenue_license', 'Vehicle Revenue License',
      'Current year revenue license', Icons.receipt_long_outlined),
];

// ─── Upload entry state ────────────────────────────────────────────────────
class _UploadEntry {
  UploadState state;
  String? fileName;
  File? nativeFile;
  Uint8List? webBytes;
  String? publicUrl;
  double progress;

  _UploadEntry()
      : state = UploadState.idle,
        progress = 0.0;
}

class DocumentUploadPage extends StatefulWidget {
  const DocumentUploadPage({super.key});

  @override
  State<DocumentUploadPage> createState() => _DocumentUploadPageState();
}

class _DocumentUploadPageState extends State<DocumentUploadPage> {
  late Map<String, dynamic> _args;
  bool _argsLoaded = false;
  bool _isSubmitting = false;

  final Map<String, _UploadEntry> _uploads = {
    for (final s in _slots) s.id: _UploadEntry(),
  };

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_argsLoaded) {
      _args = (ModalRoute.of(context)?.settings.arguments
              as Map<String, dynamic>?) ??
          {};
      _argsLoaded = true;
    }
  }

  bool get _allUploaded =>
      _uploads.values.every((e) => e.state == UploadState.done);

  // ─── Pick a file and simulate upload progress ─────────────────────────
  Future<void> _pickFile(String slotId) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['jpg', 'jpeg', 'png', 'pdf'],
      withData: kIsWeb, // need bytes on web
    );
    if (result == null || result.files.isEmpty) return;

    final picked = result.files.first;
    final entry = _uploads[slotId]!;

    setState(() {
      entry.state = UploadState.uploading;
      entry.fileName = picked.name;
      entry.progress = 0.0;
      if (kIsWeb) {
        entry.webBytes = picked.bytes;
      } else {
        entry.nativeFile = File(picked.path!);
      }
    });

    // Animate progress bar (cosmetic — real upload happens on Submit)
    for (int i = 1; i <= 10; i++) {
      await Future.delayed(const Duration(milliseconds: 80));
      if (!mounted) return;
      setState(() => entry.progress = i / 10);
    }

    setState(() => entry.state = UploadState.done);
  }

  // ─── Submit all data to Supabase ──────────────────────────────────────
  Future<void> _submit() async {
    if (!_allUploaded) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please upload all required documents first.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final email = (_args['email'] as String? ?? '').trim();

      // The password may sit at the top level OR inside the nested
      // pendingDriverArgs map, depending on how vehicle_details spreads args.
      final pendingArgs =
          (_args['pendingDriverArgs'] as Map?)?.cast<String, dynamic>() ?? {};
      final rawPassword = (_args['password'] as String?)?.trim().isNotEmpty == true
          ? (_args['password'] as String).trim()
          : (pendingArgs['password'] as String? ?? '').trim();

      debugPrint('>>> [DocumentUpload] email=$email  password present=${rawPassword.isNotEmpty}');

      if (rawPassword.isEmpty) {
        throw Exception(
            'Password was not passed through the registration flow. '
            'Please restart registration from Step 1.');
      }

      final phone = (_args['phone'] as String?)?.trim() ??
          (pendingArgs['phone'] as String? ?? '');


      // ── 1. Create the Supabase auth account NOW (deferred from Step 1)
      //       so the OTP email is sent immediately before the OTP screen.
      debugPrint('>>> [DocumentUpload] Calling auth.signUp for: $email');
      final signUpRes = await Supabase.instance.client.auth.signUp(
        email: email,
        password: rawPassword,
      );

      // Detect email-enumeration-protection case (user already exists)
      if (signUpRes.user != null &&
          (signUpRes.user!.identities == null ||
              signUpRes.user!.identities!.isEmpty)) {
        debugPrint('>>> [DocumentUpload] Email already registered.');
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                'This email is already registered. Please log in or reset your password.'),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 5),
          ),
        );
        setState(() => _isSubmitting = false);
        return;
      }

      final userId = signUpRes.user?.id;
      if (userId == null) {
        throw Exception('Account creation failed — no user ID returned. '
            'Check Supabase SMTP / rate limits and try again.');
      }
      debugPrint('>>> [DocumentUpload] signUp OK. userId=$userId');

      // ── 2. Insert driver profile
      final driverId = await SupabaseService.instance.insertDriver(
        DriverModel(
          fullName: (_args['name'] as String?)?.trim() ??
              (pendingArgs['name'] as String? ?? ''),
          phone: phone,
          nicNumber: (_args['nic'] as String?)?.trim() ??
              (pendingArgs['nic'] as String? ?? ''),
          userId: userId,
          email: email,
          status: 'pending_approval',
        ),
      );

      // ── 3. Insert vehicle
      await SupabaseService.instance.insertVehicle(
        VehicleModel(
          driverId: driverId,
          vehicleType: _args['vehicle_type'] as String? ?? '',
          brand: _args['vehicle_brand'] as String? ?? '',
          model: _args['vehicle_model'] as String? ?? '',
          plateNumber: _args['plate_number'] as String? ?? '',
          color: _args['color'] as String? ?? '',
          productionYear: _args['production_year'] as int? ?? 0,
        ),
      );

      // ── 4. Upload each document
      for (final slot in _slots) {
        final entry = _uploads[slot.id]!;
        final ext = entry.fileName?.split('.').last ?? 'jpg';
        final storagePath = '$driverId/${slot.id}.$ext';

        entry.publicUrl = await SupabaseService.instance.uploadDocument(
          storagePath: storagePath,
          nativeFile: entry.nativeFile,
          webBytes: entry.webBytes,
          fileName: entry.fileName ?? slot.id,
          contentType: ext == 'pdf' ? 'application/pdf' : 'image/$ext',
        );
      }

      // ── 5. All done — OTP email was dispatched by signUp above.
      //       Show success dialog which navigates to /otp_verification.
      if (!mounted) return;
      _showSuccessDialog(email);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Submission failed: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  void _showSuccessDialog(String email) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        contentPadding: const EdgeInsets.all(32),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppColors.primaryYellow.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.check_circle_rounded,
                  color: AppColors.primaryYellow, size: 56),
            ),
            const SizedBox(height: 20),
            const Text(
              'Application Submitted!',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textDark),
            ),
            const SizedBox(height: 10),
            Text(
              'Your account has been created for $email.\n\n'
              "We'll review your documents and notify you within 24–48 hours.",
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: 13, color: AppColors.textGrey, height: 1.5),
            ),
            const SizedBox(height: 28),
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop();
                Navigator.pushNamed(
                  context,
                  '/otp_verification',
                  arguments: {
                    'email': email,
                    'isSignUp': true,
                  },
                );
              },
              child: const Text('Verify Email'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(context),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                    horizontal: 24.0, vertical: 16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── Titles
                    Text(
                      'Upload Documents',
                      style: Theme.of(context)
                          .textTheme
                          .headlineMedium
                          ?.copyWith(
                            fontSize: 26,
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Required to verify your identity',
                      style:
                          TextStyle(color: AppColors.textGrey, fontSize: 14),
                    ),
                    const SizedBox(height: 20),

                    // ── Progress bar
                    const RegistrationProgressBar(
                      currentStep: 3,
                      totalSteps: 3,
                      stepDescription: 'Document Upload',
                    ),
                    const SizedBox(height: 28),

                    // ── Info banner
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppColors.inputFocusedBg,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                            color: AppColors.primaryYellow.withValues(alpha: 0.4)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.info_outline,
                              color: AppColors.primaryYellowDark, size: 20),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Upload JPG, PNG or PDF. Max 10 MB per file.',
                              style: TextStyle(
                                fontSize: 12,
                                color: AppColors.primaryYellowDark
                                    .withValues(alpha: 0.9),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),

                    // ── Document upload cards
                    ..._slots.map((slot) {
                      final entry = _uploads[slot.id]!;
                      return DocumentUploadCard(
                        label: slot.label,
                        subtitle: slot.subtitle,
                        icon: slot.icon,
                        state: entry.state,
                        fileName: entry.fileName,
                        uploadProgress: entry.progress,
                        onTap: () => _pickFile(slot.id),
                      );
                    }),

                    const SizedBox(height: 12),

                    // ── Completion summary chip
                    AnimatedOpacity(
                      opacity: _allUploaded ? 1 : 0,
                      duration: const Duration(milliseconds: 400),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: Colors.green.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Row(
                          children: [
                            Icon(Icons.check_circle_rounded,
                                color: Colors.green, size: 18),
                            SizedBox(width: 8),
                            Text(
                              'All documents uploaded — ready to submit!',
                              style: TextStyle(
                                  fontSize: 13,
                                  color: Colors.green,
                                  fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),

                    // ── Submit button
                    CustomButton(
                      text: _isSubmitting
                          ? 'Submitting…'
                          : 'Submit Application',
                      isLoading: _isSubmitting,
                      onPressed: _submit,
                    ),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding:
          const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: IconButton(
              icon:
                  const Icon(Icons.arrow_back, color: AppColors.textDark),
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
    );
  }
}
