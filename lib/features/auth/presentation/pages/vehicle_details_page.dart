import 'package:flutter/material.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/widgets/custom_button.dart';
import '../../../../core/widgets/custom_text_field.dart';
import '../widgets/registration_progress_bar.dart';

// ─── Vehicle type data model ───────────────────────────────────────────────
class _VehicleTypeOption {
  final String id;
  final String label;
  final IconData icon;
  const _VehicleTypeOption(this.id, this.label, this.icon);
}

const _vehicleOptions = [
  _VehicleTypeOption('tuk_tuk', 'Tuk-Tuk', Icons.electric_rickshaw),
  _VehicleTypeOption('sedan', 'Sedan', Icons.directions_car),
  _VehicleTypeOption('suv', 'SUV', Icons.car_rental),
  _VehicleTypeOption('van', 'Mini Van', Icons.airport_shuttle),
];

// ─── Sri Lanka vehicle brand → models map ─────────────────────────────────
const Map<String, List<String>> _vehicleBrandMap = {
  'Toyota': ['Axio', 'Aqua', 'Prius', 'Crown', 'Corolla', 'Hilux', 'Land Cruiser'],
  'Suzuki': ['Alto', 'Swift', 'Wagon R', 'Celerio', 'Jimny', 'Vitara'],
  'Honda':  ['Fit', 'Vezel', 'Grace', 'Civic', 'CR-V', 'HR-V'],
  'Nissan': ['Leaf', 'Tiida', 'Dayz', 'X-Trail', 'Navara', 'Note'],
  'Bajaj':  ['RE Three-Wheeler', 'Maxima', 'Qute'],
  'Mitsubishi': ['Lancer', 'Outlander', 'Montero', 'L200 Triton', 'Mirage'],
  'Hyundai': ['i10', 'i20', 'Tucson', 'Santa Fe', 'Eon'],
  'KIA': ['Picanto', 'Sportage', 'Sorento', 'Stonic'],
};

class VehicleDetailsPage extends StatefulWidget {
  const VehicleDetailsPage({super.key});

  @override
  State<VehicleDetailsPage> createState() => _VehicleDetailsPageState();
}

class _VehicleDetailsPageState extends State<VehicleDetailsPage> {
  final _formKey = GlobalKey<FormState>();
  final _plateController = TextEditingController();
  final _colorController = TextEditingController();
  final _yearController = TextEditingController();

  String? _selectedVehicleType;
  String? _selectedBrand;
  String? _selectedModel;

