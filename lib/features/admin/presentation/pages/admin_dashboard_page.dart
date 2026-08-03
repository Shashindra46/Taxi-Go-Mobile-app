import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AdminDashboardPage extends StatefulWidget {
  const AdminDashboardPage({super.key});

  @override
  State<AdminDashboardPage> createState() => _AdminDashboardPageState();
}

class _AdminDashboardPageState extends State<AdminDashboardPage> {
  // ── Color Palette (Navy/Slate) ─────────────────────────────────────────────
  static const _adminBg     = Color(0xFF0A0F1E);
  static const _adminCard   = Color(0xFF111827);
  static const _adminAccent = Color(0xFF4F8EF7);
  static const _adminText   = Colors.white;
  static const _adminMuted  = Colors.white70;

  // ── Document slot IDs — must match what document_upload_page stored ─────────
  static const _docSlots = [
    _DocMeta('license_front',   'Driving Licence (Front)', Icons.credit_card),
    _DocMeta('license_back',    'Driving Licence (Back)',  Icons.credit_card_off_outlined),
    _DocMeta('nic',             'NIC Card',                Icons.badge_outlined),
    _DocMeta('revenue_license', 'Revenue Licence',         Icons.receipt_long_outlined),
  ];

  static const _bucket = 'driver-documents';
  // Signed URLs expire after 1 hour (3600 s) — plenty for an admin review session
  static const _signedUrlTtl = 3600;

  bool _isLoading = true;
  List<Map<String, dynamic>> _pendingDrivers = [];

  // driverId → { slotId → signedUrl | null }
  // null means "still loading", empty-string means "file not found"
  final Map<String, Map<String, String?>> _docUrls = {};
  // which driver cards have the docs panel expanded
  final Set<String> _expanded = {};

  @override
  void initState() {
    super.initState();
    _fetchPendingDrivers();
  }

  // ── Data fetching ──────────────────────────────────────────────────────────

