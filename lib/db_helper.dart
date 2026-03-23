import 'dart:math';
import 'package:mysql_client/mysql_client.dart';
import 'schedule_fairness_helper.dart';
import 'config.dart';
import 'championship_settings.dart';

class DBHelper {
  static MySQLConnection? _connection;

  // Replace hardcoded values with Config
  static String get _host => Config.dbHost;
  static int get _port => Config.dbPort;
  static String get _userName => Config.dbUser;
  static String get _password => Config.dbPassword;
  static String get _databaseName => Config.dbName;

  static Future<void> runMigrations() async {
    final conn = await getConnection();
    
    // Add arena_number column if not exists
    try {
      await conn.execute("""
        ALTER TABLE tbl_teamschedule
        ADD COLUMN arena_number INT NOT NULL DEFAULT 1
      """);
      print("✅ Migration: arena_number column added.");
    } catch (_) {
      print("ℹ️  Migration: arena_number already present.");
    }
    
    try {
      await conn.execute("""
        ALTER TABLE tbl_score
        ADD COLUMN score_individual INT DEFAULT 0,
        ADD COLUMN score_alliance INT DEFAULT 0
      """);
      print("✅ Added individual and alliance score columns to tbl_score");
    } catch (e) {
      print("ℹ️ Score columns may already exist: $e");
    }

    // Create alliance selections table
    try {
      await conn.execute("""
        CREATE TABLE IF NOT EXISTS tbl_alliance_selections (
          alliance_id INT AUTO_INCREMENT PRIMARY KEY,
          category_id INT NOT NULL,
          captain_team_id INT NOT NULL,
          partner_team_id INT NOT NULL,
          selection_round INT NOT NULL,
          created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
          FOREIGN KEY (category_id) REFERENCES tbl_category(category_id) ON DELETE CASCADE,
          FOREIGN KEY (captain_team_id) REFERENCES tbl_team(team_id) ON DELETE CASCADE,
          FOREIGN KEY (partner_team_id) REFERENCES tbl_team(team_id) ON DELETE CASCADE
        )
      """);
      print("✅ Alliance selections table created");
    } catch (e) {
      print("ℹ️ Alliance selections table check: $e");
    }
    
    // Create championship schedule table
    try {
      await conn.execute("""
        CREATE TABLE IF NOT EXISTS tbl_championship_schedule (
          match_id INT AUTO_INCREMENT PRIMARY KEY,
          category_id INT NOT NULL,
          alliance1_id INT NOT NULL,
          alliance2_id INT NOT NULL,
          match_round INT NOT NULL,
          match_position INT NOT NULL,
          schedule_time VARCHAR(20),
          arena_number INT DEFAULT 1,
          status VARCHAR(20) DEFAULT 'pending'
        )
      """);
      print("✅ Championship schedule table created");
    } catch (e) {
      print("ℹ️ Championship schedule table check: $e");
    }

    // Create championship settings table
    try {
      await conn.execute("""
        CREATE TABLE IF NOT EXISTS tbl_championship_settings (
          category_id INT PRIMARY KEY,
          matches_per_alliance INT NOT NULL DEFAULT 1,
          start_time VARCHAR(5) NOT NULL DEFAULT '13:00',
          end_time VARCHAR(5) NOT NULL DEFAULT '17:00',
          duration_minutes INT NOT NULL DEFAULT 10,
          interval_minutes INT NOT NULL DEFAULT 5,
          lunch_break_enabled BOOLEAN DEFAULT TRUE,
          updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
          FOREIGN KEY (category_id) REFERENCES tbl_category(category_id) ON DELETE CASCADE
        )
      """);
      print("✅ Championship settings table created");
    } catch (e) {
      print("ℹ️ Championship settings table check: $e");
    }

    try {
      await conn.execute("""
        ALTER TABLE tbl_championship_schedule
        ADD COLUMN category_id INT NULL AFTER match_id
      """);
      print("✅ Migration: category_id column added to tbl_championship_schedule");
    } catch (_) {
      print("ℹ️  Migration: category_id already present on tbl_championship_schedule.");
    }
    
    // In db_helper.dart, add this to runMigrations():

// Create Explorer double elimination bracket table
try {
  await conn.execute("""
    CREATE TABLE IF NOT EXISTS tbl_explorer_double_elimination (
      match_id INT AUTO_INCREMENT PRIMARY KEY,
      category_id INT NOT NULL,
      round_name VARCHAR(50) NOT NULL,
      match_position INT NOT NULL,
      bracket_side ENUM('winners', 'losers', 'grand') NOT NULL,
      round_number INT NOT NULL,
      alliance1_id INT,
      alliance2_id INT,
      winner_alliance_id INT,
      next_match_id_winner INT,
      next_match_id_loser INT,
      next_match_position_winner INT,
      next_match_position_loser INT,
      status VARCHAR(20) DEFAULT 'pending',
      schedule_time VARCHAR(20),
      created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
      FOREIGN KEY (category_id) REFERENCES tbl_category(category_id) ON DELETE CASCADE,
      FOREIGN KEY (alliance1_id) REFERENCES tbl_alliance_selections(alliance_id) ON DELETE SET NULL,
      FOREIGN KEY (alliance2_id) REFERENCES tbl_alliance_selections(alliance_id) ON DELETE SET NULL,
      FOREIGN KEY (winner_alliance_id) REFERENCES tbl_alliance_selections(alliance_id) ON DELETE SET NULL
    )
  """);
  print("✅ Explorer double elimination bracket table created");
} catch (e) {
  print("ℹ️ Explorer bracket table check: $e");
}
    // Add database indexes for performance
    await addDatabaseIndexes();
  }

