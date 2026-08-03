import 'package:flutter/material.dart';
import '../../../../core/constants/app_colors.dart';

class RegistrationProgressBar extends StatelessWidget {
  final int currentStep;
  final int totalSteps;
  final String stepDescription;

  const RegistrationProgressBar({
    super.key,
    required this.currentStep,
    required this.totalSteps,
    required this.stepDescription,
  });

  @override
  Widget build(BuildContext context) {
    final double progress = currentStep / totalSteps;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Step $currentStep of $totalSteps',
              style: const TextStyle(
                color: AppColors.textYellow,
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
            Text(
              stepDescription,
              style: const TextStyle(
                color: AppColors.textGrey,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          height: 6,
          decoration: BoxDecoration(
            color: AppColors.borderGrey.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(3),
          ),
          child: FractionallySizedBox(
            alignment: Alignment.centerLeft,
            widthFactor: progress,
            child: Container(
              decoration: BoxDecoration(
                color: AppColors.primaryYellow,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