  Future<void> _fetchPendingDrivers() async {
    setState(() => _isLoading = true);
    try {
      final response = await Supabase.instance.client
          .from('drivers')
          .select('*')
          .eq('status', 'pending_approval')
          .order('created_at', ascending: true);

      if (!mounted) return;
      setState(() {
        _pendingDrivers = List<Map<String, dynamic>>.from(response);
        _isLoading = false;
        // Pre-seed the url map so we know which drivers exist
        for (final d in _pendingDrivers) {
          final id = d['id'].toString();
          _docUrls.putIfAbsent(id, () => {});
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to load drivers: $e'),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  /// Generates signed URLs for all 4 document slots for the given [driverId].
  /// Tries multiple file extensions (jpg, jpeg, png, pdf) per slot.
  Future<void> _loadDocuments(String driverId) async {
    // Initialise all slots to null (loading state)
    final slotMap = <String, String?>{};
    for (final slot in _docSlots) {
      slotMap[slot.id] = null;
    }
    setState(() => _docUrls[driverId] = slotMap);

    final storage = Supabase.instance.client.storage.from(_bucket);
    final extensions = ['jpg', 'jpeg', 'png', 'pdf'];

    for (final slot in _docSlots) {
      String resolvedUrl = '';

      for (final ext in extensions) {
        final path = '$driverId/${slot.id}.$ext';
        try {
          final url = await storage.createSignedUrl(path, _signedUrlTtl);
          resolvedUrl = url;
          break; // found a match — stop trying other extensions
        } catch (_) {
          // File with this extension doesn't exist — try next
        }
      }

      if (!mounted) return;
      setState(() {
        _docUrls[driverId]![slot.id] = resolvedUrl; // '' means not found
      });
    }
  }

  // ── Actions ────────────────────────────────────────────────────────────────

  Future<void> _approveDriver(String id, String name) async {
    try {
      await Supabase.instance.client
          .from('drivers')
          .update({'status': 'approved'})
          .eq('id', id);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('✓ $name approved successfully!'),
          backgroundColor: Colors.green,
        ),
      );
      _fetchPendingDrivers();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Approval failed: $e'),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  Future<void> _rejectDriver(String id, String name) async {
    try {
      await Supabase.instance.client
          .from('drivers')
          .update({'status': 'rejected'})
          .eq('id', id);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('✗ $name rejected.'),
          backgroundColor: Colors.orange,
        ),
      );
      _fetchPendingDrivers();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Rejection failed: $e'),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  Future<void> _handleLogout() async {
    await Supabase.instance.client.auth.signOut();
    if (!mounted) return;
    Navigator.pushNamedAndRemoveUntil(context, '/admin_login', (r) => false);
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _adminBg,
      appBar: AppBar(
        backgroundColor: _adminCard,
        elevation: 0,
        title: const Row(
          children: [
            Icon(Icons.admin_panel_settings_rounded, color: _adminAccent),
            SizedBox(width: 8),
            Text(
              'Admin Dashboard',
              style: TextStyle(color: _adminText, fontWeight: FontWeight.w700),
            ),
          ],
        ),
        actions: [
          IconButton(
            onPressed: _fetchPendingDrivers,
            icon: const Icon(Icons.refresh_rounded, color: _adminAccent),
            tooltip: 'Refresh',
          ),
          IconButton(
            onPressed: _handleLogout,
            icon: const Icon(Icons.logout_rounded, color: Colors.redAccent),
            tooltip: 'Log Out',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: _adminAccent))
          : _pendingDrivers.isEmpty
              ? _buildEmptyState()
              : _buildDriverList(),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.check_circle_outline_rounded,
              size: 80, color: _adminAccent.withValues(alpha: 0.5)),
          const SizedBox(height: 16),
          const Text('All Caught Up!',
              style: TextStyle(
                  color: _adminText,
                  fontSize: 22,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          const Text('No drivers pending approval.',
              style: TextStyle(color: _adminMuted)),
        ],
      ),
    );
  }

  Widget _buildDriverList() {
    return RefreshIndicator(
      onRefresh: _fetchPendingDrivers,
      color: _adminAccent,
      backgroundColor: _adminCard,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _pendingDrivers.length,
        itemBuilder: (context, index) =>
            _buildDriverCard(_pendingDrivers[index]),
      ),
    );
  }

  Widget _buildDriverCard(Map<String, dynamic> driver) {
    final id    = driver['id'].toString();
    final name  = (driver['full_name'] ?? 'Unknown').toString();
    final email = (driver['email']     ?? 'No email').toString();
    final phone = (driver['phone']     ?? 'No phone').toString();
    final nic   = (driver['nic_number']?? 'No NIC'  ).toString();

    final docsLoaded  = _docUrls.containsKey(id) &&
        _docUrls[id]!.values.any((v) => v != null);
    final isExpanded  = _expanded.contains(id);

    return Card(
      color: _adminCard,
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 4,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header: Avatar + name ──────────────────────────────────────
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: _adminAccent.withValues(alpha: 0.2),
                  child: Text(
                    name.isNotEmpty ? name[0].toUpperCase() : '?',
                    style: const TextStyle(
                        color: _adminAccent, fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name,
                          style: const TextStyle(
                              color: _adminText,
                              fontSize: 17,
                              fontWeight: FontWeight.bold)),
                      Text('Pending Approval',
                          style: TextStyle(
                              color: Colors.orange.shade300,
                              fontSize: 12,
                              fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),

            // ── Info Grid ──────────────────────────────────────────────────
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _adminBg,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  _infoRow(Icons.email_outlined, 'Email', email),
                  const SizedBox(height: 8),
                  _infoRow(Icons.phone_outlined, 'Phone', phone),
                  const SizedBox(height: 8),
                  _infoRow(Icons.badge_outlined, 'NIC', nic),
                ],
              ),
            ),
            const SizedBox(height: 14),

            // ── Documents Toggle ───────────────────────────────────────────
            GestureDetector(
              onTap: () {
                setState(() {
                  if (isExpanded) {
                    _expanded.remove(id);
                  } else {
                    _expanded.add(id);
                    // Lazy-load signed URLs the first time the panel is opened
                    if (!docsLoaded) _loadDocuments(id);
                  }
                });
              },
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: _adminAccent.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                      color: _adminAccent.withValues(alpha: 0.25)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.folder_open_rounded,
                        color: _adminAccent, size: 18),
                    const SizedBox(width: 8),
                    const Text('View Documents',
                        style: TextStyle(
                            color: _adminAccent,
                            fontWeight: FontWeight.w600)),
                    const Spacer(),
                    Icon(
                      isExpanded
                          ? Icons.keyboard_arrow_up_rounded
                          : Icons.keyboard_arrow_down_rounded,
                      color: _adminAccent,
                    ),
                  ],
                ),
              ),
            ),

            // ── Documents Panel ────────────────────────────────────────────
            if (isExpanded) ...[
              const SizedBox(height: 12),
              _buildDocumentsPanel(id),
            ],

            const SizedBox(height: 14),

            // ── Action Buttons ─────────────────────────────────────────────
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _rejectDriver(id, name),
                    icon: const Icon(Icons.close_rounded,
                        color: Colors.redAccent, size: 18),
                    label: const Text('Reject',
                        style: TextStyle(color: Colors.redAccent)),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Colors.redAccent),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => _approveDriver(id, name),
                    icon: const Icon(Icons.check_rounded,
                        color: Colors.white, size: 18),
                    label: const Text('Approve',
                        style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green.shade600,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDocumentsPanel(String driverId) {
    final slotMap = _docUrls[driverId] ?? {};

    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: _docSlots.map((slot) {
        final url = slotMap[slot.id]; // null = loading, '' = not found
        return _DocThumbnail(
          label: slot.label,
          icon: slot.icon,
          url: url,
          accentColor: _adminAccent,
        );
      }).toList(),
    );
  }

  Widget _infoRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, size: 16, color: _adminMuted),
        const SizedBox(width: 8),
        Text('$label: ',
            style: const TextStyle(color: _adminMuted, fontSize: 13)),
        Expanded(
          child: Text(value,
              style: const TextStyle(
                  color: _adminText,
                  fontSize: 13,
                  fontWeight: FontWeight.w500),
              overflow: TextOverflow.ellipsis),
        ),
      ],
    );
  }
}