  // Add database indexes for better query performance
  static Future<void> addDatabaseIndexes() async {
    final conn = await getConnection();
    
    // Index for tbl_teamschedule on round_id
    try {
      await conn.execute("""
        CREATE INDEX IF NOT EXISTS idx_teamschedule_round 
        ON tbl_teamschedule(round_id)
      """);
      print("✅ Index: idx_teamschedule_round created");
    } catch (e) {
      print("ℹ️ Index idx_teamschedule_round already exists or error: $e");
    }

    // Index for tbl_teamschedule on match_id
    try {
      await conn.execute("""
        CREATE INDEX IF NOT EXISTS idx_teamschedule_match 
        ON tbl_teamschedule(match_id)
      """);
      print("✅ Index: idx_teamschedule_match created");
    } catch (e) {
      print("ℹ️ Index idx_teamschedule_match already exists or error: $e");
    }

    // Composite index for tbl_score on team_id and round_id
    try {
      await conn.execute("""
        CREATE INDEX IF NOT EXISTS idx_score_team_round 
        ON tbl_score(team_id, round_id)
      """);
      print("✅ Index: idx_score_team_round created");
    } catch (e) {
      print("ℹ️ Index idx_score_team_round already exists or error: $e");
    }

    // Index for tbl_player on team_id
    try {
      await conn.execute("""
        CREATE INDEX IF NOT EXISTS idx_player_team 
        ON tbl_player(team_id)
      """);
      print("✅ Index: idx_player_team created");
    } catch (e) {
      print("ℹ️ Index idx_player_team already exists or error: $e");
    }

    // Index for tbl_match on schedule_id
    try {
      await conn.execute("""
        CREATE INDEX IF NOT EXISTS idx_match_schedule 
        ON tbl_match(schedule_id)
      """);
      print("✅ Index: idx_match_schedule created");
    } catch (e) {
      print("ℹ️ Index idx_match_schedule already exists or error: $e");
    }

    // Index for tbl_team on category_id
    try {
      await conn.execute("""
        CREATE INDEX IF NOT EXISTS idx_team_category 
        ON tbl_team(category_id)
      """);
      print("✅ Index: idx_team_category created");
    } catch (e) {
      print("ℹ️ Index idx_team_category already exists or error: $e");
    }

    // Index for tbl_championship_schedule on category_id
    try {
      await conn.execute("""
        CREATE INDEX IF NOT EXISTS idx_championship_category
        ON tbl_championship_schedule(category_id)
      """);
      print("✅ Index: idx_championship_category created");
    } catch (e) {
      print("ℹ️ Index idx_championship_category already exists or error: $e");
    }

    // Index for tbl_mentor on school_id
    try {
      await conn.execute("""
        CREATE INDEX IF NOT EXISTS idx_mentor_school 
        ON tbl_mentor(school_id)
      """);
      print("✅ Index: idx_mentor_school created");
    } catch (e) {
      print("ℹ️ Index idx_mentor_school already exists or error: $e");
    }
  }

  // ── CHAMPIONSHIP SETTINGS ─────────────────────────────────────────────────

  // Save championship settings
  static Future<void> saveChampionshipSettings(ChampionshipSettings settings) async {
    final conn = await getConnection();
    
    await conn.execute("""
      INSERT INTO tbl_championship_settings 
        (category_id, matches_per_alliance, start_time, end_time, duration_minutes, interval_minutes, lunch_break_enabled)
      VALUES
        (:catId, :matches, :startTime, :endTime, :duration, :interval, :lunch)
      ON DUPLICATE KEY UPDATE
        matches_per_alliance = :matches,
        start_time = :startTime,
        end_time = :endTime,
        duration_minutes = :duration,
        interval_minutes = :interval,
        lunch_break_enabled = :lunch
    """, {
      "catId": settings.categoryId,
      "matches": settings.matchesPerAlliance,
      "startTime": settings.startTimeString,
      "endTime": settings.endTimeString,
      "duration": settings.durationMinutes,
      "interval": settings.intervalMinutes,
      "lunch": settings.lunchBreakEnabled ? 1 : 0,
    });
    
    print("✅ Saved championship settings for category ${settings.categoryId}");
  }

  // Load championship settings
  static Future<ChampionshipSettings?> loadChampionshipSettings(int categoryId) async {
    final conn = await getConnection();
    
    try {
      final result = await conn.execute("""
        SELECT * FROM tbl_championship_settings 
        WHERE category_id = :catId
      """, {"catId": categoryId});
      
      if (result.rows.isNotEmpty) {
        final row = result.rows.first.assoc();
        return ChampionshipSettings.fromMap(row);
      }
    } catch (e) {
      print("⚠️ Could not load championship settings: $e");
    }
    
    return null;
  }

  // Clean up orphaned championship records
  static Future<void> cleanupOrphanedChampionshipRecords() async {
    final conn = await getConnection();
    
    try {
      // Delete championship schedule entries that reference non-existent categories
      await conn.execute("""
        DELETE cs FROM tbl_championship_schedule cs
        LEFT JOIN tbl_category c ON cs.category_id = c.category_id
        WHERE c.category_id IS NULL
      """);
      
      // Delete championship settings for non-existent categories
      await conn.execute("""
        DELETE cs FROM tbl_championship_settings cs
        LEFT JOIN tbl_category c ON cs.category_id = c.category_id
        WHERE c.category_id IS NULL
      """);
      
      print("✅ Cleaned up orphaned championship records");
    } catch (e) {
      print("⚠️ Error cleaning up orphaned records: $e");
    }
  }

