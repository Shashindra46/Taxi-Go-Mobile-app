import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/constants/app_colors.dart';

class CustomerProfilePage extends StatefulWidget {
  const CustomerProfilePage({super.key});

  @override
  State<CustomerProfilePage> createState() => _CustomerProfilePageState();
}

class _CustomerProfilePageState extends State<CustomerProfilePage> {
  final _client = Supabase.instance.client;

  // Profile data
  String _email = '';
  String _displayName = '';
  String _phone = '';
  bool _isEditing = false;
  bool _isSaving = false;

  final _nameController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  void _loadProfile() {
    final user = _client.auth.currentUser;
    if (user == null) return;

    final meta = user.userMetadata ?? {};
    setState(() {
      _email = user.email ?? '';
      _displayName = (meta['full_name'] as String? ??
              meta['name'] as String? ??
              _email.split('@').first)
          .trim();
      _phone = meta['phone'] as String? ?? '';
      _nameController.text = _displayName;
    });
  }

  Future<void> _saveProfile() async {
    final newName = _nameController.text.trim();
    if (newName.isEmpty) return;
    setState(() => _isSaving = true);
    try {
      await _client.auth.updateUser(
        UserAttributes(data: {'full_name': newName}),
      );
      setState(() {
        _displayName = newName;
        _isEditing = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Profile updated!'),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.redAccent),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _signOut() async {
    await _client.auth.signOut();
    if (!mounted) return;
    Navigator.pushNamedAndRemoveUntil(context, '/login', (r) => false);
  }

  @override
  Widget build(BuildContext context) {
    final initials = _displayName.isNotEmpty ? _displayName[0].toUpperCase() : '?';

    return Scaffold(
      backgroundColor: const Color(0xFF0D0D0D),
      body: CustomScrollView(
        slivers: [
          // ── App Bar ──────────────────────────────────────────────────
          SliverAppBar(
            expandedHeight: 220,
            pinned: true,
            backgroundColor: AppColors.cardDark,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios_new_rounded,
                  color: AppColors.textLight, size: 20),
              onPressed: () => Navigator.pop(context),
            ),
            actions: [
              if (!_isEditing)
                TextButton.icon(
                  onPressed: () => setState(() => _isEditing = true),
                  icon: const Icon(Icons.edit_rounded,
                      color: AppColors.primaryYellow, size: 18),
                  label: const Text('Edit',
                      style: TextStyle(
                          color: AppColors.primaryYellow,
                          fontWeight: FontWeight.w700)),
                )
              else
                _isSaving
                    ? const Padding(
                        padding: EdgeInsets.all(14),
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              color: AppColors.primaryYellow, strokeWidth: 2),
                        ),
                      )
                    : TextButton(
                        onPressed: _saveProfile,
                        child: const Text('Save',
                            style: TextStyle(
                                color: Colors.greenAccent,
                                fontWeight: FontWeight.w800)),
                      ),
              const SizedBox(width: 8),
            ],
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      AppColors.primaryYellow.withValues(alpha: 0.15),
                      const Color(0xFF121212),
                    ],
                  ),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const SizedBox(height: 48),
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
                            color: AppColors.primaryYellow.withValues(alpha: 0.4),
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
                      _displayName,
                      style: const TextStyle(
                        color: AppColors.textLight,
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.amber.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                            color: Colors.amber.withValues(alpha: 0.4)),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.star_rounded,
                              color: Colors.amber, size: 14),
                          SizedBox(width: 4),
                          Text('4.9  Passenger',
                              style: TextStyle(
                                  color: Colors.amber,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // ── Content ─────────────────────────────────────────────────
          SliverPadding(
            padding: const EdgeInsets.all(20),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                // Section: Personal Info
                _sectionLabel('Personal Information'),
                const SizedBox(height: 12),
                _infoCard(children: [
                  _isEditing
                      ? _editField('Full Name', _nameController,
                          Icons.person_rounded)
                      : _infoTile(Icons.person_rounded, 'Full Name',
                          _displayName.isEmpty ? 'Not set' : _displayName),
                  _divider(),
                  _infoTile(Icons.email_rounded, 'Email',
                      _email.isEmpty ? 'Not set' : _email),
                  _divider(),
                  _infoTile(Icons.phone_rounded, 'Phone',
                      _phone.isEmpty ? 'Not set' : _phone),
                ]),

                const SizedBox(height: 24),

                // Section: Account
                _sectionLabel('Account'),
                const SizedBox(height: 12),
                _infoCard(children: [
                  _infoTile(Icons.shield_rounded, 'Account Status', 'Active',
                      valueColor: Colors.greenAccent),
                  _divider(),
                  _infoTile(Icons.history_rounded, 'Total Rides', '—'),
                ]),

                const SizedBox(height: 32),

                // Logout
                GestureDetector(
                  onTap: _signOut,
                  child: Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: Colors.redAccent.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                          color: Colors.redAccent.withValues(alpha: 0.25)),
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

  Widget _editField(
      String label, TextEditingController ctrl, IconData icon) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
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
            child: TextField(
              controller: ctrl,
              style: const TextStyle(
                  color: AppColors.textLight,
                  fontSize: 15,
                  fontWeight: FontWeight.w600),
              decoration: InputDecoration(
                labelText: label,
                labelStyle:
                    const TextStyle(color: AppColors.textGrey, fontSize: 11),
                enabledBorder: UnderlineInputBorder(
                    borderSide: BorderSide(
                        color: Colors.white.withValues(alpha: 0.15))),
                focusedBorder: const UnderlineInputBorder(
                    borderSide:
                        BorderSide(color: AppColors.primaryYellow, width: 2)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