  // Arguments passed in from Step 1
  late Map<String, dynamic> _step1Args;
  bool _argsLoaded = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_argsLoaded) {
      _step1Args = (ModalRoute.of(context)?.settings.arguments
              as Map<String, dynamic>?) ??
          {};
      _argsLoaded = true;
    }
  }

  @override
  void dispose() {
    _plateController.dispose();
    _colorController.dispose();
    _yearController.dispose();
    super.dispose();
  }

  void _handleNext() {
    if (_selectedVehicleType == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a vehicle type')),
      );
      return;
    }
    if (!_formKey.currentState!.validate()) return;

    // Flatten pendingDriverArgs into the top-level map so all fields
    // (including password) are directly accessible by document_upload_page.
    final pending = (_step1Args['pendingDriverArgs'] as Map?)
            ?.cast<String, dynamic>() ??
        {};

    final args = {
      ..._step1Args,   // carries email, isSignUp, pendingDriverArgs
      ...pending,      // promotes name, phone, nic, password to top level
      'vehicle_type': _selectedVehicleType,
      'vehicle_brand': _selectedBrand ?? '',
      'vehicle_model': _selectedModel ?? '',
      'plate_number': _plateController.text.trim(),
      'color': _colorController.text.trim(),
      'production_year': int.tryParse(_yearController.text.trim()) ?? 0,
    };

    Navigator.pushNamed(context, '/document_upload', arguments: args);
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
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // ── Titles
                      Text(
                        'Vehicle Details',
                        style:
                            Theme.of(context).textTheme.headlineMedium?.copyWith(
                                  fontSize: 26,
                                  fontWeight: FontWeight.w800,
                                ),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Tell us about your vehicle',
                        style: TextStyle(
                            color: AppColors.textGrey, fontSize: 14),
                      ),
                      const SizedBox(height: 20),

                      // ── Progress bar
                      const RegistrationProgressBar(
                        currentStep: 2,
                        totalSteps: 3,
                        stepDescription: 'Vehicle Details',
                      ),
                      const SizedBox(height: 32),

                      // ── Vehicle type grid
                      const Text(
                        'Vehicle Type',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textDark,
                        ),
                      ),
                      const SizedBox(height: 12),
                      GridView.count(
                        crossAxisCount: 2,
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        crossAxisSpacing: 12,
                        mainAxisSpacing: 12,
                        childAspectRatio: 1.3,
                        children: _vehicleOptions
                            .map((opt) => _VehicleTypeCard(
                                  option: opt,
                                  isSelected:
                                      _selectedVehicleType == opt.id,
                                  onTap: () => setState(
                                      () => _selectedVehicleType = opt.id),
                                ))
                            .toList(),
                      ),
                      const SizedBox(height: 24),

                      // ── Brand dropdown
                      _buildDropdownField(
                        label: 'Vehicle Brand',
                        hint: 'Select brand',
                        icon: Icons.branding_watermark_outlined,
                        value: _selectedBrand,
                        items: _vehicleBrandMap.keys.toList(),
                        onChanged: (val) {
                          setState(() {
                            _selectedBrand = val;
                            _selectedModel = null; // reset model when brand changes
                          });
                        },
                        validator: (v) =>
                            v == null ? 'Please select a brand' : null,
                      ),
                      const SizedBox(height: 18),

                      // ── Model dropdown (dynamically filtered by brand)
                      _buildDropdownField(
                        label: 'Vehicle Model',
                        hint: _selectedBrand == null
                            ? 'Select brand first'
                            : 'Select model',
                        icon: Icons.directions_car_outlined,
                        value: _selectedModel,
                        items: _selectedBrand != null
                            ? (_vehicleBrandMap[_selectedBrand] ?? [])
                            : [],
                        onChanged: _selectedBrand == null
                            ? null
                            : (val) => setState(() => _selectedModel = val),
                        validator: (v) =>
                            v == null ? 'Please select a model' : null,
                      ),
                      const SizedBox(height: 18),
                      CustomTextField(
                        label: 'Plate Number',
                        hintText: 'e.g. NB-2847',
                        prefixIcon: Icons.confirmation_number_outlined,
                        controller: _plateController,
                        validator: (v) => v == null || v.isEmpty
                            ? 'Enter plate number'
                            : null,
                      ),
                      const SizedBox(height: 18),
                      CustomTextField(
                        label: 'Vehicle Color',
                        hintText: 'e.g. White, Silver',
                        prefixIcon: Icons.palette_outlined,
                        controller: _colorController,
                        validator: (v) => v == null || v.isEmpty
                            ? 'Enter vehicle color'
                            : null,
                      ),
                      const SizedBox(height: 18),
                      CustomTextField(
                        label: 'Production Year',
                        hintText: 'e.g. 2019',
                        prefixIcon: Icons.calendar_today_outlined,
                        keyboardType: TextInputType.number,
                        controller: _yearController,
                        validator: (v) {
                          if (v == null || v.isEmpty) {
                            return 'Enter production year';
                          }
                          final y = int.tryParse(v);
                          if (y == null || y < 1980 || y > DateTime.now().year) {
                            return 'Enter a valid year';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 32),

                      CustomButton(text: 'Next →', onPressed: _handleNext),
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

  /// Builds a themed dropdown that matches the existing CustomTextField style.
  Widget _buildDropdownField({
    required String label,
    required String hint,
    required IconData icon,
    required String? value,
    required List<String> items,
    required ValueChanged<String?>? onChanged,
    required String? Function(String?)? validator,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: AppColors.textDark,
          ),
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          initialValue: value,
          hint: Text(hint,
              style: const TextStyle(color: AppColors.textGrey, fontSize: 14)),
          icon: const Icon(Icons.keyboard_arrow_down_rounded,
              color: AppColors.textGrey),
          isExpanded: true,
          decoration: InputDecoration(
            prefixIcon: Icon(icon, color: AppColors.textGrey, size: 20),
            fillColor: AppColors.inputUnfocusedBg,
            filled: true,
          ),
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w500,
            color: AppColors.textDark,
          ),
          validator: validator,
          onChanged: onChanged,
          items: items
              .map((item) => DropdownMenuItem(
                    value: item,
                    child: Text(item),
                  ))
              .toList(),
        ),
      ],
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
              icon: const Icon(Icons.arrow_back,
                  color: AppColors.textDark),
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

// ─── Vehicle Type Selector Card ───────────────────────────────────────────
class _VehicleTypeCard extends StatelessWidget {
  final _VehicleTypeOption option;
  final bool isSelected;
  final VoidCallback onTap;

  const _VehicleTypeCard({
    required this.option,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeInOut,
        decoration: BoxDecoration(
          color: isSelected ? AppColors.cardDark : AppColors.cardLight,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: isSelected
                ? AppColors.primaryYellow
                : Colors.transparent,
            width: 2,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.12),
                    blurRadius: 12,
                    offset: const Offset(0, 6),
                  )
                ]
              : null,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isSelected
                    ? AppColors.primaryYellow
                    : AppColors.borderGrey.withValues(alpha: 0.5),
                shape: BoxShape.circle,
              ),
              child: Icon(
                option.icon,
                size: 28,
                color: isSelected
                    ? AppColors.textDark
                    : AppColors.textGrey,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              option.label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: isSelected
                    ? AppColors.textLight
                    : AppColors.textDark,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