  // Enhanced championship schedule generation with settings
  static Future<void> generateChampionshipScheduleWithSettings(
    int categoryId,
    ChampionshipSettings settings,
  ) async {
    final conn = await getConnection();
    
    try {
      print("🏆 Starting championship schedule generation for category $categoryId");
      
      // Get alliances
      final alliancesResult = await conn.execute("""
        SELECT alliance_id, selection_round
        FROM tbl_alliance_selections 
        WHERE category_id = :catId
        ORDER BY selection_round
      """, {"catId": categoryId});
      
      final alliances = alliancesResult.rows.map((r) => r.assoc()).toList();
      
      if (alliances.isEmpty) {
        throw Exception('No alliances found');
      }
      
      // First, delete existing schedule for this category
      await conn.execute(
        "DELETE FROM tbl_championship_schedule WHERE category_id = :catId",
        {"catId": categoryId},
      );
      
      final numAlliances = alliances.length;
      int matchesInserted = 0;
      
      // Parse times
      int currentHour = settings.startTime.hour;
      int currentMinute = settings.startTime.minute;
      
      String formatTime(int hour, int minute) {
        return '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
      }
      
      if (numAlliances == 2) {
        // CASE 1: Only 2 alliances - DIRECT FINAL SERIES
        print("🎯 Generating FINAL SERIES with ${settings.matchesPerAlliance} matches");
        
        for (int matchNum = 1; matchNum <= settings.matchesPerAlliance; matchNum++) {
          final timeStr = formatTime(currentHour, currentMinute);
          
          await conn.execute("""
            INSERT INTO tbl_championship_schedule 
              (category_id, alliance1_id, alliance2_id, match_round, match_position, schedule_time, status)
            VALUES
              (:catId, :a1, :a2, 1, :pos, :time, 'pending')
          """, {
            "catId": categoryId,
            "a1": alliances[0]['alliance_id'],
            "a2": alliances[1]['alliance_id'],
            "pos": matchNum,
            "time": timeStr,
          });
          
          matchesInserted++;
          print("  ✅ Match $matchNum at $timeStr");
          
          // Advance time
          currentMinute += settings.durationMinutes + settings.intervalMinutes;
          while (currentMinute >= 60) {
            currentMinute -= 60;
            currentHour++;
          }
        }
        
      } else if (numAlliances == 4) {
        // CASE 2: 4 alliances - SEMIFINALS + FINAL
        print("🎯 Generating SEMIFINALS");
        
        // Semifinal 1
        String time1 = formatTime(currentHour, currentMinute);
        await conn.execute("""
          INSERT INTO tbl_championship_schedule 
            (category_id, alliance1_id, alliance2_id, match_round, match_position, schedule_time, status)
          VALUES
            (:catId, :a1, :a4, 1, 1, :time, 'pending')
        """, {
          "catId": categoryId,
          "a1": alliances[0]['alliance_id'],
          "a4": alliances[3]['alliance_id'],
          "time": time1,
        });
        matchesInserted++;
        
        // Advance time for next match
        currentMinute += settings.durationMinutes + settings.intervalMinutes;
        while (currentMinute >= 60) {
          currentMinute -= 60;
          currentHour++;
        }
        
        // Semifinal 2
        String time2 = formatTime(currentHour, currentMinute);
        await conn.execute("""
          INSERT INTO tbl_championship_schedule 
            (category_id, alliance1_id, alliance2_id, match_round, match_position, schedule_time, status)
          VALUES
            (:catId, :a2, :a3, 1, 2, :time, 'pending')
        """, {
          "catId": categoryId,
          "a2": alliances[1]['alliance_id'],
          "a3": alliances[2]['alliance_id'],
          "time": time2,
        });
        matchesInserted++;
        
        // Advance time for final
        currentMinute += settings.durationMinutes + settings.intervalMinutes;
        while (currentMinute >= 60) {
          currentMinute -= 60;
          currentHour++;
        }
        
        // Final matches
        print("🎯 Generating FINAL with ${settings.matchesPerAlliance} matches");
        
        for (int matchNum = 1; matchNum <= settings.matchesPerAlliance; matchNum++) {
          String timeStr = formatTime(currentHour, currentMinute);
          
          await conn.execute("""
            INSERT INTO tbl_championship_schedule 
              (category_id, alliance1_id, alliance2_id, match_round, match_position, schedule_time, status)
            VALUES
              (:catId, 0, 0, 2, :pos, :time, 'pending')
          """, {
            "catId": categoryId,
            "pos": matchNum,
            "time": timeStr,
          });
          
          matchesInserted++;
          
          // Advance time for next match
          currentMinute += settings.durationMinutes + settings.intervalMinutes;
          while (currentMinute >= 60) {
            currentMinute -= 60;
            currentHour++;
          }
        }
        
      } else if (numAlliances == 8) {
        // CASE 3: 8 alliances - QUARTERFINALS + SEMIFINALS + FINAL
        print("🎯 Generating QUARTERFINALS");
        
        // Quarterfinals
        for (int i = 0; i < 4; i++) {
          String timeStr = formatTime(currentHour, currentMinute);
          
          await conn.execute("""
            INSERT INTO tbl_championship_schedule 
              (category_id, alliance1_id, alliance2_id, match_round, match_position, schedule_time, status)
            VALUES
              (:catId, :a1, :a2, 1, :pos, :time, 'pending')
          """, {
            "catId": categoryId,
            "a1": alliances[i * 2]['alliance_id'],
            "a2": alliances[i * 2 + 1]['alliance_id'],
            "pos": i + 1,
            "time": timeStr,
          });
          
          matchesInserted++;
          
          // Advance time for next match
          currentMinute += settings.durationMinutes + settings.intervalMinutes;
          while (currentMinute >= 60) {
            currentMinute -= 60;
            currentHour++;
          }
        }
        
        print("🎯 Generating SEMIFINALS");
        
        // Semifinals
        for (int i = 0; i < 2; i++) {
          String timeStr = formatTime(currentHour, currentMinute);
          
          await conn.execute("""
            INSERT INTO tbl_championship_schedule 
              (category_id, alliance1_id, alliance2_id, match_round, match_position, schedule_time, status)
            VALUES
              (:catId, 0, 0, 2, :pos, :time, 'pending')
          """, {
            "catId": categoryId,
            "pos": i + 1,
            "time": timeStr,
          });
          
          matchesInserted++;
          
          // Advance time for next match
          currentMinute += settings.durationMinutes + settings.intervalMinutes;
          while (currentMinute >= 60) {
            currentMinute -= 60;
            currentHour++;
          }
        }
        
        print("🎯 Generating FINAL with ${settings.matchesPerAlliance} matches");
        
        // Final
        for (int matchNum = 1; matchNum <= settings.matchesPerAlliance; matchNum++) {
          String timeStr = formatTime(currentHour, currentMinute);
          
          await conn.execute("""
            INSERT INTO tbl_championship_schedule 
              (category_id, alliance1_id, alliance2_id, match_round, match_position, schedule_time, status)
            VALUES
              (:catId, 0, 0, 3, :pos, :time, 'pending')
          """, {
            "catId": categoryId,
            "pos": matchNum,
            "time": timeStr,
          });
          
          matchesInserted++;
          
          // Advance time for next match
          currentMinute += settings.durationMinutes + settings.intervalMinutes;
          while (currentMinute >= 60) {
            currentMinute -= 60;
            currentHour++;
          }
        }
      }
      
      print("✅ Generated $matchesInserted championship matches with settings");
      
    } catch (e, stackTrace) {
      print("❌ Error generating championship schedule: $e");
      print(stackTrace);
      throw Exception('Failed to generate championship schedule: $e');
    }
  }

  // ── Connection ────────────────────────────────────────────────────────────

  static Future<MySQLConnection> getConnection() async {
    try {
      if (_connection != null && _connection!.connected) {
        return _connection!;
      }
    } catch (_) {
      _connection = null;
    }

    _connection = await MySQLConnection.createConnection(
      host:         _host,
      port:         _port,
      userName:     _userName,
      password:     _password,
      databaseName: _databaseName,
      secure:       false,
    );

    await _connection!.connect();
    print("✅ Database connected!");
    return _connection!;
  }

  static Future<void> closeConnection() async {
    try { await _connection?.close(); } catch (_) {}
    _connection = null;
    print("🔌 Database disconnected.");
  }

  // ── SCHOOLS ───────────────────────────────────────────────────────────────

  static Future<List<Map<String, dynamic>>> getSchools() async {
    final conn = await getConnection();
    final result = await conn.execute(
      "SELECT * FROM tbl_school ORDER BY school_name"
    );
    return result.rows.map((r) => r.assoc()).toList();
  }

  // ── CATEGORIES ────────────────────────────────────────────────────────────

  static Future<List<Map<String, dynamic>>> getCategories() async {
    final conn = await getConnection();
    final result = await conn.execute(
      "SELECT * FROM tbl_category ORDER BY category_id"
    );
    return result.rows.map((r) => r.assoc()).toList();
  }

  static Future<void> seedCategories() async {
    final conn = await getConnection();
    const categories = [
      'Aspiring Makers (mBot 1)',
      'Emerging Innovators (mBot 2)',
      'Navigation',
      'Soccer',
    ];
    for (final cat in categories) {
      await conn.execute(
        "INSERT IGNORE INTO tbl_category (category_type) VALUES (:cat)",
        {"cat": cat},
      );
    }
    print("✅ Categories seeded.");
  }

