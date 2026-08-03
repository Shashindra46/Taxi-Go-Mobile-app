import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/driver_model.dart';
import '../models/vehicle_model.dart';
import 'supabase_config.dart';

class SupabaseService {
  SupabaseService._();
  static final SupabaseService instance = SupabaseService._();

  SupabaseClient get _client => Supabase.instance.client;

  // ─── Auth ─────────────────────────────────────────────────────────────────

  /// Signs up a new driver with email + password.
  /// Returns the created [User] on success.
  Future<User> signUpDriver({
    required String email,
    required String password,
  }) async {
    final response = await _client.auth.signUp(
      email: email,
      password: password,
    );
    if (response.user == null) {
      throw Exception('Sign-up failed: no user returned.');
    }
    return response.user!;
  }

  // ─── Database ─────────────────────────────────────────────────────────────

  /// Inserts a driver profile row into the `drivers` table.
  /// Returns the inserted row's `id` (UUID).
  Future<String> insertDriver(DriverModel driver) async {
    final rows = await _client
        .from(SupabaseConfig.driversTable)
        .insert(driver.toMap())
        .select('id');
    if (rows.isEmpty) throw Exception('Driver insert returned no id.');
    return rows.first['id'] as String;
  }

  /// Inserts a vehicle row into the `vehicles` table.
  /// Returns the inserted row's `id` (UUID).
  Future<String> insertVehicle(VehicleModel vehicle) async {
    final rows = await _client
        .from(SupabaseConfig.vehiclesTable)
        .insert(vehicle.toMap())
        .select('id');
    if (rows.isEmpty) throw Exception('Vehicle insert returned no id.');
    return rows.first['id'] as String;
  }

  // ─── Storage ──────────────────────────────────────────────────────────────

  /// Uploads a document file to the `driver-documents` bucket.
  ///
  /// On native (Android/iOS): provide [nativeFile].
  /// On web: provide [webBytes] + [fileName].
  ///
  /// Returns the public URL of the uploaded file.
  Future<String> uploadDocument({
    required String storagePath,
    File? nativeFile,
    Uint8List? webBytes,
    required String fileName,
    String contentType = 'image/jpeg',
  }) async {
    final bucket = _client.storage.from(SupabaseConfig.documentsBucket);

    if (kIsWeb) {
      if (webBytes == null) throw ArgumentError('webBytes required on web.');
      await bucket.uploadBinary(
        storagePath,
        webBytes,
        fileOptions: FileOptions(contentType: contentType, upsert: true),
      );
    } else {
      if (nativeFile == null) throw ArgumentError('nativeFile required on native.');
      await bucket.upload(
        storagePath,
        nativeFile,
        fileOptions: FileOptions(contentType: contentType, upsert: true),
      );
    }

    return bucket.getPublicUrl(storagePath);
  }
}
