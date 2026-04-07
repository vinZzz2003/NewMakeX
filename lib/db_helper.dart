import 'dart:math';
import 'dart:async';
import 'package:mysql_client/mysql_client.dart';
import 'schedule_fairness_helper.dart';
import 'config.dart';
import 'championship_settings.dart';

class DBHelper {
  static MySQLConnection? _connection;

  // Broadcast stream for bracket updates. Emits category_id when a bracket match is updated.
  static final StreamController<int> bracketUpdateController = StreamController<int>.broadcast();

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
      await executeDual("""
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
      await executeDual("""
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
      await executeDual("""
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
      print("ℹ️ Migration: category_id already present on tbl_championship_schedule.");
    }

    // Create Explorer double elimination bracket table
    try {
      await executeDual("""
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

    // ============================================================
    // ADD THESE NEW MIGRATIONS HERE
    // ============================================================
    // Add round_name column to tbl_championship_schedule
    try {
      await conn.execute("""
        ALTER TABLE tbl_championship_schedule
        ADD COLUMN round_name VARCHAR(50) DEFAULT NULL
      """);
      print("✅ Added round_name column to tbl_championship_schedule");
    } catch (e) {
      print("ℹ️ round_name column may already exist: $e");
    }

    // Add bracket_side column to tbl_championship_schedule
    try {
      await conn.execute("""
        ALTER TABLE tbl_championship_schedule
        ADD COLUMN bracket_side VARCHAR(20) DEFAULT 'winners'
      """);
      print("✅ Added bracket_side column to tbl_championship_schedule");
    } catch (e) {
      print("ℹ️ bracket_side column may already exist: $e");
    }

    // Add match_number column to tbl_championship_schedule
    try {
      await conn.execute("""
        ALTER TABLE tbl_championship_schedule
        ADD COLUMN match_number INT NOT NULL DEFAULT 1
      """);
      print("✅ Added match_number column to tbl_championship_schedule");
    } catch (e) {
      print("ℹ️ match_number column may already exist: $e");
    }

    // Add winner_alliance_id column to tbl_championship_schedule
    try {
      await conn.execute("""
        ALTER TABLE tbl_championship_schedule
        ADD COLUMN winner_alliance_id INT DEFAULT NULL
      """);
      print("✅ Added winner_alliance_id column to tbl_championship_schedule");
    } catch (e) {
      print("ℹ️ winner_alliance_id column may already exist: $e");
    }

    // Add schedule_time column to tbl_championship_bestof3
    try {
      await conn.execute("""
        ALTER TABLE tbl_championship_bestof3
        ADD COLUMN schedule_time VARCHAR(20) DEFAULT '--:--'
      """);
      print("✅ Added schedule_time column to tbl_championship_bestof3");
    } catch (e) {
      print("ℹ️ schedule_time column may already exist: $e");
    }

    // Add match_round column to tbl_championship_bestof3
    try {
      await conn.execute("""
        ALTER TABLE tbl_championship_bestof3
        ADD COLUMN match_round INT NOT NULL DEFAULT 1
      """);
      print("✅ Added match_round column to tbl_championship_bestof3");
    } catch (e) {
      print("ℹ️ match_round column may already exist: $e");
    }

    // Add match_position column to tbl_championship_bestof3
    try {
      await conn.execute("""
        ALTER TABLE tbl_championship_bestof3
        ADD COLUMN match_position INT NOT NULL DEFAULT 1
      """);
      print("✅ Added match_position column to tbl_championship_bestof3");
    } catch (e) {
      print("ℹ️ match_position column may already exist: $e");
    }

    // Add bracket_side column to tbl_championship_bestof3
    try {
      await conn.execute("""
        ALTER TABLE tbl_championship_bestof3
        ADD COLUMN bracket_side VARCHAR(20) NOT NULL DEFAULT 'winners'
      """);
      print("✅ Added bracket_side column to tbl_championship_bestof3");
    } catch (e) {
      print("ℹ️ bracket_side column may already exist: $e");
    }

    // Add missing columns to explorer championship schedule
    try {
      await conn.execute("""
        ALTER TABLE tbl_explorer_championship_schedule
        ADD COLUMN IF NOT EXISTS match_number INT NOT NULL DEFAULT 1,
        ADD COLUMN IF NOT EXISTS round_name VARCHAR(50) DEFAULT NULL,
        ADD COLUMN IF NOT EXISTS bracket_side VARCHAR(20) DEFAULT 'winners',
        ADD COLUMN IF NOT EXISTS winner_alliance_id INT DEFAULT NULL
      """);
      print("✅ Added missing columns to tbl_explorer_championship_schedule");
    } catch (e) {
      print("ℹ️ Explorer championship schedule columns check: $e");
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

  // Tables that have explorer-specific counterparts (base names without 'tbl_' prefix)
  static const List<String> _explorerTableBases = [
    'alliance_selections',
    'championship_scores',
    'championship_schedule',
    'championship_settings',
    'double_elimination',
    'match',
    'schedule',
    'teamschedule',
    'player',
    'mentor',
    'school',
    'category_settings',
    'score',
    'team',
    'round',
    'category',
  ];

  // Executes the given SQL against the original tables, then attempts to run
  // a transformed copy against explorer-specific tables (tbl_explorer_...)
  // Non-fatal: explorer writes are best-effort and errors are logged only.
  static Future<dynamic> executeDual(
    String sql, [
    Map<String, dynamic>? params,
  ]) async {
    final conn = await getConnection();

    // Execute against original tables first and keep the result
    final result = await conn.execute(sql, params ?? {});

    // Build explorer variant by replacing table names where applicable
    String explorerSql = sql;
    bool explorerGenerated = false;
    bool explorerExecuted = false;
    try {
      for (final base in _explorerTableBases) {
        final original = 'tbl_' + base;
        final explorer = 'tbl_explorer_' + base;
        explorerSql = explorerSql.replaceAll(
          RegExp(r'\b' + original + r'\b'),
          explorer,
        );
      }

      if (explorerSql != sql) {
        explorerGenerated = true;
      }
    } catch (e) {
      print('ℹ️ executeDual failed to generate explorer SQL: $e');
      explorerGenerated = false;
      explorerSql = sql;
    }

    // If explorer variant was generated, execute it (one-time)
    if (explorerGenerated && !explorerExecuted) {
      try {
        await conn.execute(explorerSql, params ?? {});
        print('ℹ️ executeDual: wrote explorer mirror');
        explorerExecuted = true;
      } catch (e) {
        print('ℹ️ executeDual explorer write skipped or failed: $e');
      }
    }

    return result;
  }

  // This centralizes the bracket propagation logic so other UI layers can call it.
  static Future<void> updateBracketWinner(int matchId, int winnerId) async {
    final conn = await getConnection();
    int _emittedCategoryId = 0;
    
    int _affectedRows(dynamic r) {
      try {
        if (r == null) return 0;
        if (r.affectedRows != null) return r.affectedRows as int;
        if (r.rowsAffected != null) return r.rowsAffected as int;
        return 0;
      } catch (_) {
        return 0;
      }
    }

    try {
      await conn.execute("START TRANSACTION");

      // First, get the category_id and other match details
      int categoryId = 0;
      String roundName = '';
      int roundNumber = 0;
      int matchPosition = 0;
      String bracketSide = '';
      int? nextMatchIdWinner;
      int? nextMatchIdLoser;
      int? nextWinnerPos;
      int? nextLoserPos;
      int alliance1Id = 0;
      int alliance2Id = 0;

      // Try to get match details from the table
      final matchDetails = await conn.execute(
        """
        SELECT category_id, round_name, round_number, match_position, bracket_side,
               next_match_id_winner, next_match_position_winner,
               next_match_id_loser, next_match_position_loser,
               alliance1_id, alliance2_id
        FROM tbl_double_elimination
        WHERE match_id = :matchId
        """,
        {"matchId": matchId},
      );

      if (matchDetails.rows.isNotEmpty) {
        final data = matchDetails.rows.first.assoc();
        categoryId = int.tryParse(data['category_id']?.toString() ?? '0') ?? 0;
        roundName = data['round_name']?.toString() ?? '';
        roundNumber = int.tryParse(data['round_number']?.toString() ?? '0') ?? 0;
        matchPosition = int.tryParse(data['match_position']?.toString() ?? '0') ?? 0;
        bracketSide = data['bracket_side']?.toString() ?? '';
        nextMatchIdWinner = int.tryParse(data['next_match_id_winner']?.toString() ?? '0');
        nextMatchIdLoser = int.tryParse(data['next_match_id_loser']?.toString() ?? '0');
        nextWinnerPos = int.tryParse(data['next_match_position_winner']?.toString() ?? '1');
        nextLoserPos = int.tryParse(data['next_match_position_loser']?.toString() ?? '1');
        alliance1Id = int.tryParse(data['alliance1_id']?.toString() ?? '0') ?? 0;
        alliance2Id = int.tryParse(data['alliance2_id']?.toString() ?? '0') ?? 0;
      }

      if (categoryId == 0) {
        print("❌ updateBracketWinner: Could not find match $matchId");
        await conn.execute("ROLLBACK");
        return;
      }

      _emittedCategoryId = categoryId;
      final int loserId = (winnerId == alliance1Id) ? alliance2Id : alliance1Id;

      // Update BOTH tables explicitly
      
      // 1. Update winner in tbl_double_elimination
      await conn.execute(
        """
        UPDATE tbl_double_elimination
        SET winner_alliance_id = :winnerId, status = 'completed'
        WHERE match_id = :matchId
        """,
        {"winnerId": winnerId, "matchId": matchId},
      );
      
      // 2. Update winner in tbl_explorer_double_elimination
      await conn.execute(
        """
        UPDATE tbl_explorer_double_elimination
        SET winner_alliance_id = :winnerId, status = 'completed'
        WHERE match_id = :matchId
        """,
        {"winnerId": winnerId, "matchId": matchId},
      );
      
      print('✅ Updated winner in both tables for match $matchId');

      // Propagate winner to next matches in BOTH tables
      if (nextMatchIdWinner != null && nextMatchIdWinner > 0) {
        if (nextWinnerPos == 1) {
          await conn.execute(
            """
            UPDATE tbl_double_elimination
            SET alliance1_id = :winnerId
            WHERE match_id = :nextMatchId AND (alliance1_id IS NULL OR alliance1_id = 0)
            """,
            {"winnerId": winnerId, "nextMatchId": nextMatchIdWinner},
          );
          await conn.execute(
            """
            UPDATE tbl_explorer_double_elimination
            SET alliance1_id = :winnerId
            WHERE match_id = :nextMatchId AND (alliance1_id IS NULL OR alliance1_id = 0)
            """,
            {"winnerId": winnerId, "nextMatchId": nextMatchIdWinner},
          );
          print('✅ Propagated winner to match $nextMatchIdWinner pos1 in both tables');
        } else {
          await conn.execute(
            """
            UPDATE tbl_double_elimination
            SET alliance2_id = :winnerId
            WHERE match_id = :nextMatchId AND (alliance2_id IS NULL OR alliance2_id = 0)
            """,
            {"winnerId": winnerId, "nextMatchId": nextMatchIdWinner},
          );
          await conn.execute(
            """
            UPDATE tbl_explorer_double_elimination
            SET alliance2_id = :winnerId
            WHERE match_id = :nextMatchId AND (alliance2_id IS NULL OR alliance2_id = 0)
            """,
            {"winnerId": winnerId, "nextMatchId": nextMatchIdWinner},
          );
          print('✅ Propagated winner to match $nextMatchIdWinner pos2 in both tables');
        }
      }

      // Propagate loser to next matches in BOTH tables
      if (nextMatchIdLoser != null && nextMatchIdLoser > 0 && loserId > 0) {
        if (nextLoserPos == 1) {
          await conn.execute(
            """
            UPDATE tbl_double_elimination
            SET alliance1_id = :loserId
            WHERE match_id = :nextMatchId AND (alliance1_id IS NULL OR alliance1_id = 0)
            """,
            {"loserId": loserId, "nextMatchId": nextMatchIdLoser},
          );
          await conn.execute(
            """
            UPDATE tbl_explorer_double_elimination
            SET alliance1_id = :loserId
            WHERE match_id = :nextMatchId AND (alliance1_id IS NULL OR alliance1_id = 0)
            """,
            {"loserId": loserId, "nextMatchId": nextMatchIdLoser},
          );
          print('✅ Propagated loser to match $nextMatchIdLoser pos1 in both tables');
        } else {
          await conn.execute(
            """
            UPDATE tbl_double_elimination
            SET alliance2_id = :loserId
            WHERE match_id = :nextMatchId AND (alliance2_id IS NULL OR alliance2_id = 0)
            """,
            {"loserId": loserId, "nextMatchId": nextMatchIdLoser},
          );
          await conn.execute(
            """
            UPDATE tbl_explorer_double_elimination
            SET alliance2_id = :loserId
            WHERE match_id = :nextMatchId AND (alliance2_id IS NULL OR alliance2_id = 0)
            """,
            {"loserId": loserId, "nextMatchId": nextMatchIdLoser},
          );
          print('✅ Propagated loser to match $nextMatchIdLoser pos2 in both tables');
        }
      }

      await conn.execute("COMMIT");
      
      // Auto-sync championship schedule after bracket update
      await syncChampionshipScheduleFromBracket(_emittedCategoryId);
      await syncScheduleWinnersFromBestOf3(_emittedCategoryId);
      await updateWaitingMatches(_emittedCategoryId);
      
      // Sync explorer tables
      await syncExplorerBracketTable(_emittedCategoryId);
      await syncExplorerChampionshipSchedule(_emittedCategoryId);
      
      try {
        if (_emittedCategoryId > 0) {
          bracketUpdateController.add(_emittedCategoryId);
          print('ℹ️ updateBracketWinner: emitted bracket update for category $_emittedCategoryId');
        }
      } catch (_) {}
    } catch (e) {
      try {
        await conn.execute("ROLLBACK");
      } catch (_) {}
      print("❌ updateBracketWinner error: $e");
      rethrow;
    }
  }

  // Mark all matches in a Best-of-3 series when the series winner is known
  static Future<void> updateSeriesWinner({
    required int categoryId,
    required int roundNumber,
    required int matchPosition,
    required String bracketSide,
    required int winnerId,
  }) async {
    final conn = await getConnection();
    try {
      await DBHelper.executeDual(
        """
        UPDATE tbl_championship_schedule
        SET
          status = CASE
            WHEN match_number <= 2 THEN 'completed'
            ELSE 'not_needed'
          END,
          winner_alliance_id = CASE
            WHEN match_number <= 2 THEN :winnerId
            ELSE NULL
          END
        WHERE category_id = :catId AND match_round = :roundNum AND match_position = :matchPos
        """,
        {
          "winnerId": winnerId,
          "catId": categoryId,
          "roundNum": roundNumber,
          "matchPos": matchPosition,
        },
      );
      print('ℹ️ updateSeriesWinner: updated schedule for category $categoryId round $roundNumber pos $matchPosition with winner $winnerId');
      
      // Auto-sync championship schedule after series winner is set
      await syncChampionshipScheduleFromBracket(categoryId);
      await syncScheduleWinnersFromBestOf3(categoryId);
      await updateWaitingMatches(categoryId);
      await syncExplorerChampionshipSchedule(categoryId);
      
    } catch (e) {
      print('❌ updateSeriesWinner error: $e');
      rethrow;
    }
  }

  // Auto-sync championship schedule from bracket table
  static Future<void> syncChampionshipScheduleFromBracket(int categoryId) async {
    final conn = await getConnection();
    
    try {
      print("🔄 Auto-syncing championship schedule for category $categoryId");
      
      // Get settings
      final settings = await loadChampionshipSettings(categoryId);
      final matchesPerSeries = settings?.matchesPerAlliance ?? 3;
      
      // Use the canonical bracket table
      const String bracketTable = 'tbl_double_elimination';
      print("📊 Syncing from bracket table: $bracketTable");
      
      // Get ALL matches from bracket that have both alliances
      final bracketMatches = await conn.execute("""
        SELECT 
          round_number,
          match_position,
          bracket_side,
          round_name,
          alliance1_id,
          alliance2_id,
          winner_alliance_id,
          schedule_time
        FROM $bracketTable
        WHERE category_id = :catId
          AND alliance1_id IS NOT NULL 
          AND alliance1_id > 0
          AND alliance2_id IS NOT NULL 
          AND alliance2_id > 0
        ORDER BY 
          CASE bracket_side
            WHEN 'winners' THEN 1
            WHEN 'losers' THEN 2
            WHEN 'grand' THEN 3
          END,
          round_number,
          match_position
      """, {"catId": categoryId});
      
      if (bracketMatches.rows.isEmpty) {
        print("⚠️ No bracket matches to sync for category $categoryId");
        return;
      }
      
      print("📊 Found ${bracketMatches.rows.length} bracket matches to sync");
      
      // Clear existing schedule for this category
      await executeDual(
        "DELETE FROM tbl_championship_schedule WHERE category_id = :catId",
        {"catId": categoryId},
      );
      
      int matchesInserted = 0;
      
      for (final row in bracketMatches.rows) {
        final data = row.assoc();
        final alliance1Id = int.parse(data['alliance1_id'].toString());
        final alliance2Id = int.parse(data['alliance2_id'].toString());
        final winnerId = int.tryParse(data['winner_alliance_id']?.toString() ?? '0') ?? 0;
        final roundNumber = int.parse(data['round_number'].toString());
        final matchPosition = int.parse(data['match_position'].toString());
        final bracketSide = data['bracket_side'].toString();
        final roundName = data['round_name']?.toString() ?? '';
        final baseTime = data['schedule_time']?.toString() ?? '13:00';
        
        // Parse base time
        List<String> timeParts = baseTime.split(':');
        int baseHour = int.parse(timeParts[0]);
        int baseMinute = int.parse(timeParts[1]);
        
        for (int matchNum = 1; matchNum <= matchesPerSeries; matchNum++) {
          // Calculate time (add 8 min per match)
          int minute = baseMinute + (matchNum - 1) * 8;
          int hour = baseHour;
          while (minute >= 60) {
            minute -= 60;
            hour++;
          }
          final timeStr = '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
          
          // Determine if match is completed
          bool isMatchCompleted = false;
          if (winnerId > 0) {
            if (matchNum <= 2) {
              isMatchCompleted = true;
            } else if (matchNum == 3) {
              // Check if Match 3 was actually played
              try {
                final check = await conn.execute("""
                  SELECT COUNT(*) as cnt FROM tbl_championship_bestof3
                  WHERE category_id = :catId 
                    AND match_round = :roundNum 
                    AND match_position = :matchPos
                    AND match_number = 3
                    AND is_completed = 1
                """, {
                  "catId": categoryId,
                  "roundNum": roundNumber,
                  "matchPos": matchPosition,
                });
                isMatchCompleted = int.parse(check.rows.first.assoc()['cnt']?.toString() ?? '0') > 0;
              } catch (e) {}
            }
          }
          
          await executeDual("""
            INSERT INTO tbl_championship_schedule 
              (category_id, alliance1_id, alliance2_id, match_round, match_position, 
               schedule_time, status, match_number, winner_alliance_id, round_name, bracket_side)
            VALUES
              (:catId, :a1, :a2, :roundNum, :pos, :time, :status, :matchNum, :winnerId, :roundName, :bracketSide)
          """, {
            "catId": categoryId,
            "a1": alliance1Id,
            "a2": alliance2Id,
            "roundNum": roundNumber,
            "pos": matchPosition,
            "time": timeStr,
            "status": isMatchCompleted ? 'completed' : 'pending',
            "matchNum": matchNum,
            "winnerId": isMatchCompleted ? winnerId : null,
            "roundName": roundName,
            "bracketSide": bracketSide,
          });
          
          matchesInserted++;
        }
      }
      
      print("✅ Auto-synced $matchesInserted matches to championship schedule for category $categoryId");
      
    } catch (e, stackTrace) {
      print("❌ Auto-sync error for category $categoryId: $e");
      print(stackTrace);
    }
  }

  // Sync championship schedule winners from Best-of-3 results
  static Future<void> syncScheduleWinnersFromBestOf3(int categoryId) async {
    final conn = await getConnection();
    
    try {
      print("🔄 Syncing schedule winners from Best-of-3 for category $categoryId");
      
      // Get ALL Best-of-3 results
      final result = await conn.execute("""
        SELECT 
          match_round,
          match_position,
          bracket_side,
          match_number,
          winner_alliance_id,
          is_completed
        FROM tbl_championship_bestof3
        WHERE category_id = :catId AND is_completed = 1
        ORDER BY match_round, match_position, bracket_side, match_number
      """, {"catId": categoryId});
      
      if (result.rows.isEmpty) {
        print("⚠️ No Best-of-3 results found for category $categoryId");
        return;
      }
      
      print("📊 Found ${result.rows.length} Best-of-3 results");
      
      // Group by series (round, position, bracket_side)
      final Map<String, Map<int, int>> seriesResults = {};
      
      for (final row in result.rows) {
        final data = row.assoc();
        final roundNum = int.parse(data['match_round'].toString());
        final matchPos = int.parse(data['match_position'].toString());
        final bracketSide = data['bracket_side'].toString();
        final matchNumber = int.parse(data['match_number'].toString());
        final winnerId = int.parse(data['winner_alliance_id'].toString());
        
        final seriesKey = '${roundNum}_${matchPos}_${bracketSide}';
        
        if (!seriesResults.containsKey(seriesKey)) {
          seriesResults[seriesKey] = {};
        }
        seriesResults[seriesKey]![matchNumber] = winnerId;
      }
      
      int updatedCount = 0;
      
      // For each series, determine which matches should have winners
      for (final entry in seriesResults.entries) {
        final parts = entry.key.split('_');
        final roundNum = int.parse(parts[0]);
        final matchPos = int.parse(parts[1]);
        final bracketSide = parts[2];
        final matchWinners = entry.value;
        
        // Get all alliance IDs for this series from the schedule
        final scheduleCheck = await conn.execute("""
          SELECT DISTINCT alliance1_id, alliance2_id
          FROM tbl_championship_schedule
          WHERE category_id = :catId
            AND match_round = :roundNum
            AND match_position = :matchPos
            AND bracket_side = :bracketSide
          LIMIT 1
        """, {
          "catId": categoryId,
          "roundNum": roundNum,
          "matchPos": matchPos,
          "bracketSide": bracketSide,
        });
        
        if (scheduleCheck.rows.isEmpty) {
          print("⚠️ No schedule entry found for series R${roundNum}P${matchPos} $bracketSide");
          continue;
        }
        
        final scheduleData = scheduleCheck.rows.first.assoc();
        final alliance1Id = int.parse(scheduleData['alliance1_id'].toString());
        final alliance2Id = int.parse(scheduleData['alliance2_id'].toString());
        
        // Count wins for each alliance
        int winsA = 0;
        int winsB = 0;
        
        for (final winner in matchWinners.values) {
          if (winner == alliance1Id) winsA++;
          else if (winner == alliance2Id) winsB++;
        }
        
        print("📊 Series R${roundNum}P${matchPos} $bracketSide: Wins A=$winsA, B=$winsB");
        
        // Determine series winner (if any)
        int? seriesWinner;
        if (winsA >= 2) seriesWinner = alliance1Id;
        else if (winsB >= 2) seriesWinner = alliance2Id;
        
        // Update each match in the series
        for (int matchNum = 1; matchNum <= 3; matchNum++) {
          final bool matchExists = matchWinners.containsKey(matchNum);
          final bool seriesDecided = seriesWinner != null;
          final bool match3NotNeeded = (matchNum == 3) && seriesDecided && !matchExists;
          
          int? winnerId;
          String status = 'pending';
          
          if (matchExists) {
            winnerId = matchWinners[matchNum];
            status = 'completed';
          } else if (match3NotNeeded) {
            winnerId = null;
            status = 'break';
          } else if (seriesDecided && matchNum <= 2) {
            continue;
          }
          
          // Update the schedule
          await executeDual("""
            UPDATE tbl_championship_schedule 
            SET winner_alliance_id = :winnerId, status = :status
            WHERE category_id = :catId 
              AND match_round = :roundNum 
              AND match_position = :matchPos
              AND bracket_side = :bracketSide
              AND match_number = :matchNum
          """, {
            "winnerId": winnerId,
            "status": status,
            "catId": categoryId,
            "roundNum": roundNum,
            "matchPos": matchPos,
            "bracketSide": bracketSide,
            "matchNum": matchNum,
          });
          
          updatedCount++;
          print("  ✅ Updated Match $matchNum: winner=$winnerId, status=$status");
        }
      }
      
      print("✅ Synced schedule winners from Best-of-3 for category $categoryId (updated $updatedCount matches)");
    } catch (e) {
      print("❌ Error syncing schedule winners: $e");
    }
  }

  // Update waiting matches when bracket updates with new alliances
static Future<void> updateWaitingMatches(int categoryId) async {
  final conn = await getConnection();
  
  try {
    const String bracketTable = 'tbl_double_elimination';
    
    // Get all waiting matches from schedule (including those with placeholder -1)
    final waitingMatches = await conn.execute("""
      SELECT match_round, match_position, bracket_side
      FROM tbl_championship_schedule
      WHERE category_id = :catId 
        AND status = 'waiting'
      GROUP BY match_round, match_position, bracket_side
    """, {"catId": categoryId});
    
    print("📊 Checking ${waitingMatches.rows.length} waiting match series");
    
    int updatedCount = 0;
    
    for (final waiting in waitingMatches.rows) {
      final data = waiting.assoc();
      final roundNum = int.parse(data['match_round'].toString());
      final matchPos = int.parse(data['match_position'].toString());
      final bracketSide = data['bracket_side'].toString();
      
      // Check if bracket now has both alliances
      final bracketCheck = await conn.execute("""
        SELECT alliance1_id, alliance2_id
        FROM $bracketTable
        WHERE category_id = :catId 
          AND round_number = :roundNum 
          AND match_position = :matchPos
          AND bracket_side = :bracketSide
      """, {
        "catId": categoryId,
        "roundNum": roundNum,
        "matchPos": matchPos,
        "bracketSide": bracketSide,
      });
      
      if (bracketCheck.rows.isNotEmpty) {
        final bracketData = bracketCheck.rows.first.assoc();
        int a1 = int.tryParse(bracketData['alliance1_id']?.toString() ?? '0') ?? 0;
        int a2 = int.tryParse(bracketData['alliance2_id']?.toString() ?? '0') ?? 0;
        
        if (a1 > 0 && a2 > 0) {
          // Update all matches in this series from waiting to pending
          await executeDual("""
            UPDATE tbl_championship_schedule
            SET alliance1_id = :a1, alliance2_id = :a2, status = 'pending'
            WHERE category_id = :catId 
              AND match_round = :roundNum 
              AND match_position = :matchPos
              AND bracket_side = :bracketSide
              AND status = 'waiting'
          """, {
            "a1": a1,
            "a2": a2,
            "catId": categoryId,
            "roundNum": roundNum,
            "matchPos": matchPos,
            "bracketSide": bracketSide,
          });
          
          updatedCount++;
          print("✅ Updated ${bracketSide.toUpperCase()} Round $roundNum Match $matchPos from waiting to pending (A1=$a1, A2=$a2)");
        }
      }
    }
    
    print("✅ Updated $updatedCount match series from waiting to pending");
    
  } catch (e) {
    print("❌ Error updating waiting matches: $e");
  }
}

  // Sync explorer bracket table from canonical table
  static Future<void> syncExplorerBracketTable(int categoryId) async {
    final conn = await getConnection();
    
    try {
      await conn.execute("""
        INSERT INTO tbl_explorer_double_elimination 
          (match_id, category_id, round_name, match_position, bracket_side, 
           round_number, alliance1_id, alliance2_id, winner_alliance_id,
           next_match_id_winner, next_match_id_loser, next_match_position_winner, 
           next_match_position_loser, status, schedule_time)
        SELECT 
          match_id, category_id, round_name, match_position, bracket_side,
          round_number, alliance1_id, alliance2_id, winner_alliance_id,
          next_match_id_winner, next_match_id_loser, next_match_position_winner,
          next_match_position_loser, status, schedule_time
        FROM tbl_double_elimination
        WHERE category_id = :catId
        ON DUPLICATE KEY UPDATE
          alliance1_id = VALUES(alliance1_id),
          alliance2_id = VALUES(alliance2_id),
          winner_alliance_id = VALUES(winner_alliance_id),
          status = VALUES(status)
      """, {"catId": categoryId});
      
      print("✅ Synced explorer bracket table for category $categoryId");
    } catch (e) {
      print("❌ Error syncing explorer bracket table: $e");
    }
  }

  // Sync explorer championship schedule from canonical table
  static Future<void> syncExplorerChampionshipSchedule(int categoryId) async {
    final conn = await getConnection();
    
    try {
      // Ensure the explorer table has required columns
      try {
        await conn.execute("""
          ALTER TABLE tbl_explorer_championship_schedule
          ADD COLUMN IF NOT EXISTS match_number INT NOT NULL DEFAULT 1,
          ADD COLUMN IF NOT EXISTS round_name VARCHAR(50) DEFAULT NULL,
          ADD COLUMN IF NOT EXISTS bracket_side VARCHAR(20) DEFAULT 'winners',
          ADD COLUMN IF NOT EXISTS winner_alliance_id INT DEFAULT NULL
        """);
      } catch (e) {
        print("ℹ️ Column check for explorer championship schedule: $e");
      }
      
      await conn.execute("""
        INSERT INTO tbl_explorer_championship_schedule 
          (match_id, category_id, alliance1_id, alliance2_id, match_round, 
           match_position, schedule_time, status, match_number, round_name, 
           bracket_side, winner_alliance_id)
        SELECT 
          match_id, category_id, alliance1_id, alliance2_id, match_round,
          match_position, schedule_time, status, match_number, round_name,
          bracket_side, winner_alliance_id
        FROM tbl_championship_schedule
        WHERE category_id = :catId
        ON DUPLICATE KEY UPDATE
          alliance1_id = VALUES(alliance1_id),
          alliance2_id = VALUES(alliance2_id),
          match_round = VALUES(match_round),
          match_position = VALUES(match_position),
          schedule_time = VALUES(schedule_time),
          status = VALUES(status),
          match_number = VALUES(match_number),
          round_name = VALUES(round_name),
          bracket_side = VALUES(bracket_side),
          winner_alliance_id = VALUES(winner_alliance_id)
      """, {"catId": categoryId});
      
      print("✅ Synced explorer championship schedule for category $categoryId");
    } catch (e) {
      print("❌ Error syncing explorer championship schedule: $e");
    }
  }

  // category and bracket side has all winners set (i.e., is finished).
  static Future<bool> isRoundCompleted(
    int categoryId,
    String bracketSide,
    int roundNumber, {
    List<int>? requiredPositions,
  }) async {
    final conn = await getConnection();
    try {
      const String tableName = 'tbl_double_elimination';

      String sql =
          """
        SELECT COUNT(*) AS pending FROM $tableName
        WHERE category_id = :catId
          AND bracket_side = :bracketSide
          AND round_number = :roundNum
          AND (winner_alliance_id IS NULL OR winner_alliance_id = 0)
      """;
      final params = {
        "catId": categoryId,
        "bracketSide": bracketSide,
        "roundNum": roundNumber,
      };

      if (requiredPositions != null && requiredPositions.isNotEmpty) {
        final placeholders = requiredPositions.map((i) => ':p$i').join(',');
        sql += " AND match_position IN ($placeholders)";
        for (final p in requiredPositions) params['p$p'] = p;
      }

      final res = await conn.execute(sql, params);
      if (res.rows.isNotEmpty) {
        final pendingStr = res.rows.first.assoc()['pending']?.toString() ?? '0';
        final pending = int.tryParse(pendingStr) ?? 0;
        return pending == 0;
      }
    } catch (e) {
      print('ℹ️ isRoundCompleted failed: $e');
    }
    return false;
  }

  // Cache for resolved double-elimination table names per category
  static final Map<int, String> _doubleElimTableCache = {};

  // Resolve which double-elimination table to use for a given category.
  static Future<String> getDoubleEliminationTableForCategory(int categoryId) async {
    if (_doubleElimTableCache.containsKey(categoryId)) return _doubleElimTableCache[categoryId]!;
    
    // Always use canonical table for consistency
    const String tableName = 'tbl_double_elimination';
    _doubleElimTableCache[categoryId] = tableName;
    return tableName;
  }

  // Ensure parent rows exist in category-specific tables before inserting dependent rows.
  static Future<void> _ensureCategoryParents(
    MySQLConnection conn,
    String slug,
    Map<String, dynamic> params,
  ) async {
    // This method is kept but simplified - not used for explorer sync anymore
    print('ℹ️ _ensureCategoryParents called but not needed for explorer sync');
  }

  // ── CHAMPIONSHIP SETTINGS ─────────────────────────────────────────────────

  // Save championship settings
  static Future<void> saveChampionshipSettings(
    ChampionshipSettings settings,
  ) async {
    final conn = await getConnection();

    await executeDual(
      """
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
    """,
      {
        "catId": settings.categoryId,
        "matches": settings.matchesPerAlliance,
        "startTime": settings.startTimeString,
        "endTime": settings.endTimeString,
        "duration": settings.durationMinutes,
        "interval": settings.intervalMinutes,
        "lunch": settings.lunchBreakEnabled ? 1 : 0,
      },
    );

    print("✅ Saved championship settings for category ${settings.categoryId}");
  }

  // Load championship settings
  static Future<ChampionshipSettings?> loadChampionshipSettings(
    int categoryId,
  ) async {
    final conn = await getConnection();

    try {
      final result = await conn.execute(
        """
        SELECT * FROM tbl_championship_settings 
        WHERE category_id = :catId
      """,
        {"catId": categoryId},
      );

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
      await executeDual("""
        DELETE cs FROM tbl_championship_schedule cs
        LEFT JOIN tbl_category c ON cs.category_id = c.category_id
        WHERE c.category_id IS NULL
      """);

      // Delete championship settings for non-existent categories
      await executeDual("""
        DELETE cs FROM tbl_championship_settings cs
        LEFT JOIN tbl_category c ON cs.category_id = c.category_id
        WHERE c.category_id IS NULL
      """);

      print("✅ Cleaned up orphaned championship records");
    } catch (e) {
      print("⚠️ Error cleaning up orphaned records: $e");
    }
  }

  // Enhanced championship schedule generation - includes ALL bracket matches
static Future<void> generateChampionshipScheduleWithSettings(
  int categoryId,
  ChampionshipSettings settings,
) async {
  final conn = await getConnection();

  try {
    print("🏆 Starting championship schedule generation for category $categoryId");
    print("📊 Matches per alliance: ${settings.matchesPerAlliance}");

    // Use canonical bracket table
    const String bracketTable = 'tbl_double_elimination';
    print("📊 Using bracket table: $bracketTable");

    // Get ALL matches from the double elimination table (including future rounds)
    final bracketMatches = await conn.execute("""
      SELECT 
        match_id,
        round_number,
        match_position,
        bracket_side,
        round_name,
        alliance1_id,
        alliance2_id,
        winner_alliance_id
      FROM $bracketTable
      WHERE category_id = :catId
      ORDER BY 
        CASE bracket_side
          WHEN 'winners' THEN 1
          WHEN 'losers' THEN 2
          WHEN 'grand' THEN 3
        END,
        round_number,
        match_position
    """, {"catId": categoryId});

    if (bracketMatches.rows.isEmpty) {
      throw Exception('No bracket matches found. Generate bracket first.');
    }

    print("📊 Found ${bracketMatches.rows.length} total bracket matches");

    // Clear existing schedule for this category
    await executeDual(
      "DELETE FROM tbl_championship_schedule WHERE category_id = :catId",
      {"catId": categoryId},
    );

    // Parse times
    int currentHour = settings.startTime.hour;
    int currentMinute = settings.startTime.minute;

    String formatTime(int hour, int minute) {
      return '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
    }

    void skipLunch() {
      if (settings.lunchBreakEnabled && currentHour == 12) {
        currentHour = 13;
        currentMinute = 0;
      }
    }

    void advanceTime() {
      currentMinute += settings.durationMinutes + settings.intervalMinutes;
      while (currentMinute >= 60) {
        currentMinute -= 60;
        currentHour++;
      }
      skipLunch();
    }

    skipLunch();

    int matchesInserted = 0;

    // For EACH bracket match (including future rounds), generate schedule entries
    for (final row in bracketMatches.rows) {
      final data = row.assoc();
      int alliance1Id = int.tryParse(data['alliance1_id']?.toString() ?? '0') ?? 0;
      int alliance2Id = int.tryParse(data['alliance2_id']?.toString() ?? '0') ?? 0;
      final roundNumber = int.parse(data['round_number'].toString());
      final matchPosition = int.parse(data['match_position'].toString());
      final bracketSide = data['bracket_side'].toString();
      
      // Get round name from bracket or generate it
      String roundName = data['round_name']?.toString() ?? '';
      if (roundName.isEmpty) {
        roundName = _getRoundDisplayName(roundNumber, bracketSide);
      }
      
      // Determine if this match is ready to be played or still waiting
      // For waiting matches (alliance IDs are 0), we still need to insert schedule entries
      // but with placeholder alliances that will be updated later
      bool isReady = (alliance1Id > 0 && alliance2Id > 0);
      String baseStatus = isReady ? 'pending' : 'waiting';
      
      // For waiting matches, use temporary placeholder IDs (will be updated when alliances are known)
      // But we must have valid IDs for the NOT NULL columns
      if (alliance1Id == 0) alliance1Id = -1;  // Use -1 as placeholder for TBD
      if (alliance2Id == 0) alliance2Id = -1;  // Use -1 as placeholder for TBD
      
      for (int matchNum = 1; matchNum <= settings.matchesPerAlliance; matchNum++) {
        final timeStr = formatTime(currentHour, currentMinute);
        
        // For waiting matches, we still insert with placeholder alliances
        // They will be updated when the bracket match becomes ready
        await executeDual("""
          INSERT INTO tbl_championship_schedule 
            (category_id, alliance1_id, alliance2_id, match_round, match_position, 
             schedule_time, status, match_number, round_name, bracket_side)
          VALUES
            (:catId, :a1, :a2, :roundNum, :pos, :time, :status, :matchNum, :roundName, :bracketSide)
        """, {
          "catId": categoryId,
          "a1": alliance1Id,
          "a2": alliance2Id,
          "roundNum": roundNumber,
          "pos": matchPosition,
          "time": timeStr,
          "status": baseStatus,
          "matchNum": matchNum,
          "roundName": roundName,
          "bracketSide": bracketSide,
        });

        matchesInserted++;
        
        // Only advance time for matches that are pending (will be played)
        if (isReady) {
          advanceTime();
        }
        
        print("  ✅ Generated ${bracketSide.toUpperCase()} Round $roundNumber Match $matchPosition (Game $matchNum/${settings.matchesPerAlliance}) at $timeStr - Status: $baseStatus");
      }
    }

    print("✅ Generated $matchesInserted championship matches from bracket table");
    print("   - Pending matches: Ready to play");
    print("   - Waiting matches: Awaiting previous round results (placeholders used)");
    
    // Update waiting matches to set proper alliance IDs when they become available
    await updateWaitingMatches(categoryId);
    
    // Sync to explorer table
    await syncExplorerChampionshipSchedule(categoryId);

  } catch (e, stackTrace) {
    print("❌ Error generating championship schedule: $e");
    print(stackTrace);
    throw Exception('Failed to generate championship schedule: $e');
  }
}

  // Helper function to get display round name
  static String _getRoundDisplayName(int roundNumber, String bracketSide) {
    if (bracketSide == 'winners') {
      switch (roundNumber) {
        case 1: return "Quarter-Final";
        case 2: return "Semi-Final";
        case 3: return "Winner's Final";
        default: return "Winner's Round $roundNumber";
      }
    } else if (bracketSide == 'losers') {
      switch (roundNumber) {
        case 1: return "Loser's Round 1";
        case 2: return "Loser's Round 2";
        case 3: return "Loser's Round 3";
        case 4: return "Loser's Final";
        default: return "Loser's Round $roundNumber";
      }
    } else if (bracketSide == 'grand') {
      if (roundNumber == 1) return "Grand Final";
      return "Grand Final (Reset)";
    }
    return "Match";
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
      host: _host,
      port: _port,
      userName: _userName,
      password: _password,
      databaseName: _databaseName,
      secure: false,
    );

    await _connection!.connect();
    print("✅ Database connected!");
    return _connection!;
  }

  static Future<void> closeConnection() async {
    try {
      await _connection?.close();
    } catch (_) {}
    _connection = null;
    print("🔌 Database disconnected.");
  }

  // ── SCHOOLS ───────────────────────────────────────────────────────────────

  static Future<List<Map<String, dynamic>>> getSchools() async {
    final conn = await getConnection();
    final result = await conn.execute(
      "SELECT * FROM tbl_school ORDER BY school_name",
    );
    return result.rows.map((r) => r.assoc()).toList();
  }

  // ── CATEGORIES ────────────────────────────────────────────────────────────

  static Future<List<Map<String, dynamic>>> getCategories() async {
    final conn = await getConnection();
    final result = await conn.execute(
      "SELECT * FROM tbl_category ORDER BY category_id",
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
    int categoryId,
  ) async {
    final conn = await getConnection();
    final result = await conn.execute(
      """
      SELECT t.team_id, t.team_name, t.team_ispresent,
             c.category_type, m.mentor_name
      FROM tbl_team t
      JOIN tbl_category c ON t.category_id = c.category_id
      JOIN tbl_mentor   m ON t.mentor_id   = m.mentor_id
      WHERE t.category_id = :categoryId
      ORDER BY t.team_id
    """,
      {"categoryId": categoryId},
    );
    return result.rows.map((r) => r.assoc()).toList();
  }

  // ── SCHEDULE ──────────────────────────────────────────────────────────────

  static Future<void> clearSchedule() async {
    final conn = await getConnection();
    await executeDual("DELETE FROM tbl_teamschedule");
    await executeDual("DELETE FROM tbl_match");
    await executeDual("DELETE FROM tbl_schedule");
    // Reset AUTO_INCREMENT so match IDs start from 1 again
    await executeDual("ALTER TABLE tbl_teamschedule AUTO_INCREMENT = 1");
    await executeDual("ALTER TABLE tbl_match AUTO_INCREMENT = 1");
    await executeDual("ALTER TABLE tbl_schedule AUTO_INCREMENT = 1");
    print("✅ Schedule cleared and IDs reset.");
  }

  static Future<int> insertSchedule({
    required String startTime,
    required String endTime,
  }) async {
    final conn = await getConnection();
    final result = await executeDual(
      """
      INSERT INTO tbl_schedule (schedule_start, schedule_end)
      VALUES (:start, :end)
    """,
      {"start": startTime, "end": endTime},
    );
    return result.lastInsertID.toInt();
  }

  static Future<int> insertMatch(int scheduleId) async {
    final conn = await getConnection();
    final result = await executeDual(
      """
      INSERT INTO tbl_match (schedule_id) VALUES (:scheduleId)
    """,
      {"scheduleId": scheduleId},
    );
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
    final exists =
        int.tryParse(roundCheck.rows.first.assoc()['cnt']?.toString() ?? '0') ??
        0;

    if (exists == 0) {
      print("⚠️ Round $roundId does not exist - creating it now");
      try {
        await executeDual(
          """
          INSERT INTO tbl_round (round_id, round_type, round_number)
          VALUES (:id, :type, :number)
        """,
          {"id": roundId, "type": 'Round $roundId', "number": roundId},
        );
        print("✅ Created round $roundId");
      } catch (e) {
        print("❌ Failed to create round $roundId: $e");
        return;
      }
    }

    print(
      "📝 Inserting: match=$matchId, round=$roundId, team=$teamId, arena=$arenaNumber",
    );

    await executeDual(
      """
      INSERT INTO tbl_teamschedule (match_id, round_id, team_id, referee_id, arena_number)
      VALUES (:match, :round, :team, :ref, :arena)
    """,
      {
        "match": matchId,
        "round": roundId,
        "team": teamId,
        "ref": refereeId,
        "arena": arenaNumber,
      },
    );
  }

  // ── ROUNDS ────────────────────────────────────────────────────────────────

  static Future<void> seedRounds(int maxRounds) async {
    final conn = await getConnection();

    // Check if we already have enough rounds
    final checkResult = await conn.execute(
      "SELECT COUNT(*) as cnt FROM tbl_round",
    );
    final count =
        int.tryParse(
          checkResult.rows.first.assoc()['cnt']?.toString() ?? '0',
        ) ??
        0;

    if (count < maxRounds) {
      // Add missing rounds
      for (int i = count + 1; i <= maxRounds; i++) {
        try {
          await executeDual(
            """
            INSERT INTO tbl_round (round_id, round_type, round_number)
            VALUES (:id, :type, :number)
          """,
            {"id": i, "type": 'Round $i', "number": i},
          );
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
      await executeDual("""
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

      await conn.execute(
        """
        INSERT INTO tbl_category_settings (category_id, matches_per_team)
        VALUES (:catId, :matches)
        ON DUPLICATE KEY UPDATE matches_per_team = :matches
      """,
        {"catId": categoryId, "matches": matchesPerTeam},
      );
      print(
        "📊 Stored matches per team for category $categoryId: $matchesPerTeam",
      );
    }

    // ── IMPORTANT: Seed rounds BEFORE inserting any matches ─────────────────
    final maxRuns = runsPerCategory.values.isEmpty
        ? 1
        : runsPerCategory.values.reduce((a, b) => a > b ? a : b);

    await executeDual("DELETE FROM tbl_round");
    await executeDual("ALTER TABLE tbl_round AUTO_INCREMENT = 1");
    await seedRounds(maxRuns);

    final roundCheck = await conn.execute(
      "SELECT COUNT(*) as cnt FROM tbl_round",
    );
    final roundCount =
        int.tryParse(roundCheck.rows.first.assoc()['cnt']?.toString() ?? '0') ??
        0;
    print("✅ $roundCount rounds seeded (1-$maxRuns)");

    // ── Get first available referee with validation ──────────────────────────
    final refResult = await conn.execute(
      "SELECT referee_id FROM tbl_referee ORDER BY referee_id LIMIT 1",
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
        print(
          "Need to create ${availableTeams.length ~/ 4} matches in this round",
        );

        // Shuffle for randomness
        availableTeams.shuffle(random);

        // Create matches for this round - one for each group of 4 teams
        for (int m = 0; m < availableTeams.length; m += 4) {
          if (m + 3 >= availableTeams.length) break;

          // Take 4 teams for this match
          final matchTeams = availableTeams.sublist(m, m + 4);
          matchCounter++;

          print(
            "\nCreating Match $matchCounter (Round $round) with teams: $matchTeams",
          );

          // Try to find a fair RED/BLUE split for these 4 teams
          Map<String, dynamic>? bestMatch;
          int bestScore = -1;

          // Try all possible RED/BLUE splits (6 combinations)
          final List<List<int>> redCombinations = [
            [0, 1],
            [0, 2],
            [0, 3],
            [1, 2],
            [1, 3],
            [2, 3],
          ];

          for (final redIndices in redCombinations) {
            final redIds = [
              matchTeams[redIndices[0]],
              matchTeams[redIndices[1]],
            ];
            final blueIds = matchTeams
                .where((id) => !redIds.contains(id))
                .toList();

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
            final endStr =
                '${endHour.toString().padLeft(2, '0')}:${endMinute.toString().padLeft(2, '0')}:00';

            final scheduleId = await insertSchedule(
              startTime: startStr,
              endTime: endStr,
            );
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

            final redNames = redIds
                .map((id) => teamMap[id]!['team_name'])
                .join(', ');
            final blueNames = blueIds
                .map((id) => teamMap[id]!['team_name'])
                .join(', ');
            print(
              "✅ Match $matchCounter: RED: [$redNames] vs BLUE: [$blueNames] at $startStr",
            );

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

      teamStats.putIfAbsent(
        teamId,
        () => {
          'teamId': teamId,
          'teamName': teamName,
          'category': category,
          'red': 0,
          'blue': 0,
          'rounds': <int>{},
          'roundArena': <int, int>{},
        },
      );

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
      final maxRound = roundsSet.isEmpty
          ? 0
          : roundsSet.reduce((a, b) => a > b ? a : b);
      final missingRounds = <int>[];
      for (int r = 1; r <= maxRound; r++) {
        if (!roundsSet.contains(r)) {
          missingRounds.add(r);
        }
      }

      final sortedRounds = roundsSet.toList()..sort();
      final roundArena = stats['roundArena'] as Map<int, int>;
      final arenaSequence = sortedRounds
          .map((r) => roundArena[r] == 1 ? 'R' : 'B')
          .join(' → ');

      String fairnessIcon = '✅';
      if (((stats['red'] as int) - (stats['blue'] as int)).abs() > 1) {
        fairnessIcon = '⚠️';
      } else if (missingRounds.isNotEmpty) {
        fairnessIcon = '❌';
      }

      print(
        "$fairnessIcon ${stats['category']} - ${stats['teamName']}: RED=${stats['red']}, BLUE=${stats['blue']} | Rounds: ${roundsSet.join(', ')}",
      );
      print("   Arena sequence: $arenaSequence");

      if (missingRounds.isNotEmpty) {
        print("   ⚠️  MISSING ROUNDS: $missingRounds");
      }

      if (((stats['red'] as int) - (stats['blue'] as int)).abs() > 1) {
        print(
          "   ⚠️  Red/Blue imbalance: Should be within 1 game of each other",
        );
      }
    });

    // Summary statistics
    print("\n=== FAIRNESS SUMMARY ===");
    final teamCount = teamStats.length;
    final totalMatches =
        teamStats.values.fold(
          0,
          (sum, stats) => sum + (stats['red'] as int) + (stats['blue'] as int),
        ) ~/
        2;

    print("Total teams: $teamCount");
    print("Total matches: $totalMatches");

    final perfectTeams = teamStats.values
        .where((stats) => stats['red'] == stats['blue'])
        .length;

    print(
      "Perfectly balanced teams (equal RED/BLUE): $perfectTeams/$teamCount",
    );

    if (perfectTeams == teamCount) {
      print("🎉 ALL TEAMS HAVE PERFECT RED/BLUE BALANCE!");
    } else {
      print(
        "⚠️ Some teams have imbalance. Maximum allowed difference is 1 game.",
      );
    }
  }

  // ── SCORES ────────────────────────────────────────────────────────────────

  static Future<List<Map<String, dynamic>>> getScoresByCategory(
    int categoryId,
  ) async {
    final conn = await getConnection();
    final result = await conn.execute(
      """
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
    """,
      {"categoryId": categoryId},
    );

    final rows = result.rows.map((r) => r.assoc()).toList();
    print(
      "📊 getScoresByCategory for category $categoryId returned ${rows.length} rows",
    );
    for (var row in rows) {
      print(
        "   Row: team_id=${row['team_id']}, round_id=${row['round_id']}, score=${row['score_totalscore']}",
      );
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
    final checkResult = await conn.execute(
      """
      SELECT COUNT(*) as cnt FROM tbl_score 
      WHERE team_id = :teamId AND round_id = :roundId
    """,
      {"teamId": teamId, "roundId": roundId},
    );

    final exists =
        int.tryParse(
          checkResult.rows.first.assoc()['cnt']?.toString() ?? '0',
        ) ??
        0;

    if (exists > 0) {
      // Update existing
      print("🔄 Updating existing score record");
      await executeDual(
        """
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
      """,
        {
          "indep": independentScore,
          "alliance": allianceScore,
          "viol": violation,
          "total": totalScore,
          "duration": totalDuration,
          "match": matchParam,
          "ref": refereeId,
          "team": teamId,
          "round": roundId,
        },
      );
    } else {
      // Insert new
      print("➕ Inserting new score record");
      await executeDual(
        """
        INSERT INTO tbl_score
          (score_individual, score_alliance, score_violation, score_totalscore,
           score_totalduration, score_isapproved,
           match_id, round_id, team_id, referee_id)
        VALUES
          (:indep, :alliance, :viol, :total, :duration, 0,
           :match, :round, :team, :ref)
      """,
        {
          "indep": independentScore,
          "alliance": allianceScore,
          "viol": violation,
          "total": totalScore,
          "duration": totalDuration,
          "match": matchParam,
          "round": roundId,
          "team": teamId,
          "ref": refereeId,
        },
      );
    }

    print("✅ Score saved successfully for team $teamId, round $roundId");
  }

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
      final allTeamsRes = await conn.execute(
        """
      SELECT 
        ts.team_id,
        t.team_name,
        ts.arena_number,
        ts.round_id
      FROM tbl_teamschedule ts
      JOIN tbl_team t ON ts.team_id = t.team_id
      WHERE ts.match_id = :matchId AND ts.round_id = :roundId
      ORDER BY ts.arena_number, ts.team_id
    """,
        {"matchId": matchId, "roundId": roundId},
      );

      final allTeams = allTeamsRes.rows.map((r) => r.assoc()).toList();

      if (allTeams.isEmpty) {
        print("❌ No teams found in match $matchId, round $roundId");
        return;
      }

      print("✅ Found ${allTeams.length} total teams in match:");
      for (final team in allTeams) {
        print(
          "   - Team ${team['team_id']} (${team['team_name']}), Arena ${team['arena_number']}",
        );
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

      print(
        "\n✅ Source team found: ${sourceTeam!['team_name']} in Arena $sourceArena",
      );

      // IMPORTANT FIX: For 1v1 matches, the partner is in the OTHER arena
      // For 2v2 matches, partners are in the SAME arena
      List<int> targetTeamIds = [];

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
        final partnerTeams =
            teamsByArena[sourceArena]?.where((team) {
              return int.parse(team['team_id'].toString()) != sourceTeamId;
            }).toList() ??
            [];

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
          roundId,
          matchId,
          allianceScore,
        );
      }

      // Verify the updates worked
      print("\n📋 STEP 3: Verifying updates...");
      for (final team in allTeams) {
        final teamId = int.parse(team['team_id'].toString());
        final verifyResult = await conn.execute(
          """
        SELECT score_alliance, score_totalscore
        FROM tbl_score
        WHERE team_id = :teamId AND round_id = :roundId
      """,
          {"teamId": teamId, "roundId": roundId},
        );

        if (verifyResult.rows.isNotEmpty) {
          final data = verifyResult.rows.first.assoc();
          print(
            "   Team ${team['team_name']}: ALL=${data['score_alliance']}, TOTAL=${data['score_totalscore']}",
          );
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
    final checkRes = await conn.execute(
      """
    SELECT COUNT(*) as cnt FROM tbl_score
    WHERE team_id = :teamId AND round_id = :roundId
  """,
      {"teamId": teamId, "roundId": roundId},
    );

    final exists = int.parse(checkRes.rows.first.assoc()['cnt'].toString());

    if (exists > 0) {
      // Update existing score
      print("    ✅ Score record exists - updating");

      // Get current scores
      final currentRes = await conn.execute(
        """
      SELECT score_individual, score_alliance, score_violation
      FROM tbl_score
      WHERE team_id = :teamId AND round_id = :roundId
    """,
        {"teamId": teamId, "roundId": roundId},
      );

      final current = currentRes.rows.first.assoc();
      final individual = int.parse(current['score_individual'].toString());
      final currentAlliance = int.parse(current['score_alliance'].toString());
      final violation = int.parse(current['score_violation'].toString());

      // Add the new alliance score to existing alliance score
      final newAlliance = currentAlliance + allianceScore;
      final newTotal = individual + newAlliance - violation;

      print(
        "     Current: IND=$individual, ALL=$currentAlliance, VIO=$violation, TOTAL=${individual + currentAlliance - violation}",
      );
      print("     New: ALL=$newAlliance, TOTAL=$newTotal");

      await executeDual(
        """
      UPDATE tbl_score
      SET 
        score_alliance = :alliance,
        score_totalscore = :total
      WHERE team_id = :teamId AND round_id = :roundId
    """,
        {
          "alliance": newAlliance,
          "total": newTotal,
          "teamId": teamId,
          "roundId": roundId,
        },
      );

      print("    ✅ Updated: ALL=$newAlliance, TOTAL=$newTotal");
    } else {
      // Insert new score
      print("    ⚠️ No score record exists - creating new");

      await executeDual(
        """
      INSERT INTO tbl_score
        (team_id, round_id, score_individual, score_alliance, score_violation, 
         score_totalscore, score_totalduration, score_isapproved, match_id, referee_id)
      VALUES
        (:teamId, :roundId, 0, :alliance, 0, :total, '00:00', 0, :matchId, NULL)
    """,
        {
          "teamId": teamId,
          "roundId": roundId,
          "alliance": allianceScore,
          "total": allianceScore,
          "matchId": matchId,
        },
      );

      print("    ✅ Created new: TOTAL=$allianceScore");
    }

    // Verify the update
    final verifyRes = await conn.execute(
      """
    SELECT score_alliance, score_totalscore
    FROM tbl_score
    WHERE team_id = :teamId AND round_id = :roundId
  """,
      {"teamId": teamId, "roundId": roundId},
    );

    if (verifyRes.rows.isNotEmpty) {
      final data = verifyRes.rows.first.assoc();
      print(
        "     Verification: ALL=${data['score_alliance']}, TOTAL=${data['score_totalscore']}",
      );
    }
  }

  // Debug method to check match structure
  static Future<void> debugCheckMatch(int matchId, int roundId) async {
    final conn = await getConnection();

    print("\n🔍 DEBUG: Checking match $matchId, round $roundId");

    final result = await conn.execute(
      """
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
    """,
      {"matchId": matchId, "roundId": roundId},
    );

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
  static Future<int?> getMatchPartner(
    int matchId,
    int teamId,
    int roundId,
  ) async {
    final conn = await getConnection();

    final result = await conn.execute(
      """
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
    """,
      {"matchId": matchId, "roundId": roundId, "teamId": teamId},
    );

    if (result.rows.isNotEmpty) {
      return int.tryParse(
        result.rows.first.assoc()['team_id']?.toString() ?? '0',
      );
    }
    return null;
  }
}