  // ── TEAMS ─────────────────────────────────────────────────────────────────

  static Future<List<Map<String, dynamic>>> getTeams() async {
    final conn = await getConnection();
    final result = await conn.execute("""
      SELECT t.team_id, t.team_name, t.team_ispresent,
             c.category_type, m.mentor_name
      FROM tbl_team t
      JOIN tbl_category c ON t.category_id = c.category_id
      JOIN tbl_mentor   m ON t.mentor_id   = m.mentor_id
      ORDER BY t.team_id
    """);
    return result.rows.map((r) => r.assoc()).toList();
  }

  static Future<List<Map<String, dynamic>>> getTeamsByCategory(
      int categoryId) async {
    final conn = await getConnection();
    final result = await conn.execute("""
      SELECT t.team_id, t.team_name, t.team_ispresent,
             c.category_type, m.mentor_name
      FROM tbl_team t
      JOIN tbl_category c ON t.category_id = c.category_id
      JOIN tbl_mentor   m ON t.mentor_id   = m.mentor_id
      WHERE t.category_id = :categoryId
      ORDER BY t.team_id
    """, {"categoryId": categoryId});
    return result.rows.map((r) => r.assoc()).toList();
  }

  // ── SCHEDULE ──────────────────────────────────────────────────────────────

  static Future<void> clearSchedule() async {
    final conn = await getConnection();
    await conn.execute("DELETE FROM tbl_teamschedule");
    await conn.execute("DELETE FROM tbl_match");
    await conn.execute("DELETE FROM tbl_schedule");
    // Reset AUTO_INCREMENT so match IDs start from 1 again
    await conn.execute("ALTER TABLE tbl_teamschedule AUTO_INCREMENT = 1");
    await conn.execute("ALTER TABLE tbl_match AUTO_INCREMENT = 1");
    await conn.execute("ALTER TABLE tbl_schedule AUTO_INCREMENT = 1");
    print("✅ Schedule cleared and IDs reset.");
  }

  static Future<int> insertSchedule({
    required String startTime,
    required String endTime,
  }) async {
    final conn = await getConnection();
    final result = await conn.execute("""
      INSERT INTO tbl_schedule (schedule_start, schedule_end)
      VALUES (:start, :end)
    """, {"start": startTime, "end": endTime});
    return result.lastInsertID.toInt();
  }

  static Future<int> insertMatch(int scheduleId) async {
    final conn = await getConnection();
    final result = await conn.execute("""
      INSERT INTO tbl_match (schedule_id) VALUES (:scheduleId)
    """, {"scheduleId": scheduleId});
    return result.lastInsertID.toInt();
  }

  static Future<void> insertTeamSchedule({
    required int matchId,
    required int roundId,
    required int teamId,
    required int refereeId,
    int arenaNumber = 1,
  }) async {
    final conn = await getConnection();
    
    // Verify the round exists before inserting - if not, create it
    final roundCheck = await conn.execute(
      "SELECT COUNT(*) as cnt FROM tbl_round WHERE round_id = :roundId",
      {"roundId": roundId},
    );
    final exists = int.tryParse(roundCheck.rows.first.assoc()['cnt']?.toString() ?? '0') ?? 0;
    
    if (exists == 0) {
      print("⚠️ Round $roundId does not exist - creating it now");
      try {
        await conn.execute("""
          INSERT INTO tbl_round (round_id, round_type, round_number)
          VALUES (:id, :type, :number)
        """, {
          "id": roundId,
          "type": 'Round $roundId',
          "number": roundId,
        });
        print("✅ Created round $roundId");
      } catch (e) {
        print("❌ Failed to create round $roundId: $e");
        return;
      }
    }
    
    print("📝 Inserting: match=$matchId, round=$roundId, team=$teamId, arena=$arenaNumber");
    
    await conn.execute("""
      INSERT INTO tbl_teamschedule (match_id, round_id, team_id, referee_id, arena_number)
      VALUES (:match, :round, :team, :ref, :arena)
    """, {
      "match": matchId,
      "round": roundId,
      "team":  teamId,
      "ref":   refereeId,
      "arena": arenaNumber,
    });
  }

  // ── ROUNDS ────────────────────────────────────────────────────────────────

  static Future<void> seedRounds(int maxRounds) async {
    final conn = await getConnection();
    
    // Check if we already have enough rounds
    final checkResult = await conn.execute("SELECT COUNT(*) as cnt FROM tbl_round");
    final count = int.tryParse(checkResult.rows.first.assoc()['cnt']?.toString() ?? '0') ?? 0;
    
    if (count < maxRounds) {
      // Add missing rounds
      for (int i = count + 1; i <= maxRounds; i++) {
        try {
          await conn.execute("""
            INSERT INTO tbl_round (round_id, round_type, round_number)
            VALUES (:id, :type, :number)
          """, {
            "id": i,
            "type": 'Round $i',
            "number": i,
          });
          print("✅ Added round $i");
        } catch (e) {
          print("⚠️ Could not add round $i: $e");
        }
      }
    } else {
      print("ℹ️ Rounds table already has $count entries, skipping seed.");
    }
  }

