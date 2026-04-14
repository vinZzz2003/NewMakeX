// double_elimination_bracket.dart
import 'package:flutter/material.dart';
import 'package:mysql_client/mysql_client.dart';
import 'dart:math' as math;
import 'db_helper.dart';
import 'championship_settings.dart';
import 'championship_settings_dialog.dart';
import 'constants.dart';

class DoubleEliminationBracket extends StatefulWidget {
  final int categoryId;
  final String categoryName;
  final VoidCallback? onMatchUpdated;

  const DoubleEliminationBracket({
    super.key,
    required this.categoryId,
    required this.categoryName,
    this.onMatchUpdated,
  });

  @override
  State<DoubleEliminationBracket> createState() =>
      _DoubleEliminationBracketState();
}

class _DoubleEliminationBracketState extends State<DoubleEliminationBracket> {
  List<Map<String, dynamic>> _alliances = [];
  List<Map<String, dynamic>> _matches = [];
  bool _isLoading = true;
  String? _error;
  ChampionshipSettings? _settings;
  bool _isGenerating = false;
  bool _isResetting = false;
  bool _autoProcessEnabled = true;

  static const double matchWidth = 240;
  static const double matchHeight = 90;
  static const double columnGap = 40;
  static const double rowGap = 10;

  late double columnWidth = 280;
  late int _bracketSize = 0;
  late int _totalRounds = 0;
  late int _numAlliances = 0;
  late Map<String, Map<String, dynamic>> _matchNodes = {};

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final settings = await DBHelper.loadChampionshipSettings(
        widget.categoryId,
      );

      setState(() {
        _settings =
            settings ?? ChampionshipSettings.defaults(widget.categoryId);
      });

