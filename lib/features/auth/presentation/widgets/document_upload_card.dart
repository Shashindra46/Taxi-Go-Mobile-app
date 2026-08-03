import 'package:flutter/material.dart';
import '../../../../core/constants/app_colors.dart';

enum UploadState { idle, uploading, done, error }

class DocumentUploadCard extends StatelessWidget {
  final String label;
  final String subtitle;
  final IconData icon;
  final UploadState state;
  final String? fileName;
  final double uploadProgress; // 0.0 – 1.0
  final VoidCallback onTap;

  const DocumentUploadCard({
    super.key,
    required this.label,
    required this.subtitle,
    required this.icon,
    required this.state,
    required this.onTap,
    this.fileName,
    this.uploadProgress = 0.0,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: state == UploadState.uploading ? null : onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: _bgColor,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: _borderColor,
            width: state == UploadState.idle ? 1.5 : 1.5,
            strokeAlign: BorderSide.strokeAlignInside,
          ),
        ),
        child: Row(
          children: [
            // Left Icon Badge
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: _iconBgColor,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: _iconColor, size: 26),
            ),
            const SizedBox(width: 14),

            // Middle Content
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: _labelColor,
                    ),
                  ),
                  const SizedBox(height: 3),
                  if (state == UploadState.idle) ...[
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textGrey,
                      ),
                    ),
                  ] else if (state == UploadState.uploading) ...[
                    const SizedBox(height: 4),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: uploadProgress,
                        backgroundColor: AppColors.borderGrey,
                        valueColor: const AlwaysStoppedAnimation<Color>(
                          AppColors.primaryYellow,
                        ),
                        minHeight: 6,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Uploading… ${(uploadProgress * 100).toInt()}%',
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.textGrey,
                      ),
                    ),
                  ] else if (state == UploadState.done) ...[
                    Text(
                      fileName ?? 'Uploaded',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textGrey,
                      ),
                    ),
                  ] else if (state == UploadState.error) ...[
                    const Text(
                      'Upload failed — tap to retry',
                      style: TextStyle(fontSize: 12, color: Colors.red),
                    ),
                  ],
                ],
              ),
            ),

            const SizedBox(width: 10),

            // Right action indicator
            _buildTrailing(),
          ],
        ),
      ),
    );
  }

  Widget _buildTrailing() {
    switch (state) {
      case UploadState.idle:
        return Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: AppColors.inputUnfocusedBg,
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Icon(
            Icons.upload_rounded,
            size: 20,
            color: AppColors.textGrey,
          ),
        );
      case UploadState.uploading:
        return const SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(
            strokeWidth: 2.5,
            valueColor:
                AlwaysStoppedAnimation<Color>(AppColors.primaryYellow),
          ),
        );
      case UploadState.done:
        return Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.green.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Icon(Icons.check_circle_rounded,
              size: 22, color: Colors.green),
        );
      case UploadState.error:
        return Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.red.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Icon(Icons.refresh_rounded,
              size: 22, color: Colors.red),
        );
    }
  }

  Color get _bgColor {
    switch (state) {
      case UploadState.idle:
        return AppColors.cardLight;
      case UploadState.uploading:
        return const Color(0xFFFFFAE8);
      case UploadState.done:
        return Colors.green.withValues(alpha: 0.06);
      case UploadState.error:
        return Colors.red.withValues(alpha: 0.05);
    }
  }

  Color get _borderColor {
    switch (state) {
      case UploadState.idle:
        return AppColors.borderGrey;
      case UploadState.uploading:
        return AppColors.primaryYellow;
      case UploadState.done:
        return Colors.green.withValues(alpha: 0.4);
      case UploadState.error:
        return Colors.red.withValues(alpha: 0.4);
    }
  }

  Color get _iconBgColor {
    switch (state) {
      case UploadState.idle:
        return AppColors.inputUnfocusedBg;
      case UploadState.uploading:
        return AppColors.primaryYellow.withValues(alpha: 0.15);
      case UploadState.done:
        return Colors.green.withValues(alpha: 0.12);
      case UploadState.error:
        return Colors.red.withValues(alpha: 0.1);
    }
  }

  Color get _iconColor {
    switch (state) {
      case UploadState.idle:
        return AppColors.textGrey;
      case UploadState.uploading:
        return AppColors.primaryYellowDark;
      case UploadState.done:
        return Colors.green;
      case UploadState.error:
        return Colors.red;
    }
  }

  Color get _labelColor {
    switch (state) {
      case UploadState.idle:
        return AppColors.textDark;
      case UploadState.uploading:
        return AppColors.textDark;
      case UploadState.done:
        return AppColors.textDark;
      case UploadState.error:
        return Colors.red;
    }
  }
}