  static Future<void> generateSchedule({
    required Map<int, int> runsPerCategory,
    required Map<int, int> arenasPerCategory,
    required String startTime,
    required String endTime,
    required int durationMinutes,
    required int intervalMinutes,
    bool lunchBreak = true,
  }) async {
    final conn = await DBHelper.getConnection();

    // ── Clear old schedule first ─────────────────────────────────────────────
    await clearSchedule();

    // ── Store the matches per team setting in a new table or settings table ──
    // First, create a table to store category settings if it doesn't exist
    try {
      await conn.execute("""
        CREATE TABLE IF NOT EXISTS tbl_category_settings (
          category_id INT PRIMARY KEY,
          matches_per_team INT NOT NULL DEFAULT 4,
          updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
          FOREIGN KEY (category_id) REFERENCES tbl_category(category_id) ON DELETE CASCADE
        )
      """);
      print("✅ Category settings table created or already exists");
    } catch (e) {
      print("ℹ️ Category settings table check: $e");
    }

    // Store the matches per team for each category
    for (final entry in runsPerCategory.entries) {
      final categoryId = entry.key;
      final matchesPerTeam = entry.value;
      
      await conn.execute("""
        INSERT INTO tbl_category_settings (category_id, matches_per_team)
        VALUES (:catId, :matches)
        ON DUPLICATE KEY UPDATE matches_per_team = :matches
      """, {
        "catId": categoryId,
        "matches": matchesPerTeam,
      });
      print("📊 Stored matches per team for category $categoryId: $matchesPerTeam");
    }

    // ── IMPORTANT: Seed rounds BEFORE inserting any matches ─────────────────
    final maxRuns = runsPerCategory.values.isEmpty
        ? 1
        : runsPerCategory.values.reduce((a, b) => a > b ? a : b);
    
    await conn.execute("DELETE FROM tbl_round");
    await conn.execute("ALTER TABLE tbl_round AUTO_INCREMENT = 1");
    await seedRounds(maxRuns);
    
    final roundCheck = await conn.execute("SELECT COUNT(*) as cnt FROM tbl_round");
    final roundCount = int.tryParse(roundCheck.rows.first.assoc()['cnt']?.toString() ?? '0') ?? 0;
    print("✅ $roundCount rounds seeded (1-$maxRuns)");

    // ── Get first available referee with validation ──────────────────────────
    final refResult = await conn.execute(
      "SELECT referee_id FROM tbl_referee ORDER BY referee_id LIMIT 1"
    );
    if (refResult.rows.isEmpty) {
      throw Exception('No referees found. Please add at least one referee.');
    }
    final defaultRefereeId = int.parse(
      refResult.rows.first.assoc()['referee_id'] ?? '0',
    );
    
    // Validate referee ID is valid (>0)
    if (defaultRefereeId <= 0) {
      throw Exception('Invalid referee ID. Please check referee table.');
    }

    // ── Parse start / end times ───────────────────────────────────────────────
    final startParts = startTime.split(':');
    final startHourBase = int.parse(startParts[0]);
    final startMinuteBase = int.parse(startParts[1]);

    final endParts = endTime.split(':');
    final endLimitH = int.parse(endParts[0]);
    final endLimitM = int.parse(endParts[1]);
    final endLimitMinutes = endLimitH * 60 + endLimitM;

    // ── Schedule each category ────────────────────────────────────────────────
    for (final entry in runsPerCategory.entries) {
      final categoryId = entry.key;
      final runs = entry.value; // matches per team
      final teams = await getTeamsByCategory(categoryId);
      if (teams.isEmpty) continue;

      final teamCount = teams.length;
      final totalMatches = (teamCount * runs) ~/ 4;
      final matchesPerRound = teamCount ~/ 4;
      
      print("\n=== SCHEDULING CATEGORY $categoryId with $teamCount teams ===");
      print("Matches per team: $runs");
      print("Total matches needed: $totalMatches");
      print("Matches per round: $matchesPerRound");
      print("Total rounds: $runs");

      // Reset time to startTime for EVERY category
      int hour = startHourBase;
      int minute = startMinuteBase;

      // Helper: current time in minutes
      int currentMinutes() => hour * 60 + minute;

      // Helper: skip lunch break 12:00–13:00
      void skipLunch() {
        if (lunchBreak && hour == 12) {
          hour = 13;
          minute = 0;
        }
      }

      void advanceTime(int minutes) {
        minute += minutes;
        while (minute >= 60) {
          minute -= 60;
          hour++;
        }
        skipLunch();
      }

      skipLunch();

      // ── PROPER ROUND-ROBIN SCHEDULING ─────────────────────────────
      final random = Random();
      
      // Initialize fairness tracker
      final tracker = FairnessTracker(categoryId, runs, teams);
      
      // Create a map for quick team lookup
      final Map<int, Map<String, dynamic>> teamMap = {};
      for (final team in teams) {
        final teamId = int.parse(team['team_id'].toString());
        teamMap[teamId] = team;
      }
      
      // Target counts for RED/BLUE balance
      final targetRed = (runs / 2).ceil();
      final targetBlue = (runs / 2).floor();
      
      int matchCounter = 0;
      
      // For each round
      for (int round = 1; round <= runs; round++) {
        print("\n=== ROUND $round ===");
        
        // Get all teams that need to play in this round
        final availableTeams = <int>[];
        for (final team in teams) {
          final teamId = int.parse(team['team_id'].toString());
          final stats = tracker.teamData[teamId]!;
          
          if (!stats.playedRounds.contains(round)) {
            availableTeams.add(teamId);
          }
        }
        
        print("Available teams for round $round: $availableTeams");
        print("Need to create ${availableTeams.length ~/ 4} matches in this round");
        
        // Shuffle for randomness
        availableTeams.shuffle(random);
        
        // Create matches for this round - one for each group of 4 teams
        for (int m = 0; m < availableTeams.length; m += 4) {
          if (m + 3 >= availableTeams.length) break;
          
          // Take 4 teams for this match
          final matchTeams = availableTeams.sublist(m, m + 4);
          matchCounter++;
          
          print("\nCreating Match $matchCounter (Round $round) with teams: $matchTeams");
          
          // Try to find a fair RED/BLUE split for these 4 teams
          Map<String, dynamic>? bestMatch;
          int bestScore = -1;
          
          // Try all possible RED/BLUE splits (6 combinations)
          final List<List<int>> redCombinations = [
            [0, 1], [0, 2], [0, 3], [1, 2], [1, 3], [2, 3]
          ];
          
          for (final redIndices in redCombinations) {
            final redIds = [
              matchTeams[redIndices[0]],
              matchTeams[redIndices[1]]
            ];
            final blueIds = matchTeams.where((id) => !redIds.contains(id)).toList();
            
            // Check RED balance
            bool redBalanceOk = true;
            for (final teamId in redIds) {
              final stats = tracker.teamData[teamId]!;
              if (stats.redCount >= targetRed) {
                redBalanceOk = false;
                break;
              }
            }
            if (!redBalanceOk) continue;
            
            // Check BLUE balance
            bool blueBalanceOk = true;
            for (final teamId in blueIds) {
              final stats = tracker.teamData[teamId]!;
              if (stats.blueCount >= targetBlue) {
                blueBalanceOk = false;
                break;
              }
            }
            if (!blueBalanceOk) continue;
            
            // Check fairness constraints
            if (!tracker.isMatchFair(redIds, blueIds, round)) {
              continue;
            }
            
            // Calculate score - prefer teams that need this arena more
            int score = 0;
            for (final teamId in redIds) {
              final stats = tracker.teamData[teamId]!;
              score += (targetRed - stats.redCount) * 2;
            }
            for (final teamId in blueIds) {
              final stats = tracker.teamData[teamId]!;
              score += (targetBlue - stats.blueCount);
            }
            
            if (score > bestScore) {
              bestScore = score;
              bestMatch = {
                'red': List<int>.from(redIds),
                'blue': List<int>.from(blueIds),
              };
            }
          }
          
          if (bestMatch != null) {
            // Valid match found
            final redIds = bestMatch['red'] as List<int>;
            final blueIds = bestMatch['blue'] as List<int>;
            
            // Record the match in tracker
            tracker.recordMatch(redIds, blueIds, round);
            
            // Create database entries
            if (currentMinutes() + durationMinutes > endLimitMinutes) {
              print("⚠️ End time reached — stopping scheduling");
              break;
            }
            
            final startHH = hour.toString().padLeft(2, '0');
            final startMM = minute.toString().padLeft(2, '0');
            final startStr = '$startHH:$startMM:00';

            int endHour = hour;
            int endMinute = minute + durationMinutes;
            while (endMinute >= 60) {
              endMinute -= 60;
              endHour++;
            }
            final endStr = '${endHour.toString().padLeft(2, '0')}:${endMinute.toString().padLeft(2, '0')}:00';

            final scheduleId = await insertSchedule(startTime: startStr, endTime: endStr);
            final matchId = await insertMatch(scheduleId);
            
            // Insert RED teams (Arena 1)
            for (final teamId in redIds) {
              print("  Inserting RED team $teamId into Arena 1");
              await insertTeamSchedule(
                matchId: matchId,
                roundId: round,
                teamId: teamId,
                refereeId: defaultRefereeId,
                arenaNumber: 1,
              );
            }
            
            // Insert BLUE teams (Arena 2)
            for (final teamId in blueIds) {
              print("  Inserting BLUE team $teamId into Arena 2");
              await insertTeamSchedule(
                matchId: matchId,
                roundId: round,
                teamId: teamId,
                refereeId: defaultRefereeId,
                arenaNumber: 2,
              );
            }
            
            final redNames = redIds.map((id) => teamMap[id]!['team_name']).join(', ');
            final blueNames = blueIds.map((id) => teamMap[id]!['team_name']).join(', ');
            print("✅ Match $matchCounter: RED: [$redNames] vs BLUE: [$blueNames] at $startStr");
            
            advanceTime(durationMinutes + intervalMinutes);
          } else {
            print("⚠️ Could not find fair match for teams $matchTeams");
            // Try a different ordering
            availableTeams.shuffle(random);
            m -= 4; // Retry this group
          }
        }
      }
      
      // Verify fairness for this category
      tracker.verifyFairness();
      print("\n=== CATEGORY $categoryId COMPLETE ===");
      print("Total matches generated: $matchCounter");
    }

    print("\n✅ Schedule generated successfully!");
    await verifyScheduleFairness();
  }

