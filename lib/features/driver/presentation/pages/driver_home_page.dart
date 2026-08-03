import 'dart:math' as math;
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/constants/app_colors.dart';
import 'driver_profile_page.dart';

class DriverHomePage extends StatefulWidget {
  const DriverHomePage({super.key});

  @override
  State<DriverHomePage> createState() => _DriverHomePageState();
}

class _DriverHomePageState extends State<DriverHomePage>
    with TickerProviderStateMixin {
  // ── State ──────────────────────────────────────────────────────────────
  bool _isOnline = false;
  StreamSubscription<List<Map<String, dynamic>>>? _ridesSubscription;
  bool _isShowingRidePopup = false;
  Map<String, dynamic>? _acceptedRide;

  // ── Ride lifecycle status ('accepted' | 'arrived' | 'in_progress') ──────
  String _rideStatus = 'idle';
  bool _hasInitialBoundsFitted = false;

  // ── Payment tracking ────────────────────────────────────────────────────
  RealtimeChannel? _paymentChannel;
  Timer?           _paymentPollTimer;  // fallback polling every 3s
  String? _completedRideId;
  double _completedFare = 0;
  /// 'cash' or 'card' once customer selects; drives UI reactively.
  String? _pendingPaymentMethod;

  // ── Driver Profile ──────────────────────────────────────────────────────
  /// The vehicle type from the `vehicles` table (e.g. 'car', 'tuk', 'bike').
  /// null while the profile fetch is in-flight.
  String? _driverVehicleType;
  bool _isProfileLoaded = false;
  /// The primary key of this driver's row in the `drivers` table.
  /// Cached here so we can update location_latitude/longitude in one place.
  String? _driverDbId;

  // ── Map / Location ──────────────────────────────────────────────────────
  final MapController _mapController = MapController();
  LatLng? _driverLocation;
  StreamSubscription<Position>? _locationStream; // live GPS broadcaster
  List<LatLng> _navRoutePoints = [];             // OSRM route to pickup
  static const LatLng _defaultCenter = LatLng(6.8941, 79.9012);

  // ── Animations ─────────────────────────────────────────────────────────
  late final AnimationController _pulseCtrl;
  late final AnimationController _scanCtrl;
  late final Animation<double> _pulseAnim;

  bool _forcePickupPinLock = false;

  // ── Mock daily summary (replace with real Supabase query later) ────────
  static const int _todayRides = 7;
  static const double _todayEarnings = 2450.0;
  static const double _rating = 4.8;
  static const String _onlineHours = '4h 30m';

  String get _firstName {
    final email =
        Supabase.instance.client.auth.currentUser?.email ?? 'driver@taxigo.app';
    final name = email.split('@').first;
    return name[0].toUpperCase() + name.substring(1);
  }

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);

    _scanCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    );

    _pulseAnim = Tween<double>(begin: 0.82, end: 1.0)
        .animate(CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut));

    _checkPermissionsAndGetLocation();
    _loadDriverVehicleType();
  }

  Future<void> _checkPermissionsAndGetLocation() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return;

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) return;
      }
      if (permission == LocationPermission.deniedForever) return;

      final position = await Geolocator.getCurrentPosition();
      if (!mounted) return;
      setState(() {
        _driverLocation = LatLng(position.latitude, position.longitude);
      });
      _mapController.move(_driverLocation!, 15.0);
    } catch (e) {
      debugPrint('Location error: $e');
    }
  }

  /// Fetches the logged-in driver's vehicle type from the `vehicles` table
  /// and maps the registration ID to the ride-request ID used by customers.
  ///
  /// Registration page stores:  'tuk_tuk' | 'sedan' | 'suv' | 'van'
  /// Ride request page stores:  'tuk'     | 'car'   | 'car' | 'van'
  Future<void> _loadDriverVehicleType() async {
    // Maps vehicle_details_page IDs → customer_home_page _selectedVehicle IDs
    const rideTypeMap = {
      'tuk_tuk':  'tuk',
      'sedan':    'car',
      'suv':      'car',
      'van':      'van',
      'bike':     'bike',
      'car':      'car',
      'commuter': 'commuter',
    };

    try {
      final uid = Supabase.instance.client.auth.currentUser?.id;
      if (uid == null) return;

      // 1. Fetch driver row AND its primary key 'id'
      final driverRow = await Supabase.instance.client
          .from('drivers')
          .select('id')
          .eq('user_id', uid)
          .maybeSingle();

      if (driverRow == null || driverRow['id'] == null) {
        if (mounted) setState(() => _isProfileLoaded = true);
        return;
      }

      // Cache the driver DB id for location updates
      _driverDbId = driverRow['id'] as String;

      // 2. Fetch vehicle using driver_id
      final rows = await Supabase.instance.client
          .from('vehicles')
          .select('vehicle_type')
          .eq('driver_id', driverRow['id'])
          .limit(1);

      if (!mounted) return;
      if (rows.isNotEmpty) {
        final raw = (rows.first['vehicle_type'] as String).toLowerCase().trim();
        final mapped = rideTypeMap[raw] ?? raw; // fallback: use as-is
        setState(() {
          _driverVehicleType = mapped;
          _isProfileLoaded = true;
        });
        debugPrint('Driver vehicle type: raw=$raw → mapped=$mapped');
      } else {
        setState(() => _isProfileLoaded = true);
        debugPrint('No vehicle row for driver (id: ${driverRow['id']}) — listening to all pending rides');
      }
    } catch (e) {
      debugPrint('Failed to load driver vehicle type: $e');
      if (mounted) setState(() => _isProfileLoaded = true);
    }
  }

  @override
  void dispose() {
    _ridesSubscription?.cancel();
    _locationStream?.cancel();
    _paymentChannel?.unsubscribe();
    _paymentPollTimer?.cancel();
    _pulseCtrl.dispose();
    _scanCtrl.dispose();
    super.dispose();
  }

  void _toggleOnline(bool value) {
    setState(() => _isOnline = value);
    if (value) {
      _scanCtrl.repeat();
      if (_isProfileLoaded) {
        _startListeningForRides();
      } else {
        // Profile still loading — wait then start
        _loadDriverVehicleType().then((_) {
          if (_isOnline && mounted) _startListeningForRides();
        });
      }
      // Write 'online' status + current GPS to the drivers table so the
      // customer map can display this driver as a nearby car icon.
      _updateDriverOnlineStatus(online: true);
      _startBroadcastingLocation();
    } else {
      _scanCtrl.stop(canceled: false);
      _ridesSubscription?.cancel();
      // Clear GPS and mark driver as offline in the drivers table.
      _updateDriverOnlineStatus(online: false);
      _stopBroadcastingLocation();
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          value
              ? '✅ You are now Online. Accepting ride requests.'
              : '🔴 You are now Offline.',
        ),
        backgroundColor: value ? Colors.green.shade700 : Colors.grey.shade700,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  /// Writes the driver's online/offline status and GPS location to the
  /// `drivers` table so the customer map can fetch and display nearby cars.
  ///
  /// Wrapped in try/catch — if the `location_latitude` / `location_longitude`
  /// columns don't exist yet the call will fail silently and not break the app.
  Future<void> _updateDriverOnlineStatus({required bool online}) async {
    final id = _driverDbId;
    if (id == null) return;
    try {
      final payload = online
          ? {
              'status': 'online',
              'location_latitude': _driverLocation?.latitude,
              'location_longitude': _driverLocation?.longitude,
            }
          : {
              'status': 'approved', // revert to base approved state
              'location_latitude': null,
              'location_longitude': null,
            };
      await Supabase.instance.client
          .from('drivers')
          .update(payload)
          .eq('id', id);
    } catch (e) {
      debugPrint('Driver online status update error: $e');
    }
  }

  void _startListeningForRides() {
    _ridesSubscription?.cancel();

    // ── Important SDK constraint ─────────────────────────────────────────────
    // supabase-dart v2's .stream() only supports ONE .eq() filter (it overwrites
    // _streamFilter on each call). We cannot filter by both 'status' and
    // 'vehicle_type' via chained .eq() calls — the second silently drops the first.
    //
    // Solution: apply the narrower, more selective filter via .eq() on the stream
    // (vehicle_type, which reduces the dataset the most), then enforce the
    // 'status == pending' condition locally inside the listener.
    // ────────────────────────────────────────────────────────────────────────

    void handleRides(List<Map<String, dynamic>> rides) {
      // Local filter: strictly enforce both status AND vehicle_type matching
      final pending = rides.where((r) {
        if (r['status'] != 'pending') return false;
        if (_driverVehicleType != null && r['vehicle_type'] != _driverVehicleType) return false;
        return true;
      }).toList();

      if (pending.isNotEmpty && !_isShowingRidePopup && _acceptedRide == null) {
        _showRidePopup(pending.first);
      }
    }

    void handleError(Object error) {
      debugPrint('Ride stream error: $error');
    }

    if (_driverVehicleType != null) {
      // Stream only rides matching this driver's vehicle type;
      // status is enforced locally above.
      _ridesSubscription = Supabase.instance.client
          .from('rides')
          .stream(primaryKey: ['id'])
          .eq('vehicle_type', _driverVehicleType!)
          .listen(handleRides, onError: handleError);
    } else {
      // No vehicle profile yet — stream all rides and filter locally.
      _ridesSubscription = Supabase.instance.client
          .from('rides')
          .stream(primaryKey: ['id'])
          .listen(handleRides, onError: handleError);
    }
  }

  void _showRidePopup(Map<String, dynamic> ride) {
    if (!mounted) return;
    _isShowingRidePopup = true;

    final vehicleIcons = {
      'bike': Icons.motorcycle,
      'tuk': Icons.local_taxi,
      'car': Icons.directions_car,
      'van': Icons.airport_shuttle,
      'commuter': Icons.directions_bus_rounded,
    };
    final vehicleType = ride['vehicle_type'] as String? ?? 'car';
    final vehicleIcon = vehicleIcons[vehicleType] ?? Icons.directions_car;
    final fare = (ride['fare'] as num?)?.toDouble() ?? 0.0;
    final pickupName = ride['pickup_name'] as String? ?? 'Unknown';
    final dropName = ride['drop_name'] as String? ?? 'Unknown';

    showModalBottomSheet(
      context: context,
      isDismissible: false,
      enableDrag: false,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Container(
          decoration: const BoxDecoration(
            color: Color(0xFF161616),
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
              // Drag handle
              Container(
                width: 38, height: 4,
                margin: const EdgeInsets.only(top: 10, bottom: 14),
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              // Pulsing header badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: AppColors.primaryYellow.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(30),
                  border: Border.all(color: AppColors.primaryYellow.withValues(alpha: 0.4)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.notifications_active_rounded,
                        color: AppColors.primaryYellow, size: 16),
                    const SizedBox(width: 8),
                    const Text(
                      'NEW RIDE REQUEST',
                      style: TextStyle(
                        color: AppColors.primaryYellow,
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              // Fare + Vehicle row
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Row(
                  children: [
                    // Fare pill
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.06),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Column(
                          children: [
                            const Text('Fare', style: TextStyle(color: AppColors.textGrey, fontSize: 11)),
                            const SizedBox(height: 4),
                            Text(
                              'LKR ${fare.toStringAsFixed(0)}',
                              style: const TextStyle(
                                color: AppColors.primaryYellow,
                                fontSize: 20,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    // Vehicle pill
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.06),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Column(
                          children: [
                            const Text('Vehicle', style: TextStyle(color: AppColors.textGrey, fontSize: 11)),
                            const SizedBox(height: 4),
                            Icon(vehicleIcon, color: Colors.white, size: 24),
                            const SizedBox(height: 2),
                            Text(
                              vehicleType[0].toUpperCase() + vehicleType.substring(1),
                              style: const TextStyle(color: AppColors.textLight, fontSize: 12, fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              // Route display
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.04),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
                  ),
                  child: Column(
                    children: [
                      _RouteRow(
                        icon: Icons.my_location_rounded,
                        iconColor: AppColors.primaryYellow,
                        label: 'PICKUP',
                        name: pickupName,
                      ),
                      Padding(
                        padding: const EdgeInsets.only(left: 11, top: 4, bottom: 4),
                        child: Container(width: 2, height: 22, color: Colors.white12),
                      ),
                      _RouteRow(
                        icon: Icons.location_on_rounded,
                        iconColor: Colors.redAccent,
                        label: 'DROP',
                        name: dropName,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),
              // Action buttons
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Row(
                  children: [
                    // Decline
                    Expanded(
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.redAccent,
                          side: const BorderSide(color: Colors.redAccent),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        ),
                        onPressed: () {
                          _isShowingRidePopup = false;
                          Navigator.pop(ctx);
                        },
                        child: const Text('Decline', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    // Accept
                    Expanded(
                      flex: 2,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primaryYellow,
                          foregroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          elevation: 0,
                        ),
                        onPressed: () {
                          Navigator.pop(ctx);
                          _acceptRide(ride);
                        },
                        child: const Text(
                          'Accept Ride  →',
                          style: TextStyle(fontWeight: FontWeight.w900, fontSize: 17),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),   // Column
        ),     // SingleChildScrollView
      );       // Container
      },
    ).then((_) {
      _isShowingRidePopup = false;
    });
  }

  Future<void> _acceptRide(Map<String, dynamic> ride) async {
    try {
      final uid = Supabase.instance.client.auth.currentUser!.id;
      await Supabase.instance.client
          .from('rides')
          .update({'status': 'accepted', 'driver_id': uid})
          .eq('id', ride['id']);

      if (!mounted) return;
      setState(() {
        _acceptedRide = ride;
        _rideStatus = 'accepted';
        _hasInitialBoundsFitted = false; // Reset bounds flag for new ride
      });

      // Try fitting immediately (will succeed if GPS is already locked)
      _fitMapToActiveRoute();

      _startBroadcastingLocation(ride['id'] as String);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ride Accepted! Heading to pickup.'), backgroundColor: Colors.green),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to accept ride: $e'), backgroundColor: Colors.redAccent),
      );
    }
  }

  // ── Ride lifecycle transitions ───────────────────────────────────────────
  Future<void> _updateRideStatus(String newStatus) async {
    final ride = _acceptedRide;
    if (ride == null) return;
    final rideId = ride['id'] as String;

    try {
      await Supabase.instance.client
          .from('rides')
          .update({'status': newStatus})
          .eq('id', rideId);

      if (!mounted) return;

      if (newStatus == 'arrived') {
        // Show drop-off route immediately from pickup spot
        setState(() {
          _rideStatus   = 'arrived';
          _navRoutePoints = []; // erase pickup→driver route
        });
        _fitMapToActiveRoute();
      } else if (newStatus == 'in_progress') {
        // If coming from 'arrived', we already have the drop-off route.
        // Avoid wiping it to prevent visual flickering.
        setState(() {
          _rideStatus = 'in_progress';
          _forcePickupPinLock = true;
        });
        _fitMapToActiveRoute();
        
        // Unconditionally lock to pickup pin for 4 seconds for web/laptop testing
        Future.delayed(const Duration(seconds: 4), () {
          if (mounted) setState(() => _forcePickupPinLock = false);
        });
      } else if (newStatus == 'completed') {
        // Stop GPS; keep _acceptedRide alive so the payment UI stays visible
        _stopBroadcastingLocation();
        
        final dropLat = (ride['drop_latitude'] as num).toDouble();
        final dropLng = (ride['drop_longitude'] as num).toDouble();
        final dropPt  = LatLng(dropLat, dropLng);

        final fare = (ride['fare'] as num?)?.toDouble() ?? 0.0;
        _completedRideId = rideId;
        _completedFare   = fare;
        // Transition to 'completed' phase — UI stays, just awaiting payment
        setState(() {
          _rideStatus     = 'completed';
          _navRoutePoints = [];
          // Snap driver marker exactly to the drop-off coordinates
          _driverLocation = dropPt;
          // _acceptedRide intentionally NOT cleared here
        });
        // Start listening for customer's payment selection
        if (mounted) _listenForPayment(rideId, fare);
      } else {
        setState(() => _rideStatus = newStatus);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Update failed: $e'), backgroundColor: Colors.redAccent),
      );
    }
  }

  /// Intelligently fits the map camera bounds based on the current ride phase.
  /// Refetches the OSRM route if needed and fits the bounds.
  Future<void> _fitMapToActiveRoute() async {
    final ride = _acceptedRide;
    if (ride == null) return;
    
    final pickupPt = LatLng(
      (ride['pickup_latitude'] as num).toDouble(),
      (ride['pickup_longitude'] as num).toDouble(),
    );
    final dropPt = LatLng(
      (ride['drop_latitude'] as num).toDouble(),
      (ride['drop_longitude'] as num).toDouble(),
    );

    if (_rideStatus == 'accepted') {
      if (_driverLocation == null) return; // Wait for GPS to lock
      
      // Set flag immediately to prevent concurrent triggers from fast GPS updates
      _hasInitialBoundsFitted = true; 
      
      await _fetchNavRoute(_driverLocation!, pickupPt);
      try {
        _mapController.fitCamera(
          CameraFit.bounds(
            bounds: LatLngBounds.fromPoints([
              _driverLocation!, 
              pickupPt,
              ..._navRoutePoints, // Include all route curves
            ]),
            padding: const EdgeInsets.all(60), // Safer padding for all screen sizes
          ),
        );
      } catch (e) {
        debugPrint('>>> [MapFitError] accepted phase: $e');
      }
    } else if (_rideStatus == 'arrived' || _rideStatus == 'in_progress') {
      if (_navRoutePoints.isEmpty) {
        await _fetchNavRoute(pickupPt, dropPt);
      }
      try {
        _mapController.fitCamera(
          CameraFit.bounds(
            bounds: LatLngBounds.fromPoints([
              pickupPt, 
              dropPt,
              if (_rideStatus == 'in_progress' && _driverLocation != null) _driverLocation!,
              ..._navRoutePoints,
            ]),
            padding: const EdgeInsets.only(top: 60, left: 50, right: 50, bottom: 140),
          ),
        );
      } catch (e) {
        debugPrint('>>> [MapFitError] in_progress phase: $e');
      }
    }
  }

  /// Clears the active ride completely and returns driver to dashboard.
  /// Called ONLY after payment is fully settled.
  void _clearActiveRide() {
    if (!mounted) return;
    _paymentPollTimer?.cancel();
    _paymentPollTimer = null;
    _paymentChannel?.unsubscribe();
    _paymentChannel = null;
    setState(() {
      _acceptedRide         = null;
      _rideStatus           = 'idle'; // back to idle — no active ride
      _navRoutePoints       = [];
      _pendingPaymentMethod = null;
    });
    // Resume idle broadcasting if they are still online
    if (_isOnline) {
      _startBroadcastingLocation();
    }
  }

  // ── Payment listener (driver side) ─────────────────────────────────────

  /// Shared handler called by both the realtime channel AND the poll timer.
  void _handlePaymentUpdate(Map<String, dynamic> row) {
    if (!mounted) return;
    
    // Safely parse and lowercase strings
    final payMethod = (row['payment_method'] ?? '').toString().toLowerCase().trim();
    final payStatus = (row['payment_status'] ?? '').toString().toLowerCase().trim();
    
    debugPrint('[PaymentUpdate] FULL ROW: $row');
    debugPrint('[PaymentUpdate] method=$payMethod  status=$payStatus  pendingNow=$_pendingPaymentMethod');

    if (payMethod == 'card' && payStatus == 'paid') {
      debugPrint('[PaymentUpdate] → CARD PAID — clearing ride');
      _paymentPollTimer?.cancel();
      _paymentChannel?.unsubscribe();
      _paymentChannel = null;
      _clearActiveRide();
      _showPaymentReceivedDialog(_completedFare, method: 'card');
    } else if (payMethod == 'cash' && payStatus == 'pending') {
      debugPrint('✅ MATCH FOUND! Triggering setState for Cash...');
      setState(() {
          _pendingPaymentMethod = 'cash';
      });
    } else if (payMethod == 'cash' && payStatus == 'paid') {
      debugPrint('[PaymentUpdate] → CASH PAID — stopping listeners');
      _paymentPollTimer?.cancel();
      _paymentChannel?.unsubscribe();
      _paymentChannel = null;
    }
  }

  void _listenForPayment(String rideId, double fare) {
    debugPrint('[listenForPayment] Starting listeners for ride: $rideId');

    // ─ 1. Realtime postgres_changes channel (fast path) ──────────────────
    _paymentChannel?.unsubscribe();
    _paymentChannel = Supabase.instance.client
        .channel('payment-$rideId')
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'rides',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'id',
            value: rideId,
          ),
          callback: (payload) {
            debugPrint('[PaymentChannel] RAW PAYLOAD: ${payload.newRecord}');
            _handlePaymentUpdate(payload.newRecord);
          },
        )
        .subscribe((status, [error]) {
          debugPrint('[PaymentChannel] subscription status=$status  error=$error');
        });

    // ─ 2. Polling fallback every 3s (guarantees detection even if WS fails) ─
    _paymentPollTimer?.cancel();
    _paymentPollTimer = Timer.periodic(const Duration(seconds: 3), (_) async {
      if (!mounted) return;
      try {
        final row = await Supabase.instance.client
            .from('rides')
            .select('payment_method, payment_status')
            .eq('id', rideId)
            .single();
        debugPrint('[PaymentPoll] fetched: $row');
        _handlePaymentUpdate(row);
      } catch (e) {
        debugPrint('[PaymentPoll] fetch error: $e');
      }
    });
  }

  /// Shown to driver when customer pays by card (auto-confirmed).
  void _showPaymentReceivedDialog(double fare, {required String method}) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Dialog(
        backgroundColor: const Color(0xFF1A1A1A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 72, height: 72,
                decoration: BoxDecoration(
                  color: Colors.greenAccent.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.check_circle_rounded,
                    color: Colors.greenAccent, size: 42),
              ),
              const SizedBox(height: 20),
              Text(
                method == 'card' ? '🔔  Card Payment Received!' : '💵  Cash Received!',
                style: const TextStyle(
                  color: AppColors.textLight, fontSize: 20, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 8),
              Text(
                method == 'card'
                    ? 'The passenger paid via card. Earnings recorded!'
                    : 'Cash confirmed. Earnings recorded!',
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.textGrey, fontSize: 13, height: 1.5),
              ),
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
                decoration: BoxDecoration(
                  color: AppColors.primaryYellow.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: AppColors.primaryYellow.withValues(alpha: 0.3)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.payments_rounded, color: AppColors.primaryYellow, size: 22),
                    const SizedBox(width: 10),
                    Text(
                      'LKR ${_completedFare.toStringAsFixed(0)} earned',
                      style: const TextStyle(
                        color: AppColors.primaryYellow,
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryYellow,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    elevation: 0,
                  ),
                  onPressed: () {
                    _clearActiveRide();
                    Navigator.pop(ctx);
                  },
                  child: const Text('Back to Dashboard',
                      style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }



  /// Snaps a given GPS coordinate to the closest point on the provided polyline.
  /// Eliminates live GPS jitter by locking the visual car marker directly to the drawn route.
  LatLng _snapToPolyline(LatLng gps, List<LatLng> polyline) {
    if (polyline.isEmpty) return gps;
    if (polyline.length == 1) return polyline.first;

    double minDistSq = double.infinity;
    LatLng closest = gps;

    double distSq(LatLng a, LatLng b) {
      final dLon = a.longitude - b.longitude;
      final dLat = a.latitude - b.latitude;
      return dLon * dLon + dLat * dLat;
    }

    for (int i = 0; i < polyline.length - 1; i++) {
      final p1 = polyline[i];
      final p2 = polyline[i + 1];
      
      final l2 = distSq(p1, p2);
      if (l2 == 0.0) {
        final d = distSq(gps, p1);
        if (d < minDistSq) {
          minDistSq = d;
          closest = p1;
        }
        continue;
      }

      double t = ((gps.longitude - p1.longitude) * (p2.longitude - p1.longitude) + 
                  (gps.latitude - p1.latitude) * (p2.latitude - p1.latitude)) / l2;
      if (t < 0.0) t = 0.0;
      if (t > 1.0) t = 1.0;
      
      final projLon = p1.longitude + t * (p2.longitude - p1.longitude);
      final projLat = p1.latitude + t * (p2.latitude - p1.latitude);
      
      final proj = LatLng(projLat, projLon);
      final d = distSq(gps, proj);
      if (d < minDistSq) {
        minDistSq = d;
        closest = proj;
      }
    }
    return closest;
  }

  /// Fetches a road-accurate route from OSRM and stores decoded LatLng points.
  Future<void> _fetchNavRoute(LatLng from, LatLng to) async {
    try {
      final url = Uri.parse(
        'https://router.project-osrm.org/route/v1/driving/'
        '${from.longitude},${from.latitude};'
        '${to.longitude},${to.latitude}'
        '?overview=full&geometries=geojson',
      );
      final res = await http.get(url).timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) return;
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final coords = data['routes'][0]['geometry']['coordinates'] as List;
      final points = coords
          .map((c) => LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble()))
          .toList();
      if (mounted) setState(() => _navRoutePoints = points);
    } catch (e) {
      debugPrint('Nav route fetch error: $e');
    }
  }

  /// Streams the driver's GPS. Updates the `drivers` table for nearby tracking.
  /// If `rideId` is provided, also updates the `rides` table for active trips.
  void _startBroadcastingLocation([String? rideId]) {
    _locationStream?.cancel();
    _locationStream = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 10, // metres before emitting a new position
      ),
    ).listen((position) async {
      final newLoc = LatLng(position.latitude, position.longitude);
      // Update local driver marker
      if (mounted) {
        setState(() => _driverLocation = newLoc);
        if (_acceptedRide != null) {
          // If this is the first GPS fix after accepting, trigger bounds fit
          if (!_hasInitialBoundsFitted && _rideStatus == 'accepted') {
            _fitMapToActiveRoute();
          }

          if (_rideStatus == 'arrived' || _rideStatus == 'in_progress') {
            // Route from PICKUP to DROP-OFF is locked and fixed.
            // Avoid redundant OSRM API calls if we already drew it.
            if (_navRoutePoints.isEmpty) {
              final dropLat = (_acceptedRide!['drop_latitude'] as num).toDouble();
              final dropLng = (_acceptedRide!['drop_longitude'] as num).toDouble();
              final pickupLat = (_acceptedRide!['pickup_latitude'] as num).toDouble();
              final pickupLng = (_acceptedRide!['pickup_longitude'] as num).toDouble();
              _fetchNavRoute(LatLng(pickupLat, pickupLng), LatLng(dropLat, dropLng)).then((_) {
                _fitMapToActiveRoute();
              });
            } else {
              // Smoothly track driver as they head to drop-off
              _fitMapToActiveRoute();
            }
          } else {
            // Route to PICKUP until ride starts (refetch every 10m to keep path accurate)
            final pickupLat = (_acceptedRide!['pickup_latitude'] as num).toDouble();
            final pickupLng = (_acceptedRide!['pickup_longitude'] as num).toDouble();
            _fetchNavRoute(newLoc, LatLng(pickupLat, pickupLng)).then((_) {
               // Smoothly track driver as they head to pickup
               _fitMapToActiveRoute();
            });
          }
        } else {
          // Idle tracking — just slowly pan the map with the driver as they move
          _mapController.move(newLoc, _mapController.camera.zoom);
        }
      }
      
      if (rideId != null) {
        // Push coordinates to Supabase rides table (for customer tracking)
        try {
          await Supabase.instance.client.from('rides').update({
            'driver_latitude':  position.latitude,
            'driver_longitude': position.longitude,
          }).eq('id', rideId);
        } catch (e) {
          debugPrint('Location broadcast error (rides): $e');
        }
      }
      // Also update drivers table so nearby-driver layer stays fresh
      final dbId = _driverDbId;
      if (dbId != null) {
        try {
          await Supabase.instance.client.from('drivers').update({
            'location_latitude':  position.latitude,
            'location_longitude': position.longitude,
          }).eq('id', dbId);
        } catch (e) {
          debugPrint('Location broadcast error (drivers): $e');
        }
      }
    });
  }

  void _stopBroadcastingLocation() {
    _locationStream?.cancel();
    _locationStream = null;
    if (mounted) setState(() => _navRoutePoints = []);
    // Clear GPS from drivers table so customer map removes this car icon
    final dbId = _driverDbId;
    if (dbId != null) {
      Supabase.instance.client.from('drivers').update({
        'location_latitude':  null,
        'location_longitude': null,
      }).eq('id', dbId).then((_) {
        debugPrint('Cleared driver GPS from drivers table.');
      }).catchError((e) {
        debugPrint('Failed to clear driver GPS: $e');
      });
    }
  }

  Future<void> _signOut() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text('Sign Out?',
            style: TextStyle(color: AppColors.textLight)),
        content: const Text('You will need to sign in again to go online.',
            style: TextStyle(color: AppColors.textGrey)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel',
                  style: TextStyle(color: AppColors.textGrey))),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Sign Out',
                  style: TextStyle(color: Colors.redAccent))),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await Supabase.instance.client.auth.signOut();
    if (!mounted) return;
    Navigator.pushNamedAndRemoveUntil(context, '/login', (r) => false);
  }

  // ── Build ───────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D0D),
      body: SafeArea(
        child: Column(
          children: [
            _buildTopBar(),
            Expanded(child: _buildMapArea()),
            _buildEarningsCard(),
          ],
        ),
      ),
    );
  }

  // ── Top Bar ─────────────────────────────────────────────────────────────
  Widget _buildTopBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 16, 12),
      decoration: BoxDecoration(
        color: AppColors.cardDark,
        border: Border(
          bottom: BorderSide(
              color: Colors.white.withValues(alpha: 0.07)),
        ),
      ),
      child: Row(
        children: [
          // Avatar — tappable → driver profile
          GestureDetector(
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => const DriverProfilePage()),
            ),
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    AppColors.primaryYellow,
                    AppColors.primaryYellowDark,
                  ],
                ),
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Text(
                  _firstName[0],
                  style: const TextStyle(
                    color: AppColors.textDark,
                    fontWeight: FontWeight.w900,
                    fontSize: 18,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          // Greeting
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Hey, $_firstName 👋',
                  style: const TextStyle(
                    color: AppColors.textLight,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  child: Row(
                    key: ValueKey(_isOnline),
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 7,
                        height: 7,
                        decoration: BoxDecoration(
                          color: _isOnline ? Colors.greenAccent : Colors.grey,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 5),
                      Text(
                        _isOnline ? 'Online' : 'Offline',
                        style: TextStyle(
                          color: _isOnline
                              ? Colors.greenAccent
                              : AppColors.textGrey,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // Online/Offline toggle
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: _isOnline
                  ? Colors.green.withValues(alpha: 0.15)
                  : Colors.white.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(30),
              border: Border.all(
                color: _isOnline
                    ? Colors.green.withValues(alpha: 0.5)
                    : Colors.white.withValues(alpha: 0.1),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _isOnline ? 'ONLINE' : 'OFFLINE',
                  style: TextStyle(
                    color:
                        _isOnline ? Colors.greenAccent : AppColors.textGrey,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.6,
                  ),
                ),
                const SizedBox(width: 4),
                Transform.scale(
                  scale: 0.75,
                  child: Switch.adaptive(
                    value: _isOnline,
                    onChanged: _toggleOnline,
                    activeColor: Colors.greenAccent,
                    activeTrackColor:
                        Colors.green.withValues(alpha: 0.4),
                    inactiveThumbColor: AppColors.textGrey,
                    inactiveTrackColor:
                        Colors.white.withValues(alpha: 0.1),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          // Sign-out icon
          GestureDetector(
            onTap: _signOut,
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.logout_rounded,
                  color: AppColors.textGrey, size: 18),
            ),
          ),
        ],
      ),

    );
  }

  /// Returns static destination/pickup pins only.
  List<Marker> _getStaticMarkers() {
    final markers = <Marker>[];

    double? pickupLat, pickupLng, dropLat, dropLng;
    if (_acceptedRide != null) {
      pickupLat = (_acceptedRide!['pickup_latitude'] as num?)?.toDouble();
      pickupLng = (_acceptedRide!['pickup_longitude'] as num?)?.toDouble();
      dropLat = (_acceptedRide!['drop_latitude'] as num?)?.toDouble();
      dropLng = (_acceptedRide!['drop_longitude'] as num?)?.toDouble();
    }

    final pickupPoint = (pickupLat != null && pickupLng != null)
        ? LatLng(pickupLat, pickupLng)
        : null;
    final dropPoint = (dropLat != null && dropLng != null)
        ? LatLng(dropLat, dropLng)
        : null;

    // Pickup pin: show when 'accepted' or 'arrived'
    final showPickup =
        _rideStatus == 'accepted' || _rideStatus == 'arrived';
    if (showPickup && pickupPoint != null) {
      markers.add(Marker(
        point: pickupPoint,
        width: 56,
        height: 56,
        child: Container(
          decoration: BoxDecoration(
            color: Colors.greenAccent,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                  color: Colors.greenAccent.withValues(alpha: 0.55),
                  blurRadius: 14,
                  spreadRadius: 3),
            ],
          ),
          child:
              const Icon(Icons.person_pin_circle_rounded, color: Colors.black, size: 32),
        ),
      ));
    }

    // Destination pin: show when 'arrived' or 'in_progress'
    final showDestination =
        _rideStatus == 'arrived' || _rideStatus == 'in_progress';
    if (showDestination && dropPoint != null) {
      markers.add(Marker(
        point: dropPoint,
        width: 56,
        height: 56,
        child: Container(
          decoration: BoxDecoration(
            color: Colors.redAccent,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                  color: Colors.redAccent.withValues(alpha: 0.55),
                  blurRadius: 14,
                  spreadRadius: 3),
            ],
          ),
          child: const Icon(Icons.flag_rounded, color: Colors.black, size: 32),
        ),
      ));
    }

    return markers;
  }

  /// Dedicated driver vehicle marker — separate layer so it is never
  /// hidden by static-pin reconciliation.
  List<Marker> _getDriverMarker() {
    // We always want to render the driver icon if their location is known.
    // It is no longer restricted to just active rides.
    LatLng? point = _driverLocation;

    // Phase-specific overrides for precise visual anchoring
    if (_acceptedRide != null) {
      if (_rideStatus == 'arrived') {
        // Snap precisely to the pickup point
        final pickupLat = (_acceptedRide!['pickup_latitude'] as num?)?.toDouble();
        final pickupLng = (_acceptedRide!['pickup_longitude'] as num?)?.toDouble();
        if (pickupLat != null && pickupLng != null) {
          point = LatLng(pickupLat, pickupLng);
        }
      } else if (_rideStatus == 'in_progress') {
        // Prevent visual jump at the exact moment 'Start Ride' is tapped.
        final pickupLat = (_acceptedRide!['pickup_latitude'] as num?)?.toDouble();
        final pickupLng = (_acceptedRide!['pickup_longitude'] as num?)?.toDouble();
        if (pickupLat != null && pickupLng != null && point != null) {
          final pPt = LatLng(pickupLat, pickupLng);
          
          if (_forcePickupPinLock) {
            point = pPt; // Unconditional lock for laptop/web testing
          } else {
            // Keep the car firmly on the pickup pin until the driver physically 
            // drives away (e.g., > 40 meters), ensuring smooth visual tracking origin.
            final dist = const Distance().as(LengthUnit.Meter, point, pPt);
            if (dist < 40) {
              point = pPt;
            } else {
              // Snap raw live GPS strictly to the active route polyline to remove jitter
              point = _snapToPolyline(point, _navRoutePoints);
            }
          }
        }
      } else if (_rideStatus == 'completed') {
        // Firmly snap and lock precisely to the drop-off point to prevent drift
        final dropLat = (_acceptedRide!['drop_latitude'] as num?)?.toDouble();
        final dropLng = (_acceptedRide!['drop_longitude'] as num?)?.toDouble();
        if (dropLat != null && dropLng != null) {
          point = LatLng(dropLat, dropLng);
        }
      }
    }

    debugPrint('>>> [DriverMarker-DRV] resolved point=$point');

    if (point == null) {
      debugPrint('>>> [DriverMarker-DRV] ❌ point is null — marker SKIPPED');
      return [];
    }

    return [
      Marker(
        point: point,
        width: 56,
        height: 56,
        child: Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            color: AppColors.primaryYellow,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: AppColors.primaryYellow.withValues(alpha: 0.6),
                blurRadius: 16,
                spreadRadius: 4,
              ),
            ],
          ),
          child: const Icon(
            Icons.local_taxi_rounded,
            color: Colors.black,
            size: 30,
          ),
        ),
      ),
    ];
  }

  // ── Map Area ────────────────────────────────────────────────────────────
  Widget _buildMapArea() {
    final center = _driverLocation ?? _defaultCenter;
    return Stack(
      children: [
        // Map background
        FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            initialCenter: center,
            initialZoom: 14.0,
          ),
          children: [
            TileLayer(
              urlTemplate:
                  'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png',
              userAgentPackageName: 'com.taxigo.app',
            ),
            // Navigation polyline — driver → pickup
            if (_navRoutePoints.isNotEmpty)
              PolylineLayer(
                polylines: [
                  Polyline(
                    points: _navRoutePoints,
                    color: const Color(0xFF4FC3F7), // light blue nav line
                    strokeWidth: 5.0,
                    borderColor: Colors.blueAccent.withValues(alpha: 0.4),
                    borderStrokeWidth: 2.0,
                  ),
                ],
              ),
            // Static location pins (pickup + destination)
            MarkerLayer(
              markers: _getStaticMarkers(),
              rotate: true,
            ),
            // Dedicated driver vehicle icon — separate layer so it
            // is NEVER hidden by static-pin reconciliation.
            MarkerLayer(
              markers: _getDriverMarker(),
              rotate: true,
            ),
          ],
        ),

        // Offline overlay
        AnimatedOpacity(
          opacity: _isOnline ? 0.0 : 1.0,
          duration: const Duration(milliseconds: 450),
          child: IgnorePointer(
            ignoring: _isOnline,
            child: Container(
              color: Colors.black.withValues(alpha: 0.72),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(22),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.06),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.power_settings_new_rounded,
                          color: AppColors.textGrey, size: 48),
                    ),
                    const SizedBox(height: 20),
                    const Text(
                      "You're Offline",
                      style: TextStyle(
                        color: AppColors.textLight,
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Toggle the switch above to start\naccepting ride requests',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: AppColors.textGrey.withValues(alpha: 0.8),
                        fontSize: 13,
                        height: 1.5,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),

        // Online pulse badge
        if (_isOnline)
          Positioned(
            top: 16,
            right: 16,
            child: AnimatedBuilder(
              animation: _pulseAnim,
              builder: (context, child) => Transform.scale(
                scale: _pulseAnim.value,
                child: child,
              ),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                decoration: BoxDecoration(
                  color: Colors.green,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.green.withValues(alpha: 0.55),
                      blurRadius: 16,
                      spreadRadius: 3,
                    ),
                  ],
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.circle, color: Colors.white, size: 7),
                    SizedBox(width: 6),
                    Text(
                      'Looking for rides...',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

        // Ride request placeholder card
        AnimatedPositioned(
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeOutCubic,
          bottom: _isOnline ? 20 : -120,
          left: 20,
          right: 20,
          child: _acceptedRide != null ? _buildActiveRideCard() : _buildRideRequestCard(),
        ),
      ],
    );
  }

  Widget _buildRideRequestCard() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: AppColors.primaryYellow.withValues(alpha: 0.25),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.5),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.primaryYellow.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.hail_rounded,
                color: AppColors.primaryYellow, size: 24),
          ),
          const SizedBox(width: 14),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Searching for passengers...',
                  style: TextStyle(
                    color: AppColors.textLight,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                SizedBox(height: 3),
                Text(
                  'Ride requests will appear automatically',
                  style: TextStyle(
                      color: AppColors.textGrey, fontSize: 11),
                ),
              ],
            ),
          ),
          const _ThreeDots(),
        ],
      ),
    );
  }

  Widget _buildActiveRideCard() {
    debugPrint('🔄 UI REBUILDING. Current pending method: $_pendingPaymentMethod');
    final ride = _acceptedRide!;

    // Dynamic content per lifecycle phase
    final phaseConfig = switch (_rideStatus) {
      'arrived' => (
          headline: 'Passenger at pickup',
          subtext: ride['pickup_name'] as String? ?? '',
          badge: 'ARRIVED',
          badgeColor: Colors.orangeAccent,
          icon: Icons.person_pin_circle_rounded,
          btnLabel: 'Start Ride  →',
          btnColor: AppColors.primaryYellow,
          btnFg: Colors.black,
          btnEnabled: true,
        ),
      'in_progress' => (
          headline: 'Heading to drop-off...',
          subtext: ride['drop_name'] as String? ?? '',
          badge: 'IN PROGRESS',
          badgeColor: Colors.blueAccent,
          icon: Icons.flag_rounded,
          btnLabel: 'End Ride  ✓',
          btnColor: Colors.redAccent,
          btnFg: Colors.white,
          btnEnabled: true,
        ),
      'completed' => (() {
        final isCashPending = _pendingPaymentMethod?.toLowerCase() == 'cash';
        return (
          headline: isCashPending
              ? 'Cash payment received?'
              : 'Awaiting payment...',
          subtext: isCashPending
              ? '💵  LKR ${_completedFare.toStringAsFixed(0)} — confirm cash receipt'
              : 'LKR ${_completedFare.toStringAsFixed(0)} — waiting for customer',
          badge: 'PAYMENT',
          badgeColor: isCashPending
              ? Colors.amberAccent
              : AppColors.primaryYellow,
          icon: Icons.payments_rounded,
          btnLabel: isCashPending
              ? '✓  Confirm Cash Received'
              : 'Waiting for Payment...',
          btnColor: isCashPending
              ? Colors.amberAccent
              : Colors.white.withValues(alpha: 0.1),
          btnFg: isCashPending ? Colors.black : Colors.white38,
          btnEnabled: isCashPending,
        );
      })(),
      _ => (
          headline: 'Heading to pickup...',
          subtext: ride['pickup_name'] as String? ?? '',
          badge: 'ACCEPTED',
          badgeColor: Colors.greenAccent,
          icon: Icons.navigation_rounded,
          btnLabel: "I've Arrived",
          btnColor: Colors.greenAccent,
          btnFg: Colors.black,
          btnEnabled: true,
        ),
    };

    final nextStatus = switch (_rideStatus) {
      'arrived'     => 'in_progress',
      'in_progress' => 'completed',
      _             => 'arrived',
    };

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.green.shade900.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.greenAccent.withValues(alpha: 0.5)),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.5), blurRadius: 24, offset: const Offset(0, 8)),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(11),
                decoration: BoxDecoration(
                  color: phaseConfig.badgeColor.withValues(alpha: 0.18),
                  shape: BoxShape.circle,
                ),
                child: Icon(phaseConfig.icon, color: phaseConfig.badgeColor, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      phaseConfig.headline,
                      style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      phaseConfig.subtext,
                      style: const TextStyle(color: Colors.greenAccent, fontSize: 12),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              // Status pill
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: phaseConfig.badgeColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: phaseConfig.badgeColor.withValues(alpha: 0.5)),
                ),
                child: Text(
                  phaseConfig.badge,
                  style: TextStyle(color: phaseConfig.badgeColor, fontSize: 9, fontWeight: FontWeight.w900, letterSpacing: 0.8),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          // Action button — behaviour differs for 'completed' (cash confirm) vs others
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: phaseConfig.btnColor,
                foregroundColor: phaseConfig.btnFg,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                elevation: 0,
              ),
              onPressed: phaseConfig.btnEnabled
                  ? () async {
                      final isCashPending = _pendingPaymentMethod?.toLowerCase() == 'cash';
                      if (_rideStatus == 'completed' && isCashPending) {
                        // Confirm cash: write paid, clear ride, show success
                        final rideId = _completedRideId ?? '';
                        final fare   = _completedFare;
                        try {
                          await Supabase.instance.client
                              .from('rides')
                              .update({'payment_status': 'paid'})
                              .eq('id', rideId);
                          _paymentChannel?.unsubscribe();
                          _paymentChannel = null;
                          _clearActiveRide();
                          if (mounted) _showPaymentReceivedDialog(fare, method: 'cash');
                        } catch (e) {
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Error: $e'),
                                backgroundColor: Colors.redAccent,
                                behavior: SnackBarBehavior.floating,
                              ),
                            );
                          }
                        }
                      } else {
                        _updateRideStatus(nextStatus);
                      }
                    }
                  : null,
              child: Text(
                phaseConfig.btnLabel,
                style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Earnings Summary Card ───────────────────────────────────────────────
  Widget _buildEarningsCard() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
      decoration: BoxDecoration(
        color: AppColors.cardDark,
        border: Border(
          top: BorderSide(color: Colors.white.withValues(alpha: 0.07)),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              const Text(
                "Today's Summary",
                style: TextStyle(
                  color: AppColors.textLight,
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const Spacer(),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.primaryYellow.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text(
                  'Today',
                  style: TextStyle(
                    color: AppColors.primaryYellow,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          IntrinsicHeight(
            child: Row(
              children: [
                _StatTile(
                  icon: Icons.payments_rounded,
                  label: 'Earnings',
                  value: 'LKR ${_todayEarnings.toInt()}',
                  valueColor: AppColors.primaryYellow,
                  iconColor: AppColors.primaryYellow,
                ),
                _VerticalDivider(),
                _StatTile(
                  icon: Icons.directions_car_rounded,
                  label: 'Rides',
                  value: '$_todayRides',
                ),
                _VerticalDivider(),
                _StatTile(
                  icon: Icons.access_time_rounded,
                  label: 'Online',
                  value: _onlineHours,
                ),
                _VerticalDivider(),
                _StatTile(
                  icon: Icons.star_rounded,
                  label: 'Rating',
                  value: '$_rating ⭐',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}



// ── Stat Tile ──────────────────────────────────────────────────────────────
class _StatTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color valueColor;
  final Color iconColor;

  const _StatTile({
    required this.icon,
    required this.label,
    required this.value,
    this.valueColor = AppColors.textLight,
    this.iconColor = AppColors.textGrey,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: iconColor, size: 18),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              color: valueColor,
              fontSize: 13,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(
              color: AppColors.textGrey,
              fontSize: 10,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _VerticalDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 44,
      color: Colors.white.withValues(alpha: 0.08),
    );
  }
}

// ── Three loading dots ─────────────────────────────────────────────────────
class _ThreeDots extends StatefulWidget {
  const _ThreeDots();

  @override
  State<_ThreeDots> createState() => _ThreeDotsState();
}

class _ThreeDotsState extends State<_ThreeDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 900))
      ..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, child) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (i) {
            final delay = i / 3;
            final raw = (_ctrl.value - delay) % 1.0;
            final opacity = (math.sin(raw * math.pi)).clamp(0.2, 1.0);
            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 2),
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                color: AppColors.primaryYellow.withValues(alpha: opacity),
                shape: BoxShape.circle,
              ),
            );
          }),
        );
      },
    );
  }
}

// ── Route Row (used in ride request popup) ────────────────────────────────
class _RouteRow extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String label;
  final String name;

  const _RouteRow({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.name,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: iconColor, size: 20),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  color: AppColors.textGrey,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                name,
                style: const TextStyle(
                  color: AppColors.textLight,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
