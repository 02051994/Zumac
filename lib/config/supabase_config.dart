class SupabaseConfig {
  static const String supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'AQUI_VA_LA_URL_DEL_PROYECTO_SUPABASE',
  );
  static const String supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: 'AQUI_VA_LA_CLAVE_PUBLICABLE_ANON_DE_SUPABASE',
  );

  static bool get isConfigured {
    final uri = Uri.tryParse(supabaseUrl);
    return uri != null &&
        uri.hasScheme &&
        uri.host.isNotEmpty &&
        !supabaseAnonKey.startsWith('AQUI_VA_');
  }

  static void ensureConfigured() {
    if (isConfigured) return;
    throw StateError(
      'Falta configurar SUPABASE_URL y SUPABASE_ANON_KEY. '
      'Use --dart-define-from-file=supabase.runtime.json y tome como base '
      'supabase.runtime.example.json.',
    );
  }
}
