/// Supabase project configuration.
///
/// The anon key is a public, client-safe JWT — it's meant to ship in apps.
/// Row-Level Security policies on the `SW_saves` table gate access to
/// `auth.uid() = user_id`, so clients can only read/write their own row.
class SupabaseConfig {
  static const url = 'https://kxubvflddbmzlcukpfhe.supabase.co';
  static const anonKey =
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imt4dWJ2ZmxkZGJtemxjdWtwZmhlIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzYxNDU5NjEsImV4cCI6MjA5MTcyMTk2MX0.oQuWQw_EdvnvGOTadGi10qacatpkD6ZxSUbFh6DDLkM';

  /// Table prefix used to namespace this app's tables in the shared schema.
  static const tablePrefix = 'SW_';
  static const saveTable = '${tablePrefix}saves';
}
