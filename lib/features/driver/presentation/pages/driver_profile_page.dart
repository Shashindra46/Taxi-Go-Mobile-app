import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/constants/app_colors.dart';

class DriverProfilePage extends StatefulWidget {
  const DriverProfilePage({super.key});

  @override
  State<DriverProfilePage> createState() => _DriverProfilePageState();
}

class _DriverProfilePageState extends State<DriverProfilePage> {
  final _client = Supabase.instance.client;

  // Driver profile fields
  String _driverId = '';
  String _fullName = '';
  String _email = '';
  String _phone = '';
  String _status = '';

  // Vehicle fields
  String _vehicleType = '';
  String _vehicleBrand = '';
  String _vehicleModel = '';
  String _plateNumber = '';
  String _vehicleColor = '';
  int _productionYear = 0;

  bool _isLoading = true;
  String? _error;

  // Maps driver registration vehicle type IDs → display labels & icons
  static const Map<String, String> _vehicleLabels = {
    'tuk_tuk': 'Tuk-Tuk',
    'sedan': 'Sedan',
    'suv': 'SUV',
    'van': 'Mini Van',
    'bike': 'Motorcycle',
    'car': 'Car',
    'commuter': 'Commuter',
  };

  static const Map<String, IconData> _vehicleIcons = {
    'tuk_tuk': Icons.electric_rickshaw,
    'sedan': Icons.directions_car,
    'suv': Icons.car_rental,
    'van': Icons.airport_shuttle,
    'bike': Icons.motorcycle,
    'car': Icons.directions_car,
    'commuter': Icons.directions_bus_rounded,
  };

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final uid = _client.auth.currentUser?.id;
      if (uid == null) throw Exception('Not authenticated');

      // Fetch driver row
      final driverRow = await _client
          .from('drivers')
          .select('id, full_name, phone, email, status')
          .eq('user_id', uid)
          .maybeSingle();

      // Fetch vehicle row using the driver's primary key
      Map<String, dynamic>? vehicleRow;
      if (driverRow != null && driverRow['id'] != null) {
        vehicleRow = await _client
            .from('vehicles')
            .select('vehicle_type, brand, model, plate_number, color, production_year')
            .eq('driver_id', driverRow['id'])
            .maybeSingle();
      }

