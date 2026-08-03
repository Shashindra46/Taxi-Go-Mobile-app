// TaxiGo — Supabase Configuration
//
// Replace the placeholder values below with your actual Supabase project
// credentials. Find them at: Supabase Dashboard → Settings → API
//
// ⚠️ Never commit real credentials to a public repository.
// Use flutter_dotenv or similar for production builds.

class SupabaseConfig {
  /// Your Supabase project URL, e.g. "https://xyzcompany.supabase.co"
  static const String supabaseUrl = 'https://ydoqwhebaxbfrwyimzve.supabase.co';

  /// Your Supabase anon (public) key
  static const String supabaseAnonKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Inlkb3F3aGViYXhiZnJ3eWltenZlIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODIxMzgwMTcsImV4cCI6MjA5NzcxNDAxN30.ud1F2jt7s7o1McLwtv5oH3XPYOU-W7Ve6a9gDUSnMIw';

  /// Storage bucket name for driver documents
  static const String documentsBucket = 'driver-documents';

  /// Database table names
  static const String driversTable = 'drivers';
  static const String vehiclesTable = 'vehicles';
}