  static Future<void> verifyScheduleFairness() async {
    final conn = await DBHelper.getConnection();
    
    print("\n=== FINAL FAIRNESS VERIFICATION ===");
    
    final result = await conn.execute("""
      SELECT 
        ts.match_id,
        ts.round_id,
        t.team_id,
        t.team_name,
        ts.arena_number,
        c.category_type
      FROM tbl_teamschedule ts
      JOIN tbl_team t ON ts.team_id = t.team_id
      JOIN tbl_category c ON t.category_id = c.category_id
      ORDER BY c.category_id, t.team_id, ts.round_id
    """);
    
    final scheduleRows = result.rows.map((r) => r.assoc()).toList();
    
    // Print fairness report
    final Map<int, Map<String, dynamic>> teamStats = {};
    
    for (final row in scheduleRows) {
      final data = row;
      final teamId = int.parse(data['team_id'].toString());
      final roundId = int.parse(data['round_id'].toString());
      final arenaNum = int.parse(data['arena_number'].toString());
      final teamName = data['team_name'].toString();
      final category = data['category_type'].toString();
      
      teamStats.putIfAbsent(teamId, () => {
        'teamId': teamId,
        'teamName': teamName,
        'category': category,
        'red': 0,
        'blue': 0,
        'rounds': <int>{},
        'roundArena': <int, int>{},
      });
      
      final stats = teamStats[teamId]!;
      
      if (arenaNum == 1) {
        stats['red'] = (stats['red'] as int) + 1;
      } else {
        stats['blue'] = (stats['blue'] as int) + 1;
      }
      
      (stats['rounds'] as Set<int>).add(roundId);
      (stats['roundArena'] as Map<int, int>)[roundId] = arenaNum;
    }
    
    // Print fairness report
    teamStats.forEach((teamId, stats) {
      final roundsSet = stats['rounds'] as Set<int>;
      final maxRound = roundsSet.isEmpty ? 0 : roundsSet.reduce((a, b) => a > b ? a : b);
      final missingRounds = <int>[];
      for (int r = 1; r <= maxRound; r++) {
        if (!roundsSet.contains(r)) {
          missingRounds.add(r);
        }
      }
      
      final sortedRounds = roundsSet.toList()..sort();
      final roundArena = stats['roundArena'] as Map<int, int>;
      final arenaSequence = sortedRounds.map((r) => roundArena[r] == 1 ? 'R' : 'B').join(' → ');
      
      String fairnessIcon = '✅';
      if (((stats['red'] as int) - (stats['blue'] as int)).abs() > 1) {
        fairnessIcon = '⚠️';
      } else if (missingRounds.isNotEmpty) {
        fairnessIcon = '❌';
      }
      
      print("$fairnessIcon ${stats['category']} - ${stats['teamName']}: RED=${stats['red']}, BLUE=${stats['blue']} | Rounds: ${roundsSet.join(', ')}");
      print("   Arena sequence: $arenaSequence");
      
      if (missingRounds.isNotEmpty) {
        print("   ⚠️  MISSING ROUNDS: $missingRounds");
      }
      
      if (((stats['red'] as int) - (stats['blue'] as int)).abs() > 1) {
        print("   ⚠️  Red/Blue imbalance: Should be within 1 game of each other");
      }
    });
    
    // Summary statistics
    print("\n=== FAIRNESS SUMMARY ===");
    final teamCount = teamStats.length;
    final totalMatches = teamStats.values.fold(0, (sum, stats) => sum + (stats['red'] as int) + (stats['blue'] as int)) ~/ 2;
    
    print("Total teams: $teamCount");
    print("Total matches: $totalMatches");
    
    final perfectTeams = teamStats.values.where((stats) => stats['red'] == stats['blue']).length;
    
    print("Perfectly balanced teams (equal RED/BLUE): $perfectTeams/$teamCount");
    
    if (perfectTeams == teamCount) {
      print("🎉 ALL TEAMS HAVE PERFECT RED/BLUE BALANCE!");
    } else {
      print("⚠️ Some teams have imbalance. Maximum allowed difference is 1 game.");
    }
  }

  // ── SCORES ────────────────────────────────────────────────────────────────

  static Future<List<Map<String, dynamic>>> getScoresByCategory(
      int categoryId) async {
    final conn = await getConnection();
    final result = await conn.execute("""
      SELECT
        t.team_id,
        t.team_name,
        COALESCE(s.round_id, 0) as round_id,
        COALESCE(s.score_totalscore, 0) as score_totalscore,
        COALESCE(s.score_totalduration, '00:00') as score_totalduration
      FROM tbl_team t
      LEFT JOIN tbl_score s ON s.team_id = t.team_id
      WHERE t.category_id = :categoryId
      ORDER BY t.team_id, s.round_id
    """, {"categoryId": categoryId});
    
    final rows = result.rows.map((r) => r.assoc()).toList();
    print("📊 getScoresByCategory for category $categoryId returned ${rows.length} rows");
    for (var row in rows) {
      print("   Row: team_id=${row['team_id']}, round_id=${row['round_id']}, score=${row['score_totalscore']}");
    }
    return rows;
  }

