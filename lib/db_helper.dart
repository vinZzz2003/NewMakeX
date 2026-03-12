import 'dart:math';
import 'package:mysql_client/mysql_client.dart';
import 'schedule_fairness_helper.dart'; // Import the fairness helper

// Move this class to the top level, outside of DBHelper
class _TeamFairnessStats {
  final int teamId;
  final String teamName;
  final String category;
  int red = 0;
  int blue = 0;
  Set<int> rounds = {};
  Map<int, int> roundArena = {};
  
  _TeamFairnessStats({
    required this.teamId,
    required this.teamName,
    required this.category,
  });
}

class DBHelper {
  static MySQLConnection? _connection;

  static const String _host         = "127.0.0.1";
  static const int    _port         = 3306;
  static const String _userName     = "root";
  static const String _password     = "root";
  static const String _databaseName = "make_x";

  // ── MIGRATIONS ───────────────────────────────────────────────────────────
  static Future<void> runMigrations() async {
    final conn = await getConnection();
    try {
      await conn.execute("""
        ALTER TABLE tbl_teamschedule
        ADD COLUMN arena_number INT NOT NULL DEFAULT 1
      """);
      print("✅ Migration: arena_number column added.");
    } catch (_) {
      print("ℹ️  Migration: arena_number already present.");
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
    // ✅ Reset AUTO_INCREMENT so match IDs start from 1 again
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
  
  // Verify the round exists before inserting
  final roundCheck = await conn.execute(
    "SELECT COUNT(*) as cnt FROM tbl_round WHERE round_id = :roundId",
    {"roundId": roundId},
  );
  final exists = int.tryParse(roundCheck.rows.first.assoc()['cnt']?.toString() ?? '0') ?? 0;
  
  if (exists == 0) {
    print("⚠️ Round $roundId does not exist in database!");
    return;
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
          "number": i,  // Add the round_number
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

  // ── Get first available referee ──────────────────────────────────────────
  final refResult = await conn.execute(
    "SELECT referee_id FROM tbl_referee ORDER BY referee_id LIMIT 1"
  );
  if (refResult.rows.isEmpty) {
    throw Exception('No referees found. Please add at least one referee.');
  }
  final defaultRefereeId = int.parse(
    refResult.rows.first.assoc()['referee_id'] ?? '0',
  );

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
    final matchesPerRound = teamCount ~/ 4; // With 8 teams, this is 2 matches per round
    
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

    // ── FIXED: PROPER ROUND-ROBIN SCHEDULING ─────────────────────────────
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
    final targetRed = (runs / 2).ceil();  // With runs=4, targetRed=2
    final targetBlue = (runs / 2).floor(); // With runs=4, targetBlue=2
    
    int matchCounter = 0;
    
    // For each round
    for (int round = 1; round <= runs; round++) {
      print("\n=== ROUND $round ===");
      
      // Get all teams that need to play in this round
      final availableTeams = <int>[];
      for (final team in teams) {
        final teamId = int.parse(team['team_id'].toString());
        final stats = tracker.teamData[teamId]!;
        
        // Team hasn't played this round yet
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
          
          // Insert RED teams
          for (final teamId in redIds) {
            await insertTeamSchedule(
              matchId: matchId,
              roundId: round,
              teamId: teamId,
              refereeId: defaultRefereeId,
              arenaNumber: 1,
            );
          }
          
          // Insert BLUE teams
          for (final teamId in blueIds) {
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
    
    // Now this will work because _TeamFairnessStats is defined at top level
    final Map<int, _TeamFairnessStats> teamStats = {};
    
    for (final row in result.rows) {
      final data = row.assoc();
      final teamId = int.parse(data['team_id'].toString());
      final roundId = int.parse(data['round_id'].toString());
      final arenaNum = int.parse(data['arena_number'].toString());
      final teamName = data['team_name'].toString();
      final category = data['category_type'].toString();
      
      teamStats.putIfAbsent(teamId, () => _TeamFairnessStats(
        teamId: teamId,
        teamName: teamName,
        category: category,
      ));
      
      final stats = teamStats[teamId]!;
      
      if (arenaNum == 1) {
        stats.red++;
      } else {
        stats.blue++;
      }
      
      stats.rounds.add(roundId);
      stats.roundArena[roundId] = arenaNum;
    }
    
    // Print fairness report
    teamStats.forEach((teamId, stats) {
      // Check if any rounds are missing
      final maxRound = stats.rounds.isEmpty ? 0 : stats.rounds.reduce((a, b) => a > b ? a : b);
      final missingRounds = <int>[];
      for (int r = 1; r <= maxRound; r++) {
        if (!stats.rounds.contains(r)) {
          missingRounds.add(r);
        }
      }
      
      // Check arena alternation pattern
      final sortedRounds = stats.rounds.toList()..sort();
      final arenaSequence = sortedRounds.map((r) => stats.roundArena[r] == 1 ? 'R' : 'B').join(' → ');
      
      // Color code based on fairness
      String fairnessIcon = '✅';
      if ((stats.red - stats.blue).abs() > 1) {
        fairnessIcon = '⚠️';
      } else if (missingRounds.isNotEmpty) {
        fairnessIcon = '❌';
      }
      
      print("$fairnessIcon ${stats.category} - ${stats.teamName}: RED=${stats.red}, BLUE=${stats.blue} | Rounds: ${stats.rounds.join(', ')}");
      print("   Arena sequence: $arenaSequence");
      
      if (missingRounds.isNotEmpty) {
        print("   ⚠️  MISSING ROUNDS: $missingRounds");
      }
      
      if ((stats.red - stats.blue).abs() > 1) {
        print("   ⚠️  Red/Blue imbalance: Should be within 1 game of each other");
      }
    });
    
    // Summary statistics
    print("\n=== FAIRNESS SUMMARY ===");
    final teamCount = teamStats.length;
    final totalMatches = teamStats.values.fold(0, (sum, stats) => sum + stats.red + stats.blue) ~/ 2;
    
    print("Total teams: $teamCount");
    print("Total matches: $totalMatches");
    
    // Check if any team has perfect balance
    final perfectTeams = teamStats.values.where((stats) => stats.red == stats.blue).length;
    
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
        s.round_id,
        COALESCE(s.score_totalscore,    0)       AS score_totalscore,
        COALESCE(s.score_totalduration, '00:00') AS score_totalduration
      FROM tbl_team t
      LEFT JOIN tbl_score s ON s.team_id = t.team_id
      WHERE t.category_id = :categoryId
      ORDER BY t.team_id, s.round_id
    """, {"categoryId": categoryId});
    return result.rows.map((r) => r.assoc()).toList();
  }

  static Future<void> upsertScore({
    required int teamId,
    required int roundId,
    required int matchId,
    required int refereeId,
    required int independentScore,
    required int violation,
    required int totalScore,
    required String totalDuration,
  }) async {
    final conn = await getConnection();
    await conn.execute("""
      INSERT INTO tbl_score
        (score_independentscore, score_violation, score_totalscore,
         score_totalduration, score_isapproved,
         match_id, round_id, team_id, referee_id)
      VALUES
        (:indep, :viol, :total, :duration, 0,
         :match, :round, :team, :ref)
      ON DUPLICATE KEY UPDATE
        score_independentscore = :indep,
        score_violation        = :viol,
        score_totalscore       = :total,
        score_totalduration    = :duration
    """, {
      "indep":    independentScore,
      "viol":     violation,
      "total":    totalScore,
      "duration": totalDuration,
      "match":    matchId,
      "round":    roundId,
      "team":     teamId,
      "ref":      refereeId,
    });
  }
}