      await _loadAlliances();
      await _loadMatches();
    } catch (e, stackTrace) {
      print("❌ DoubleEliminationBracket error: $e");
      print(stackTrace);
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _loadAlliances() async {
    try {
      final conn = await DBHelper.getConnection();
      final result = await conn.execute(
        """
        SELECT 
          a.alliance_id,
          a.selection_round as alliance_rank,
          COALESCE(t1.team_name, 'Unknown') as captain_name,
          COALESCE(t2.team_name, 'Unknown') as partner_name
        FROM tbl_alliance_selections a
        LEFT JOIN tbl_team t1 ON a.captain_team_id = t1.team_id
        LEFT JOIN tbl_team t2 ON a.partner_team_id = t2.team_id
        WHERE a.category_id = :catId
        ORDER BY a.selection_round
      """,
        {"catId": widget.categoryId},
      );

      setState(() {
        _alliances = result.rows.map((r) => r.assoc()).toList();
        _numAlliances = _alliances.length;
      });

      print("✅ Loaded ${_alliances.length} alliances");
    } catch (e) {
      print("Error loading alliances: $e");
    }
  }

  Future<void> _loadMatches({bool autoProcessByes = true}) async {
  try {
    final conn = await DBHelper.getConnection();

    try {
      await conn.execute("SELECT 1 FROM tbl_double_elimination LIMIT 1");
    } catch (e) {
      await _createDoubleEliminationTable(conn);
    }

    final result = await conn.execute(
      """
      SELECT 
        match_id,
        round_name,
        match_position,
        bracket_side,
        round_number,
        alliance1_id,
        alliance2_id,
        winner_alliance_id,
        next_match_id_winner,
        next_match_id_loser,
        next_match_position_winner,
        next_match_position_loser,
        status,
        schedule_time
      FROM tbl_double_elimination
      WHERE category_id = :catId
      ORDER BY 
        CASE bracket_side
          WHEN 'winners' THEN 1
          WHEN 'losers' THEN 2
          WHEN 'grand' THEN 3
        END,
        round_number,
        match_position
    """,
      {"catId": widget.categoryId},
    );

    final matches = result.rows.map((r) {
      final data = r.assoc();

      if (data['alliance1_id'] != null &&
          int.parse(data['alliance1_id'].toString()) > 0) {
        final alliance = _getAllianceById(
          int.parse(data['alliance1_id'].toString()),
        );
        data['alliance1_name'] = alliance != null
            ? '${alliance['captain_name']} / ${alliance['partner_name']}'
            : 'Unknown';
        data['alliance1_rank'] = alliance != null
            ? '#${alliance['alliance_rank']}'
            : '#?';
      } else {
        data['alliance1_name'] = 'TBD';
        data['alliance1_rank'] = '';
      }

      if (data['alliance2_id'] != null &&
          int.parse(data['alliance2_id'].toString()) > 0) {
        final alliance = _getAllianceById(
          int.parse(data['alliance2_id'].toString()),
        );
        data['alliance2_name'] = alliance != null
            ? '${alliance['captain_name']} / ${alliance['partner_name']}'
            : 'Unknown';
        data['alliance2_rank'] = alliance != null
            ? '#${alliance['alliance_rank']}'
            : '#?';
      } else {
        data['alliance2_name'] = 'TBD';
        data['alliance2_rank'] = '';
      }

      return data;
    }).toList();

    print("✅ Loaded ${matches.length} double elimination matches");

    setState(() {
      _matches = matches;
      _isLoading = false;
    });

    // Fix Grand Finals reset if needed
    await _fixGrandFinalsResetIfNeeded();

    // CRITICAL FIX: Reload matches after fixing GF2
    // This ensures GF2 appears in the UI
    if (mounted && await _needsReloadAfterReset()) {
      print("🔄 Reloading matches after GF2 creation...");
      final refreshedResult = await conn.execute(
        """
        SELECT 
          match_id,
          round_name,
          match_position,
          bracket_side,
          round_number,
          alliance1_id,
          alliance2_id,
          winner_alliance_id,
          next_match_id_winner,
          next_match_id_loser,
          next_match_position_winner,
          next_match_position_loser,
          status,
          schedule_time
        FROM tbl_double_elimination
        WHERE category_id = :catId
        ORDER BY 
          CASE bracket_side
            WHEN 'winners' THEN 1
            WHEN 'losers' THEN 2
            WHEN 'grand' THEN 3
          END,
          round_number,
          match_position
      """,
        {"catId": widget.categoryId},
      );

      final refreshedMatches = refreshedResult.rows.map((r) {
        final data = r.assoc();

        if (data['alliance1_id'] != null &&
            int.parse(data['alliance1_id'].toString()) > 0) {
          final alliance = _getAllianceById(
            int.parse(data['alliance1_id'].toString()),
          );
          data['alliance1_name'] = alliance != null
              ? '${alliance['captain_name']} / ${alliance['partner_name']}'
              : 'Unknown';
          data['alliance1_rank'] = alliance != null
              ? '#${alliance['alliance_rank']}'
              : '#?';
        } else {
          data['alliance1_name'] = 'TBD';
          data['alliance1_rank'] = '';
        }

        if (data['alliance2_id'] != null &&
            int.parse(data['alliance2_id'].toString()) > 0) {
          final alliance = _getAllianceById(
            int.parse(data['alliance2_id'].toString()),
          );
          data['alliance2_name'] = alliance != null
              ? '${alliance['captain_name']} / ${alliance['partner_name']}'
              : 'Unknown';
          data['alliance2_rank'] = alliance != null
              ? '#${alliance['alliance_rank']}'
              : '#?';
        } else {
          data['alliance2_name'] = 'TBD';
          data['alliance2_rank'] = '';
        }

        return data;
      }).toList();

      setState(() {
        _matches = refreshedMatches;
      });
      
      print("✅ Reloaded ${refreshedMatches.length} matches after GF2 creation");
    }

    if (autoProcessByes &&
        _autoProcessEnabled &&
        !_isResetting &&
        _numAlliances > 4) {
      await _autoProcessByeMatches();
    }
  } catch (e) {
    print("Error loading matches: $e");
    setState(() {
      _isLoading = false;
      _error = "Error loading matches: $e";
    });
  }
}

// Add this helper method to check if reload is needed
Future<bool> _needsReloadAfterReset() async {
  final conn = await DBHelper.getConnection();
  final result = await conn.execute(
    "SELECT COUNT(*) as cnt FROM tbl_double_elimination WHERE category_id = :catId AND round_name = 'GF2'",
    {"catId": widget.categoryId},
  );
  final count = int.parse(result.rows.first.assoc()['cnt']?.toString() ?? '0');
  // Also check if GF2 is not already in our current matches list
  final hasGf2InMatches = _matches.any((m) => m['round_name'] == 'GF2');
  return count > 0 && !hasGf2InMatches;
}


  Future<bool> _fixGrandFinalsResetIfNeeded() async {
  final conn = await DBHelper.getConnection();
  bool gf2Created = false;
  
  try {
    // Check if we have a GF1 completed with a winner
    final gf1Result = await conn.execute(
      """
      SELECT match_id, alliance1_id, alliance2_id, winner_alliance_id, status
      FROM tbl_double_elimination
      WHERE category_id = :catId AND round_name = 'GF1' AND bracket_side = 'grand'
      LIMIT 1
      """,
      {"catId": widget.categoryId},
    );
    
    if (gf1Result.rows.isEmpty) return false;
    
    final gf1 = gf1Result.rows.first.assoc();
    final gf1Winner = int.tryParse(gf1['winner_alliance_id']?.toString() ?? '0') ?? 0;
    final gf1Status = gf1['status']?.toString() ?? 'pending';
    
    // Check if GF1 is completed
    if (gf1Winner == 0 || gf1Status != 'completed') return false;
    
    final alliance1Id = int.parse(gf1['alliance1_id'].toString());
    final alliance2Id = int.parse(gf1['alliance2_id'].toString());
    
    // CRITICAL: Determine if reset is needed
    // Reset is needed ONLY if the Loser's Bracket champion won GF1
    // First, find out which alliance is from Loser's Bracket
    // Check Loser's Bracket final winner (L4_1)
    final loserFinalResult = await conn.execute(
      """
      SELECT winner_alliance_id FROM tbl_double_elimination
      WHERE category_id = :catId AND bracket_side = 'losers'
      ORDER BY round_number DESC LIMIT 1
      """,
      {"catId": widget.categoryId},
    );
    
    int loserBracketChampion = 0;
    if (loserFinalResult.rows.isNotEmpty) {
      loserBracketChampion = int.tryParse(
        loserFinalResult.rows.first.assoc()['winner_alliance_id']?.toString() ?? '0'
      ) ?? 0;
    }
    
    // Determine if reset is needed
    final bool needReset = (gf1Winner == loserBracketChampion && loserBracketChampion != 0);
    
    print("🎯 GF1 completed! Winner: $gf1Winner, Loser Bracket Champion: $loserBracketChampion, needReset: $needReset");
    
    if (!needReset) {
  // Winner's bracket champion won - tournament is OVER
  print("🎯 Winner's bracket champion won! Tournament complete.");
  
  // Check if GF2 already exists before deleting
  final gf2ExistsCheck = await conn.execute(
    "SELECT COUNT(*) as cnt FROM tbl_double_elimination WHERE category_id = :catId AND round_name = 'GF2'",
    {"catId": widget.categoryId},
  );
  final hasGf2 = int.parse(gf2ExistsCheck.rows.first.assoc()['cnt']?.toString() ?? '0') > 0;
  
  if (hasGf2) {
    print("⚠️ GF2 already exists but needReset=false - tournament may have been reset already!");
    // Don't delete GF2, just mark tournament complete
  } else {
    // Only delete if GF2 doesn't exist
    await DBHelper.executeDual(
      """
      DELETE FROM tbl_double_elimination 
      WHERE category_id = :catId AND round_name = 'GF2' AND bracket_side = 'grand'
      """,
      {"catId": widget.categoryId},
    );
    await DBHelper.executeDual(
      """
      DELETE FROM tbl_explorer_double_elimination 
      WHERE category_id = :catId AND round_name = 'GF2' AND bracket_side = 'grand'
      """,
      {"catId": widget.categoryId},
    );
  }
  
  // Mark tournament as complete
  await DBHelper.executeDual(
    """
    UPDATE tbl_double_elimination 
    SET status = 'completed'
    WHERE category_id = :catId AND bracket_side = 'grand'
    """,
    {"catId": widget.categoryId},
  );
  
  return false;
}
    
    // Only proceed with GF2 creation if reset is needed
    print("🎯 Loser's bracket champion won! Creating GF2 for reset match...");
    
    // Check if GF2 already exists
    final gf2Result = await conn.execute(
      """
      SELECT match_id, alliance1_id, alliance2_id, status
      FROM tbl_double_elimination
      WHERE category_id = :catId AND round_name = 'GF2' AND bracket_side = 'grand'
      LIMIT 1
      """,
      {"catId": widget.categoryId},
    );
    
    if (gf2Result.rows.isEmpty) {
      // Create GF2
      await DBHelper.executeDual(
        """
        INSERT INTO tbl_double_elimination 
          (category_id, round_name, match_position, bracket_side, round_number, 
           alliance1_id, alliance2_id, status)
        VALUES
          (:catId, 'GF2', 2, 'grand', 2, :a1, :a2, 'pending')
        """,
        {"catId": widget.categoryId, "a1": alliance1Id, "a2": alliance2Id},
      );
      await DBHelper.executeDual(
        """
        INSERT INTO tbl_explorer_double_elimination 
          (category_id, round_name, match_position, bracket_side, round_number, 
           alliance1_id, alliance2_id, status)
        VALUES
          (:catId, 'GF2', 2, 'grand', 2, :a1, :a2, 'pending')
        """,
        {"catId": widget.categoryId, "a1": alliance1Id, "a2": alliance2Id},
      );
      print("✅ Created GF2 with Alliance $alliance1Id vs Alliance $alliance2Id");
      gf2Created = true;
    } else {
      final gf2 = gf2Result.rows.first.assoc();
      final gf2Alliance1 = int.tryParse(gf2['alliance1_id']?.toString() ?? '0') ?? 0;
      final gf2Alliance2 = int.tryParse(gf2['alliance2_id']?.toString() ?? '0') ?? 0;
      
      // Check if GF2 is missing the second alliance
      if (gf2Alliance2 == 0 || gf2Alliance2 == null) {
        print("⚠️ GF2 is missing alliance2_id, fixing...");
        await DBHelper.executeDual(
          """
          UPDATE tbl_double_elimination 
          SET alliance1_id = :a1, alliance2_id = :a2, status = 'pending', winner_alliance_id = NULL
          WHERE round_name = 'GF2' AND category_id = :catId
          """,
          {"a1": alliance1Id, "a2": alliance2Id, "catId": widget.categoryId},
        );
        await DBHelper.executeDual(
          """
          UPDATE tbl_explorer_double_elimination 
          SET alliance1_id = :a1, alliance2_id = :a2, status = 'pending', winner_alliance_id = NULL
          WHERE round_name = 'GF2' AND category_id = :catId
          """,
          {"a1": alliance1Id, "a2": alliance2Id, "catId": widget.categoryId},
        );
        gf2Created = true;
      }
    }
  } catch (e) {
    print("❌ Error fixing Grand Finals reset: $e");
  }
  
  return gf2Created;
}

  Future<void> _createDoubleEliminationTable(MySQLConnection conn) async {
    try {
      await DBHelper.executeDual("""
        CREATE TABLE IF NOT EXISTS tbl_double_elimination (
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
      print("✅ Created tbl_double_elimination table");
    } catch (e) {
      print("⚠️ Error creating table: $e");
    }
  }

  Map<String, dynamic>? _getAllianceById(int id) {
  try {
    return _alliances.firstWhere(
      (a) => int.parse(a['alliance_id'].toString()) == id,
    );
  } catch (e) {
    return null;
  }
}

String _getAllianceRank(int allianceId) {
  final alliance = _getAllianceById(allianceId);
  return alliance != null ? '#${alliance['alliance_rank']}' : '#?';
}

  Future<void> _syncWithScheduleTab(int matchId, int winnerId) async {
    final conn = await DBHelper.getConnection();

    try {
      // Find the round_number and match_position for this double-elimination match
      final deRow = await conn.execute(
        """
        SELECT round_number, match_position FROM tbl_double_elimination WHERE match_id = :matchId
      """,
        {"matchId": matchId},
      );

      if (deRow.rows.isNotEmpty) {
        final rd = deRow.rows.first.assoc();
        final roundNum =
            int.tryParse(rd['round_number']?.toString() ?? '0') ?? 0;
        final matchPos =
            int.tryParse(rd['match_position']?.toString() ?? '0') ?? 0;

        if (roundNum > 0 && matchPos > 0) {
          final scheduleMatch = await conn.execute(
            """
            SELECT match_id, status FROM tbl_championship_schedule
            WHERE category_id = :catId AND match_round = :roundNum AND match_position = :matchPos
          """,
            {
              "catId": widget.categoryId,
              "roundNum": roundNum,
              "matchPos": matchPos,
            },
          );

          if (scheduleMatch.rows.isNotEmpty) {
            await DBHelper.executeDual(
              """
                UPDATE tbl_championship_schedule 
                SET status = 'completed', winner_alliance_id = :winnerId
                WHERE category_id = :catId AND match_round = :roundNum AND match_position = :matchPos
              """,
              {
                "winnerId": winnerId,
                "catId": widget.categoryId,
                "roundNum": roundNum,
                "matchPos": matchPos,
              },
            );
            print(
              "✅ Synced with schedule tab: Match $matchId completed (round $roundNum pos $matchPos)",
            );
          }
        }
      }
    } catch (e) {
      print("⚠️ Could not sync with schedule tab: $e");
    }
  }

  Future<void> _autoProcessByeMatches() async {
    final conn = await DBHelper.getConnection();

    print("🔄 Auto-processing bye matches...");

    final result = await conn.execute(
      """
      SELECT match_id, round_name, alliance1_id, alliance2_id, 
             next_match_id_winner, next_match_position_winner,
             next_match_id_loser, next_match_position_loser
      FROM tbl_double_elimination
      WHERE category_id = :catId AND winner_alliance_id IS NULL
    """,
      {"catId": widget.categoryId},
    );

    bool updated = false;

    for (final row in result.rows) {
      final data = row.assoc();
      final matchIdStr = data['match_id']?.toString();
      final alliance1IdStr = data['alliance1_id']?.toString();
      final alliance2IdStr = data['alliance2_id']?.toString();
      final roundName = data['round_name'] as String;

      if (matchIdStr == null) continue;

      final matchId = int.tryParse(matchIdStr);
      if (matchId == null) continue;

      bool hasTeam1 =
          alliance1IdStr != null &&
          int.tryParse(alliance1IdStr) != null &&
          int.parse(alliance1IdStr) > 0;
      bool hasTeam2 =
          alliance2IdStr != null &&
          int.tryParse(alliance2IdStr) != null &&
          int.parse(alliance2IdStr) > 0;

      if (roundName.startsWith('W1_') && hasTeam1 && !hasTeam2) {
        final winnerId = int.parse(alliance1IdStr!);
        print("🔄 Auto-advancing bye match: $roundName");
        await DBHelper.executeDual(
          """
          UPDATE tbl_double_elimination
          SET winner_alliance_id = :winnerId, status = 'completed'
          WHERE match_id = :matchId
        """,
          {"winnerId": winnerId, "matchId": matchId},
        );

        await _propagateWinnerFromMatch(matchId, winnerId);
        await _syncWithScheduleTab(matchId, winnerId);
        updated = true;
      } else if (roundName.startsWith('W1_') && !hasTeam1 && hasTeam2) {
        final winnerId = int.parse(alliance2IdStr!);
        print("🔄 Auto-advancing bye match: $roundName");
        await DBHelper.executeDual(
          """
          UPDATE tbl_double_elimination
          SET winner_alliance_id = :winnerId, status = 'completed'
          WHERE match_id = :matchId
        """,
          {"winnerId": winnerId, "matchId": matchId},
        );

        await _propagateWinnerFromMatch(matchId, winnerId);
        await _syncWithScheduleTab(matchId, winnerId);
        updated = true;
      }
    }

    if (updated) {
      print("✅ Bye matches auto-processed, reloading...");
      
      widget.onMatchUpdated?.call();
    }
  }

  Future<void> _propagateWinnerFromMatch(int matchId, int winnerId) async {
    final conn = await DBHelper.getConnection();

    final matchDetails = await conn.execute(
      """
      SELECT round_name, next_match_id_winner, next_match_position_winner,
             next_match_id_loser, next_match_position_loser,
             alliance1_id, alliance2_id, bracket_side, category_id
      FROM tbl_double_elimination
      WHERE match_id = :matchId
      """,
      {"matchId": matchId},
    );

    if (matchDetails.rows.isEmpty) return;

    final data = matchDetails.rows.first.assoc();
    final roundName = data['round_name'] as String;
    final bracketSide = data['bracket_side']?.toString() ?? '';
    
    // SPECIAL HANDLING FOR GRAND FINALS RESET
if (roundName == 'GF1' && bracketSide == 'grand') {
  // Get both alliances from GF1
  final alliance1Id = int.parse(data['alliance1_id']?.toString() ?? '0');
  final alliance2Id = int.parse(data['alliance2_id']?.toString() ?? '0');
  final categoryId = int.parse(data['category_id']?.toString() ?? '0');
  
  print("🎯 GF1 completed! Winner: $winnerId");
  
  // Find out which alliance is from Loser's Bracket
  final loserFinalResult = await conn.execute(
    """
    SELECT winner_alliance_id FROM tbl_double_elimination
    WHERE category_id = :catId AND bracket_side = 'losers'
    ORDER BY round_number DESC LIMIT 1
    """,
    {"catId": categoryId},
  );
  
  int loserBracketChampion = 0;
  if (loserFinalResult.rows.isNotEmpty) {
    loserBracketChampion = int.tryParse(
      loserFinalResult.rows.first.assoc()['winner_alliance_id']?.toString() ?? '0'
    ) ?? 0;
  }
  
  // Check if reset is needed (Loser's bracket champion won)
  final bool needReset = (winnerId == loserBracketChampion && loserBracketChampion != 0);
  
  if (needReset) {
  // NEED RESET - Create GF2 dynamically
  print("🎯 Loser's bracket champion won! Creating GF2 for reset match...");
  
  // Temporarily disable foreign key checks
  await conn.execute("SET FOREIGN_KEY_CHECKS = 0");
  
  try {
    // Check if GF2 already exists
    final gf2Check = await conn.execute(
      "SELECT match_id FROM tbl_double_elimination WHERE category_id = :catId AND round_name = 'GF2'",
      {"catId": categoryId},
    );
    
    int gf2Id;
    if (gf2Check.rows.isEmpty) {
      // Create GF2
      final insertResult = await DBHelper.executeDual(
        """
        INSERT INTO tbl_double_elimination 
          (category_id, round_name, match_position, bracket_side, round_number, 
           alliance1_id, alliance2_id, status)
        VALUES
          (:catId, 'GF2', 2, 'grand', 2, :a1, :a2, 'pending')
        """,
        {"catId": categoryId, "a1": alliance1Id, "a2": alliance2Id},
      );
      gf2Id = insertResult.lastInsertID.toInt();
      
      await DBHelper.executeDual(
        """
        INSERT INTO tbl_explorer_double_elimination 
          (category_id, round_name, match_position, bracket_side, round_number, 
           alliance1_id, alliance2_id, status)
        VALUES
          (:catId, 'GF2', 2, 'grand', 2, :a1, :a2, 'pending')
        """,
        {"catId": categoryId, "a1": alliance1Id, "a2": alliance2Id},
      );
      
      print("✅ Created GF2 with ID $gf2Id");
    } else {
      gf2Id = int.parse(gf2Check.rows.first.assoc()['match_id'].toString());
      await DBHelper.executeDual(
        """
        UPDATE tbl_double_elimination 
        SET alliance1_id = :a1, alliance2_id = :a2, status = 'pending', winner_alliance_id = NULL
        WHERE match_id = :gf2Id
        """,
        {"a1": alliance1Id, "a2": alliance2Id, "gf2Id": gf2Id},
      );
      print("✅ Updated existing GF2 with ID $gf2Id");
    }
    
    // Update GF1's next winner pointer to GF2
    await DBHelper.executeDual(
      """
      UPDATE tbl_double_elimination 
      SET next_match_id_winner = :gf2Id, next_match_position_winner = 1
      WHERE match_id = :matchId
      """,
      {"gf2Id": gf2Id, "matchId": matchId},
    );
    
    // COMMIT the transaction
    await conn.execute("COMMIT");
    print("✅ GF2 creation committed to database");
    
  } catch (e) {
    print("❌ Error creating GF2: $e");
    await conn.execute("ROLLBACK");
  } finally {
    await conn.execute("SET FOREIGN_KEY_CHECKS = 1");
  }
} else {
    // Winner's bracket champion won - tournament is OVER
    print("🎯 Winner's bracket champion won! Tournament complete. No GF2 needed.");
    
    // Delete any existing GF2 if it was created by mistake
    await DBHelper.executeDual(
      """
      DELETE FROM tbl_double_elimination 
      WHERE category_id = :catId AND round_name = 'GF2' AND bracket_side = 'grand'
      """,
      {"catId": categoryId},
    );
    await DBHelper.executeDual(
      """
      DELETE FROM tbl_explorer_double_elimination 
      WHERE category_id = :catId AND round_name = 'GF2' AND bracket_side = 'grand'
      """,
      {"catId": categoryId},
    );
    
    // Mark tournament as complete
    await DBHelper.executeDual(
      """
      UPDATE tbl_double_elimination 
      SET status = 'completed'
      WHERE category_id = :catId AND bracket_side = 'grand'
      """,
      {"catId": categoryId},
    );
  }
  
  return; // Don't continue with normal propagation
}

    // NORMAL PROPAGATION LOGIC FOR OTHER MATCHES
    final alliance1Id = int.parse(data['alliance1_id']?.toString() ?? '0');
    final alliance2Id = int.parse(data['alliance2_id']?.toString() ?? '0');
    final loserId = winnerId == alliance1Id ? alliance2Id : alliance1Id;

    print("📊 Propagating from $roundName: winner=$winnerId, loser=$loserId");

    // Propagate winner to next match
    final nextMatchIdWinnerStr = await _getNextMatchId(conn, matchId, 'winner');
    if (nextMatchIdWinnerStr != null && nextMatchIdWinnerStr != '0') {
      final nextMatchId = int.tryParse(nextMatchIdWinnerStr);
      if (nextMatchId != null) {
        final winnerPos = await _getNextMatchPosition(conn, matchId, 'winner');

        print("🎯 Propagating winner to match ID $nextMatchId at position $winnerPos");

        if (winnerPos == 1) {
          await DBHelper.executeDual(
            """
            UPDATE tbl_double_elimination 
            SET alliance1_id = :winnerId
            WHERE match_id = :nextMatchId AND (alliance1_id IS NULL OR alliance1_id = 0)
            """,
            {"winnerId": winnerId, "nextMatchId": nextMatchId},
          );
        } else {
          await DBHelper.executeDual(
            """
            UPDATE tbl_double_elimination 
            SET alliance2_id = :winnerId
            WHERE match_id = :nextMatchId AND (alliance2_id IS NULL OR alliance2_id = 0)
            """,
            {"winnerId": winnerId, "nextMatchId": nextMatchId},
          );
        }
        
        // Also update explorer table
        if (winnerPos == 1) {
          await DBHelper.executeDual(
            """
            UPDATE tbl_explorer_double_elimination 
            SET alliance1_id = :winnerId
            WHERE match_id = :nextMatchId AND (alliance1_id IS NULL OR alliance1_id = 0)
            """,
            {"winnerId": winnerId, "nextMatchId": nextMatchId},
          );
        } else {
          await DBHelper.executeDual(
            """
            UPDATE tbl_explorer_double_elimination 
            SET alliance2_id = :winnerId
            WHERE match_id = :nextMatchId AND (alliance2_id IS NULL OR alliance2_id = 0)
            """,
            {"winnerId": winnerId, "nextMatchId": nextMatchId},
          );
        }
      }
    }

    // Propagate loser to next match
    if (loserId > 0) {
      final nextMatchIdLoserStr = await _getNextMatchId(conn, matchId, 'loser');
      if (nextMatchIdLoserStr != null && nextMatchIdLoserStr != '0') {
        final nextMatchIdLoser = int.tryParse(nextMatchIdLoserStr);
        if (nextMatchIdLoser != null) {
          final loserPos = await _getNextMatchPosition(conn, matchId, 'loser');

          print("🎯 Propagating loser to match ID $nextMatchIdLoser at position $loserPos");

          if (loserPos == 1) {
            await DBHelper.executeDual(
              """
              UPDATE tbl_double_elimination 
              SET alliance1_id = :loserId
              WHERE match_id = :nextMatchId AND (alliance1_id IS NULL OR alliance1_id = 0)
              """,
              {"loserId": loserId, "nextMatchId": nextMatchIdLoser},
            );
          } else {
            await DBHelper.executeDual(
              """
              UPDATE tbl_double_elimination 
              SET alliance2_id = :loserId
              WHERE match_id = :nextMatchId AND (alliance2_id IS NULL OR alliance2_id = 0)
              """,
              {"loserId": loserId, "nextMatchId": nextMatchIdLoser},
            );
          }
          
          // Also update explorer table
          if (loserPos == 1) {
            await DBHelper.executeDual(
              """
              UPDATE tbl_explorer_double_elimination 
              SET alliance1_id = :loserId
              WHERE match_id = :nextMatchId AND (alliance1_id IS NULL OR alliance1_id = 0)
              """,
              {"loserId": loserId, "nextMatchId": nextMatchIdLoser},
            );
          } else {
            await DBHelper.executeDual(
              """
              UPDATE tbl_explorer_double_elimination 
              SET alliance2_id = :loserId
              WHERE match_id = :nextMatchId AND (alliance2_id IS NULL OR alliance2_id = 0)
              """,
              {"loserId": loserId, "nextMatchId": nextMatchIdLoser},
            );
          }
        }
      }
    }
  }

  Future<String?> _getNextMatchId(
    MySQLConnection conn,
    int matchId,
    String type,
  ) async {
    final result = await conn.execute(
      """
      SELECT next_match_id_$type as next_id
      FROM tbl_double_elimination
      WHERE match_id = :matchId
    """,
      {"matchId": matchId},
    );

    if (result.rows.isNotEmpty) {
      return result.rows.first.assoc()['next_id']?.toString();
    }
    return null;
  }

  Future<int> _getNextMatchPosition(
    MySQLConnection conn,
    int matchId,
    String type,
  ) async {
    final result = await conn.execute(
      """
      SELECT next_match_position_$type as position
      FROM tbl_double_elimination
      WHERE match_id = :matchId
    """,
      {"matchId": matchId},
    );

    if (result.rows.isNotEmpty) {
      return int.tryParse(
            result.rows.first.assoc()['position']?.toString() ?? '1',
          ) ??
          1;
    }
    return 1;
  }

  Future<void> _resetBracket() async {
  final confirm = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: const Color(0xFF2D0E7A),
      title: const Text(
        'Reset Bracket?',
        style: TextStyle(color: Colors.white),
      ),
      content: const Text(
        'This will reset all match results and clear all winners. This action cannot be undone.',
        style: TextStyle(color: Colors.white70),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text(
            'CANCEL',
            style: TextStyle(color: Colors.white54),
          ),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text(
            'RESET',
            style: TextStyle(color: Colors.redAccent),
          ),
        ),
      ],
    ),
  );

  if (confirm != true) return;

  setState(() => _isResetting = true);

  try {
    _autoProcessEnabled = false;

    // Reload settings and alliances to ensure fresh data
    final settings = await DBHelper.loadChampionshipSettings(widget.categoryId);
    _settings = settings ?? ChampionshipSettings.defaults(widget.categoryId);
    
    await _loadAlliances(); // Reload alliances to get current state

    final conn = await DBHelper.getConnection();
    await DBHelper.executeDual(
      "DELETE FROM tbl_double_elimination WHERE category_id = :catId",
      {"catId": widget.categoryId},
    );
    await DBHelper.executeDual(
      "DELETE FROM tbl_championship_schedule WHERE category_id = :catId",
      {"catId": widget.categoryId},
    );

    await _generateFlexibleBracket();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ Bracket reset successfully'),
          backgroundColor: Colors.green,
        ),
      );
    }
  } catch (e) {
    print("❌ Error resetting bracket: $e");
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('❌ Error resetting bracket: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  } finally {
    setState(() {
      _isResetting = false;
      _autoProcessEnabled = true;
    });
  }
}

  Future<void> _generateDoubleEliminationBracket() async {
    if (_settings == null) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF2D0E7A),
        title: Text(
          'Generate Double Elimination Bracket?',
          style: const TextStyle(color: Colors.white),
        ),
        content: Text(
          'This will create a double elimination bracket for ${_alliances.length} alliances.\n\n'
          '• Winner\'s bracket: Standard single elimination\n'
          '• Loser\'s bracket: Losers drop down\n'
          '• If Winner\'s bracket champion loses, a second grand final match is played',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text(
              'CANCEL',
              style: TextStyle(color: Colors.white54),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('GENERATE', style: TextStyle(color: kAccentGold)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _isGenerating = true);

    try {
      await _generateFlexibleBracket();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '✅ Double elimination bracket generated with ${_matches.length} matches',
            ),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('❌ Error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isGenerating = false);
    }
  }

  Future<void> _generateFlexibleBracket() async {
  final conn = await DBHelper.getConnection();

  await _createDoubleEliminationTable(conn);

  await DBHelper.executeDual(
    "DELETE FROM tbl_double_elimination WHERE category_id = :catId",
    {"catId": widget.categoryId},
  );

  // Ensure settings is loaded
  if (_settings == null) {
    final settings = await DBHelper.loadChampionshipSettings(widget.categoryId);
    _settings = settings ?? ChampionshipSettings.defaults(widget.categoryId);
  }

  // SPECIAL CASE: Only 2 alliances
  if (_numAlliances == 2) {
    print("🎯 Only 2 alliances detected - creating single final match");
    
    final allianceIds = _alliances
        .map((a) => int.parse(a['alliance_id'].toString()))
        .toList();
    
    await conn.execute("SET FOREIGN_KEY_CHECKS = 0");
    try {
      await DBHelper.executeDual(
        """
        INSERT INTO tbl_double_elimination 
          (category_id, round_name, match_position, bracket_side, round_number, 
           alliance1_id, alliance2_id, schedule_time, status)
        VALUES
          (:catId, 'FINAL', 1, 'grand', 1, 
           :a1, :a2, :time, 'pending')
        """,
        {
          "catId": widget.categoryId,
          "a1": allianceIds[0],
          "a2": allianceIds[1],
          "time": _settings!.startTimeString,
        },
      );
    } finally {
      await conn.execute("SET FOREIGN_KEY_CHECKS = 1");
    }
    
    print("✅ Created single final match for 2 alliances");
    await _loadMatches(autoProcessByes: false);
    return;
  }

  _bracketSize = 1;
  while (_bracketSize < _numAlliances) {
    _bracketSize <<= 1;
  }

  _totalRounds = (math.log(_bracketSize) / math.ln2).ceil();

  print(
    "🎯 Bracket size: $_bracketSize (next power of 2 after $_numAlliances)",
  );
  print("🎯 Total rounds: $_totalRounds");

  columnWidth = 280 + (_totalRounds * 8).toDouble();

  // Standard tournament seeding
  List<int?> seededAlliances = List.filled(_bracketSize, null);
  List<int> allianceIds = _alliances
      .map((a) => int.parse(a['alliance_id'].toString()))
      .toList();

  if (_numAlliances == 8) {
    // 8-team seeding: 1-8, 4-5, 3-6, 2-7
    List<int> seedingOrder = [0, 7, 3, 4, 2, 5, 1, 6];
    for (int i = 0; i < allianceIds.length; i++) {
      int position = seedingOrder[i];
      if (position < _bracketSize) {
        seededAlliances[position] = allianceIds[i];
      }
    }
  } else if (_numAlliances == 4) {
    // 4-team seeding: 1-4, 2-3
    List<int> seedingOrder = [0, 3, 1, 2];
    for (int i = 0; i < allianceIds.length; i++) {
      int position = seedingOrder[i];
      if (position < _bracketSize) {
        seededAlliances[position] = allianceIds[i];
      }
    }
  } else {
    // Generic seeding
    for (int i = 0; i < allianceIds.length; i++) {
      int allianceId = allianceIds[i];
      int position;
      if (i < allianceIds.length / 2) {
        position = i * 2;
      } else {
        int pairIndex = allianceIds.length - 1 - i;
        position = pairIndex * 2 + 1;
      }
      if (position < _bracketSize) {
        seededAlliances[position] = allianceId;
      }
    }
  }

  print("📊 Seeded alliances: $seededAlliances");
  int byeCount = seededAlliances.where((id) => id == null).length;
  print("📊 Number of byes: $byeCount");

  _matchNodes = {};
  await _generateCorrectMatchNodes(seededAlliances);
  await _insertAllMatches(conn);

  print("✅ Bracket generated successfully");

  await _loadMatches(autoProcessByes: false);
}

  Future<void> _generateCorrectMatchNodes(List<int?> seededAlliances) async {
  int matchIndex = 0;

  // STEP 1: Create Winner's Bracket matches
  print("🎯 Creating Winner's Bracket");

  if (_numAlliances == 4) {
  print("🎯 Generating 4-team double elimination bracket (using working 8-team pattern)");
  
  // Winner's Semi-finals (WSF_1 and WSF_2)
  for (int i = 0; i < 2; i++) {
    int? a1 = seededAlliances[i * 2];
    int? a2 = seededAlliances[i * 2 + 1];
    
    String matchId = i == 0 ? 'WSF_1' : 'WSF_2';
    
    _matchNodes[matchId] = {
      'id': matchId,
      'bracketSide': 'winners',
      'roundNumber': 1,
      'matchPosition': i + 1,
      'alliance1Id': a1 != null && a1 > 0 ? a1 : null,
      'alliance2Id': a2 != null && a2 > 0 ? a2 : null,
      'nextWinnerId': i == 0 ? 'WF_1' : 'WF_1',
      'nextWinnerPos': i == 0 ? 1 : 2,
      'nextLoserId': i == 0 ? 'LSF_1' : 'LSF_1',
      'nextLoserPos': i == 0 ? 1 : 2,
      'isByeMatch': (a1 == null || a1 == 0) || (a2 == null || a2 == 0),
    };
  }
  
  // Winner's Final (WF_1) - MATCHES 8-TEAM PATTERN
  _matchNodes['WF_1'] = {
    'id': 'WF_1',
    'bracketSide': 'winners',
    'roundNumber': 2,
    'matchPosition': 1,
    'alliance1Id': null,
    'alliance2Id': null,
    'nextWinnerId': 'GF1',  // CRITICAL: Use 'GF1' not 'GF_1'
    'nextWinnerPos': 1,
    'nextLoserId': 'LF_1',
    'nextLoserPos': 2,
    'isByeMatch': false,
  };
  
  // Loser's Semi-final (LSF_1)
  _matchNodes['LSF_1'] = {
    'id': 'LSF_1',
    'bracketSide': 'losers',
    'roundNumber': 1,
    'matchPosition': 1,
    'alliance1Id': null,
    'alliance2Id': null,
    'nextWinnerId': 'LF_1',
    'nextWinnerPos': 1,
    'nextLoserId': null,
    'nextLoserPos': null,
    'isByeMatch': false,
  };
  
  // Loser's Final (LF_1)
  _matchNodes['LF_1'] = {
    'id': 'LF_1',
    'bracketSide': 'losers',
    'roundNumber': 2,
    'matchPosition': 1,
    'alliance1Id': null,
    'alliance2Id': null,
    'nextWinnerId': 'GF1',  // CRITICAL: Use 'GF1' not 'GF_1'
    'nextWinnerPos': 2,
    'nextLoserId': null,
    'nextLoserPos': null,
    'isByeMatch': false,
  };
  
  // Grand Final 1 (GF1) - MATCHES 8-TEAM PATTERN
  _matchNodes['GF1'] = {
    'id': 'GF1',
    'bracketSide': 'grand',
    'roundNumber': 1,
    'matchPosition': 1,
    'alliance1Id': null,
    'alliance2Id': null,
    'nextWinnerId': null,  // Will be set to GF2 if reset needed
    'nextWinnerPos': null,
    'nextLoserId': null,
    'nextLoserPos': null,
    'isByeMatch': false,
  };
  

  // by updateBracketWinner when loser's bracket champion wins GF1
  
  print("📊 Generated ${_matchNodes.length} matches for 4-team bracket");
  print("   Winner's Bracket: WSF_1, WSF_2, WF_1");
  print("   Loser's Bracket: LSF_1, LF_1");
  print("   Grand Finals: GF1 (GF2 created dynamically if reset needed)");
  return;
}

  // Original logic for 8+ teams (starts here)
  // Create first round matches (W1_1 to W1_4)
  for (int i = 0; i < _bracketSize; i += 2) {
    matchIndex++;
    int? a1 = seededAlliances[i];
    int? a2 = seededAlliances[i + 1];

    bool hasTeam = (a1 != null && a1 > 0) || (a2 != null && a2 > 0);

    if (!hasTeam) {
      print("⚠️ Skipping match W1_$matchIndex - no teams");
      continue;
    }

    String matchId = 'W1_$matchIndex';

    _matchNodes[matchId] = {
      'id': matchId,
      'bracketSide': 'winners',
      'roundNumber': 1,
      'matchPosition': matchIndex,
      'alliance1Id': a1 != null && a1 > 0 ? a1 : null,
      'alliance2Id': a2 != null && a2 > 0 ? a2 : null,
      'nextWinnerId': null,
      'nextWinnerPos': null,
      'nextLoserId': null,
      'nextLoserPos': null,
      'isByeMatch': (a1 == null || a1 == 0) || (a2 == null || a2 == 0),
    };
  }

  int actualFirstRoundMatches = _matchNodes.length;
  print("📊 Actual first round matches: $actualFirstRoundMatches");

  // Create W2 (Semi-finals) - 2 matches
  for (int i = 0; i < 2; i++) {
    String matchId = 'W2_${i + 1}';
    _matchNodes[matchId] = {
      'id': matchId,
      'bracketSide': 'winners',
      'roundNumber': 2,
      'matchPosition': i + 1,
      'alliance1Id': null,
      'alliance2Id': null,
      'nextWinnerId': null,
      'nextWinnerPos': null,
      'nextLoserId': null,
      'nextLoserPos': null,
      'isByeMatch': false,
    };
  }

  // Create W3 (Winner's Final) - 1 match
  _matchNodes['W3_1'] = {
    'id': 'W3_1',
    'bracketSide': 'winners',
    'roundNumber': 3,
    'matchPosition': 1,
    'alliance1Id': null,
    'alliance2Id': null,
    'nextWinnerId': null,
    'nextWinnerPos': null,
    'nextLoserId': null,
    'nextLoserPos': null,
    'isByeMatch': false,
  };

  // Connect Winner's bracket (only if nodes exist)
  if (_matchNodes.containsKey('W1_1') && _matchNodes.containsKey('W1_2')) {
    _matchNodes['W1_1']!['nextWinnerId'] = 'W2_1';
    _matchNodes['W1_1']!['nextWinnerPos'] = 1;
    _matchNodes['W1_2']!['nextWinnerId'] = 'W2_1';
    _matchNodes['W1_2']!['nextWinnerPos'] = 2;
  }

  if (_matchNodes.containsKey('W1_3') && _matchNodes.containsKey('W1_4')) {
    _matchNodes['W1_3']!['nextWinnerId'] = 'W2_2';
    _matchNodes['W1_3']!['nextWinnerPos'] = 1;
    _matchNodes['W1_4']!['nextWinnerId'] = 'W2_2';
    _matchNodes['W1_4']!['nextWinnerPos'] = 2;
  }

  if (_matchNodes.containsKey('W2_1') && _matchNodes.containsKey('W2_2')) {
    _matchNodes['W2_1']!['nextWinnerId'] = 'W3_1';
    _matchNodes['W2_1']!['nextWinnerPos'] = 1;
    _matchNodes['W2_2']!['nextWinnerId'] = 'W3_1';
    _matchNodes['W2_2']!['nextWinnerPos'] = 2;
  }

  // STEP 2: Create Loser's Bracket matches
  print("🎯 Creating Loser's Bracket");

  // L1 (Loser's Round 1) - 2 matches (4 first-round losers)
  for (int i = 0; i < 2; i++) {
    String matchId = 'L1_${i + 1}';
    _matchNodes[matchId] = {
      'id': matchId,
      'bracketSide': 'losers',
      'roundNumber': 1,
      'matchPosition': i + 1,
      'alliance1Id': null,
      'alliance2Id': null,
      'nextWinnerId': null,
      'nextWinnerPos': null,
      'nextLoserId': null,
      'nextLoserPos': null,
      'isByeMatch': false,
    };
  }

  // L2 (Loser's Round 2) - 2 matches (L1 winners vs W2 losers)
  for (int i = 0; i < 2; i++) {
    String matchId = 'L2_${i + 1}';
    _matchNodes[matchId] = {
      'id': matchId,
      'bracketSide': 'losers',
      'roundNumber': 2,
      'matchPosition': i + 1,
      'alliance1Id': null,
      'alliance2Id': null,
      'nextWinnerId': null,
      'nextWinnerPos': null,
      'nextLoserId': null,
      'nextLoserPos': null,
      'isByeMatch': false,
    };
  }

  // L3 (Loser's Round 3) - 1 match (L2 winners)
  _matchNodes['L3_1'] = {
    'id': 'L3_1',
    'bracketSide': 'losers',
    'roundNumber': 3,
    'matchPosition': 1,
    'alliance1Id': null,
    'alliance2Id': null,
    'nextWinnerId': null,
    'nextWinnerPos': null,
    'nextLoserId': null,
    'nextLoserPos': null,
    'isByeMatch': false,
  };

  // L4 (Loser's Final) - 1 match (L3 winner vs W3 loser)
  _matchNodes['L4_1'] = {
    'id': 'L4_1',
    'bracketSide': 'losers',
    'roundNumber': 4,
    'matchPosition': 1,
    'alliance1Id': null,
    'alliance2Id': null,
    'nextWinnerId': null,
    'nextWinnerPos': null,
    'nextLoserId': null,
    'nextLoserPos': null,
    'isByeMatch': false,
  };

  // STEP 3: Connect Winner's bracket losers to Loser's bracket (only if nodes exist)
  print("🎯 Connecting winners to losers bracket");

  if (_matchNodes.containsKey('W1_1') && _matchNodes.containsKey('W1_2')) {
    _matchNodes['W1_1']!['nextLoserId'] = 'L1_1';
    _matchNodes['W1_1']!['nextLoserPos'] = 1;
    _matchNodes['W1_2']!['nextLoserId'] = 'L1_1';
    _matchNodes['W1_2']!['nextLoserPos'] = 2;
  }

  if (_matchNodes.containsKey('W1_3') && _matchNodes.containsKey('W1_4')) {
    _matchNodes['W1_3']!['nextLoserId'] = 'L1_2';
    _matchNodes['W1_3']!['nextLoserPos'] = 1;
    _matchNodes['W1_4']!['nextLoserId'] = 'L1_2';
    _matchNodes['W1_4']!['nextLoserPos'] = 2;
  }

  if (_matchNodes.containsKey('W2_1')) {
    _matchNodes['W2_1']!['nextLoserId'] = 'L2_1';
    _matchNodes['W2_1']!['nextLoserPos'] = 2;
  }
  
  if (_matchNodes.containsKey('W2_2')) {
    _matchNodes['W2_2']!['nextLoserId'] = 'L2_2';
    _matchNodes['W2_2']!['nextLoserPos'] = 2;
  }

  if (_matchNodes.containsKey('W3_1')) {
    _matchNodes['W3_1']!['nextLoserId'] = 'L4_1';
    _matchNodes['W3_1']!['nextLoserPos'] = 2;
  }

  // STEP 4: Connect Loser's bracket matches to each other
  print("🎯 Connecting loser's bracket progression");

  if (_matchNodes.containsKey('L1_1')) {
    _matchNodes['L1_1']!['nextWinnerId'] = 'L2_1';
    _matchNodes['L1_1']!['nextWinnerPos'] = 1;
  }
  
  if (_matchNodes.containsKey('L1_2')) {
    _matchNodes['L1_2']!['nextWinnerId'] = 'L2_2';
    _matchNodes['L1_2']!['nextWinnerPos'] = 1;
  }

  if (_matchNodes.containsKey('L2_1')) {
    _matchNodes['L2_1']!['nextWinnerId'] = 'L3_1';
    _matchNodes['L2_1']!['nextWinnerPos'] = 1;
  }
  
  if (_matchNodes.containsKey('L2_2')) {
    _matchNodes['L2_2']!['nextWinnerId'] = 'L3_1';
    _matchNodes['L2_2']!['nextWinnerPos'] = 2;
  }

  if (_matchNodes.containsKey('L3_1')) {
    _matchNodes['L3_1']!['nextWinnerId'] = 'L4_1';
    _matchNodes['L3_1']!['nextWinnerPos'] = 1;
  }

  // STEP 5: Create Grand Finals
  print("🎯 Creating Grand Finals");

  if (_matchNodes.containsKey('W3_1')) {
    _matchNodes['W3_1']!['nextWinnerId'] = 'GF1';
    _matchNodes['W3_1']!['nextWinnerPos'] = 1;
  }

  if (_matchNodes.containsKey('L4_1')) {
    _matchNodes['L4_1']!['nextWinnerId'] = 'GF1';
    _matchNodes['L4_1']!['nextWinnerPos'] = 2;
  }

  // Create GF1 only
  _matchNodes['GF1'] = {
    'id': 'GF1',
    'bracketSide': 'grand',
    'roundNumber': 1,
    'matchPosition': 1,
    'alliance1Id': null,
    'alliance2Id': null,
    'nextWinnerId': null,
    'nextWinnerPos': null,
    'nextLoserId': null,
    'nextLoserPos': null,
    'isByeMatch': false,
  };

  print("📊 Total matches generated: ${_matchNodes.length}");
  print("   Winner's Bracket: 7 matches (W1:4, W2:2, W3:1)");
  print("   Loser's Bracket: 6 matches (L1:2, L2:2, L3:1, L4:1)");
  print("   Grand Finals: 2 matches (GF1, GF2)");
  print("   Total: 15 matches");
}

  Future<void> _insertAllMatches(MySQLConnection conn) async {
  // Ensure settings is not null before using
  if (_settings == null) {
    final settings = await DBHelper.loadChampionshipSettings(widget.categoryId);
    _settings = settings ?? ChampionshipSettings.defaults(widget.categoryId);
  }
  
  int currentHour = _settings!.startTime.hour;
  int currentMinute = _settings!.startTime.minute;

  String formatTime(int hour, int minute) {
    return '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
  }

  var sortedMatches = _matchNodes.values.toList()
    ..sort((a, b) {
      int sideOrder(String side) {
        if (side == 'winners') return 1;
        if (side == 'losers') return 2;
        return 3;
      }
      if (a['bracketSide'] != b['bracketSide']) {
        return sideOrder(a['bracketSide']).compareTo(sideOrder(b['bracketSide']));
      }
      if (a['roundNumber'] != b['roundNumber']) {
        return a['roundNumber'].compareTo(b['roundNumber']);
      }
      return a['matchPosition'].compareTo(b['matchPosition']);
    });

  print("📊 Inserting ${sortedMatches.length} matches");

  // Disable foreign key checks temporarily
  await conn.execute("SET FOREIGN_KEY_CHECKS = 0");
  
  try {
    for (var node in sortedMatches) {
      String timeStr = formatTime(currentHour, currentMinute);
      String roundName = node['id'];

      // Convert 0 to NULL for foreign key constraints
      int? a1 = node['alliance1Id'];
      int? a2 = node['alliance2Id'];
      
      // Use null for 0 values to satisfy foreign key constraint
      Object? a1Param = (a1 != null && a1 > 0) ? a1 : null;
      Object? a2Param = (a2 != null && a2 > 0) ? a2 : null;

      var result = await DBHelper.executeDual(
        """
        INSERT INTO tbl_double_elimination 
          (category_id, round_name, match_position, bracket_side, round_number, 
           alliance1_id, alliance2_id, schedule_time, status)
        VALUES
          (:catId, :roundName, :pos, :side, :roundNum, 
           :a1, :a2, :time, 'pending')
        """,
        {
          "catId": widget.categoryId,
          "roundName": roundName,
          "pos": node['matchPosition'],
          "side": node['bracketSide'],
          "roundNum": node['roundNumber'],
          "a1": a1Param,
          "a2": a2Param,
          "time": timeStr,
        },
      );

      node['dbId'] = result.lastInsertID.toInt();

      // Only advance time for matches that have teams
      if ((node['alliance1Id'] != null && node['alliance1Id'] > 0) ||
          (node['alliance2Id'] != null && node['alliance2Id'] > 0)) {
        currentMinute += _settings!.durationMinutes + _settings!.intervalMinutes;
        while (currentMinute >= 60) {
          currentMinute -= 60;
          currentHour++;
        }
      }
    }
  } finally {
    // Re-enable foreign key checks
    await conn.execute("SET FOREIGN_KEY_CHECKS = 1");
  }

  // Set up next match connections
  for (var node in sortedMatches) {
    if (node['nextWinnerId'] != null) {
      var nextNode = _matchNodes[node['nextWinnerId']];
      if (nextNode != null && nextNode['dbId'] != null) {
        await DBHelper.executeDual(
          """
          UPDATE tbl_double_elimination 
          SET next_match_id_winner = :nextId, next_match_position_winner = :pos
          WHERE match_id = :currentId
          """,
          {
            "nextId": nextNode['dbId'],
            "pos": node['nextWinnerPos'],
            "currentId": node['dbId'],
          },
        );
      }
    }

    if (node['nextLoserId'] != null) {
      var nextNode = _matchNodes[node['nextLoserId']];
      if (nextNode != null && nextNode['dbId'] != null) {
        await DBHelper.executeDual(
          """
          UPDATE tbl_double_elimination 
          SET next_match_id_loser = :nextId, next_match_position_loser = :pos
          WHERE match_id = :currentId
          """,
          {
            "nextId": nextNode['dbId'],
            "pos": node['nextLoserPos'],
            "currentId": node['dbId'],
          },
        );
      }
    }
  }

  print("✅ Inserted and connected all matches");
}

  String _getRoundName(int round, int matchCount, String bracketSide) {
    if (bracketSide == 'winners') {
      if (round == _totalRounds) {
        return 'WINNER\'S FINAL';
      } else if (round == _totalRounds - 1) {
        return 'SEMI-FINALS';
      } else if (round == _totalRounds - 2) {
        return 'QUARTER-FINALS';
      } else {
        return 'ROUND $round';
      }
    } else if (bracketSide == 'losers') {
      if (_numAlliances == 8) {
        if (round == 4) return 'LOSER\'S FINAL';
        if (round == 3) return 'LOSER\'S SEMI-FINAL';
        if (round == 2) return 'LOSER\'S ROUND 2';
        return 'LOSER\'S ROUND 1';
      } else if (_numAlliances == 4) {
        if (round == 2) return 'LOSER\'S FINAL';
        return 'LOSER\'S ROUND 1';
      }
      return 'LOSER\'S ROUND $round';
    }
    return 'ROUND $round';
  }

  Widget _buildHeader(String title, Color color, double width) {
    return Container(
      width: width,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Text(
        title,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.bold,
          fontSize: 13,
        ),
        textAlign: TextAlign.center,
      ),
    );
  }

  Widget _buildMatchCard(Map<String, dynamic> match, Color sideColor) {
    final alliance1IdStr = match['alliance1_id']?.toString();
    final alliance2IdStr = match['alliance2_id']?.toString();
    final roundName = match['round_name'] as String;

    int? alliance1Id = alliance1IdStr != null
        ? int.tryParse(alliance1IdStr)
        : null;
    int? alliance2Id = alliance2IdStr != null
        ? int.tryParse(alliance2IdStr)
        : null;

    // Updated conditions to handle placeholder (-1) as TBD
    final hasBothTeams =
        (alliance1Id != null && alliance1Id > 0 && alliance1Id != -1) &&
        (alliance2Id != null && alliance2Id > 0 && alliance2Id != -1);
    final hasOneTeam =
        (alliance1Id != null && alliance1Id > 0 && alliance1Id != -1) ||
        (alliance2Id != null && alliance2Id > 0 && alliance2Id != -1);
    final hasNoTeams = (!hasBothTeams && !hasOneTeam);

    final winnerIdStr = match['winner_alliance_id']?.toString();
    final isPlayed =
        winnerIdStr != null &&
        int.tryParse(winnerIdStr) != null &&
        int.parse(winnerIdStr) > 0;
    final winnerIs1 = isPlayed && winnerIdStr == alliance1IdStr;
    final winnerIs2 = isPlayed && winnerIdStr == alliance2IdStr;

    bool canTap = false;
    if (!isPlayed && (hasBothTeams || hasOneTeam)) {
      canTap = true;
    }

    if (roundName == 'GF2') {
      final hasAnyTeam =
          (alliance1Id != null && alliance1Id > 0) ||
          (alliance2Id != null && alliance2Id > 0);
      canTap = !isPlayed && hasAnyTeam;
    }

    if (hasNoTeams) {
      return Container(
        width: matchWidth,
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.02),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.white.withOpacity(0.1), width: 1),
        ),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.05),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(6),
                  topRight: Radius.circular(6),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    match['round_name'] ?? '',
                    style: const TextStyle(color: Colors.white38, fontSize: 10),
                  ),
                  Text(
                    match['schedule_time'] ?? '--:--',
                    style: const TextStyle(color: Colors.white24, fontSize: 9),
                  ),
                ],
              ),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Text(
                '—',
                style: TextStyle(color: Colors.white24, fontSize: 20),
              ),
            ),
          ],
        ),
      );
    }

    return GestureDetector(
      onTap: canTap ? () => _showMatchScoreDialog(match) : null,
      child: Container(
        width: matchWidth,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              const Color(0xFF1A0A4A),
              const Color(0xFF2D0E7A).withOpacity(0.5),
            ],
          ),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isPlayed ? Colors.green : sideColor,
            width: 2,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.2),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: sideColor.withOpacity(0.2),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(6),
                  topRight: Radius.circular(6),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    match['round_name'] ?? '',
                    style: TextStyle(
                      color: sideColor,
                      fontWeight: FontWeight.bold,
                      fontSize: 10,
                    ),
                  ),
                  Text(
                    match['schedule_time'] ?? '--:--',
                    style: const TextStyle(color: Colors.white70, fontSize: 9),
                  ),
                ],
              ),
            ),

            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: BoxDecoration(
                color: winnerIs1 ? Colors.green.withOpacity(0.2) : null,
              ),
              child: Row(
                children: [
                  Container(
                    width: 20,
                    height: 20,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: sideColor.withOpacity(0.2),
                      border: Border.all(color: sideColor, width: 1.5),
                    ),
                    child: Center(
                      child: Text(
                        match['alliance1_rank']?.replaceAll('#', '') ?? '?',
                        style: TextStyle(
                          color: sideColor,
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      match['alliance1_name'] ?? 'TBD',
                      style: TextStyle(
                        color: winnerIs1 ? Colors.green : Colors.white,
                        fontWeight: winnerIs1
                            ? FontWeight.bold
                            : FontWeight.normal,
                        fontSize: 10,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (winnerIs1)
                    const Icon(
                      Icons.emoji_events,
                      color: Color(0xFFFFD700),
                      size: 12,
                    ),
                ],
              ),
            ),

            Container(height: 1, color: Colors.white.withOpacity(0.1)),

            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: BoxDecoration(
                color: winnerIs2 ? Colors.green.withOpacity(0.2) : null,
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(6),
                  bottomRight: Radius.circular(6),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 20,
                    height: 20,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: sideColor.withOpacity(0.2),
                      border: Border.all(color: sideColor, width: 1.5),
                    ),
                    child: Center(
                      child: Text(
                        match['alliance2_rank']?.replaceAll('#', '') ?? '?',
                        style: TextStyle(
                          color: sideColor,
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      match['alliance2_name'] ?? 'TBD',
                      style: TextStyle(
                        color: winnerIs2 ? Colors.green : Colors.white,
                        fontWeight: winnerIs2
                            ? FontWeight.bold
                            : FontWeight.normal,
                        fontSize: 10,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (winnerIs2)
                    const Icon(
                      Icons.emoji_events,
                      color: Color(0xFFFFD700),
                      size: 12,
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWinnerBracketColumn({
    required String title,
    required Color color,
    required Map<int, List<Map<String, dynamic>>> matchesByRound,
    required List<int> rounds,
    required double width,
  }) {
    return SizedBox(
      width: width,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(title, color, width),
          const SizedBox(height: 20),
          ...rounds.map((round) {
            final matches = matchesByRound[round] ?? [];
            final roundName = _getRoundName(round, matches.length, 'winners');

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    roundName,
                    style: TextStyle(
                      color: color,
                      fontWeight: FontWeight.bold,
                      fontSize: 11,
                    ),
                  ),
                ),
                ...matches.asMap().entries.map((entry) {
                  final index = entry.key;
                  final match = entry.value;

                  return Container(
                    margin: EdgeInsets.only(
                      bottom: index < matches.length - 1 ? rowGap : 0,
                    ),
                    child: _buildMatchCard(match, color),
                  );
                }),
                const SizedBox(height: 12),
              ],
            );
          }).toList(),
        ],
      ),
    );
  }

  Widget _buildLoserBracketColumn({
    required String title,
    required Color color,
    required Map<int, List<Map<String, dynamic>>> matchesByRound,
    required List<int> rounds,
    required double width,
  }) {
    return SizedBox(
      width: width,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(title, color, width),
          const SizedBox(height: 20),
          ...rounds.map((round) {
            final matches = matchesByRound[round] ?? [];
            final roundName = _getRoundName(round, matches.length, 'losers');

            double verticalOffset = 0;
            if (round > 1) {
              verticalOffset = (round - 1) * 15.0;
            }

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  margin: EdgeInsets.only(top: verticalOffset, bottom: 8),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    roundName,
                    style: TextStyle(
                      color: color,
                      fontWeight: FontWeight.bold,
                      fontSize: 11,
                    ),
                  ),
                ),
                ...matches.asMap().entries.map((entry) {
                  final index = entry.key;
                  final match = entry.value;

                  return Container(
                    margin: EdgeInsets.only(
                      bottom: index < matches.length - 1 ? rowGap : 0,
                    ),
                    child: _buildMatchCard(match, color),
                  );
                }),
                const SizedBox(height: 12),
              ],
            );
          }).toList(),
        ],
      ),
    );
  }

  Widget _buildEliminatedColumn({
    required String title,
    required Color color,
    required List<Map<String, dynamic>> eliminated,
    required double width,
  }) {
    return SizedBox(
      width: width,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(title, color, width),
          const SizedBox(height: 20),
          if (eliminated.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Text(
                'No eliminated alliances',
                style: TextStyle(color: Colors.white.withOpacity(0.5)),
              ),
            ),
          ...eliminated.map((e) {
            return Container(
              margin: const EdgeInsets.only(bottom: rowGap),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.02),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: color.withOpacity(0.15)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: color.withOpacity(0.12),
                      border: Border.all(color: color, width: 1.2),
                    ),
                    child: Center(
                      child: Text(
                        (e['alliance_rank'] ?? '').toString().replaceAll(
                          '#',
                          '',
                        ),
                        style: TextStyle(
                          color: color,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      e['alliance_name'] ?? 'Unknown',
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
        ],
      ),
    );
  }

  Widget _buildBracketContent() {
  final Map<int, List<Map<String, dynamic>>> winnersByRound = {};
  final Map<int, List<Map<String, dynamic>>> losersByRound = {};
  final List<Map<String, dynamic>> grandFinalMatches = [];

  for (final match in _matches) {
    final side = match['bracket_side'] as String;
    final roundNum = int.parse(match['round_number']?.toString() ?? '1');

    if (side == 'winners') {
      winnersByRound.putIfAbsent(roundNum, () => []).add(match);
    } else if (side == 'losers') {
      losersByRound.putIfAbsent(roundNum, () => []).add(match);
    } else if (side == 'grand') {
      grandFinalMatches.add(match);
    }
  }

  final winnersRounds = winnersByRound.keys.toList()..sort();
  final losersRounds = losersByRound.keys.toList()..sort();

    // Track losses per alliance and elimination order
  final Map<int, int> allianceLosses = {};
  final Map<int, int> eliminationOrder = {}; // Store elimination index (1 = first eliminated)
  final Map<int, int> eliminationRound = {}; // Store which round they were eliminated

  for (final a in _alliances) {
    final id = int.parse(a['alliance_id'].toString());
    allianceLosses[id] = 0;
  }

  int eliminationCounter = 0;
  
    // Process matches in TRUE chronological tournament order
  final sortedMatches = List<Map<String, dynamic>>.from(_matches);
  sortedMatches.sort((a, b) {
    // Grand Finals Round 2 (GF2) should ALWAYS be last
    final nameA = a['round_name'] as String? ?? '';
    final nameB = b['round_name'] as String? ?? '';
    
    if (nameA == 'GF2') return 1;
    if (nameB == 'GF2') return -1;
    
    if (nameA == 'GF1' && nameB != 'GF1') return 1;
    if (nameB == 'GF1' && nameA != 'GF1') return -1;
    
    // Winners bracket matches happen before losers bracket matches of same round
    final sideA = a['bracket_side'] as String;
    final sideB = b['bracket_side'] as String;
    final sideOrder = {'winners': 1, 'losers': 2};
    if (sideA != sideB && sideA != 'grand' && sideB != 'grand') {
      return (sideOrder[sideA] ?? 3).compareTo(sideOrder[sideB] ?? 3);
    }
    
    // Sort by round number
    final roundA = int.parse(a['round_number']?.toString() ?? '0');
    final roundB = int.parse(b['round_number']?.toString() ?? '0');
    if (roundA != roundB) return roundA.compareTo(roundB);
    
    // For same round, sort by match_position
    final posA = int.parse(a['match_position']?.toString() ?? '0');
    final posB = int.parse(b['match_position']?.toString() ?? '0');
    
    // SPECIAL: For Losers Round 1, ensure L1_1 (pos 1) comes BEFORE L1_2 (pos 2)
    if (sideA == 'losers' && roundA == 1) {
      return posA.compareTo(posB);
    }
    
    return posA.compareTo(posB);
  });
  
  // DEBUG: Print the match processing order
  print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");
  print("📋 MATCH PROCESSING ORDER:");
  for (int i = 0; i < sortedMatches.length; i++) {
    final m = sortedMatches[i];
    final name = m['round_name'] as String? ?? '';
    final side = m['bracket_side'] as String;
    final pos = m['match_position'];
    print("   ${i+1}. $name ($side, pos $pos)");
  }
  print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");

  for (final match in sortedMatches) {
    final winnerStr = match['winner_alliance_id']?.toString();
    if (winnerStr == null || winnerStr == '0') continue;
    
    final winnerId = int.tryParse(winnerStr) ?? 0;
    final a1 = int.tryParse(match['alliance1_id']?.toString() ?? '0') ?? 0;
    final a2 = int.tryParse(match['alliance2_id']?.toString() ?? '0') ?? 0;
    final roundNum = int.parse(match['round_number']?.toString() ?? '1');
    final bracketSide = match['bracket_side'] as String;
    
    if (winnerId == 0) continue;
    
    final loserId = (winnerId == a1) ? a2 : a1;
    if (loserId > 0 && loserId != 0) {
      final currentLosses = allianceLosses[loserId] ?? 0;
      final newLosses = currentLosses + 1;
      allianceLosses[loserId] = newLosses;
      
      // CRITICAL: Only record elimination on the SECOND loss (newLosses == 2)
      if (newLosses == 2 && !eliminationOrder.containsKey(loserId)) {
        eliminationCounter++;
        eliminationOrder[loserId] = eliminationCounter;
        eliminationRound[loserId] = roundNum;
        print("📊 ${_getAllianceRank(loserId)} ELIMINATED (2nd loss) in round $roundNum ($bracketSide) - Order: $eliminationCounter");
      } else {
        print("📊 ${_getAllianceRank(loserId)} now has $newLosses loss(es) (Round $roundNum, $bracketSide)");
      }
    }
  }

    // Build eliminated list sorted by match order (chronological)
  final List<Map<String, dynamic>> eliminatedAlliances = [];
  
  // Get all alliances with exactly 2 losses (eliminated)
  final List<Map<String, dynamic>> eliminatedWithOrder = [];
  for (final a in _alliances) {
    final id = int.parse(a['alliance_id'].toString());
    final losses = allianceLosses[id] ?? 0;
    if (losses >= 2 && eliminationOrder.containsKey(id)) {
      eliminatedWithOrder.add({
        'alliance_id': id,
        'alliance_rank': '#${a['alliance_rank']}',
        'alliance_name': '${a['captain_name']} / ${a['partner_name']}',
        'elimination_order': eliminationOrder[id] ?? 999,
        'elimination_round': eliminationRound[id] ?? 0,
      });
    }
  }
  
  // Sort by elimination order (which is already chronological from match processing)
  eliminatedWithOrder.sort((a, b) {
    return (a['elimination_order'] as int).compareTo(b['elimination_order'] as int);
  });
  
  for (final entry in eliminatedWithOrder) {
    eliminatedAlliances.add({
      'alliance_id': entry['alliance_id'],
      'alliance_rank': entry['alliance_rank'],
      'alliance_name': entry['alliance_name'],
    });
  }
  
  // Print elimination order for debugging
  print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");
  print("🏆 ELIMINATION ORDER (by 2nd loss):");
  for (int i = 0; i < eliminatedAlliances.length; i++) {
    final e = eliminatedAlliances[i];
    print("   ${i+1}. ${e['alliance_rank']} - ${e['alliance_name']}");
  }
  print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");

  return IntrinsicHeight(
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildWinnerBracketColumn(
          title: 'WINNER\'S BRACKET',
          color: const Color(0xFF00CFFF),
          matchesByRound: winnersByRound,
          rounds: winnersRounds,
          width: columnWidth,
        ),
        const SizedBox(width: columnGap),
        Padding(
          padding: const EdgeInsets.only(top: 60),
          child: _buildLoserBracketColumn(
            title: 'LOSER\'S BRACKET',
            color: const Color(0xFFFF6B6B),
            matchesByRound: losersByRound,
            rounds: losersRounds,
            width: columnWidth,
          ),
        ),
        const SizedBox(width: columnGap * 2),
        Padding(
          padding: const EdgeInsets.only(top: 120),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeader('GRAND FINAL', const Color(0xFFFFD700), columnWidth),
              const SizedBox(height: 20),
              ...grandFinalMatches.map(
                (match) => Padding(
                  padding: const EdgeInsets.only(bottom: rowGap),
                  child: _buildMatchCard(match, const Color(0xFFFFD700)),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: columnGap * 2),
        Padding(
          padding: const EdgeInsets.only(top: 100),
          child: _buildEliminatedColumn(
            title: 'ELIMINATED',
            color: Colors.grey,
            eliminated: eliminatedAlliances,
            width: columnWidth,
          ),
        ),
      ],
    ),
  );
}


  Widget _buildBracketLayout() {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              OutlinedButton.icon(
                onPressed: _isResetting ? null : _resetBracket,
                icon: _isResetting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(
                        Icons.restart_alt,
                        color: Colors.orange,
                        size: 20,
                      ),
                label: Text(
                  _isResetting ? 'RESETTING...' : 'RESET BRACKET',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.orange,
                  side: const BorderSide(color: Colors.orange, width: 2),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 12,
                  ),
                ),
              ),
            ],
          ),
        ),

        Expanded(
          child: Container(
            decoration: BoxDecoration(
              border: Border.all(color: Colors.transparent),
            ),
            child: SingleChildScrollView(
              scrollDirection: Axis.vertical,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: _buildBracketContent(),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _showMatchScoreDialog(Map<String, dynamic> match) async {
    final canPlay = await _canPlayMatch(match);

    if (!canPlay) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('❌ Previous matches must be completed first'),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 2),
          ),
        );
      }
      return;
    }

    final alliance1IdStr = match['alliance1_id']?.toString();
    final alliance2IdStr = match['alliance2_id']?.toString();

    int? alliance1Id = alliance1IdStr != null
        ? int.tryParse(alliance1IdStr)
        : null;
    int? alliance2Id = alliance2IdStr != null
        ? int.tryParse(alliance2IdStr)
        : null;

    final winnerIdStr = match['winner_alliance_id']?.toString();
    final hasWinner =
        winnerIdStr != null &&
        int.tryParse(winnerIdStr) != null &&
        int.parse(winnerIdStr) > 0;

    if (hasWinner) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('This match already has a winner'),
            backgroundColor: Colors.orange,
          ),
        );
      }
      return;
    }

    if ((alliance1Id == null || alliance1Id == 0) &&
        (alliance2Id != null && alliance2Id > 0)) {
      int winnerId = alliance2Id;
      String winnerName = match['alliance2_name'] ?? 'Team';

      bool? confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: const Color(0xFF2D0E7A),
          title: const Text(
            'Advance Team?',
            style: TextStyle(color: Colors.white),
          ),
          content: Text(
            '$winnerName has a BYE and automatically advances.\n\nDo you want to advance them to the next round?',
            style: const TextStyle(color: Colors.white70),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text(
                'CANCEL',
                style: TextStyle(color: Colors.white54),
              ),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFFD700),
              ),
              child: const Text(
                'ADVANCE',
                style: TextStyle(color: Colors.black),
              ),
            ),
          ],
        ),
      );

      if (confirm == true) {
        await _updateMatchResult(match, winnerId);
      }
      return;
    } else if ((alliance2Id == null || alliance2Id == 0) &&
        (alliance1Id != null && alliance1Id > 0)) {
      int winnerId = alliance1Id;
      String winnerName = match['alliance1_name'] ?? 'Team';

      bool? confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: const Color(0xFF2D0E7A),
          title: const Text(
            'Advance Team?',
            style: TextStyle(color: Colors.white),
          ),
          content: Text(
            '$winnerName has a BYE and automatically advances.\n\nDo you want to advance them to the next round?',
            style: const TextStyle(color: Colors.white70),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text(
                'CANCEL',
                style: TextStyle(color: Colors.white54),
              ),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFFD700),
              ),
              child: const Text(
                'ADVANCE',
                style: TextStyle(color: Colors.black),
              ),
            ),
          ],
        ),
      );

      if (confirm == true) {
        await _updateMatchResult(match, winnerId);
      }
      return;
    }

    int? selectedWinnerId;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          backgroundColor: const Color(0xFF2D0E7A),
          title: const Text(
            'Enter Match Result',
            style: TextStyle(color: Colors.white),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Select Winner:',
                style: TextStyle(color: Colors.white70),
              ),
              const SizedBox(height: 16),
              if (match['alliance1_id'] != null &&
                  int.parse(match['alliance1_id'].toString()) > 0)
                ListTile(
                  title: Text(
                    match['alliance1_name'] ?? 'Alliance 1',
                    style: const TextStyle(color: Colors.white),
                  ),
                  leading: Radio<int>(
                    value: int.parse(match['alliance1_id'].toString()),
                    groupValue: selectedWinnerId,
                    onChanged: (value) {
                      setState(() {
                        selectedWinnerId = value;
                      });
                    },
                  ),
                ),
              if (match['alliance2_id'] != null &&
                  int.parse(match['alliance2_id'].toString()) > 0)
                ListTile(
                  title: Text(
                    match['alliance2_name'] ?? 'Alliance 2',
                    style: const TextStyle(color: Colors.white),
                  ),
                  leading: Radio<int>(
                    value: int.parse(match['alliance2_id'].toString()),
                    groupValue: selectedWinnerId,
                    onChanged: (value) {
                      setState(() {
                        selectedWinnerId = value;
                      });
                    },
                  ),
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text(
                'CANCEL',
                style: TextStyle(color: Colors.white54),
              ),
            ),
            ElevatedButton(
              onPressed: () async {
                if (selectedWinnerId != null) {
                  await _updateMatchResult(match, selectedWinnerId!);
                  if (ctx.mounted) Navigator.pop(ctx);
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFFD700),
              ),
              child: const Text('SAVE', style: TextStyle(color: Colors.black)),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _updateMatchResult(
    Map<String, dynamic> match,
    int winnerId,
  ) async {
    try {
      final matchId = int.parse(match['match_id'].toString());
      await DBHelper.updateBracketWinner(matchId, winnerId);

      // Reload matches and notify listeners
      await _loadMatches(autoProcessByes: false);
      widget.onMatchUpdated?.call();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Match result recorded'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      print("❌ Error updating match: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('❌ Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<bool> _canPlayMatch(Map<String, dynamic> match) async {
    final roundName = match['round_name'] as String;

    final alliance1IdStr = match['alliance1_id']?.toString();
    final alliance2IdStr = match['alliance2_id']?.toString();

    int? alliance1Id = alliance1IdStr != null
        ? int.tryParse(alliance1IdStr)
        : null;
    int? alliance2Id = alliance2IdStr != null
        ? int.tryParse(alliance2IdStr)
        : null;

    bool hasValidTeam1 = alliance1Id != null && alliance1Id > 0;
    bool hasValidTeam2 = alliance2Id != null && alliance2Id > 0;

    if (!hasValidTeam1 && !hasValidTeam2) {
      return false;
    }

    if (hasValidTeam1 != hasValidTeam2) {
      return true;
    }

    final conn = await DBHelper.getConnection();

    if (roundName.startsWith('W')) {
      final parts = roundName.split('_');
      if (parts.length < 2) return true;

      final round = int.parse(parts[0].substring(1));
      final pos = int.parse(parts[1]);

      if (round > 1) {
        final prevMatch1 = 'W${round - 1}_${pos * 2 - 1}';
        final prevMatch2 = 'W${round - 1}_${pos * 2}';

        final result1 = await conn.execute(
          """
        SELECT winner_alliance_id FROM tbl_double_elimination 
        WHERE category_id = :catId AND round_name = :matchName
      """,
          {"catId": widget.categoryId, "matchName": prevMatch1},
        );

        final result2 = await conn.execute(
          """
        SELECT winner_alliance_id FROM tbl_double_elimination 
        WHERE category_id = :catId AND round_name = :matchName
      """,
          {"catId": widget.categoryId, "matchName": prevMatch2},
        );

        final hasWinner1 =
            result1.rows.isNotEmpty &&
            result1.rows.first.assoc()['winner_alliance_id'] != null &&
            int.parse(
                  result1.rows.first.assoc()['winner_alliance_id'].toString(),
                ) >
                0;
        final hasWinner2 =
            result2.rows.isNotEmpty &&
            result2.rows.first.assoc()['winner_alliance_id'] != null &&
            int.parse(
                  result2.rows.first.assoc()['winner_alliance_id'].toString(),
                ) >
                0;

        return hasWinner1 && hasWinner2;
      }
    } else if (roundName.startsWith('L')) {
      final parts = roundName.split('_');
      if (parts.length < 2) return true;

      final round = int.parse(parts[0].substring(1));
      final pos = int.parse(parts[1]);

      if (round == 1) {
        // L1 matches: need winners from W1 matches
        final wMatch1 = 'W1_${pos * 2 - 1}';
        final wMatch2 = 'W1_${pos * 2}';

        final result1 = await conn.execute(
          """
        SELECT winner_alliance_id FROM tbl_double_elimination 
        WHERE category_id = :catId AND round_name = :matchName
      """,
          {"catId": widget.categoryId, "matchName": wMatch1},
        );

        final result2 = await conn.execute(
          """
        SELECT winner_alliance_id FROM tbl_double_elimination 
        WHERE category_id = :catId AND round_name = :matchName
      """,
          {"catId": widget.categoryId, "matchName": wMatch2},
        );

        final hasLoser1 =
            result1.rows.isNotEmpty &&
            result1.rows.first.assoc()['winner_alliance_id'] != null &&
            int.parse(
                  result1.rows.first.assoc()['winner_alliance_id'].toString(),
                ) >
                0;
        final hasLoser2 =
            result2.rows.isNotEmpty &&
            result2.rows.first.assoc()['winner_alliance_id'] != null &&
            int.parse(
                  result2.rows.first.assoc()['winner_alliance_id'].toString(),
                ) >
                0;

        // Actually we need the LOSERS, but the method checks for winner_alliance_id
        // In L1, both participants come from losers of W1, so we need both W1 matches to be completed
        return hasLoser1 && hasLoser2;
      } else if (round == 2) {
        // L2 matches need:
        // - Winner of L1_${pos} (top position)
        // - Loser of W2_${pos} (bottom position)

        // Check L1 winner
        final l1Match = 'L1_${pos}';
        final resultL1 = await conn.execute(
          """
        SELECT winner_alliance_id FROM tbl_double_elimination 
        WHERE category_id = :catId AND round_name = :matchName
      """,
          {"catId": widget.categoryId, "matchName": l1Match},
        );

        final hasL1Winner =
            resultL1.rows.isNotEmpty &&
            resultL1.rows.first.assoc()['winner_alliance_id'] != null &&
            int.parse(
                  resultL1.rows.first.assoc()['winner_alliance_id'].toString(),
                ) >
                0;

        // Check W2 loser
        final w2Match = 'W2_${pos}';
        final resultW2 = await conn.execute(
          """
        SELECT winner_alliance_id FROM tbl_double_elimination 
        WHERE category_id = :catId AND round_name = :matchName
      """,
          {"catId": widget.categoryId, "matchName": w2Match},
        );

        final hasW2Winner =
            resultW2.rows.isNotEmpty &&
            resultW2.rows.first.assoc()['winner_alliance_id'] != null &&
            int.parse(
                  resultW2.rows.first.assoc()['winner_alliance_id'].toString(),
                ) >
                0;

        // We need both L1 to have a winner AND W2 to have a winner (so that it has a loser)
        return hasL1Winner && hasW2Winner;
      } else if (round == 3) {
        // L3 match: needs winners from both L2 matches
        final l2Match1 = 'L2_1';
        final l2Match2 = 'L2_2';

        final result1 = await conn.execute(
          """
        SELECT winner_alliance_id FROM tbl_double_elimination 
        WHERE category_id = :catId AND round_name = :matchName
      """,
          {"catId": widget.categoryId, "matchName": l2Match1},
        );

        final result2 = await conn.execute(
          """
        SELECT winner_alliance_id FROM tbl_double_elimination 
        WHERE category_id = :catId AND round_name = :matchName
      """,
          {"catId": widget.categoryId, "matchName": l2Match2},
        );

        final hasWinner1 =
            result1.rows.isNotEmpty &&
            result1.rows.first.assoc()['winner_alliance_id'] != null &&
            int.parse(
                  result1.rows.first.assoc()['winner_alliance_id'].toString(),
                ) >
                0;
        final hasWinner2 =
            result2.rows.isNotEmpty &&
            result2.rows.first.assoc()['winner_alliance_id'] != null &&
            int.parse(
                  result2.rows.first.assoc()['winner_alliance_id'].toString(),
                ) >
                0;

        return hasWinner1 && hasWinner2;
      } else if (round == 4) {
        // L4 (Loser's Final): needs winner of L3 and loser of W3

        // Check L3 winner
        final resultL3 = await conn.execute(
          """
        SELECT winner_alliance_id FROM tbl_double_elimination 
        WHERE category_id = :catId AND round_name = 'L3_1'
      """,
          {"catId": widget.categoryId},
        );

        final hasL3Winner =
            resultL3.rows.isNotEmpty &&
            resultL3.rows.first.assoc()['winner_alliance_id'] != null &&
            int.parse(
                  resultL3.rows.first.assoc()['winner_alliance_id'].toString(),
                ) >
                0;

        // Check W3 (needs to have a winner to have a loser)
        final resultW3 = await conn.execute(
          """
        SELECT winner_alliance_id FROM tbl_double_elimination 
        WHERE category_id = :catId AND round_name = 'W3_1'
      """,
          {"catId": widget.categoryId},
        );

        final hasW3Winner =
            resultW3.rows.isNotEmpty &&
            resultW3.rows.first.assoc()['winner_alliance_id'] != null &&
            int.parse(
                  resultW3.rows.first.assoc()['winner_alliance_id'].toString(),
                ) >
                0;

        return hasL3Winner && hasW3Winner;
      }
    } else if (roundName == 'GF1') {
      final winnerFinalResult = await conn.execute(
        """
      SELECT winner_alliance_id FROM tbl_double_elimination 
      WHERE category_id = :catId AND bracket_side = 'winners'
      ORDER BY round_number DESC LIMIT 1
    """,
        {"catId": widget.categoryId},
      );

      final loserFinalResult = await conn.execute(
        """
      SELECT winner_alliance_id FROM tbl_double_elimination 
      WHERE category_id = :catId AND bracket_side = 'losers'
      ORDER BY round_number DESC LIMIT 1
    """,
        {"catId": widget.categoryId},
      );

      final hasWinnerFinal =
          winnerFinalResult.rows.isNotEmpty &&
          winnerFinalResult.rows.first.assoc()['winner_alliance_id'] != null &&
          int.parse(
                winnerFinalResult.rows.first
                    .assoc()['winner_alliance_id']
                    .toString(),
              ) >
              0;
      final hasLoserFinal =
          loserFinalResult.rows.isNotEmpty &&
          loserFinalResult.rows.first.assoc()['winner_alliance_id'] != null &&
          int.parse(
                loserFinalResult.rows.first
                    .assoc()['winner_alliance_id']
                    .toString(),
              ) >
              0;

      return hasWinnerFinal && hasLoserFinal;
    } else if (roundName == 'GF2') {
      final gf1Result = await conn.execute(
        """
      SELECT winner_alliance_id, alliance1_id, alliance2_id 
      FROM tbl_double_elimination 
      WHERE category_id = :catId AND round_name = 'GF1'
    """,
        {"catId": widget.categoryId},
      );

      if (gf1Result.rows.isEmpty) return false;

      final data = gf1Result.rows.first.assoc();
      final winnerId = data['winner_alliance_id'];

      if (winnerId == null || int.parse(winnerId.toString()) == 0) {
        return false;
      }

      final loserFinalResult = await conn.execute(
        """
      SELECT winner_alliance_id FROM tbl_double_elimination 
      WHERE category_id = :catId AND bracket_side = 'losers'
      ORDER BY round_number DESC LIMIT 1
    """,
        {"catId": widget.categoryId},
      );

      if (loserFinalResult.rows.isEmpty) return false;

      final loserFinalWinner = loserFinalResult.rows.first
          .assoc()['winner_alliance_id'];

      // GF2 is only playable if the loser's bracket champion won GF1
      return winnerId.toString() == loserFinalWinner?.toString();
    }

    return true;
  }

  Future<bool> _matchExists(MySQLConnection conn, String roundName) async {
    final result = await conn.execute(
      """
      SELECT COUNT(*) as cnt FROM tbl_double_elimination 
      WHERE category_id = :catId AND round_name = :matchName
    """,
      {"catId": widget.categoryId, "matchName": roundName},
    );

    if (result.rows.isNotEmpty) {
      return int.parse(result.rows.first.assoc()['cnt']?.toString() ?? '0') > 0;
    }
    return false;
  }

  Future<void> _showSettingsDialog() async {
    if (_settings == null) return;

    await showDialog<ChampionshipSettings>(
      context: context,
      builder: (context) => ChampionshipSettingsDialog(
        settings: _settings!,
        onSave: (updatedSettings) async {
          await DBHelper.saveChampionshipSettings(updatedSettings);
          setState(() => _settings = updatedSettings);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('✅ Settings saved for ${widget.categoryName}'),
                backgroundColor: Colors.green,
                duration: const Duration(seconds: 2),
              ),
            );
          }
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: Color(0xFFFFD700)),
            SizedBox(height: 16),
            Text('Loading bracket...', style: TextStyle(color: Colors.white54)),
          ],
        ),
      );
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, color: Colors.redAccent, size: 48),
            const SizedBox(height: 16),
            Text(
              'Error loading bracket',
              style: TextStyle(color: Colors.redAccent),
            ),
            const SizedBox(height: 8),
            Text(
              _error!,
              style: TextStyle(color: Colors.white38, fontSize: 12),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton(onPressed: _loadData, child: const Text('RETRY')),
          ],
        ),
      );
    }

    if (_matches.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFFFFD700).withOpacity(0.1),
                border: Border.all(
                  color: const Color(0xFFFFD700).withOpacity(0.3),
                  width: 2,
                ),
              ),
              child: const Icon(
                Icons.account_tree,
                size: 64,
                color: Color(0xFFFFD700),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'No Bracket Generated Yet',
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '${_alliances.length} alliances detected',
              style: TextStyle(
                color: Colors.white.withOpacity(0.5),
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ElevatedButton.icon(
                  onPressed: _isGenerating
                      ? null
                      : _generateDoubleEliminationBracket,
                  icon: _isGenerating
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.auto_awesome),
                  label: Text(
                    _isGenerating ? 'GENERATING...' : 'GENERATE BRACKET',
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFFD700),
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 12,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                IconButton(
                  icon: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: const Color(0xFFFFD700).withOpacity(0.1),
                      border: Border.all(
                        color: const Color(0xFFFFD700).withOpacity(0.3),
                      ),
                    ),
                    child: const Icon(
                      Icons.settings_rounded,
                      color: Color(0xFFFFD700),
                      size: 20,
                    ),
                  ),
                  onPressed: () => _showSettingsDialog(),
                  tooltip: 'Championship Settings',
                ),
              ],
            ),
          ],
        ),
      );
    }

    return _buildBracketLayout();
  }
}