  static Future<void> upsertScore({
    required int teamId,
    required int roundId,
    required int matchId,
    int? refereeId,
    required int independentScore,
    required int violation,
    int allianceScore = 0,
    required int totalScore,
    required String totalDuration,
  }) async {
    final conn = await getConnection();
    final matchParam = (matchId > 0) ? matchId : null;
    
    print("📝 UPSERT SCORE CALLED:");
    print("   teamId: $teamId");
    print("   roundId: $roundId");
    print("   matchId: $matchId");
    print("   independentScore: $independentScore");
    print("   allianceScore: $allianceScore");
    print("   violation: $violation");
    print("   totalScore: $totalScore");
    
    // Check if record exists
    final checkResult = await conn.execute("""
      SELECT COUNT(*) as cnt FROM tbl_score 
      WHERE team_id = :teamId AND round_id = :roundId
    """, {
      "teamId": teamId,
      "roundId": roundId,
    });
    
    final exists = int.tryParse(checkResult.rows.first.assoc()['cnt']?.toString() ?? '0') ?? 0;
    
    if (exists > 0) {
      // Update existing
      print("🔄 Updating existing score record");
      await conn.execute("""
        UPDATE tbl_score
        SET 
          score_individual = :indep,
          score_alliance = :alliance,
          score_violation = :viol,
          score_totalscore = :total,
          score_totalduration = :duration,
          match_id = :match,
          referee_id = :ref
        WHERE team_id = :team AND round_id = :round
      """, {
        "indep": independentScore,
        "alliance": allianceScore,
        "viol": violation,
        "total": totalScore,
        "duration": totalDuration,
        "match": matchParam,
        "ref": refereeId,
        "team": teamId,
        "round": roundId,
      });
    } else {
      // Insert new
      print("➕ Inserting new score record");
      await conn.execute("""
        INSERT INTO tbl_score
          (score_individual, score_alliance, score_violation, score_totalscore,
           score_totalduration, score_isapproved,
           match_id, round_id, team_id, referee_id)
        VALUES
          (:indep, :alliance, :viol, :total, :duration, 0,
           :match, :round, :team, :ref)
      """, {
        "indep": independentScore,
        "alliance": allianceScore,
        "viol": violation,
        "total": totalScore,
        "duration": totalDuration,
        "match": matchParam,
        "round": roundId,
        "team": teamId,
        "ref": refereeId,
      });
    }
    
    print("✅ Score saved successfully for team $teamId, round $roundId");
  }

// db_helper.dart - Fix the propagateAllianceScoreForMatch method

static Future<void> propagateAllianceScoreForMatch({
  required int matchId,
  required int roundId,
  required int sourceTeamId,
  required int allianceScore,
}) async {
  print("\n🔍🔍🔍 PROPAGATE CALLED 🔍🔍🔍");
  print("   matchId: $matchId");
  print("   roundId: $roundId");
  print("   sourceTeamId: $sourceTeamId");
  print("   allianceScore: $allianceScore");
  
  if (matchId <= 0) {
    print("❌ Cannot propagate: matchId is $matchId (invalid)");
    return;
  }

  final conn = await getConnection();

  try {
    // First, let's check what teams are in this match
    print("\n📋 STEP 1: Getting all teams in match $matchId, round $roundId");
    final allTeamsRes = await conn.execute("""
      SELECT 
        ts.team_id,
        t.team_name,
        ts.arena_number,
        ts.round_id
      FROM tbl_teamschedule ts
      JOIN tbl_team t ON ts.team_id = t.team_id
      WHERE ts.match_id = :matchId AND ts.round_id = :roundId
      ORDER BY ts.arena_number, ts.team_id
    """, {
      "matchId": matchId,
      "roundId": roundId,
    });

    final allTeams = allTeamsRes.rows.map((r) => r.assoc()).toList();
    
    if (allTeams.isEmpty) {
      print("❌ No teams found in match $matchId, round $roundId");
      return;
    }

    print("✅ Found ${allTeams.length} total teams in match:");
    for (final team in allTeams) {
      print("   - Team ${team['team_id']} (${team['team_name']}), Arena ${team['arena_number']}");
    }
    
    // Determine if this is a 1v1 or 2v2 match based on number of teams
    final bool isOneVsOne = allTeams.length == 2;
    print("\n📋 Match type: ${isOneVsOne ? '1v1' : '2v2'}");

    // Group by arena
    final Map<int, List<Map<String, dynamic>>> teamsByArena = {};
    for (final team in allTeams) {
      final arena = int.parse(team['arena_number'].toString());
      teamsByArena.putIfAbsent(arena, () => []).add(team);
    }
    
    print("\n📋 Teams by arena:");
    for (final entry in teamsByArena.entries) {
      print("  Arena ${entry.key}:");
      for (final team in entry.value) {
        print("    - Team ${team['team_id']} (${team['team_name']})");
      }
    }

    // Find which arena the source team is in
    int? sourceArena;
    Map<String, dynamic>? sourceTeam;
    for (final arenaEntry in teamsByArena.entries) {
      for (final team in arenaEntry.value) {
        if (int.parse(team['team_id'].toString()) == sourceTeamId) {
          sourceArena = arenaEntry.key;
          sourceTeam = team;
          break;
        }
      }
      if (sourceArena != null) break;
    }

    if (sourceArena == null) {
      print("❌ Could not find source team $sourceTeamId in any arena");
      return;
    }

    print("\n✅ Source team found: ${sourceTeam!['team_name']} in Arena $sourceArena");

    // IMPORTANT FIX: For 1v1 matches, the partner is in the OTHER arena
    // For 2v2 matches, partners are in the SAME arena
    List<int> targetTeamIds = [];
    
    // In db_helper.dart, this part is already correct:
if (isOneVsOne) {
  // 1v1 match: Partner is the opponent in the other arena
  print("\n🔄 1v1 match detected - sharing with opponent");
  final opponentArena = sourceArena == 1 ? 2 : 1;
  final opponentTeams = teamsByArena[opponentArena] ?? [];
  
  for (final opponent in opponentTeams) {
    targetTeamIds.add(int.parse(opponent['team_id'].toString()));
  }
  print("   Target opponent teams: $targetTeamIds");
  
} else {
  // 2v2 match: Partners are teammates in the same arena (excluding self)
  print("\n🔄 2v2 match detected - sharing with teammates");
  final partnerTeams = teamsByArena[sourceArena]?.where((team) {
    return int.parse(team['team_id'].toString()) != sourceTeamId;
  }).toList() ?? [];
  
  for (final partner in partnerTeams) {
    targetTeamIds.add(int.parse(partner['team_id'].toString()));
  }
  print("   Target partner teams: $targetTeamIds");
}

    // Propagate to all target teams using the SAME roundId
    for (final targetTeamId in targetTeamIds) {
      print("\n🔄 Propagating to team $targetTeamId for round $roundId");
      await _updateTeamScore(
        conn, 
        targetTeamId, 
        roundId,  // Use the SAME roundId as the source
        matchId, 
        allianceScore
      );
    }

    // Verify the updates worked
    print("\n📋 STEP 3: Verifying updates...");
    for (final team in allTeams) {
      final teamId = int.parse(team['team_id'].toString());
      final verifyResult = await conn.execute("""
        SELECT score_alliance, score_totalscore
        FROM tbl_score
        WHERE team_id = :teamId AND round_id = :roundId
      """, {
        "teamId": teamId,
        "roundId": roundId,
      });

      if (verifyResult.rows.isNotEmpty) {
        final data = verifyResult.rows.first.assoc();
        print("   Team ${team['team_name']}: ALL=${data['score_alliance']}, TOTAL=${data['score_totalscore']}");
      } else {
        print("   Team ${team['team_name']}: No score record found!");
      }
    }

    print("\n✅✅✅ Propagation complete for match $matchId ✅✅✅");

  } catch (e, stackTrace) {
    print('❌ Error in propagateAllianceScoreForMatch: $e');
    print(stackTrace);
  }
}

// Helper method to update a team's score
static Future<void> _updateTeamScore(
  MySQLConnection conn,
  int teamId,
  int roundId,
  int matchId,
  int allianceScore,
) async {
  print("  📝 Processing team $teamId for round $roundId");
  print("     Alliance score to add: $allianceScore");

  // First, check if the team has a score record for this round
  final checkRes = await conn.execute("""
    SELECT COUNT(*) as cnt FROM tbl_score
    WHERE team_id = :teamId AND round_id = :roundId
  """, {
    "teamId": teamId,
    "roundId": roundId,
  });

  final exists = int.parse(checkRes.rows.first.assoc()['cnt'].toString());

  if (exists > 0) {
    // Update existing score
    print("    ✅ Score record exists - updating");
    
    // Get current scores
    final currentRes = await conn.execute("""
      SELECT score_individual, score_alliance, score_violation
      FROM tbl_score
      WHERE team_id = :teamId AND round_id = :roundId
    """, {
      "teamId": teamId,
      "roundId": roundId,
    });

    final current = currentRes.rows.first.assoc();
    final individual = int.parse(current['score_individual'].toString());
    final currentAlliance = int.parse(current['score_alliance'].toString());
    final violation = int.parse(current['score_violation'].toString());
    
    // Add the new alliance score to existing alliance score
    final newAlliance = currentAlliance + allianceScore;
    final newTotal = individual + newAlliance - violation;

    print("     Current: IND=$individual, ALL=$currentAlliance, VIO=$violation, TOTAL=${individual + currentAlliance - violation}");
    print("     New: ALL=$newAlliance, TOTAL=$newTotal");

    await conn.execute("""
      UPDATE tbl_score
      SET 
        score_alliance = :alliance,
        score_totalscore = :total
      WHERE team_id = :teamId AND round_id = :roundId
    """, {
      "alliance": newAlliance,
      "total": newTotal,
      "teamId": teamId,
      "roundId": roundId,
    });

    print("    ✅ Updated: ALL=$newAlliance, TOTAL=$newTotal");
  } else {
    // Insert new score
    print("    ⚠️ No score record exists - creating new");
    
    await conn.execute("""
      INSERT INTO tbl_score
        (team_id, round_id, score_individual, score_alliance, score_violation, 
         score_totalscore, score_totalduration, score_isapproved, match_id, referee_id)
      VALUES
        (:teamId, :roundId, 0, :alliance, 0, :total, '00:00', 0, :matchId, NULL)
    """, {
      "teamId": teamId,
      "roundId": roundId,
      "alliance": allianceScore,
      "total": allianceScore,
      "matchId": matchId,
    });

    print("    ✅ Created new: TOTAL=$allianceScore");
  }
  
  // Verify the update
  final verifyRes = await conn.execute("""
    SELECT score_alliance, score_totalscore
    FROM tbl_score
    WHERE team_id = :teamId AND round_id = :roundId
  """, {
    "teamId": teamId,
    "roundId": roundId,
  });
  
  if (verifyRes.rows.isNotEmpty) {
    final data = verifyRes.rows.first.assoc();
    print("     Verification: ALL=${data['score_alliance']}, TOTAL=${data['score_totalscore']}");
  }
}