// ── Document slot metadata ─────────────────────────────────────────────────

class _DocMeta {
  final String   id;
  final String   label;
  final IconData icon;
  const _DocMeta(this.id, this.label, this.icon);
}

// ── Individual document thumbnail widget ───────────────────────────────────

class _DocThumbnail extends StatelessWidget {
  final String   label;
  final IconData icon;
  final String?  url;          // null = loading, '' = not found, else valid URL
  final Color    accentColor;

  const _DocThumbnail({
    required this.label,
    required this.icon,
    required this.url,
    required this.accentColor,
  });

  static const _card   = Color(0xFF111827);
  static const _bg     = Color(0xFF0A0F1E);
  static const _muted  = Colors.white54;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: url != null && url!.isNotEmpty
          ? () => _showFullScreen(context, url!, label)
          : null,
      child: Container(
        width: 155,
        decoration: BoxDecoration(
          color: _card,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Preview area (128 × 100) ───────────────────────────────────
            ClipRRect(
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(12)),
              child: SizedBox(
                height: 100,
                width: double.infinity,
                child: _buildPreview(),
              ),
            ),
            // ── Label ─────────────────────────────────────────────────────
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Row(
                children: [
                  Icon(icon, size: 13, color: accentColor),
                  const SizedBox(width: 5),
                  Expanded(
                    child: Text(
                      label,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w600),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPreview() {
    // ── Still loading ──────────────────────────────────────────────────────
    if (url == null) {
      return Container(
        color: _bg,
        child: const Center(
          child: SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(
                strokeWidth: 2, color: Color(0xFF4F8EF7)),
          ),
        ),
      );
    }

    // ── File not found in storage ──────────────────────────────────────────
    if (url!.isEmpty) {
      return Container(
        color: _bg,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.cloud_off_rounded, color: _muted, size: 28),
            const SizedBox(height: 6),
            const Text('Not uploaded',
                style: TextStyle(color: _muted, fontSize: 10)),
          ],
        ),
      );
    }

    // ── PDF file — can't render inline, show icon ──────────────────────────
    if (url!.toLowerCase().contains('.pdf')) {
      return Container(
        color: _bg,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.picture_as_pdf_rounded,
                color: Colors.redAccent.shade100, size: 36),
            const SizedBox(height: 6),
            const Text('PDF — tap to open',
                style: TextStyle(color: _muted, fontSize: 10)),
          ],
        ),
      );
    }

    // ── Image file — render with error fallback ────────────────────────────
    return Image.network(
      url!,
      fit: BoxFit.cover,
      // Show a shimmer-style skeleton while the image loads
      loadingBuilder: (context, child, loadingProgress) {
        if (loadingProgress == null) return child;
        return Container(
          color: _bg,
          child: Center(
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: const Color(0xFF4F8EF7),
              value: loadingProgress.expectedTotalBytes != null
                  ? loadingProgress.cumulativeBytesLoaded /
                      loadingProgress.expectedTotalBytes!
                  : null,
            ),
          ),
        );
      },
      // Graceful fallback for 403 Forbidden, broken URLs, or network errors
      errorBuilder: (context, error, stackTrace) {
        return Container(
          color: _bg,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.broken_image_rounded,
                  color: Colors.redAccent.shade100, size: 28),
              const SizedBox(height: 6),
              const Text('Failed to load',
                  style: TextStyle(color: _muted, fontSize: 10)),
            ],
          ),
        );
      },
    );
  }

  void _showFullScreen(
      BuildContext context, String imageUrl, String title) {
    showDialog(
      context: context,
      barrierColor: Colors.black87,
      builder: (_) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Title bar ─────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(title,
                      style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 15)),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white70),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            // ── Full-size image ────────────────────────────────────────────
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: imageUrl.toLowerCase().contains('.pdf')
                  ? Container(
                      height: 300,
                      color: const Color(0xFF111827),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.picture_as_pdf_rounded,
                              color: Colors.redAccent.shade100, size: 64),
                          const SizedBox(height: 12),
                          const Text('PDF document',
                              style: TextStyle(color: Colors.white70)),
                        ],
                      ),
                    )
                  : Image.network(
                      imageUrl,
                      fit: BoxFit.contain,
                      loadingBuilder: (context, child, progress) {
                        if (progress == null) return child;
                        return const SizedBox(
                          height: 300,
                          child: Center(
                            child: CircularProgressIndicator(
                                color: Color(0xFF4F8EF7)),
                          ),
                        );
                      },
                      errorBuilder: (_, __, ___) => Container(
                        height: 300,
                        color: const Color(0xFF111827),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.broken_image_rounded,
                                color: Colors.redAccent.shade100, size: 48),
                            const SizedBox(height: 8),
                            const Text('Could not load image',
                                style: TextStyle(color: Colors.white54)),
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
