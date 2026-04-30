import 'package:flutter_dotenv/flutter_dotenv.dart';

class Config {
  static Future<void> load() async {
    // Load from assets folder instead of root
    await dotenv.load(fileName: "assets/.env");
  }
  // Database Configuration
  static String get dbHost => dotenv.env['DB_HOST'] ?? '192.168.18.129';
  static int get dbPort => int.tryParse(dotenv.env['DB_PORT'] ?? '3306') ?? 3306;
  static String get dbUser => dotenv.env['DB_USER'] ?? 'root';
  static String get dbPassword => dotenv.env['DB_PASSWORD'] ?? 'root';
  static String get dbName => dotenv.env['DB_NAME'] ?? 'make_x';

  // App Configuration
  static String get appName => dotenv.env['APP_NAME'] ?? 'RoboVenture';
  static String get appVersion => dotenv.env['APP_VERSION'] ?? '1.0.0';
  static bool get debugMode => dotenv.env['DEBUG_MODE']?.toLowerCase() == 'true';

  // Schedule Defaults
  static int get defaultMatchesPerTeam => 
      int.tryParse(dotenv.env['DEFAULT_MATCHES_PER_TEAM'] ?? '4') ?? 4;
  static int get defaultDurationMinutes => 
      int.tryParse(dotenv.env['DEFAULT_DURATION_MINUTES'] ?? '2') ?? 2;
  static int get defaultIntervalMinutes => 
      int.tryParse(dotenv.env['DEFAULT_INTERVAL_MINUTES'] ?? '1') ?? 1;
  static String get defaultStartTime => 
      dotenv.env['DEFAULT_START_TIME'] ?? '09:00';
  static String get defaultEndTime => 
      dotenv.env['DEFAULT_END_TIME'] ?? '17:00';

  // Arena Configuration
  static int get maxTeamsPerArena => 
      int.tryParse(dotenv.env['MAX_TEAMS_PER_ARENA'] ?? '30') ?? 30;

  // Feature Flags
  static bool get enableLunchBreak => 
      dotenv.env['ENABLE_LUNCH_BREAK']?.toLowerCase() == 'true';
  static int get lunchStartHour => 
      int.tryParse(dotenv.env['LUNCH_START_HOUR'] ?? '12') ?? 12;
  static int get lunchEndHour => 
      int.tryParse(dotenv.env['LUNCH_END_HOUR'] ?? '13') ?? 13;

  // UI Configuration
  static String get primaryColorHex => 
      dotenv.env['PRIMARY_COLOR'] ?? '#00CFFF';
  static String get secondaryColorHex => 
      dotenv.env['SECONDARY_COLOR'] ?? '#FFFFD700';
  static String get backgroundColorHex => 
      dotenv.env['BACKGROUND_COLOR'] ?? '#0E0630';
}