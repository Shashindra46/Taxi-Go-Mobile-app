import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/widgets/custom_button.dart';

class CustomerHomePage extends StatefulWidget {
  const CustomerHomePage({super.key});

  @override
  State<CustomerHomePage> createState() => _CustomerHomePageState();
}

class _CustomerHomePageState extends State<CustomerHomePage>
    with SingleTickerProviderStateMixin {
  final _pickupController = TextEditingController();
  final _destinationController = TextEditingController();
  bool _isSearching = false;
  String _selectedVehicle = 'tuk';

  final MapController _mapController = MapController();
  LatLng? _currentLocation;
  LatLng? _pickupLocation;
  LatLng? _destinationLocation;
  List<LatLng> _routePoints = [];
  double _calculatedDistanceKm = 0.0;
  int _calculatedDurationMins = 0;

  Timer? _debounce;
  List<dynamic> _pickupSuggestions = [];
  List<dynamic> _destSuggestions = [];
  String? _activeRideId; // tracks the DB row to delete on cancel

  // ── Live Driver Tracking ─────────────────────────────────────────────
  LatLng? _driverLiveLocation;
  List<LatLng> _driverToPickupRoutePoints = []; // OSRM route: driver → pickup
  StreamSubscription<List<Map<String, dynamic>>>? _rideStatusSubscription;
  bool _isRideAccepted = false;
  Map<String, dynamic>? _activeRideData;
  /// Current sub-status of an accepted ride for customer-facing UI.
  /// 'idle' = no active ride | 'accepted' | 'arrived' | 'in_progress'
  String _ridePhase = 'idle'; // ← default: no ride active
  bool _hasInitialBoundsFitted = false;
  bool _forcePickupPinLock = false;

  // ── Nearby Online Drivers ─────────────────────────────────────────────
  /// Rows from `drivers` table where status = 'online' with live GPS.
  List<Map<String, dynamic>> _nearbyDrivers = [];
  Timer? _nearbyDriversTimer;

  late final AnimationController _pulseCtrl;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
    
    _checkPermissionsAndGetLocation();
    // Start polling for nearby online drivers every 15 s
    _nearbyDriversTimer = Timer.periodic(
      const Duration(seconds: 15),
      (_) => _fetchNearbyDrivers(),
    );
    _fetchNearbyDrivers(); // immediate first load
  }

  Future<void> _checkPermissionsAndGetLocation() async {
    bool serviceEnabled;
    LocationPermission permission;

    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return; // Location services are disabled
    }

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        return; // Permissions are denied
      }
    }
    
    if (permission == LocationPermission.deniedForever) {
      return; // Permissions are permanently denied
    } 

    final position = await Geolocator.getCurrentPosition();
    if (!mounted) return;
    
    setState(() {
      _currentLocation = LatLng(position.latitude, position.longitude);
    });
    
    _mapController.move(_currentLocation!, 15.0);
  }

  void _onSearchChanged(String query, bool isPickup) {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    
    if (query.length < 3) {
      setState(() {
        if (isPickup) {
          _pickupSuggestions = [];
        } else {
          _destSuggestions = [];
        }
      });
      return;
    }

    _debounce = Timer(const Duration(milliseconds: 500), () async {
      final url = Uri.parse('https://nominatim.openstreetmap.org/search?q=${Uri.encodeComponent(query)}&format=json&countrycodes=lk&addressdetails=1&limit=5');
      try {
        final res = await http.get(url);
        if (res.statusCode == 200) {
          final List data = json.decode(res.body);
          if (mounted) {
            setState(() {
              if (isPickup) {
                _pickupSuggestions = data;
              } else {
                _destSuggestions = data;
              }
            });
          }
        }
      } catch (e) {
        debugPrint('Geocode error: $e');
      }
    });
  }

  /// Uses OSRM Nearest API to instantly snap raw geocoded points (which might
  /// land in the sea or inside buildings) to the nearest drivable road network.
  Future<LatLng> _snapToRoad(LatLng point) async {
    try {
      final url = Uri.parse('https://router.project-osrm.org/nearest/v1/driving/${point.longitude},${point.latitude}');
      final res = await http.get(url).timeout(const Duration(seconds: 4));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final waypoints = data['waypoints'] as List?;
        if (waypoints != null && waypoints.isNotEmpty) {
          final loc = waypoints[0]['location'] as List; // [lon, lat]
          return LatLng((loc[1] as num).toDouble(), (loc[0] as num).toDouble());
        }
      }
    } catch (e) {
      debugPrint('OSRM Nearest error: $e');
    }
    return point; // fallback to original
  }

  Future<void> _fetchRouteAndDraw() async {
    final pickupText = _pickupController.text.trim();
    final destinationText = _destinationController.text.trim();
    if (destinationText.isEmpty) return;
    
    try {
      // 1. Geocode Pickup if not already selected
      if (_pickupLocation == null) {
        LatLng? activePickup = _currentLocation;
        if (pickupText.isNotEmpty && pickupText.toLowerCase() != 'current location') {
          final pickupUrl = Uri.parse('https://nominatim.openstreetmap.org/search?q=${Uri.encodeComponent(pickupText)}&format=json&countrycodes=lk&addressdetails=1&limit=1');
          final pickupRes = await http.get(pickupUrl);
          if (pickupRes.statusCode == 200) {
            final List data = json.decode(pickupRes.body);
            if (data.isNotEmpty) {
              final lat = double.parse(data[0]['lat'].toString());
              final lon = double.parse(data[0]['lon'].toString());
              activePickup = await _snapToRoad(LatLng(lat, lon));
            }
          }
        }

        if (activePickup == null) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not determine pickup location.')));
          return;
        }
        setState(() => _pickupLocation = activePickup);
      }

      // 2. Geocode Destination if not already selected
      if (_destinationLocation == null) {
        final nomUrl = Uri.parse('https://nominatim.openstreetmap.org/search?q=${Uri.encodeComponent(destinationText)}&format=json&countrycodes=lk&addressdetails=1&limit=1');
        final nomRes = await http.get(nomUrl);
        if (nomRes.statusCode == 200) {
          final List data = json.decode(nomRes.body);
          if (data.isNotEmpty) {
            final lat = double.parse(data[0]['lat'].toString());
            final lon = double.parse(data[0]['lon'].toString());
            final snapped = await _snapToRoad(LatLng(lat, lon));
            setState(() => _destinationLocation = snapped);
          } else {
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Destination not found.')));
            return;
          }
        }
      }
      
      if (_destinationLocation == null || _pickupLocation == null) return;

      // 3. Fetch OSRM Route
      final start = '${_pickupLocation!.longitude},${_pickupLocation!.latitude}';
      final end = '${_destinationLocation!.longitude},${_destinationLocation!.latitude}';
      final osrmUrl = Uri.parse('https://router.project-osrm.org/route/v1/driving/$start;$end?overview=full&geometries=geojson');
      
      final osrmRes = await http.get(osrmUrl);
      if (osrmRes.statusCode == 200) {
        final osrmData = json.decode(osrmRes.body);
        final routes = osrmData['routes'] as List;
        if (routes.isNotEmpty) {
          final geometry = routes[0]['geometry']['coordinates'] as List;
          final distanceInMeters = routes[0]['distance'] as num;
          final durationInSeconds = routes[0]['duration'] as num;
          
          // OSRM automatically snaps the requested coordinates to the nearest valid road.
          // Nominatim sometimes returns geographic centers (which may be in the sea for coastal towns).
          // We update our pins to the snapped road coordinates so they align perfectly with the route.
          final waypoints = osrmData['waypoints'] as List?;
          LatLng? snappedPickup;
          LatLng? snappedDest;
          if (waypoints != null && waypoints.length >= 2) {
            final w0 = waypoints[0]['location'] as List; // [lon, lat]
            final w1 = waypoints[1]['location'] as List;
            snappedPickup = LatLng((w0[1] as num).toDouble(), (w0[0] as num).toDouble());
            snappedDest = LatLng((w1[1] as num).toDouble(), (w1[0] as num).toDouble());
          }
          
          setState(() {
            if (snappedPickup != null) _pickupLocation = snappedPickup;
            if (snappedDest != null) _destinationLocation = snappedDest;

            _calculatedDistanceKm = distanceInMeters / 1000;
            _calculatedDurationMins = (durationInSeconds / 60).round();
            _routePoints = geometry.map((coord) {
              return LatLng(coord[1] as double, coord[0] as double);
            }).toList();
          });
          
          if (_routePoints.isNotEmpty) {
            _mapController.fitCamera(
              CameraFit.bounds(
                bounds: LatLngBounds.fromPoints([_pickupLocation!, _destinationLocation!, ..._routePoints]),
                padding: const EdgeInsets.only(top: 100, left: 60, right: 60, bottom: 250), // Safer for bottom sheets
              ),
            );
          }
        }
      }
    } catch (e) {
      debugPrint('Routing error: $e');
    }
  }

  /// Fetches drivers from Supabase whose status is 'online' and who have
  /// a live GPS location stored in the `drivers` table.
  Future<void> _fetchNearbyDrivers() async {
    if (!mounted) return;
    try {
      final rows = await Supabase.instance.client
          .from('drivers')
          .select('id, location_latitude, location_longitude')
          .eq('status', 'online')
          .not('location_latitude', 'is', null)
          .not('location_longitude', 'is', null);
      if (mounted) {
        setState(() => _nearbyDrivers = List<Map<String, dynamic>>.from(rows));
      }
    } catch (e) {
      debugPrint('Nearby drivers fetch error: $e');
      // Silently swallow — columns may not exist yet; map stays clean.
    }
  }

  @override
  void dispose() {
    _nearbyDriversTimer?.cancel();
    _debounce?.cancel();
    _rideStatusSubscription?.cancel();
    _pickupController.dispose();
    _destinationController.dispose();
    _pulseCtrl.dispose();
    super.dispose();
  }



  Future<void> _requestRide() async {
    // Guard: both fields must have confirmed geocoded locations
    if (_pickupLocation == null || _destinationLocation == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select a valid pickup and destination from the suggestions.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() => _isSearching = true);

    try {
      final uid = Supabase.instance.client.auth.currentUser?.id;
      if (uid == null) throw Exception('User not authenticated.');

      final fare = _calculatePrice(_selectedVehicle).toDouble();

      final response = await Supabase.instance.client.from('rides').insert({
        'customer_id':       uid,
        'pickup_name':       _pickupController.text.trim(),
        'pickup_latitude':   _pickupLocation!.latitude,
        'pickup_longitude':  _pickupLocation!.longitude,
        'drop_name':         _destinationController.text.trim(),
        'drop_latitude':     _destinationLocation!.latitude,
        'drop_longitude':    _destinationLocation!.longitude,
        'vehicle_type':      _selectedVehicle,
        'fare':              fare,
        'status':            'pending',
      }).select('id').single();

      setState(() => _activeRideId = response['id'] as String?);

      // Begin listening for driver location updates
      if (_activeRideId != null) _listenToRideStatus(_activeRideId!);

    } catch (e) {
      if (!mounted) return;
      setState(() => _isSearching = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to request ride: $e'),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  Future<void> _cancelSearch() async {
    // Delete the pending ride row from the DB if one was created
    if (_activeRideId != null) {
      try {
        await Supabase.instance.client
            .from('rides')
            .delete()
            .eq('id', _activeRideId!)
            .eq('status', 'pending');
      } catch (e) {
        debugPrint('Failed to cancel ride in DB: $e');
      }
    }

    _rideStatusSubscription?.cancel();
    _rideStatusSubscription = null;

    setState(() {
      _isSearching = false;
      _isRideAccepted = false;
      _ridePhase = 'idle'; // reset so no ghost driver marker shows
      _hasInitialBoundsFitted = false; // Reset bounds flag
      _activeRideData = null;
      _activeRideId = null;
      _driverLiveLocation = null;
      _driverToPickupRoutePoints = [];
      _pickupController.clear();
      _destinationController.clear();
      _routePoints.clear();
      _destinationLocation = null;
      _pickupLocation = null;
      _calculatedDistanceKm = 0.0;
      _calculatedDurationMins = 0;
      _pickupSuggestions.clear();
      _destSuggestions.clear();
    });
  }

  /// Subscribe to realtime updates for the active ride row.
  /// Reads driver_latitude / driver_longitude whenever the driver moves.
  void _listenToRideStatus(String rideId) {
    _rideStatusSubscription?.cancel();
    _rideStatusSubscription = Supabase.instance.client
        .from('rides')
        .stream(primaryKey: ['id'])
        .eq('id', rideId)
        .listen((rows) {
      if (rows.isEmpty || !mounted) return;
      final row = rows.first;

      // Update driver marker when coordinates arrive
      final driverLat = row['driver_latitude'];
      final driverLng = row['driver_longitude'];
      if (driverLat != null && driverLng != null) {
        final newDriverLoc = LatLng(
          (driverLat as num).toDouble(),
          (driverLng as num).toDouble(),
        );
        setState(() => _driverLiveLocation = newDriverLoc);

        if (_ridePhase == 'in_progress' || _ridePhase == 'arrived') {
          // Route from PICKUP to DROP-OFF is locked and fixed.
          final dropLat = (row['drop_latitude'] as num?)?.toDouble();
          final dropLng = (row['drop_longitude'] as num?)?.toDouble();
          final pickupLat = (row['pickup_latitude'] as num?)?.toDouble();
          final pickupLng = (row['pickup_longitude'] as num?)?.toDouble();
          if (dropLat != null && dropLng != null && pickupLat != null && pickupLng != null) {
            if (_driverToPickupRoutePoints.isEmpty) {
              _fetchDriverToDropRoute(LatLng(pickupLat, pickupLng), LatLng(dropLat, dropLng));
            }
          }
          // Intelligently fit bounds to include the driver without cropping route
          _fitMapToCustomerActiveRoute();
        } else {
          // Heading to pickup: route from driver to PICKUP
          final pickupPt = _pickupLocation ?? _currentLocation;
          if (pickupPt != null) {
            // Update route as driver approaches
            _fetchDriverIncomingRoute(newDriverLoc, pickupPt);
            // Snap map bounds to include driver and pickup properly
            if (!_hasInitialBoundsFitted) {
              _fitMapToCustomerActiveRoute();
            } else {
               // Subtly re-frame if needed, or rely on original bounds 
               _fitMapToCustomerActiveRoute();
            }
          }
        }
      }

      // React to status changes
      final status = row['status'] as String?;
      if (status == 'accepted' && mounted && !_isRideAccepted) {
        setState(() {
          _isSearching = false;
          _isRideAccepted = true;
          _ridePhase = 'accepted';
          _hasInitialBoundsFitted = false; // reset for new ride bounds
          _activeRideData = row;
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('🚕  Driver accepted! They are on their way.'),
              backgroundColor: Colors.green,
              behavior: SnackBarBehavior.floating,
              duration: Duration(seconds: 3),
            ),
          );
        }
      } else if (status == 'arrived' && mounted && _ridePhase != 'arrived') {
        // Clear driver→pickup lines; immediately draw route from pickup to drop-off
        final dropLat = (row['drop_latitude'] as num?)?.toDouble();
        final dropLng = (row['drop_longitude'] as num?)?.toDouble();
        final pickupLat = (row['pickup_latitude'] as num?)?.toDouble();
        final pickupLng = (row['pickup_longitude'] as num?)?.toDouble();

        setState(() {
          _ridePhase = 'arrived';
          _activeRideData = row;
          _driverToPickupRoutePoints = []; // erase driver→pickup route
          _routePoints               = []; // erase booking preview route
        });
        
        if (dropLat != null && dropLng != null && pickupLat != null && pickupLng != null) {
          final pickupPt = LatLng(pickupLat, pickupLng);
          final dropPt = LatLng(dropLat, dropLng);
          _fetchDriverToDropRoute(pickupPt, dropPt).then((_) {
            _fitMapToCustomerActiveRoute();
          });
        }
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('📍  Your driver has arrived at the pickup location!'),
              backgroundColor: Colors.orange,
              behavior: SnackBarBehavior.floating,
              duration: Duration(seconds: 3),
            ),
          );
        }
      } else if (status == 'in_progress' && mounted && _ridePhase != 'in_progress') {
        // Wipe BOTH polylines synchronously so the map clears instantly
        setState(() {
          _ridePhase = 'in_progress';
          _activeRideData = row;
          _routePoints = [];              // erase original booking route
          _forcePickupPinLock = true;
        });
        
        // Unconditionally lock to pickup pin for 4 seconds for web/laptop testing
        Future.delayed(const Duration(seconds: 4), () {
          if (mounted) { setState(() => _forcePickupPinLock = false); }
        });
        // Re-draw route from PICKUP to DROP-OFF
        final dropLat = (row['drop_latitude'] as num?)?.toDouble();
        final dropLng = (row['drop_longitude'] as num?)?.toDouble();
        final pickupLat = (row['pickup_latitude'] as num?)?.toDouble();
        final pickupLng = (row['pickup_longitude'] as num?)?.toDouble();

        if (dropLat != null && dropLng != null && pickupLat != null && pickupLng != null) {
          final pickupPt = LatLng(pickupLat, pickupLng);
          final dropPt = LatLng(dropLat, dropLng);
          _fetchDriverToDropRoute(pickupPt, dropPt).then((_) {
            _fitMapToCustomerActiveRoute();
          });
        }
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('🚀  Your ride has started! Heading to your destination.'),
              backgroundColor: Colors.blueAccent,
              behavior: SnackBarBehavior.floating,
              duration: Duration(seconds: 3),
            ),
          );
        }
      } else if (status == 'completed' && mounted) {
        final fare   = (_activeRideData?['fare'] as num?)?.toDouble() ?? 0.0;
        final rideId = _activeRideId ?? '';
        _rideStatusSubscription?.cancel();
        _rideStatusSubscription = null;
        // Reset map / ride state immediately
        setState(() {
          _isRideAccepted = false;
          _isSearching    = false;
          _ridePhase      = 'idle'; // reset to idle so no ghost driver marker
          _activeRideData = null;
          _driverLiveLocation        = null; // Removes driver car icon
          _driverToPickupRoutePoints = [];   // Removes path
          _routePoints               = [];   // Removes path
          _pickupLocation            = null; // Removes pickup flag
          _destinationLocation       = null; // Removes destination flag
        });
        if (_currentLocation != null) {
          _mapController.move(_currentLocation!, 15.0);
        }
        // Show payment selection instead of jumping to rating
        if (rideId.isNotEmpty) _showPaymentMethodDialog(rideId, fare);
      } else if (status == 'cancelled' && mounted) {
        _cancelSearch();
      }
    });
  }

  /// Consolidates robust camera bounds fitting logic for the customer map.
  /// Guarantees that the entire route polyline (and driver) fits on screen without crashing.
  Future<void> _fitMapToCustomerActiveRoute() async {
    final ride = _activeRideData;
    if (ride == null) return;
    
    final pickupLat = (ride['pickup_latitude'] as num?)?.toDouble();
    final pickupLng = (ride['pickup_longitude'] as num?)?.toDouble();
    final dropLat = (ride['drop_latitude'] as num?)?.toDouble();
    final dropLng = (ride['drop_longitude'] as num?)?.toDouble();

    if (pickupLat == null || pickupLng == null) return;
    final pickupPt = LatLng(pickupLat, pickupLng);

    if (_ridePhase == 'accepted') {
      if (_driverLiveLocation == null) return;
      _hasInitialBoundsFitted = true;
      
      try {
        _mapController.fitCamera(
          CameraFit.bounds(
            bounds: LatLngBounds.fromPoints([
              _driverLiveLocation!, 
              pickupPt,
              ..._driverToPickupRoutePoints, // Ensure curved incoming route fits
            ]),
            padding: const EdgeInsets.only(top: 100, left: 60, right: 60, bottom: 250),
          ),
        );
      } catch (e) {
        debugPrint('>>> [CustomerMapFitError] accepted phase: $e');
      }
    } else if (_ridePhase == 'arrived' || _ridePhase == 'in_progress') {
      if (dropLat == null || dropLng == null) return;
      final dropPt = LatLng(dropLat, dropLng);
      
      try {
        _mapController.fitCamera(
          CameraFit.bounds(
            bounds: LatLngBounds.fromPoints([
              pickupPt, 
              dropPt,
              // If driver is en-route to dropoff, include their live pos so marker isn't culled
              if (_ridePhase == 'in_progress' && _driverLiveLocation != null) _driverLiveLocation!,
              ..._routePoints, // Full trip polyline
            ]),
            padding: const EdgeInsets.only(top: 100, left: 60, right: 60, bottom: 250),
          ),
        );
      } catch (e) {
        debugPrint('>>> [CustomerMapFitError] in_progress phase: $e');
      }
    }
  }

  // ── Payment Flow ───────────────────────────────────────────────────────────
  void _showPaymentMethodDialog(String rideId, double fare) {
    _pickupController.clear();
    _destinationController.clear();
    setState(() {
      _routePoints.clear();
      _pickupLocation      = null;
      _destinationLocation = null;
      _activeRideId        = null;
      _calculatedDistanceKm   = 0.0;
      _calculatedDurationMins = 0;
    });

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Dialog(
        backgroundColor: const Color(0xFF1A1A1A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header
              Container(
                width: 68, height: 68,
                decoration: BoxDecoration(
                  color: AppColors.primaryYellow.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.payments_rounded,
                    color: AppColors.primaryYellow, size: 36),
              ),
              const SizedBox(height: 16),
              const Text('Choose Payment Method',
                  style: TextStyle(
                    color: AppColors.textLight, fontSize: 20, fontWeight: FontWeight.w900)),
              const SizedBox(height: 6),
              Text('Total Fare: LKR ${fare.toStringAsFixed(0)}',
                  style: const TextStyle(color: AppColors.primaryYellow,
                      fontSize: 15, fontWeight: FontWeight.w700)),
              const SizedBox(height: 24),

              // Cash tile
              _PaymentOptionTile(
                icon: Icons.money,
                label: 'Cash',
                subtitle: 'Pay the driver directly',
                color: Colors.greenAccent,
                onTap: () async {
                  Navigator.pop(ctx);
                  await _submitCashPayment(rideId, fare);
                },
              ),
              const SizedBox(height: 12),

              // Card tile
              _PaymentOptionTile(
                icon: Icons.credit_card_rounded,
                label: 'Card',
                subtitle: 'Pay securely with card',
                color: Colors.blueAccent,
                onTap: () {
                  Navigator.pop(ctx);
                  _showCardPaymentDialog(rideId, fare);
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _submitCashPayment(String rideId, double fare) async {
    debugPrint('🚀 [CashPayment] Initiating update for rideId: $rideId');
    debugPrint('🚀 [CashPayment] Payload to send: {payment_method: cash, payment_status: pending}');
    try {
      await Supabase.instance.client.from('rides').update({
        'payment_method': 'cash',
        'payment_status': 'pending',
      }).eq('id', rideId);
      debugPrint('✅ [CashPayment] DB update success for ride $rideId');
    } catch (e) {
      debugPrint('❌ [CashPayment] Supabase Cash Update Error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Payment update failed: $e'),
            backgroundColor: Colors.redAccent,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return; // Don't show waiting dialog if update failed
    }

    if (!mounted) return;
    // Show waiting screen — streams Supabase until driver confirms
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _CashWaitingDialog(
        rideId: rideId,
        fare: fare,
        onPaid: () {
          Navigator.pop(ctx);
          _showRatingDialog(fare);
        },
      ),
    );
  }

  void _showCardPaymentDialog(String rideId, double fare) {
    final cardCtrl   = TextEditingController();
    final expiryCtrl = TextEditingController();
    final cvvCtrl    = TextEditingController();
    final formKey    = GlobalKey<FormState>();
    bool submitting  = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => Dialog(
          backgroundColor: const Color(0xFF1A1A1A),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 44, height: 44,
                        decoration: BoxDecoration(
                          color: Colors.blueAccent.withValues(alpha: 0.12),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.credit_card_rounded,
                            color: Colors.blueAccent, size: 24),
                      ),
                      const SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Card Payment',
                              style: TextStyle(
                                  color: AppColors.textLight,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w900)),
                          Text('LKR ${fare.toStringAsFixed(0)}',
                              style: const TextStyle(
                                  color: AppColors.primaryYellow,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700)),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),

                  // Card number
                  _cardField(
                    controller: cardCtrl,
                    label: 'Card Number',
                    hint: '1234  5678  9012  3456',
                    icon: Icons.credit_card,
                    maxLength: 19,
                    keyboardType: TextInputType.number,
                    validator: (v) => (v == null || v.replaceAll(' ', '').length < 16)
                        ? 'Enter a valid 16-digit card number' : null,
                    onChanged: (v) {
                      // Auto-insert spaces
                      final digits = v.replaceAll(' ', '');
                      if (digits.length <= 16) {
                        final formatted = RegExp(r'.{1,4}')
                            .allMatches(digits)
                            .map((m) => m.group(0)!)
                            .join('  ');
                        if (formatted != v) {
                          cardCtrl.value = TextEditingValue(
                            text: formatted,
                            selection: TextSelection.collapsed(
                                offset: formatted.length));
                        }
                      }
                    },
                  ),
                  const SizedBox(height: 14),

                  Row(
                    children: [
                      Expanded(
                        child: _cardField(
                          controller: expiryCtrl,
                          label: 'Expiry',
                          hint: 'MM/YY',
                          icon: Icons.calendar_today_rounded,
                          maxLength: 5,
                          keyboardType: TextInputType.number,
                          validator: (v) =>
                              (v == null || v.length < 5) ? 'MM/YY' : null,
                          onChanged: (v) {
                            if (v.length == 2 && !v.contains('/')) {
                              expiryCtrl.text = '$v/';
                              expiryCtrl.selection = TextSelection.collapsed(
                                  offset: expiryCtrl.text.length);
                            }
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _cardField(
                          controller: cvvCtrl,
                          label: 'CVV',
                          hint: '•••',
                          icon: Icons.lock_rounded,
                          maxLength: 3,
                          obscure: true,
                          keyboardType: TextInputType.number,
                          validator: (v) =>
                              (v == null || v.length < 3) ? 'Enter CVV' : null,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),

                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blueAccent,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16)),
                        elevation: 0,
                      ),
                      onPressed: submitting
                          ? null
                          : () async {
                              if (!formKey.currentState!.validate()) return;
                              setSt(() => submitting = true);
                              try {
                                await Supabase.instance.client
                                    .from('rides')
                                    .update({
                                  'payment_method': 'card',
                                  'payment_status': 'paid',
                                }).eq('id', rideId);
                                if (!mounted) return;
                                final nav = Navigator.of(context);
                                nav.pop();
                                if (mounted) _showRatingDialog(fare);
                              } catch (e) {
                                setSt(() => submitting = false);
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text('Payment failed: $e'),
                                      backgroundColor: Colors.redAccent,
                                    ),
                                  );
                                }
                              }
                            },
                      child: submitting
                          ? const SizedBox(
                              height: 20, width: 20,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white))
                          : const Text('🔒  Submit Payment',
                              style: TextStyle(
                                  fontWeight: FontWeight.w900, fontSize: 16)),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Center(
                    child: TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('Cancel',
                          style: TextStyle(color: AppColors.textGrey)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _cardField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    required int maxLength,
    TextInputType keyboardType = TextInputType.text,
    bool obscure = false,
    String? Function(String?)? validator,
    void Function(String)? onChanged,
  }) {
    return TextFormField(
      controller: controller,
      obscureText: obscure,
      keyboardType: keyboardType,
      maxLength: maxLength,
      style: const TextStyle(color: AppColors.textLight, fontSize: 15),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        hintStyle: TextStyle(color: AppColors.textGrey.withValues(alpha: 0.5)),
        labelStyle: const TextStyle(color: AppColors.textGrey),
        prefixIcon: Icon(icon, color: AppColors.textGrey, size: 18),
        counterText: '',
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.05),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Colors.blueAccent, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Colors.redAccent),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Colors.redAccent, width: 1.5),
        ),
      ),
      validator: validator,
      onChanged: onChanged,
    );
  }

  void _showRatingDialog(double fare) {
    // ignore: prefer_final_locals — mutable dialog-local state updated by setSt()
    int selectedRating = 5;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => Dialog(
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
                    color: AppColors.primaryYellow.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.check_circle_rounded,
                      color: AppColors.primaryYellow, size: 40),
                ),
                const SizedBox(height: 20),
                const Text('Ride Completed!',
                    style: TextStyle(
                        color: AppColors.textLight,
                        fontSize: 22,
                        fontWeight: FontWeight.w900)),
                const SizedBox(height: 8),
                const Text('Thanks for riding with TaxiGo.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppColors.textGrey, fontSize: 13)),
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 24),
                  decoration: BoxDecoration(
                    color: AppColors.primaryYellow.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                        color: AppColors.primaryYellow.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.payments_rounded,
                          color: AppColors.primaryYellow, size: 20),
                      const SizedBox(width: 8),
                      Text('LKR ${fare.toStringAsFixed(0)}',
                          style: const TextStyle(
                              color: AppColors.primaryYellow,
                              fontSize: 22,
                              fontWeight: FontWeight.w900)),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                const Text('Rate your ride:',
                    style: TextStyle(color: AppColors.textGrey, fontSize: 13)),
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(5, (i) => GestureDetector(
                    onTap: () => setSt(() => selectedRating = i + 1),
                    child: Icon(
                      i < selectedRating
                          ? Icons.star_rounded
                          : Icons.star_outline_rounded,
                      color: Colors.amber,
                      size: 34,
                    ),
                  )),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primaryYellow,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16)),
                      elevation: 0,
                    ),
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('Done',
                        style: TextStyle(
                            fontWeight: FontWeight.w900, fontSize: 16)),
                  ),
                ),
              ],
            ),
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

  /// Fetches the road-accurate path from the driver's live position to the
  /// passenger's pickup point and stores it in [_driverToPickupRoutePoints].
  Future<void> _fetchDriverIncomingRoute(LatLng from, LatLng to) async {
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
      if (mounted) setState(() => _driverToPickupRoutePoints = points);
    } catch (e) {
      debugPrint('Driver incoming route error: $e');
    }
  }

  /// Fetches the road-accurate path from the driver's live position to the
  /// DROP-OFF point once the ride is in_progress.
  /// Reuses [_driverToPickupRoutePoints] so the existing PolylineLayer
  /// automatically re-renders without any widget changes.
  Future<void> _fetchDriverToDropRoute(LatLng from, LatLng to) async {
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
      if (!mounted) return;
      setState(() => _driverToPickupRoutePoints = points);
      // Re-fit camera around the new drop-off route
      if (points.length >= 2) {
        try {
          _mapController.fitCamera(
            CameraFit.bounds(
              bounds: LatLngBounds.fromPoints(points),
              padding: const EdgeInsets.fromLTRB(60, 120, 60, 320),
            ),
          );
        } catch (_) {}
      }
    } catch (e) {
      debugPrint('Driver to drop route error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D0D),
      body: Stack(
        children: [
          // 1. Base UI (Map + Booking Card)
          SafeArea(
            child: Column(
              children: [
                _buildTopBar(),
                Expanded(
                  child: Stack(
                    children: [
                      _buildMapPlaceholder(),
                      _buildLocationButton(),
                      _buildBookingCard(),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // 2. Overlay: searching → radar screen | accepted → driver panel
          if (_isSearching && !_isRideAccepted) _buildSearchingOverlay(),
          if (_isRideAccepted) _buildDriverArrivingPanel(),
        ],
      ),
    );
  }

  // ── Top Bar ─────────────────────────────────────────────────────────────
  Widget _buildTopBar() {
    final email =
        Supabase.instance.client.auth.currentUser?.email ?? 'user@taxigo.app';
    final initial = email[0].toUpperCase();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.cardDark,
        border: Border(
          bottom: BorderSide(color: Colors.white.withValues(alpha: 0.05)),
        ),
      ),
      child: Row(
        children: [
          // Tappable avatar → profile
          GestureDetector(
            onTap: () => Navigator.pushNamed(context, '/customer_profile'),
            child: Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [AppColors.primaryYellow, AppColors.primaryYellowDark],
                ),
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Text(
                  initial,
                  style: const TextStyle(
                    color: Colors.black,
                    fontWeight: FontWeight.w900,
                    fontSize: 16,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          const Text(
            'TaxiGo',
            style: TextStyle(
              color: AppColors.primaryYellow,
              fontSize: 20,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.2,
            ),
          ),
          const Spacer(),
          GestureDetector(
            onTap: () => Navigator.pushNamed(context, '/customer_profile'),
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.person_rounded,
                  color: AppColors.textGrey, size: 18),
            ),
          ),
        ],
      ),
    );
  }

  /// Returns static markers (pickup pin, destination pin) only.
  /// The driver vehicle icon is rendered in its OWN dedicated MarkerLayer
  /// so Flutter's reconciliation never drops or hides it.
  List<Marker> _getStaticMarkers() {
    final markers = <Marker>[];
    final pickupPoint = _pickupLocation ?? _currentLocation;

    // ── Pickup pin (BLUE) ──────────────────────────────────────────────────
    // Show whenever there is a pickup point and the ride is not yet completed.
    final showPickup = _ridePhase != 'in_progress';
    if (showPickup && pickupPoint != null) {
      markers.add(Marker(
        point: pickupPoint,
        width: 44,
        height: 52,
        alignment: Alignment.bottomCenter, // pin tip touches the coordinate
        child: const Icon(
          Icons.location_on_rounded,
          color: Color(0xFF1E88E5), // vivid blue
          size: 44,
          shadows: [
            Shadow(color: Colors.black38, blurRadius: 6, offset: Offset(0, 2)),
          ],
        ),
      ));
    }

    // ── Destination pin (RED) ─────────────────────────────────────────────
    // Show whenever a destination has been geocoded, regardless of ride phase.
    // This ensures the drop-off marker is always visible while the route line
    // is drawn on the map during booking preview.
    if (_destinationLocation != null) {
      markers.add(Marker(
        point: _destinationLocation!,
        width: 44,
        height: 52,
        alignment: Alignment.bottomCenter,
        child: const Icon(
          Icons.location_on_rounded,
          color: Color(0xFFE53935), // vivid red
          size: 44,
          shadows: [
            Shadow(color: Colors.black38, blurRadius: 6, offset: Offset(0, 2)),
          ],
        ),
      ));
    }

    return markers;
  }

  /// Builds small car markers for nearby online drivers (pre-booking view).
  /// Only shown when there is no active ride, so it doesn't clash with the
  /// assigned-driver overlay.
  List<Marker> _getNearbyDriverMarkers() {
    if (_isRideAccepted || _isSearching) return []; // hide during active ride
    return _nearbyDrivers
        .where((d) =>
            d['location_latitude'] != null && d['location_longitude'] != null)
        .map((d) {
          final lat = (d['location_latitude'] as num).toDouble();
          final lng = (d['location_longitude'] as num).toDouble();
          return Marker(
            point: LatLng(lat, lng),
            width: 32,
            height: 32,
            child: Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: AppColors.primaryYellow,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.black, width: 1.5),
                boxShadow: const [
                  BoxShadow(
                    color: Colors.black38,
                    blurRadius: 4,
                    offset: Offset(0, 2),
                  ),
                ],
              ),
              child: const Icon(
                Icons.directions_car_rounded,
                color: Colors.black,
                size: 18,
              ),
            ),
          );
        })
        .toList();
  }



  /// Builds the driver vehicle icon as a plain Flutter overlay.
  /// Completely bypasses flutter_map MarkerLayer culling.
  /// Returns the assigned driver vehicle icon as a flutter_map Marker.
  /// Renders instantly in sync with the map, preventing camera-pan delays.
  List<Marker> _getAssignedDriverMarker() {
    final isActive = _isRideAccepted &&
        _driverLiveLocation != null &&
        (_ridePhase == 'accepted' ||
            _ridePhase == 'arrived' ||
            _ridePhase == 'in_progress');

    if (!isActive) return [];

    // Default to real driver GPS
    LatLng point = _driverLiveLocation!;

    // Phase-specific override: when 'arrived', snap firmly to the pickup pin
    if (_ridePhase == 'arrived' && _activeRideData != null) {
      final pickupLat = (_activeRideData!['pickup_latitude'] as num?)?.toDouble();
      final pickupLng = (_activeRideData!['pickup_longitude'] as num?)?.toDouble();
      if (pickupLat != null && pickupLng != null) {
        point = LatLng(pickupLat, pickupLng);
      }
    } else if (_ridePhase == 'in_progress' && _activeRideData != null) {
      final pickupLat = (_activeRideData!['pickup_latitude'] as num?)?.toDouble();
      final pickupLng = (_activeRideData!['pickup_longitude'] as num?)?.toDouble();
      if (pickupLat != null && pickupLng != null) {
        final pPt = LatLng(pickupLat, pickupLng);
        
        if (_forcePickupPinLock) {
          point = pPt; // Unconditional lock for laptop/web testing
        } else {
          final dist = const Distance().as(LengthUnit.Meter, point, pPt);
          if (dist < 40) {
            point = pPt;
          } else {
            point = _snapToPolyline(point, _driverToPickupRoutePoints);
          }
        }
      }
    }

    const size = 36.0;
    return [
      Marker(
        point: point,
        width: size,
        height: size,
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: const Color(0xFFFFD700),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.black, width: 1.5),
            boxShadow: const [
              BoxShadow(
                color: Colors.black45,
                blurRadius: 6,
                spreadRadius: 1,
                offset: Offset(0, 2),
              ),
            ],
          ),
          child: const Icon(
            Icons.directions_car_rounded,
            color: Colors.black,
            size: 20,
          ),
        ),
      )
    ];
  }

  Widget _buildMapPlaceholder() {
    final centerLocation = _currentLocation ?? const LatLng(6.8941, 79.9012);

    return Positioned.fill(
      child: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: centerLocation,
              initialZoom: 14.0,
            ),
            children: [
              TileLayer(
                urlTemplate:
                    'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png',
                userAgentPackageName: 'com.taxigo.app',
              ),
              if (_routePoints.isNotEmpty)
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: _routePoints,
                      color: Colors.blueAccent,
                      strokeWidth: 4.0,
                    ),
                  ],
                ),
              if (_driverToPickupRoutePoints.isNotEmpty)
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: _driverToPickupRoutePoints,
                      color: Colors.amberAccent,
                      strokeWidth: 4.0,
                      borderColor: Colors.orange.withValues(alpha: 0.35),
                      borderStrokeWidth: 2.0,
                      pattern: StrokePattern.dashed(segments: [12, 6]),
                    ),
                  ],
                ),
              // Static location pins (pickup, destination)
              MarkerLayer(
                markers: _getStaticMarkers(),
              ),
              // Nearby online drivers (only shown before a ride is active)
              MarkerLayer(
                markers: _getNearbyDriverMarkers(),
              ),
              // Assigned driver vehicle icon
              MarkerLayer(
                markers: _getAssignedDriverMarker(),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLocationButton() {
    return Positioned(
      bottom: 350,
      right: 20,
      child: FloatingActionButton(
        heroTag: 'location_fab',
        backgroundColor: AppColors.cardDark,
        foregroundColor: AppColors.primaryYellow,
        elevation: 4,
        onPressed: _checkPermissionsAndGetLocation,
        child: const Icon(Icons.my_location_rounded),
      ),
    );
  }

  // ── Booking Card ────────────────────────────────────────────────────────
  Widget _buildBookingCard() {
    return DraggableScrollableSheet(
      initialChildSize: 0.45,
      minChildSize: 0.15,
      maxChildSize: 0.6,
      builder: (context, scrollController) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          decoration: BoxDecoration(
            color: AppColors.cardDark,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.5),
                blurRadius: 30,
                offset: const Offset(0, -5),
              ),
            ],
            border: Border(top: BorderSide(color: Colors.white.withValues(alpha: 0.08))),
          ),
          child: SingleChildScrollView(
            controller: scrollController,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Drag handle indicator
                Center(
                  child: Container(
                    width: 40,
                    height: 5,
                    margin: const EdgeInsets.only(bottom: 20),
                    decoration: BoxDecoration(
                      color: Colors.grey.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
                const Text(
                  'Where to?',
                  style: TextStyle(
                    color: AppColors.textLight,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 20),
                
                // Pickup Input
                _LocationInput(
                  icon: Icons.my_location_rounded,
                  iconColor: AppColors.primaryYellow,
                  hint: 'Current Location',
                  controller: _pickupController,
                  onChanged: (val) {
                    _pickupLocation = null;
                    _onSearchChanged(val, true);
                  },
                  onSubmitted: (_) => _fetchRouteAndDraw(),
                ),
                
                if (_pickupSuggestions.isNotEmpty)
                  _buildSuggestionsList(true),
                
                Padding(
                  padding: const EdgeInsets.only(left: 17, top: 4, bottom: 4),
                  child: Container(
                    width: 2,
                    height: 24,
                    color: Colors.white.withValues(alpha: 0.1),
                  ),
                ),
                
                // Destination Input
                _LocationInput(
                  icon: Icons.location_on_rounded,
                  iconColor: Colors.redAccent,
                  hint: 'Destination',
                  controller: _destinationController,
                  onChanged: (val) {
                    _destinationLocation = null;
                    _onSearchChanged(val, false);
                  },
                  onSubmitted: (_) => _fetchRouteAndDraw(),
                ),
                
                if (_destSuggestions.isNotEmpty)
                  _buildSuggestionsList(false),
                
                const SizedBox(height: 24),
                
                if (_calculatedDistanceKm > 0)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Row(
                      children: [
                        const Icon(Icons.info_outline, color: AppColors.primaryYellow, size: 16),
                        const SizedBox(width: 8),
                        Text(
                          'Distance: ${_calculatedDistanceKm.toStringAsFixed(1)} km  •  Est. Time: $_calculatedDurationMins mins',
                          style: const TextStyle(
                            color: AppColors.primaryYellow,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                
                _buildVehicleSelection(),
                
                const SizedBox(height: 28),
                
                CustomButton(
                  text: 'Request TaxiGo',
                  onPressed: _requestRide,
                ),
                
                const SizedBox(height: 24), // Extra padding for scrolling comfort
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildSuggestionsList(bool isPickup) {
    final suggestions = isPickup ? _pickupSuggestions : _destSuggestions;
    return Container(
      margin: const EdgeInsets.only(top: 4, bottom: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      constraints: const BoxConstraints(maxHeight: 200),
      child: ListView.separated(
        shrinkWrap: true,
        padding: EdgeInsets.zero,
        itemCount: suggestions.length,
        separatorBuilder: (_, index) => Divider(height: 1, color: Colors.grey[300]),
        itemBuilder: (context, index) {
          final item = suggestions[index];
          final displayName = item['display_name'] as String;
          final lat = double.parse(item['lat'].toString());
          final lon = double.parse(item['lon'].toString());
          
          return ListTile(
            leading: Icon(
              isPickup ? Icons.my_location_rounded : Icons.location_on_rounded,
              color: isPickup ? AppColors.primaryYellow : Colors.redAccent,
            ),
            title: Text(
              displayName.split(',').first,
              style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black87),
            ),
            subtitle: Text(
              displayName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.black54, fontSize: 12),
            ),
            onTap: () async {
              final snapped = await _snapToRoad(LatLng(lat, lon));
              setState(() {
                if (isPickup) {
                  _pickupController.text = displayName.split(',').first;
                  _pickupLocation = snapped;
                  _pickupSuggestions.clear();
                } else {
                  _destinationController.text = displayName.split(',').first;
                  _destinationLocation = snapped;
                  _destSuggestions.clear();
                }
              });
              
              if (_pickupController.text.isNotEmpty && _destinationController.text.isNotEmpty) {
                _fetchRouteAndDraw();
              }
            },
          );
        },
      ),
    );
  }

  int _calculatePrice(String vehicleType) {
    if (_calculatedDistanceKm == 0) return 0;
    
    switch (vehicleType) {
      case 'bike': return (60 + (50 * _calculatedDistanceKm)).round();
      case 'tuk': return (100 + (80 * _calculatedDistanceKm)).round();
      case 'car': return (200 + (150 * _calculatedDistanceKm)).round();
      case 'van': return (400 + (250 * _calculatedDistanceKm)).round();
      case 'commuter': return (600 + (350 * _calculatedDistanceKm)).round();
      default: return 0;
    }
  }

  String _getPriceStr(String vehicleType) {
    final price = _calculatePrice(vehicleType);
    return price == 0 ? 'LKR ---' : 'LKR $price';
  }

  Widget _buildVehicleSelection() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _buildVehicleOption('bike', 'Bike', Icons.motorcycle, _getPriceStr('bike'), width: 90),
          const SizedBox(width: 8),
          _buildVehicleOption('tuk', 'Tuk', Icons.local_taxi, _getPriceStr('tuk'), width: 90),
          const SizedBox(width: 8),
          _buildVehicleOption('car', 'Car', Icons.directions_car, _getPriceStr('car'), width: 90),
          const SizedBox(width: 8),
          _buildVehicleOption('van', 'Mini Van', Icons.airport_shuttle, _getPriceStr('van'), width: 96),
          const SizedBox(width: 8),
          _buildVehicleOption('commuter', 'Commuter', Icons.directions_bus_rounded, _getPriceStr('commuter'), width: 104),
        ],
      ),
    );
  }

  Widget _buildVehicleOption(String id, String name, IconData icon, String price, {double width = 90}) {
    final isSelected = _selectedVehicle == id;
    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedVehicle = id;
        });
      },
      child: Container(
        width: width,
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primaryYellow.withValues(alpha: 0.15) : Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? AppColors.primaryYellow : Colors.transparent,
            width: 1.5,
          ),
        ),
        child: Column(
          children: [
            Icon(
              icon,
              color: isSelected ? AppColors.primaryYellow : Colors.white70,
              size: 28,
            ),
            const SizedBox(height: 8),
            Text(
              name,
              style: TextStyle(
                color: isSelected ? AppColors.primaryYellow : Colors.white70,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              price,
              style: TextStyle(
                color: isSelected ? AppColors.primaryYellow.withValues(alpha: 0.9) : Colors.white38,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Searching Overlay ───────────────────────────────────────────────────
  Widget _buildSearchingOverlay() {
    return Positioned.fill(
      child: Container(
        color: const Color(0xFF0D0D0D).withValues(alpha: 0.95),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedBuilder(
                animation: _pulseCtrl,
                builder: (context, child) {
                  return Transform.scale(
                    scale: 1.0 + (_pulseCtrl.value * 0.2),
                    child: Container(
                      padding: const EdgeInsets.all(28),
                      decoration: BoxDecoration(
                        color: AppColors.primaryYellow.withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.primaryYellow.withValues(alpha: 0.2 * _pulseCtrl.value),
                            blurRadius: 40,
                            spreadRadius: 10,
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.radar_rounded,
                        color: AppColors.primaryYellow,
                        size: 64,
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 48),
              const Text(
                'Searching for nearby drivers...',
                style: TextStyle(
                  color: AppColors.textLight,
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'This usually takes about 30 seconds',
                style: TextStyle(
                  color: AppColors.textGrey,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 48),
              TextButton(
                onPressed: _cancelSearch,
                style: TextButton.styleFrom(
                  foregroundColor: Colors.redAccent,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                  backgroundColor: Colors.redAccent.withValues(alpha: 0.1),
                ),
                child: const Text(
                  'Cancel Request',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Driver Arriving Panel ───────────────────────────────────────────────
  Widget _buildDriverArrivingPanel() {
    final vehicleType = _activeRideData?['vehicle_type'] as String? ?? _selectedVehicle;
    final fare = (_activeRideData?['fare'] as num?)?.toDouble() ?? 0.0;

    final vehicleIcons = {
      'bike': Icons.motorcycle,
      'tuk': Icons.local_taxi,
      'car': Icons.directions_car,
      'van': Icons.airport_shuttle,
      'commuter': Icons.directions_bus_rounded,
    };
    final vehicleLabels = {
      'bike': 'Bike',
      'tuk': 'Tuk-Tuk',
      'car': 'Car',
      'van': 'Mini Van',
      'commuter': 'Commuter',
    };
    final vehicleIcon = vehicleIcons[vehicleType] ?? Icons.directions_car;
    final vehicleLabel = vehicleLabels[vehicleType] ?? 'Vehicle';

    // ── Phase-based header config ──
    final phaseHeader = switch (_ridePhase) {
      'arrived'     => (
          title: 'Driver has Arrived!',
          subtitle: 'Head to the pickup point',
          color: Colors.orangeAccent,
          icon: Icons.location_on_rounded,
        ),
      'in_progress' => (
          title: 'Heading to Destination',
          subtitle: 'Enjoy your ride — sit back & relax!',
          color: Colors.blueAccent,
          icon: Icons.directions_rounded,
        ),
      _ => (
          title: 'Your Driver is Coming!',
          subtitle: 'Driver is on the way to your pickup',
          color: Colors.greenAccent,
          icon: Icons.navigation_rounded,
        ),
    };

    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.cardDark,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          border: Border(top: BorderSide(color: Colors.white.withValues(alpha: 0.08))),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.6),
              blurRadius: 32,
              offset: const Offset(0, -6),
            ),
          ],
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Drag handle
                Container(
                  width: 38, height: 4,
                  margin: const EdgeInsets.only(bottom: 20),
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),

                // Header badge
                Row(
                  children: [
                    AnimatedBuilder(
                      animation: _pulseCtrl,
                      builder: (_, child) => Container(
                        width: 10, height: 10,
                        decoration: BoxDecoration(
                          color: phaseHeader.color,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: phaseHeader.color.withValues(alpha: _pulseCtrl.value * 0.8),
                              blurRadius: 8,
                              spreadRadius: 2,
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Icon(phaseHeader.icon, color: phaseHeader.color, size: 18),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            phaseHeader.title,
                            style: const TextStyle(
                              color: AppColors.textLight,
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          Text(
                            phaseHeader.subtitle,
                            style: TextStyle(color: phaseHeader.color, fontSize: 11, fontWeight: FontWeight.w500),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                // Driver + Fare info card
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                  ),
                  child: Row(
                    children: [
                      // Driver avatar placeholder
                      Container(
                        width: 52, height: 52,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [AppColors.primaryYellow, AppColors.primaryYellowDark],
                          ),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.person_rounded, color: Colors.black, size: 30),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Your Driver',
                              style: TextStyle(
                                color: AppColors.textLight,
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                Icon(vehicleIcon, color: AppColors.primaryYellow, size: 16),
                                const SizedBox(width: 6),
                                Text(
                                  vehicleLabel,
                                  style: const TextStyle(
                                    color: AppColors.textGrey,
                                    fontSize: 13,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                const Icon(Icons.star_rounded, color: Colors.amber, size: 14),
                                const Text(
                                  ' 4.8',
                                  style: TextStyle(color: AppColors.textGrey, fontSize: 13),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      // Fare badge
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            'LKR ${fare.toStringAsFixed(0)}',
                            style: const TextStyle(
                              color: AppColors.primaryYellow,
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const Text(
                            'est. fare',
                            style: TextStyle(color: AppColors.textGrey, fontSize: 11),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // Action buttons
                Row(
                  children: [
                    // Call Driver
                    Expanded(
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.primaryYellow,
                          side: const BorderSide(color: AppColors.primaryYellow),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        onPressed: () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Calling driver... (not implemented)'),
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                        },
                        icon: const Icon(Icons.call_rounded, size: 18),
                        label: const Text(
                          'Call Driver',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    // Cancel Ride
                    Expanded(
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.redAccent,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        onPressed: _cancelSearch,
                        icon: const Icon(Icons.close_rounded, size: 18),
                        label: const Text(
                          'Cancel Ride',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Shared UI Components ──────────────────────────────────────────────────

class _LocationInput extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String hint;
  final TextEditingController controller;
  final ValueChanged<String>? onSubmitted;
  final ValueChanged<String>? onChanged;

  const _LocationInput({
    required this.icon,
    required this.iconColor,
    required this.hint,
    required this.controller,
    this.onSubmitted,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.3)),
      ),
      child: TextField(
        controller: controller,
        onSubmitted: onSubmitted,
        onChanged: onChanged,
        style: const TextStyle(color: Colors.black87, fontSize: 15, fontWeight: FontWeight.w500),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: const TextStyle(color: Colors.black54, fontSize: 15),
          prefixIcon: Icon(icon, color: iconColor, size: 20),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 16),
        ),
      ),
    );
  }
}

// ── Helper Widgets ────────────────────────────────────────────────────────────

/// A tappable payment option card (Cash / Card).
class _PaymentOptionTile extends StatelessWidget {
  const _PaymentOptionTile({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: color.withValues(alpha: 0.35), width: 1.5),
        ),
        child: Row(
          children: [
            Container(
              width: 46, height: 46,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 24),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: const TextStyle(
                          color: AppColors.textLight,
                          fontSize: 16,
                          fontWeight: FontWeight.w800)),
                  const SizedBox(height: 2),
                  Text(subtitle,
                      style: const TextStyle(
                          color: AppColors.textGrey, fontSize: 12)),
                ],
              ),
            ),
            Icon(Icons.arrow_forward_ios_rounded, color: color, size: 16),
          ],
        ),
      ),
    );
  }
}

/// Shown to the customer after they select Cash.
/// Streams the ride row and fires [onPaid] when the driver confirms receipt.
class _CashWaitingDialog extends StatefulWidget {
  const _CashWaitingDialog({
    required this.rideId,
    required this.fare,
    required this.onPaid,
  });

  final String rideId;
  final double fare;
  final VoidCallback onPaid;

  @override
  State<_CashWaitingDialog> createState() => _CashWaitingDialogState();
}

class _CashWaitingDialogState extends State<_CashWaitingDialog> {
  RealtimeChannel? _channel;
  bool _paid = false;

  @override
  void initState() {
    super.initState();
    _channel = Supabase.instance.client
        .channel('cash-waiting-${widget.rideId}')
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'rides',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'id',
            value: widget.rideId,
          ),
          callback: (payload) {
            if (!mounted || _paid) return;
            final payStatus =
                payload.newRecord['payment_status'] as String?;
            debugPrint('[CashWaiting] payment_status=$payStatus');
            if (payStatus == 'paid') {
              _paid = true;
              _channel?.unsubscribe();
              widget.onPaid();
            }
          },
        )
        .subscribe((status, [error]) {
          debugPrint('[CashWaitingChannel] status=$status  error=$error');
        });
  }

  @override
  void dispose() {
    _channel?.unsubscribe();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
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
              child: const Icon(Icons.money, color: Colors.greenAccent, size: 38),
            ),
            const SizedBox(height: 20),
            const Text('Cash Payment',
                style: TextStyle(
                    color: AppColors.textLight,
                    fontSize: 20,
                    fontWeight: FontWeight.w900)),
            const SizedBox(height: 8),
            Text(
              'LKR ${widget.fare.toStringAsFixed(0)}',
              style: const TextStyle(
                  color: AppColors.primaryYellow,
                  fontSize: 26,
                  fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 16),
            const Text(
              'Please hand the cash to your driver.\nWaiting for driver to confirm receipt...',
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: AppColors.textGrey, fontSize: 13, height: 1.6),
            ),
            const SizedBox(height: 24),
            const SizedBox(
              width: 28, height: 28,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                valueColor: AlwaysStoppedAnimation(Colors.greenAccent),
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