      if (!mounted) return;
      setState(() {
        _email = _client.auth.currentUser?.email ?? '';
        if (driverRow != null) {
          _driverId = driverRow['id'] as String? ?? '';
          _fullName = driverRow['full_name'] as String? ?? '';
          _phone = driverRow['phone'] as String? ?? '';
          _status = driverRow['status'] as String? ?? '';
        }
        if (vehicleRow != null) {
          _vehicleType = vehicleRow['vehicle_type'] as String? ?? '';
          _vehicleBrand = vehicleRow['brand'] as String? ?? '';
          _vehicleModel = vehicleRow['model'] as String? ?? '';
          _plateNumber = vehicleRow['plate_number'] as String? ?? '';
          _vehicleColor = vehicleRow['color'] as String? ?? '';
          _productionYear = vehicleRow['production_year'] as int? ?? 0;
        }
        _isLoading = false;
      });
    } catch (e) {
      if (mounted) setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _signOut() async {
    await _client.auth.signOut();
    if (!mounted) return;
    Navigator.pushNamedAndRemoveUntil(context, '/login', (r) => false);
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'approved':
        return Colors.greenAccent;
      case 'pending_approval':
        return Colors.orangeAccent;
      case 'rejected':
        return Colors.redAccent;
      default:
        return AppColors.textGrey;
    }
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'approved':
        return 'Approved ✓';
      case 'pending_approval':
        return 'Pending Approval';
      case 'rejected':
        return 'Rejected';
      default:
        return status.replaceAll('_', ' ');
    }
  }

  @override
  Widget build(BuildContext context) {
    final initials = _fullName.isNotEmpty ? _fullName[0].toUpperCase() : '?';
    final vehicleLabel =
        _vehicleLabels[_vehicleType] ?? _vehicleType.replaceAll('_', ' ');
    final vehicleIcon =
        _vehicleIcons[_vehicleType] ?? Icons.directions_car;

    return Scaffold(
      backgroundColor: const Color(0xFF0D0D0D),
      floatingActionButton: _isLoading || _error != null 
          ? null 
          : FloatingActionButton(
              backgroundColor: AppColors.primaryYellow,
              foregroundColor: Colors.black,
              onPressed: _showEditProfileDialog,
              child: const Icon(Icons.edit_rounded),
            ),
      body: _isLoading
          ? const Center(
              child:
                  CircularProgressIndicator(color: AppColors.primaryYellow))
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.error_outline,
                          color: Colors.redAccent, size: 48),
                      const SizedBox(height: 12),
                      Text(_error!,
                          style:
                              const TextStyle(color: AppColors.textGrey)),
                      const SizedBox(height: 16),
                      TextButton(
                          onPressed: _loadProfile,
                          child: const Text('Retry')),
                    ],
                  ),
                )
              : CustomScrollView(
                  slivers: [
                    // ── App Bar ──────────────────────────────────────
                    SliverAppBar(
                      expandedHeight: 240,
                      pinned: true,
                      backgroundColor: AppColors.cardDark,
                      leading: IconButton(
                        icon: const Icon(Icons.arrow_back_ios_new_rounded,
                            color: AppColors.textLight, size: 20),
                        onPressed: () => Navigator.pop(context),
                      ),
                      flexibleSpace: FlexibleSpaceBar(
                        background: Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                AppColors.primaryYellow
                                    .withValues(alpha: 0.12),
                                const Color(0xFF121212),
                              ],
                            ),
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const SizedBox(height: 56),
                              // Avatar
                              Container(
                                width: 88,
                                height: 88,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  gradient: LinearGradient(
                                    colors: [
                                      AppColors.primaryYellow,
                                      AppColors.primaryYellowDark,
                                    ],
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: AppColors.primaryYellow
                                          .withValues(alpha: 0.4),
                                      blurRadius: 24,
                                      spreadRadius: 4,
                                    ),
                                  ],
                                ),
                                child: Center(
                                  child: Text(
                                    initials,
                                    style: const TextStyle(
                                      color: Colors.black,
                                      fontSize: 38,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 12),
                              Text(
                                _fullName.isEmpty ? 'Driver' : _fullName,
                                style: const TextStyle(
                                  color: AppColors.textLight,
                                  fontSize: 20,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 6),
                              // Status badge
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 14, vertical: 4),
                                decoration: BoxDecoration(
                                  color: _statusColor(_status)
                                      .withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                      color: _statusColor(_status)
                                          .withValues(alpha: 0.4)),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.verified_rounded,
                                        color: _statusColor(_status),
                                        size: 13),
                                    const SizedBox(width: 5),
                                    Text(
                                      _statusLabel(_status),
                                      style: TextStyle(
                                        color: _statusColor(_status),
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),

                    // ── Content ──────────────────────────────────────
                    SliverPadding(
                      padding: const EdgeInsets.all(20),
                      sliver: SliverList(
                        delegate: SliverChildListDelegate([
                          // Stats row
                          Row(
                            children: [
                              Expanded(
                                  child: _statCard('Total Rides', '—',
                                      Icons.route_rounded)),
                              const SizedBox(width: 12),
                              Expanded(
                                  child: _statCard('Earnings', 'LKR —',
                                      Icons.payments_rounded)),
                              const SizedBox(width: 12),
                              Expanded(
                                  child: _statCard(
                                      'Rating', '4.8 ★', Icons.star_rounded,
                                      valueColor: Colors.amber)),
                            ],
                          ),
                          const SizedBox(height: 24),

                          // Personal info
                          _sectionLabel('Personal Information'),
                          const SizedBox(height: 12),
                          _infoCard(children: [
                            _infoTile(Icons.person_rounded, 'Full Name',
                                _fullName.isEmpty ? '—' : _fullName),
                            _divider(),
                            _infoTile(Icons.email_rounded, 'Email',
                                _email.isEmpty ? '—' : _email),
                            _divider(),
                            _infoTile(Icons.phone_rounded, 'Phone',
                                _phone.isEmpty ? '—' : _phone),
                          ]),
                          const SizedBox(height: 24),

                          // Vehicle details
                          _sectionLabel('Vehicle Details'),
                          const SizedBox(height: 12),
                          _infoCard(children: [
                            _infoTile(vehicleIcon, 'Vehicle Type',
                                vehicleLabel.isEmpty ? '—' : vehicleLabel),
                            _divider(),
                            _infoTile(Icons.branding_watermark_rounded,
                                'Brand & Model',
                                [_vehicleBrand, _vehicleModel]
                                        .where((s) => s.isNotEmpty)
                                        .join(' ') 
                                        .isEmpty
                                    ? '—'
                                    : '${_vehicleBrand.isEmpty ? '' : _vehicleBrand} ${_vehicleModel.isEmpty ? '' : _vehicleModel}'.trim()),
                            _divider(),
                            _infoTile(
                                Icons.confirmation_number_rounded,
                                'License Plate',
                                _plateNumber.isEmpty ? '—' : _plateNumber),
                            _divider(),
                            _infoTile(Icons.palette_rounded, 'Color & Year',
                                [
                                  if (_vehicleColor.isNotEmpty) _vehicleColor,
                                  if (_productionYear > 0)
                                    _productionYear.toString(),
                                ].join('  •  ').isEmpty
                                    ? '—'
                                    : [
                                        if (_vehicleColor.isNotEmpty)
                                          _vehicleColor,
                                        if (_productionYear > 0)
                                          _productionYear.toString(),
                                      ].join('  •  ')),
                          ]),
                          const SizedBox(height: 24),

                          // Document status
                          _sectionLabel('Documents'),
                          const SizedBox(height: 12),
                          _infoCard(children: [
                            _infoTile(
                              Icons.description_rounded,
                              'Document Status',
                              _status == 'approved'
                                  ? 'Verified'
                                  : 'Under Review',
                              valueColor: _status == 'approved'
                                  ? Colors.greenAccent
                                  : Colors.orangeAccent,
                            ),
                          ]),
                          const SizedBox(height: 32),

                          // Sign out
                          GestureDetector(
                            onTap: _signOut,
                            child: Container(
                              padding: const EdgeInsets.all(18),
                              decoration: BoxDecoration(
                                color:
                                    Colors.redAccent.withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(18),
                                border: Border.all(
                                    color: Colors.redAccent
                                        .withValues(alpha: 0.25)),
                              ),
                              child: const Row(
                                children: [
                                  Icon(Icons.logout_rounded,
                                      color: Colors.redAccent, size: 22),
                                  SizedBox(width: 14),
                                  Text(
                                    'Sign Out',
                                    style: TextStyle(
                                      color: Colors.redAccent,
                                      fontSize: 16,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  Spacer(),
                                  Icon(Icons.chevron_right_rounded,
                                      color: Colors.redAccent, size: 20),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 40),
                        ]),
                      ),
                    ),
                  ],
                ),
    );
  }

  // ── Helpers ──────────────────────────────────────────────────────────────

  Widget _statCard(String label, String value, IconData icon,
      {Color? valueColor}) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
      decoration: BoxDecoration(
        color: AppColors.cardDark,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
      ),
      child: Column(
        children: [
          Icon(icon,
              color: valueColor ?? AppColors.primaryYellow, size: 22),
          const SizedBox(height: 8),
          Text(value,
              style: TextStyle(
                  color: valueColor ?? AppColors.textLight,
                  fontSize: 14,
                  fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text(label,
              style: const TextStyle(
                  color: AppColors.textGrey, fontSize: 10),
              textAlign: TextAlign.center),
        ],
      ),
    );
  }

  Widget _sectionLabel(String label) => Text(
        label.toUpperCase(),
        style: TextStyle(
          color: AppColors.textGrey.withValues(alpha: 0.7),
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.4,
        ),
      );

  Widget _infoCard({required List<Widget> children}) => Container(
        decoration: BoxDecoration(
          color: AppColors.cardDark,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
        ),
        child: Column(children: children),
      );

  Widget _divider() => Divider(
        height: 1,
        color: Colors.white.withValues(alpha: 0.06),
        indent: 52,
      );

  Widget _infoTile(IconData icon, String label, String value,
      {Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AppColors.primaryYellow.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: AppColors.primaryYellow, size: 18),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: const TextStyle(
                        color: AppColors.textGrey, fontSize: 11)),
                const SizedBox(height: 2),
                Text(value,
                    style: TextStyle(
                        color: valueColor ?? AppColors.textLight,
                        fontSize: 15,
                        fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showEditProfileDialog() {
    final nameCtrl = TextEditingController(text: _fullName);
    final phoneCtrl = TextEditingController(text: _phone);
    final brandCtrl = TextEditingController(text: _vehicleBrand);
    final modelCtrl = TextEditingController(text: _vehicleModel);
    final plateCtrl = TextEditingController(text: _plateNumber);
    final colorCtrl = TextEditingController(text: _vehicleColor);
    final yearCtrl = TextEditingController(text: _productionYear > 0 ? _productionYear.toString() : '');
    
    // We can also allow changing the vehicle type using a dropdown
    String selectedType = _vehicleType.isNotEmpty ? _vehicleType : _vehicleLabels.keys.first;
    if (!_vehicleLabels.containsKey(selectedType)) {
      selectedType = _vehicleLabels.keys.first;
    }

    bool isSaving = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            backgroundColor: AppColors.cardDark,
            title: const Text('Edit Profile', style: TextStyle(color: AppColors.textLight)),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _sectionLabel('Personal Info'),
                  const SizedBox(height: 8),
                  _dialogTextField(nameCtrl, 'Full Name'),
                  const SizedBox(height: 8),
                  _dialogTextField(phoneCtrl, 'Phone Number'),
                  const SizedBox(height: 16),
                  
                  _sectionLabel('Vehicle Info'),
                  const SizedBox(height: 8),
                  // Dropdown for vehicle type
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: selectedType,
                        dropdownColor: AppColors.cardDark,
                        style: const TextStyle(color: AppColors.textLight, fontSize: 14),
                        icon: const Icon(Icons.arrow_drop_down, color: AppColors.textGrey),
                        isExpanded: true,
                        items: _vehicleLabels.entries.map((e) {
                          return DropdownMenuItem(
                            value: e.key,
                            child: Text(e.value),
                          );
                        }).toList(),
                        onChanged: (val) {
                          if (val != null) {
                            setDialogState(() => selectedType = val);
                          }
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  _dialogTextField(brandCtrl, 'Vehicle Brand (e.g. Toyota)'),
                  const SizedBox(height: 8),
                  _dialogTextField(modelCtrl, 'Vehicle Model (e.g. Prius)'),
                  const SizedBox(height: 8),
                  _dialogTextField(plateCtrl, 'License Plate'),
                  const SizedBox(height: 8),
                  _dialogTextField(colorCtrl, 'Color'),
                  const SizedBox(height: 8),
                  _dialogTextField(yearCtrl, 'Production Year', isNumber: true),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: isSaving ? null : () => Navigator.pop(ctx),
                child: const Text('Cancel', style: TextStyle(color: AppColors.textGrey)),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primaryYellow,
                  foregroundColor: Colors.black,
                ),
                onPressed: isSaving
                    ? null
                    : () async {
                        setDialogState(() => isSaving = true);
                        try {
                          // Update driver table
                          if (_driverId.isNotEmpty) {
                            await _client.from('drivers').update({
                              'full_name': nameCtrl.text.trim(),
                              'phone': phoneCtrl.text.trim(),
                            }).eq('id', _driverId);

                            // Update vehicle table
                            await _client.from('vehicles').update({
                              'vehicle_type': selectedType,
                              'brand': brandCtrl.text.trim(),
                              'model': modelCtrl.text.trim(),
                              'plate_number': plateCtrl.text.trim(),
                              'color': colorCtrl.text.trim(),
                              'production_year': int.tryParse(yearCtrl.text.trim()) ?? 0,
                            }).eq('driver_id', _driverId);
                          }
                          if (!mounted) return;
                          Navigator.pop(ctx);
                          _loadProfile();
                        } catch (e) {
                          setDialogState(() => isSaving = false);
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Error saving: $e'), backgroundColor: Colors.redAccent),
                          );
                        }
                      },
                child: isSaving
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.black, strokeWidth: 2))
                    : const Text('Save'),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _dialogTextField(TextEditingController ctrl, String hint, {bool isNumber = false}) {
    return TextField(
      controller: ctrl,
      keyboardType: isNumber ? TextInputType.number : TextInputType.text,
      style: const TextStyle(color: AppColors.textLight, fontSize: 14),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: AppColors.textGrey),
        filled: true,
        fillColor: Colors.black.withValues(alpha: 0.3),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }
}