  // Debug method to check match structure
  static Future<void> debugCheckMatch(int matchId, int roundId) async {
    final conn = await getConnection();
    
    print("\n🔍 DEBUG: Checking match $matchId, round $roundId");
    
    final result = await conn.execute("""
      SELECT 
        ts.match_id,
        ts.round_id,
        ts.team_id,
        t.team_name,
        ts.arena_number
      FROM tbl_teamschedule ts
      JOIN tbl_team t ON ts.team_id = t.team_id
      WHERE ts.match_id = :matchId AND ts.round_id = :roundId
      ORDER BY ts.arena_number, ts.team_id
    """, {
      "matchId": matchId,
      "roundId": roundId,
    });
    
    final rows = result.rows.map((r) => r.assoc()).toList();
    
    if (rows.isEmpty) {
      print("❌ No teams found for match $matchId, round $roundId");
      return;
    }
    
    print("📊 Found ${rows.length} teams in this match:");
    
    // Group by arena
    final Map<int, List<Map<String, dynamic>>> byArena = {};
    for (final row in rows) {
      final arena = int.parse(row['arena_number'].toString());
      byArena.putIfAbsent(arena, () => []).add(row);
    }
    
    for (final arenaEntry in byArena.entries) {
      print("  Arena ${arenaEntry.key}:");
      for (final team in arenaEntry.value) {
        print("    - Team ${team['team_id']}: ${team['team_name']}");
      }
    }
  }

  // Helper method to get match partner for a team
  static Future<int?> getMatchPartner(int matchId, int teamId, int roundId) async {
    final conn = await getConnection();
    
    final result = await conn.execute("""
      SELECT ts2.team_id
      FROM tbl_teamschedule ts1
      JOIN tbl_teamschedule ts2 
        ON ts1.match_id = ts2.match_id 
        AND ts1.round_id = ts2.round_id
        AND ts1.arena_number = ts2.arena_number
        AND ts1.team_id != ts2.team_id
      WHERE ts1.match_id = :matchId 
        AND ts1.round_id = :roundId
        AND ts1.team_id = :teamId
      LIMIT 1
    """, {
      "matchId": matchId,
      "roundId": roundId,
      "teamId": teamId,
    });
    
    if (result.rows.isNotEmpty) {
      return int.tryParse(result.rows.first.assoc()['team_id']?.toString() ?? '0');
    }
    return null;
  }
}