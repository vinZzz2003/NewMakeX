import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'db_helper.dart';
import 'teams_players.dart';

enum StandingType {
  qualification,
  championship,
  battleOfChampions,
}

extension StandingTypeExt on StandingType {
  String get displayName {
    switch (this) {
      case StandingType.qualification:
        return 'QUALIFICATION ROUND';
      case StandingType.championship:
        return 'CHAMPIONSHIP ROUND';
      case StandingType.battleOfChampions:
        return 'BATTLE OF CHAMPIONS';
    }
  }

  Color get color {
    switch (this) {
      case StandingType.qualification:
        return const Color(0xFF00CFFF);
      case StandingType.championship:
        return const Color(0xFFFFD700);
      case StandingType.battleOfChampions:
        return const Color(0xFF00FF88);
    }
  }

  IconData get icon {
    switch (this) {
      case StandingType.qualification:
        return Icons.calendar_today_rounded;
      case StandingType.championship:
        return Icons.emoji_events_rounded;
      case StandingType.battleOfChampions:
        return Icons.military_tech_rounded;
    }
  }
}

// Score model for qualification rounds
class RoundScore {
  int individualScore;
  int allianceScore;
  int violation;
  String duration;
  
  RoundScore({
    this.individualScore = 0,
    this.allianceScore = 0,
    this.violation = 0,
    this.duration = '00:00',
  });
  
  int get totalScore => individualScore + allianceScore - violation;
  
  RoundScore copyWith({
    int? individualScore,
    int? allianceScore,
    int? violation,
    String? duration,
  }) {
    return RoundScore(
      individualScore: individualScore ?? this.individualScore,
      allianceScore: allianceScore ?? this.allianceScore,
      violation: violation ?? this.violation,
      duration: duration ?? this.duration,
    );
  }
}

// Best-of-3 Match Result Model
class BestOf3MatchResult {
  final int matchNumber;
  final int alliance1Score;
  final int alliance1Violation;
  final int alliance2Score;
  final int alliance2Violation;
  final int winnerAllianceId;
  final bool isCompleted;
  final int opponentAllianceId;
  final int matchRound;
  final int matchPosition;
  
  BestOf3MatchResult({
    required this.matchNumber,
    required this.alliance1Score,
    required this.alliance1Violation,
    required this.alliance2Score,
    required this.alliance2Violation,
    required this.winnerAllianceId,
    required this.isCompleted,
    this.opponentAllianceId = 0,
    this.matchRound = 0,
    this.matchPosition = 0,
  });
  
  int get alliance1Final => alliance1Score - alliance1Violation;
  int get alliance2Final => alliance2Score - alliance2Violation;
  
  Map<String, dynamic> toMap() {
    return {
      'match_number': matchNumber,
      // Use DB column names (alliance_score / opponent_score) as canonical
      'alliance_score': alliance1Score,
      'alliance_violation': alliance1Violation,
      'opponent_score': alliance2Score,
      'opponent_violation': alliance2Violation,
      'winner_alliance_id': winnerAllianceId,
      'is_completed': isCompleted ? 1 : 0,
      'opponent_alliance_id': opponentAllianceId,
      'match_round': matchRound,
      'match_position': matchPosition,
    };
  }
  
  factory BestOf3MatchResult.fromMap(Map<String, dynamic> map) {
    return BestOf3MatchResult(
      matchNumber: int.parse(map['match_number'].toString()),
      // Accept either naming convention (alliance1_* or alliance_*) to be resilient
      alliance1Score: int.parse((map['alliance1_score'] ?? map['alliance_score'])?.toString() ?? '0'),
      alliance1Violation: int.parse((map['alliance1_violation'] ?? map['alliance_violation'])?.toString() ?? '0'),
      alliance2Score: int.parse((map['alliance2_score'] ?? map['opponent_score'])?.toString() ?? '0'),
      alliance2Violation: int.parse((map['alliance2_violation'] ?? map['opponent_violation'])?.toString() ?? '0'),
      winnerAllianceId: int.parse(map['winner_alliance_id']?.toString() ?? '0'),
      isCompleted: (map['is_completed']?.toString() ?? '0') == '1',
      opponentAllianceId: int.parse(map['opponent_alliance_id']?.toString() ?? '0'),
      matchRound: int.parse(map['match_round']?.toString() ?? '0'),
      matchPosition: int.parse(map['match_position']?.toString() ?? '0'),
    );
  }
}

// Alliance Match Pair Model
class AllianceMatchPair {
  final int matchId;
  final int alliance1Id;
  final int alliance2Id;
  final int alliance1Rank;
  final int alliance2Rank;
  final String alliance1Name;
  final String alliance2Name;
  final int roundNumber;
  final int matchPosition;
  final String bracketSide;
  
  AllianceMatchPair({
    required this.matchId,
    required this.alliance1Id,
    required this.alliance2Id,
    required this.alliance1Rank,
    required this.alliance2Rank,
    required this.alliance1Name,
    required this.alliance2Name,
    required this.roundNumber,
    required this.matchPosition,
    required this.bracketSide,
  });
}

// Championship alliance standing model
class ChampionshipAllianceStanding {
  final int allianceId;
  final int allianceRank;
  final String captainName;
  final String partnerName;
  final Map<int, Map<String, int>> matchScores;
  int totalScore;
  
  ChampionshipAllianceStanding({
    required this.allianceId,
    required this.allianceRank,
    required this.captainName,
    required this.partnerName,
    required this.matchScores,
    required this.totalScore,
  });
  
  Map<String, int>? getMatchScore(int position) {
    return matchScores[position];
  }
  
  String get allianceName => 'Alliance #$allianceRank';
}

// Alliance standing for overview
class AllianceStanding {
  final int allianceId;
  final int allianceRank;
  final List<Map<String, dynamic>> teams;
  final int totalScore;
  final int wins;
  final int losses;
  final String status;
  
  AllianceStanding({
    required this.allianceId,
    required this.allianceRank,
    required this.teams,
    required this.totalScore,
    required this.wins,
    required this.losses,
    required this.status,
  });
}

// Champion standing for battle of champions
class ChampionStanding {
  final int allianceId;
  final int allianceRank;
  final List<Map<String, dynamic>> teams;
  final String title;
  final Color medalColor;
  
  ChampionStanding({
    required this.allianceId,
    required this.allianceRank,
    required this.teams,
    required this.title,
    required this.medalColor,
  });
}

class Standings extends StatefulWidget {
  final VoidCallback? onBack;

  const Standings({
    super.key,
    this.onBack,
  });

  @override
  State<Standings> createState() => _StandingsState();
}

class _StandingsState extends State<Standings> with TickerProviderStateMixin {
  TabController? _tabController;
  List<Map<String, dynamic>> _categories = [];
  Map<int, List<Map<String, dynamic>>> _standingsByCategory = {};

  // Store selected type per category
  final Map<int, StandingType> _selectedTypeByCategory = {};
  
  // Store data per category
  final Map<int, List<AllianceStanding>> _allianceStandingsByCategory = {};
  final Map<int, List<ChampionStanding>> _championStandingsByCategory = {};
  final Map<int, List<ChampionshipAllianceStanding>> _championshipStandingsByCategory = {};
  final Map<int, bool> _isLoadingAllianceByCategory = {};
  final Map<int, int> _championshipMatchesPerAlliance = {};
  // Championship pairings indexed by category -> matchId -> pairing
  final Map<int, Map<int, AllianceMatchPair>> _championshipPairingsByMatch = {};

  // Best-of-3 tracking
  final Map<int, Map<int, List<BestOf3MatchResult>>> _bestOf3Results = {};
  final Map<int, Map<int, int>> _allianceWins = {};
  final Map<int, Map<int, int>> _allianceMatchesPlayed = {};
  final Map<int, Map<int, AllianceMatchPair>> _allianceMatchPairings = {};

  bool _isLoading = true;
  bool _isInitializingScores = false;
  DateTime? _lastUpdated;
  Timer? _autoRefreshTimer;
  String _lastDataSignature = '';

  @override
  void initState() {
    super.initState();
    _loadData(initial: true);
    _autoRefreshTimer = Timer.periodic(
      const Duration(seconds: 10),
      (_) => _silentRefresh(),
    );
  }

  @override
  void dispose() {
    _autoRefreshTimer?.cancel();
    _tabController?.dispose();
    super.dispose();
  }

  String _buildSignature(List rows) {
    return rows.map((r) => r.toString()).join('|');
  }

  Future<void> _silentRefresh() async {
    try {
      final conn = await DBHelper.getConnection();
      final result = await conn.execute(
          "SELECT score_id, team_id, round_id, score_totalscore, score_individual, score_alliance, score_violation FROM tbl_score ORDER BY score_id");
      final rows = result.rows.map((r) => r.assoc()).toList();
      final signature = _buildSignature(rows);

      if (signature != _lastDataSignature) {
        _lastDataSignature = signature;
        await _loadData(initial: false);
      }
    } catch (_) {}
  }

  // Load match pairings for championship
  Future<void> _loadMatchPairings(int categoryId) async {
    try {
      final conn = await DBHelper.getConnection();

      // Try to prefer the double-elimination bracket table (category-specific if present)
      String? slug;
      try {
        final catRes = await conn.execute("SELECT category_type FROM tbl_category WHERE category_id = :catId LIMIT 1", {"catId": categoryId});
        if (catRes.rows.isNotEmpty) {
          slug = catRes.rows.first.assoc()['category_type']?.toString();
        }
      } catch (_) {}

      String doubleTable = 'tbl_double_elimination';
      if (slug != null && slug.trim().isNotEmpty) {
        var ctype = slug.replaceAll(RegExp(r"\(.*?\)"), '').toLowerCase();
        ctype = ctype.replaceAll(RegExp(r"[^a-z0-9]+"), '_').replaceAll(RegExp(r"_+"), '_').replaceAll(RegExp(r"^_+|_+$"), '').trim();
        if (ctype.isNotEmpty) {
          final candidate = 'tbl_${ctype}_double_elimination';
          try {
            await conn.execute('SELECT 1 FROM $candidate LIMIT 1');
            doubleTable = candidate;
          } catch (_) {}
        }
      }

      bool hasDouble = false;
      try {
        final chk = await conn.execute('SELECT COUNT(*) as cnt FROM $doubleTable WHERE category_id = :catId', {"catId": categoryId});
        if (chk.rows.isNotEmpty) {
          hasDouble = int.parse(chk.rows.first.assoc()['cnt']?.toString() ?? '0') > 0;
        }
      } catch (_) {}

      final Map<int, AllianceMatchPair> pairings = {};
      final Map<int, AllianceMatchPair> pairByMatch = {};

      if (hasDouble) {
        final result = await conn.execute("""
          SELECT 
            de.match_id,
            de.round_number,
            de.match_position,
            de.alliance1_id,
            de.alliance2_id,
            a1.selection_round as alliance1_rank,
            a2.selection_round as alliance2_rank,
            COALESCE(t1.team_name, 'Unknown') as captain1_name,
            COALESCE(t2.team_name, 'Unknown') as partner1_name,
            COALESCE(t3.team_name, 'Unknown') as captain2_name,
            COALESCE(t4.team_name, 'Unknown') as partner2_name
          FROM $doubleTable de
          LEFT JOIN tbl_alliance_selections a1 ON de.alliance1_id = a1.alliance_id
          LEFT JOIN tbl_alliance_selections a2 ON de.alliance2_id = a2.alliance_id
          LEFT JOIN tbl_team t1 ON a1.captain_team_id = t1.team_id
          LEFT JOIN tbl_team t2 ON a1.partner_team_id = t2.team_id
          LEFT JOIN tbl_team t3 ON a2.captain_team_id = t3.team_id
          LEFT JOIN tbl_team t4 ON a2.partner_team_id = t4.team_id
          WHERE de.category_id = :catId
          ORDER BY 
            CASE de.bracket_side WHEN 'winners' THEN 1 WHEN 'losers' THEN 2 WHEN 'grand' THEN 3 END,
            de.round_number, de.match_position
        """, {"catId": categoryId});

        for (final row in result.rows) {
          final data = row.assoc();
          final matchId = int.parse(data['match_id'].toString());
          final alliance1Id = int.parse(data['alliance1_id']?.toString() ?? '0');
          final alliance2Id = int.parse(data['alliance2_id']?.toString() ?? '0');

          if (alliance1Id > 0 && alliance2Id > 0) {
            final alliance1Rank = int.parse(data['alliance1_rank']?.toString() ?? '0');
            final alliance2Rank = int.parse(data['alliance2_rank']?.toString() ?? '0');
            final alliance1Name = '${data['captain1_name']} / ${data['partner1_name']}';
            final alliance2Name = '${data['captain2_name']} / ${data['partner2_name']}';
            final roundNumber = int.parse(data['round_number']?.toString() ?? '1');
            final matchPosition = int.parse(data['match_position']?.toString() ?? '1');

            final pair = AllianceMatchPair(
              matchId: matchId,
              alliance1Id: alliance1Id,
              alliance2Id: alliance2Id,
              alliance1Rank: alliance1Rank,
              alliance2Rank: alliance2Rank,
              alliance1Name: alliance1Name,
              alliance2Name: alliance2Name,
              roundNumber: roundNumber,
              matchPosition: matchPosition,
              bracketSide: data['bracket_side']?.toString() ?? 'winners',
            );

            pairings[alliance1Id] = pair;
            pairings[alliance2Id] = pair;
            pairByMatch[matchId] = pair;
          }
        }

        if (mounted) {
          setState(() {
            _allianceMatchPairings[categoryId] = pairings;
            _championshipPairingsByMatch[categoryId] = pairByMatch;
          });
        }

        print("✅ Loaded ${pairings.length ~/ 2} match pairings from double-elimination for category $categoryId (table: $doubleTable)");
        return;
      }

      // Fallback: use the category-specific or default championship schedule table
      try {
        String tableName = 'tbl_championship_schedule';
        if (slug != null && slug.trim().isNotEmpty) {
          var ctype = slug.replaceAll(RegExp(r"\(.*?\)"), '').toLowerCase();
          ctype = ctype.replaceAll(RegExp(r"[^a-z0-9]+"), '_').replaceAll(RegExp(r"_+"), '_').replaceAll(RegExp(r"^_+|_+$"), '').trim();
          if (ctype.isNotEmpty) {
            final candidate = 'tbl_${ctype}_championship_schedule';
            try {
              await conn.execute('SELECT 1 FROM $candidate LIMIT 1');
              tableName = candidate;
            } catch (_) {}
          }
        }

        final result = await conn.execute("""
          SELECT 
            cs.match_id,
            cs.match_round,
            cs.match_position,
            cs.alliance1_id,
            cs.alliance2_id,
            a1.selection_round as alliance1_rank,
            a2.selection_round as alliance2_rank,
            COALESCE(t1.team_name, 'Unknown') as captain1_name,
            COALESCE(t2.team_name, 'Unknown') as partner1_name,
            COALESCE(t3.team_name, 'Unknown') as captain2_name,
            COALESCE(t4.team_name, 'Unknown') as partner2_name
          FROM $tableName cs
          LEFT JOIN tbl_alliance_selections a1 ON cs.alliance1_id = a1.alliance_id
          LEFT JOIN tbl_alliance_selections a2 ON cs.alliance2_id = a2.alliance_id
          LEFT JOIN tbl_team t1 ON a1.captain_team_id = t1.team_id
          LEFT JOIN tbl_team t2 ON a1.partner_team_id = t2.team_id
          LEFT JOIN tbl_team t3 ON a2.captain_team_id = t3.team_id
          LEFT JOIN tbl_team t4 ON a2.partner_team_id = t4.team_id
          WHERE cs.category_id = :catId
          ORDER BY cs.match_round, cs.match_position
        """, {"catId": categoryId});

        for (final row in result.rows) {
          final data = row.assoc();
          final matchId = int.parse(data['match_id'].toString());
          final alliance1Id = int.parse(data['alliance1_id']?.toString() ?? '0');
          final alliance2Id = int.parse(data['alliance2_id']?.toString() ?? '0');
          
          if (alliance1Id > 0 && alliance2Id > 0) {
            final alliance1Rank = int.parse(data['alliance1_rank']?.toString() ?? '0');
            final alliance2Rank = int.parse(data['alliance2_rank']?.toString() ?? '0');
            final alliance1Name = '${data['captain1_name']} / ${data['partner1_name']}';
            final alliance2Name = '${data['captain2_name']} / ${data['partner2_name']}';
            final roundNumber = int.parse(data['match_round']?.toString() ?? '1');
            final matchPosition = int.parse(data['match_position']?.toString() ?? '1');
            
            final pair = AllianceMatchPair(
              matchId: matchId,
              alliance1Id: alliance1Id,
              alliance2Id: alliance2Id,
              alliance1Rank: alliance1Rank,
              alliance2Rank: alliance2Rank,
              alliance1Name: alliance1Name,
              alliance2Name: alliance2Name,
              roundNumber: roundNumber,
              matchPosition: matchPosition,
              bracketSide: data['bracket_side']?.toString() ?? 'winners',
            );

            pairings[alliance1Id] = pair;
            pairings[alliance2Id] = pair;
            pairByMatch[matchId] = pair;
          }
        }

        if (mounted) {
          setState(() {
            _allianceMatchPairings[categoryId] = pairings;
            _championshipPairingsByMatch[categoryId] = pairByMatch;
          });
        }

        print("✅ Loaded ${pairings.length ~/ 2} match pairings for category $categoryId (table: $tableName)");
      } catch (e) {
        print("❌ Error loading match pairings (fallback): $e");
      }

    } catch (e) {
      print("❌ Error loading match pairings: $e");
    }
  }

  AllianceMatchPair? _findPairingForAlliance(int categoryId, int allianceId) {
    final Map<int, AllianceMatchPair> pairings = _allianceMatchPairings[categoryId] ?? {};
    if (pairings.containsKey(allianceId)) return pairings[allianceId];
    final Map<int, AllianceMatchPair>? byMatch = _championshipPairingsByMatch[categoryId];
    if (byMatch != null) {
      for (final p in byMatch.values) {
        if (p.alliance1Id == allianceId || p.alliance2Id == allianceId) return p;
      }
    }
    return null;
  }

  // Load Best-of-3 results from database
  Future<void> _loadBestOf3Results(int categoryId) async {
    try {
      final conn = await DBHelper.getConnection();
      
      // Create table if it doesn't exist
      await DBHelper.executeDual("""
        CREATE TABLE IF NOT EXISTS tbl_championship_bestof3 (
          result_id INT AUTO_INCREMENT PRIMARY KEY,
          category_id INT NOT NULL,
          alliance_id INT NOT NULL,
          opponent_alliance_id INT NOT NULL,
          match_number INT NOT NULL,
          alliance_score INT NOT NULL DEFAULT 0,
          alliance_violation INT NOT NULL DEFAULT 0,
          opponent_score INT NOT NULL DEFAULT 0,
          opponent_violation INT NOT NULL DEFAULT 0,
          winner_alliance_id INT NOT NULL,
          is_completed BOOLEAN DEFAULT FALSE,
          match_round INT NOT NULL,
          match_position INT NOT NULL,
          created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
          FOREIGN KEY (category_id) REFERENCES tbl_category(category_id) ON DELETE CASCADE,
          FOREIGN KEY (alliance_id) REFERENCES tbl_alliance_selections(alliance_id) ON DELETE CASCADE,
          FOREIGN KEY (opponent_alliance_id) REFERENCES tbl_alliance_selections(alliance_id) ON DELETE CASCADE,
          UNIQUE KEY unique_match (category_id, alliance_id, opponent_alliance_id, match_number)
        )
      """
      );
      
      // Load existing results
      final result = await conn.execute("""
        SELECT * FROM tbl_championship_bestof3
        WHERE category_id = :catId
        ORDER BY match_round, match_position, match_number
      """, {"catId": categoryId});
      
      final Map<int, List<BestOf3MatchResult>> resultsByAlliance = {};
      final Map<int, int> winsByAlliance = {};
      final Map<int, int> playedByAlliance = {};
      
      for (final row in result.rows) {
        final data = row.assoc();
        final allianceId = int.parse(data['alliance_id'].toString());
          final resultObj = BestOf3MatchResult.fromMap(data);
        
        resultsByAlliance.putIfAbsent(allianceId, () => []).add(resultObj);
        
        if (resultObj.isCompleted && resultObj.winnerAllianceId == allianceId) {
          winsByAlliance[allianceId] = (winsByAlliance[allianceId] ?? 0) + 1;
        }
        playedByAlliance[allianceId] = (playedByAlliance[allianceId] ?? 0) + 1;
      }
      
      if (mounted) {
        setState(() {
          _bestOf3Results[categoryId] = resultsByAlliance;
          _allianceWins[categoryId] = winsByAlliance;
          _allianceMatchesPlayed[categoryId] = playedByAlliance;
        });
      }
      
      print("✅ Loaded Best-of-3 results for category $categoryId");
      
    } catch (e) {
      print("❌ Error loading Best-of-3 results: $e");
    }
  }

  // Save Best-of-3 match result
  Future<void> _saveBestOf3MatchResult({
    required int categoryId,
    required int allianceId,
    required int opponentAllianceId,
    required int matchNumber,
    required int allianceScore,
    required int allianceViolation,
    required int opponentScore,
    required int opponentViolation,
    required int roundNumber,
    required int matchPosition,
  }) async {
    try {
      // Prevent saving round 2 results until winners bracket round 1 (matches 1-3) are finished
      if (roundNumber == 2) {
        final prevFinished = await DBHelper.isRoundCompleted(categoryId, 'winners', 1, requiredPositions: [1,2,3]);
        if (!prevFinished) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Cannot save: Winners Bracket Round 1 matches 1-3 are not yet finished'),
              backgroundColor: Colors.orange,
              duration: Duration(seconds: 2),
            ),
          );
          return;
        }
      }
      final allianceFinal = allianceScore - allianceViolation;
      final opponentFinal = opponentScore - opponentViolation;
      final winnerId = allianceFinal > opponentFinal ? allianceId : opponentAllianceId;
      
      // Save the result for the first alliance
      await DBHelper.executeDual("""
        INSERT INTO tbl_championship_bestof3 
          (category_id, alliance_id, opponent_alliance_id, match_number, 
           alliance_score, alliance_violation, opponent_score, opponent_violation,
           winner_alliance_id, is_completed, match_round, match_position)
        VALUES
          (:catId, :allianceId, :opponentId, :matchNum,
           :allianceScore, :allianceViolation, :opponentScore, :opponentViolation,
           :winnerId, 1, :roundNum, :matchPos)
        ON DUPLICATE KEY UPDATE
          alliance_score = :allianceScore,
          alliance_violation = :allianceViolation,
          opponent_score = :opponentScore,
          opponent_violation = :opponentViolation,
          winner_alliance_id = :winnerId,
          is_completed = 1,
          match_round = :roundNum,
          match_position = :matchPos
      """, {
        "catId": categoryId,
        "allianceId": allianceId,
        "opponentId": opponentAllianceId,
        "matchNum": matchNumber,
        "allianceScore": allianceScore,
        "allianceViolation": allianceViolation,
        "opponentScore": opponentScore,
        "opponentViolation": opponentViolation,
        "winnerId": winnerId,
        "roundNum": roundNumber,
        "matchPos": matchPosition,
      });
      
      // Save mirrored result for the opponent
      await DBHelper.executeDual("""
        INSERT INTO tbl_championship_bestof3 
          (category_id, alliance_id, opponent_alliance_id, match_number, 
           alliance_score, alliance_violation, opponent_score, opponent_violation,
           winner_alliance_id, is_completed, match_round, match_position)
        VALUES
          (:catId, :opponentId, :allianceId, :matchNum,
           :opponentScore, :opponentViolation, :allianceScore, :allianceViolation,
           :winnerId, 1, :roundNum, :matchPos)
        ON DUPLICATE KEY UPDATE
          alliance_score = :opponentScore,
          alliance_violation = :opponentViolation,
          opponent_score = :allianceScore,
          opponent_violation = :allianceViolation,
          winner_alliance_id = :winnerId,
          is_completed = 1,
          match_round = :roundNum,
          match_position = :matchPos
      """, {
        "catId": categoryId,
        "opponentId": opponentAllianceId,
        "allianceId": allianceId,
        "matchNum": matchNumber,
        "opponentScore": opponentScore,
        "opponentViolation": opponentViolation,
        "allianceScore": allianceScore,
        "allianceViolation": allianceViolation,
        "winnerId": winnerId,
        "roundNum": roundNumber,
        "matchPos": matchPosition,
      });
      
      print("✅ Saved Best-of-3 match $matchNumber result for category $categoryId");
      
      // After saving the individual match result rows, only propagate the
      // series winner when the Best-of-3 series is decided (2 wins) or all
      // three matches have been completed. This prevents closing the series
      // after a single match.
      try {
        final conn = await DBHelper.getConnection();

        // Count wins and completed matches for this series (identified by
        // category, round and match position).
        final seriesRes = await conn.execute("""
          SELECT
            COUNT(DISTINCT CASE WHEN winner_alliance_id = :aId AND is_completed = 1 THEN match_number END) AS wins_a,
            COUNT(DISTINCT CASE WHEN winner_alliance_id = :oId AND is_completed = 1 THEN match_number END) AS wins_o,
            COUNT(DISTINCT CASE WHEN is_completed = 1 THEN match_number END) AS completed
          FROM tbl_championship_bestof3
          WHERE category_id = :catId AND match_round = :roundNum AND match_position = :matchPos
        """, {
          "aId": allianceId,
          "oId": opponentAllianceId,
          "catId": categoryId,
          "roundNum": roundNumber,
          "matchPos": matchPosition,
        });

        int winsA = 0;
        int winsO = 0;
        int completed = 0;
        if (seriesRes.rows.isNotEmpty) {
          final row = seriesRes.rows.first.assoc();
          winsA = int.tryParse(row['wins_a']?.toString() ?? '0') ?? 0;
          winsO = int.tryParse(row['wins_o']?.toString() ?? '0') ?? 0;
          completed = int.tryParse(row['completed']?.toString() ?? '0') ?? 0;
        }

        final bool seriesFinished = (winsA >= 2 || winsO >= 2 || completed >= 3);

        if (seriesFinished) {
          // determine series winner (if tie/draw leave as 0)
          int seriesWinner = 0;
          if (winsA > winsO) seriesWinner = allianceId;
          else if (winsO > winsA) seriesWinner = opponentAllianceId;

          // locate the double-elimination match id for this round/position
          final sel = await conn.execute("""
            SELECT match_id FROM tbl_double_elimination
            WHERE category_id = :catId AND round_number = :roundNum AND match_position = :matchPos
            LIMIT 1
          """, {"catId": categoryId, "roundNum": roundNumber, "matchPos": matchPosition});

          if (sel.rows.isNotEmpty) {
            final matchId = int.parse(sel.rows.first.assoc()['match_id']?.toString() ?? '0');
            if (matchId > 0 && seriesWinner > 0) {
              await DBHelper.updateBracketWinner(matchId, seriesWinner);
            }
          }
        }
      } catch (e) {
        print('ℹ️ Could not propagate winner to bracket: $e');
      }

      // Reload data
      await _loadBestOf3Results(categoryId);
      await _loadChampionshipStandings(categoryId);
      
    } catch (e) {
      print("❌ Error saving Best-of-3 result: $e");
      rethrow;
    }
  }

  // Show Best-of-3 match dialog
  void _showBestOf3MatchDialog({
    required int categoryId,
    required int allianceId,
    required int opponentAllianceId,
    required int matchNumber,
    required int roundNumber,
    required int matchPosition,
    required String bracketSide,
    required String allianceName,
    required String opponentName,
    required BestOf3MatchResult? existingResult,
    required VoidCallback onRefresh,
  }) {
    final allianceScoreController = TextEditingController(
      text: existingResult?.alliance1Score.toString() ?? '0',
    );
    final allianceViolationController = TextEditingController(
      text: existingResult?.alliance1Violation.toString() ?? '0',
    );
    final opponentScoreController = TextEditingController(
      text: existingResult?.alliance2Score.toString() ?? '0',
    );
    final opponentViolationController = TextEditingController(
      text: existingResult?.alliance2Violation.toString() ?? '0',
    );
    
    int getAllianceFinal() {
      final score = int.tryParse(allianceScoreController.text) ?? 0;
      final violation = int.tryParse(allianceViolationController.text) ?? 0;
      return score - violation;
    }
    
    int getOpponentFinal() {
      final score = int.tryParse(opponentScoreController.text) ?? 0;
      final violation = int.tryParse(opponentViolationController.text) ?? 0;
      return score - violation;
    }
    
    // mutable state for navigating to next match for this alliance
    int currentRound = roundNumber;
    int currentPos = matchPosition;
    int currentOpponentId = opponentAllianceId;
    String currentOpponent = opponentName;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final allianceFinal = getAllianceFinal();
          final opponentFinal = getOpponentFinal();
          final winnerName = allianceFinal > opponentFinal 
              ? allianceName 
              : (opponentFinal > allianceFinal ? opponentName : 'Draw');
          final isWinnerAlliance = allianceFinal > opponentFinal;
          
          // compute title from bracket side + round + series match number
          String bracketLabel = bracketSide.toLowerCase() == 'winners' ? "Winner's Bracket" : (bracketSide.toLowerCase() == 'losers' ? "Loser's Bracket" : "Grand Final");
          final titleText = '$bracketLabel Round $currentRound Match $matchNumber';

          return Dialog(
            backgroundColor: Colors.transparent,
            child: Container(
              width: 500,
              constraints: const BoxConstraints(maxHeight: 700),
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF2D0E7A), Color(0xFF1E0A5A)],
                ),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: const Color(0xFFFFD700).withOpacity(0.4),
                  width: 1.5,
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Header with bracket/round/match title and current opponent
                  Container(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Column(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFD700).withOpacity(0.15),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            titleText,
                            style: const TextStyle(
                              color: Color(0xFFFFD700),
                              fontWeight: FontWeight.bold,
                              fontSize: 18,
                              letterSpacing: 1.5,
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFF00CFFF).withOpacity(0.1),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0xFF00CFFF).withOpacity(0.3)),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Expanded(
                                child: Text(
                                  allianceName,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                  ),
                                  maxLines: 2,
                                ),
                              ),
                              const Padding(
                                padding: EdgeInsets.symmetric(horizontal: 12),
                                child: Text(
                                  'VS',
                                  style: TextStyle(
                                    color: Color(0xFFFFD700),
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                  ),
                                ),
                              ),
                              Expanded(
                                child: Text(
                                  currentOpponent,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                  ),
                                  maxLines: 2,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  
                  const SizedBox(height: 16),
                  
                  // Alliance #1 section
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: isWinnerAlliance 
                          ? Colors.green.withOpacity(0.1)
                          : Colors.white.withOpacity(0.05),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isWinnerAlliance 
                            ? Colors.green.withOpacity(0.5)
                            : Colors.white.withOpacity(0.1),
                      ),
                    ),
                    child: Column(
                      children: [
                        Text(
                          allianceName,
                          style: TextStyle(
                            color: isWinnerAlliance ? Colors.green : Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: _buildBestOf3ScoreField(
                                label: 'Alliance Score',
                                controller: allianceScoreController,
                                color: const Color(0xFFFFD700),
                                onChanged: (_) => setDialogState(() {}),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _buildBestOf3ScoreField(
                                label: 'Violation (-)',
                                controller: allianceViolationController,
                                color: Colors.redAccent,
                                onChanged: (_) => setDialogState(() {}),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            const Text('Final Score: ', style: TextStyle(color: Colors.white70)),
                            Text(
                              '$allianceFinal',
                              style: TextStyle(
                                color: isWinnerAlliance ? Colors.green : Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 18,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  
                  const SizedBox(height: 16),
                  
                  // Alliance #2 section
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: !isWinnerAlliance && opponentFinal > allianceFinal
                          ? Colors.green.withOpacity(0.1)
                          : Colors.white.withOpacity(0.05),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: !isWinnerAlliance && opponentFinal > allianceFinal
                            ? Colors.green.withOpacity(0.5)
                            : Colors.white.withOpacity(0.1),
                      ),
                    ),
                    child: Column(
                      children: [
                        Text(
                          opponentName,
                          style: TextStyle(
                            color: !isWinnerAlliance && opponentFinal > allianceFinal 
                                ? Colors.green 
                                : Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: _buildBestOf3ScoreField(
                                label: 'Alliance Score',
                                controller: opponentScoreController,
                                color: const Color(0xFFFFD700),
                                onChanged: (_) => setDialogState(() {}),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _buildBestOf3ScoreField(
                                label: 'Violation (-)',
                                controller: opponentViolationController,
                                color: Colors.redAccent,
                                onChanged: (_) => setDialogState(() {}),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            const Text('Final Score: ', style: TextStyle(color: Colors.white70)),
                            Text(
                              '$opponentFinal',
                              style: TextStyle(
                                color: !isWinnerAlliance && opponentFinal > allianceFinal 
                                    ? Colors.green 
                                    : Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 18,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  
                  const SizedBox(height: 16),
                  
                  // Winner display
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          const Color(0xFFFFD700).withOpacity(0.15),
                          const Color(0xFFFFD700).withOpacity(0.05),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFFFFD700).withOpacity(0.3)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.emoji_events, color: Color(0xFFFFD700), size: 20),
                        const SizedBox(width: 8),
                        Text(
                          '🏆 Winner: $winnerName',
                          style: const TextStyle(
                            color: Color(0xFFFFD700),
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                  
                  const SizedBox(height: 20),
                  
                  // Buttons
                  Row(
                    children: [
                      Expanded(
                        child: TextButton(
                          onPressed: () => Navigator.pop(ctx),
                          style: TextButton.styleFrom(
                            side: BorderSide(color: Colors.white.withOpacity(0.2)),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                          child: Text(
                            'CANCEL',
                            style: TextStyle(color: Colors.white.withOpacity(0.5)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      // Prev navigation: page this alliance to its previous match in the same bracket
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () async {
                            try {
                              final conn = await DBHelper.getConnection();
                              final prevRes = await conn.execute("""
                                SELECT match_id, match_position, round_number, alliance1_id, alliance2_id
                                FROM tbl_double_elimination
                                WHERE category_id = :catId
                                  AND bracket_side = :side
                                  AND round_number < :currRound
                                  AND (alliance1_id = :aid OR alliance2_id = :aid)
                                ORDER BY round_number DESC
                                LIMIT 1
                              """, {
                                "catId": categoryId,
                                "side": bracketSide,
                                "currRound": currentRound,
                                "aid": allianceId,
                              });

                              if (prevRes.rows.isEmpty) {
                                if (ctx.mounted) {
                                  ScaffoldMessenger.of(ctx).showSnackBar(
                                    const SnackBar(content: Text('No previous match found for this alliance'), backgroundColor: Colors.orange),
                                  );
                                }
                                return;
                              }

                              final pr = prevRes.rows.first.assoc();
                              final prRound = int.tryParse(pr['round_number']?.toString() ?? '0') ?? 0;
                              final prPos = int.tryParse(pr['match_position']?.toString() ?? '0') ?? 0;
                              final a1 = int.tryParse(pr['alliance1_id']?.toString() ?? '0') ?? 0;
                              final a2 = int.tryParse(pr['alliance2_id']?.toString() ?? '0') ?? 0;

                              final newOpponentId = (a1 == allianceId) ? a2 : a1;
                              if (newOpponentId == 0) {
                                if (ctx.mounted) {
                                  ScaffoldMessenger.of(ctx).showSnackBar(
                                    const SnackBar(content: Text('Previous match opponent not yet determined'), backgroundColor: Colors.orange),
                                  );
                                }
                                return;
                              }

                              final oppName = await _getAllianceDisplayName(categoryId, newOpponentId);

                              BestOf3MatchResult? prevResult;
                              try {
                                final all = _bestOf3Results[categoryId] ?? {};
                                final list = (all[allianceId] ?? []).where((r) => r.matchNumber == matchNumber && r.matchRound == prRound && r.matchPosition == prPos).toList();
                                if (list.isNotEmpty) prevResult = list.first;
                              } catch (_) {}

                              setDialogState(() {
                                currentRound = prRound;
                                currentPos = prPos;
                                currentOpponentId = newOpponentId;
                                currentOpponent = oppName;

                                allianceScoreController.text = prevResult?.alliance1Score.toString() ?? '0';
                                allianceViolationController.text = prevResult?.alliance1Violation.toString() ?? '0';
                                opponentScoreController.text = prevResult?.alliance2Score.toString() ?? '0';
                                opponentViolationController.text = prevResult?.alliance2Violation.toString() ?? '0';
                              });
                            } catch (e) {
                              if (ctx.mounted) {
                                ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text('Error loading previous match: $e')));
                              }
                            }
                          },
                          style: OutlinedButton.styleFrom(
                            side: BorderSide(color: Colors.white.withOpacity(0.12)),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                          child: const Text('PREV', style: TextStyle(color: Colors.white)),
                        ),
                      ),

                      // Next navigation: page this alliance to its next match in the same bracket
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () async {
                            try {
                              final conn = await DBHelper.getConnection();
                              final nextRes = await conn.execute("""
                                SELECT match_id, match_position, round_number, alliance1_id, alliance2_id
                                FROM tbl_double_elimination
                                WHERE category_id = :catId
                                  AND bracket_side = :side
                                  AND round_number > :currRound
                                  AND (alliance1_id = :aid OR alliance2_id = :aid)
                                ORDER BY round_number ASC
                                LIMIT 1
                              """, {
                                "catId": categoryId,
                                "side": bracketSide,
                                "currRound": currentRound,
                                "aid": allianceId,
                              });

                              if (nextRes.rows.isEmpty) {
                                if (ctx.mounted) {
                                  ScaffoldMessenger.of(ctx).showSnackBar(
                                    const SnackBar(content: Text('No next match found for this alliance'), backgroundColor: Colors.orange),
                                  );
                                }
                                return;
                              }

                              final nr = nextRes.rows.first.assoc();
                              final nrRound = int.tryParse(nr['round_number']?.toString() ?? '0') ?? 0;
                              final nrPos = int.tryParse(nr['match_position']?.toString() ?? '0') ?? 0;
                              final a1 = int.tryParse(nr['alliance1_id']?.toString() ?? '0') ?? 0;
                              final a2 = int.tryParse(nr['alliance2_id']?.toString() ?? '0') ?? 0;

                              final newOpponentId = (a1 == allianceId) ? a2 : a1;
                              if (newOpponentId == 0) {
                                if (ctx.mounted) {
                                  ScaffoldMessenger.of(ctx).showSnackBar(
                                    const SnackBar(content: Text('Next match opponent not yet determined'), backgroundColor: Colors.orange),
                                  );
                                }
                                return;
                              }

                              // load opponent display name
                              final oppName = await _getAllianceDisplayName(categoryId, newOpponentId);

                              // load existing Best-of-3 result for this alliance/matchNumber/round/position
                              BestOf3MatchResult? nextResult;
                              try {
                                final all = _bestOf3Results[categoryId] ?? {};
                                final list = (all[allianceId] ?? []).where((r) => r.matchNumber == matchNumber && r.matchRound == nrRound && r.matchPosition == nrPos).toList();
                                if (list.isNotEmpty) nextResult = list.first;
                              } catch (_) {}

                              // update mutable dialog state
                              setDialogState(() {
                                currentRound = nrRound;
                                currentPos = nrPos;
                                currentOpponentId = newOpponentId;
                                currentOpponent = oppName;

                                allianceScoreController.text = nextResult?.alliance1Score.toString() ?? '0';
                                allianceViolationController.text = nextResult?.alliance1Violation.toString() ?? '0';
                                opponentScoreController.text = nextResult?.alliance2Score.toString() ?? '0';
                                opponentViolationController.text = nextResult?.alliance2Violation.toString() ?? '0';
                              });
                            } catch (e) {
                              if (ctx.mounted) {
                                ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text('Error loading next match: $e')));
                              }
                            }
                          },
                          style: OutlinedButton.styleFrom(
                            side: BorderSide(color: Colors.white.withOpacity(0.12)),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                          child: const Text('NEXT', style: TextStyle(color: Colors.white)),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () async {
                            try {
                              await _saveBestOf3MatchResult(
                                categoryId: categoryId,
                                allianceId: allianceId,
                                opponentAllianceId: opponentAllianceId,
                                matchNumber: matchNumber,
                                allianceScore: int.tryParse(allianceScoreController.text) ?? 0,
                                allianceViolation: int.tryParse(allianceViolationController.text) ?? 0,
                                opponentScore: int.tryParse(opponentScoreController.text) ?? 0,
                                opponentViolation: int.tryParse(opponentViolationController.text) ?? 0,
                                roundNumber: roundNumber,
                                matchPosition: matchPosition,
                              );
                              if (ctx.mounted) Navigator.pop(ctx);
                              onRefresh();
                            } catch (e) {
                              if (ctx.mounted) {
                                ScaffoldMessenger.of(ctx).showSnackBar(
                                  SnackBar(
                                    content: Text('❌ Error saving: $e'),
                                    backgroundColor: Colors.red,
                                  ),
                                );
                              }
                            }
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFFFD700),
                            foregroundColor: Colors.black,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                          child: const Text('SAVE RESULT', style: TextStyle(fontWeight: FontWeight.bold)),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildBestOf3ScoreField({
    required String label,
    required TextEditingController controller,
    required Color color,
    required Function(String) onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 4),
        TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          style: TextStyle(color: color, fontSize: 14, fontWeight: FontWeight.bold),
          onChanged: onChanged,
          decoration: InputDecoration(
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(6),
              borderSide: BorderSide(color: color.withOpacity(0.3)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(6),
              borderSide: BorderSide(color: color.withOpacity(0.3)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(6),
              borderSide: BorderSide(color: color, width: 2),
            ),
          ),
        ),
      ],
    );
  }

  Future<String> _getAllianceDisplayName(int categoryId, int allianceId) async {
    try {
      final conn = await DBHelper.getConnection();
      final res = await conn.execute("""
        SELECT COALESCE(t1.team_name, 'Unknown') as captain_name, COALESCE(t2.team_name, 'Unknown') as partner_name
        FROM tbl_alliance_selections a
        LEFT JOIN tbl_team t1 ON a.captain_team_id = t1.team_id
        LEFT JOIN tbl_team t2 ON a.partner_team_id = t2.team_id
        WHERE a.alliance_id = :aid
        LIMIT 1
      """, {"aid": allianceId});
      if (res.rows.isNotEmpty) {
        final d = res.rows.first.assoc();
        return '${d['captain_name']} / ${d['partner_name']}';
      }
    } catch (e) {}
    return 'Alliance $allianceId';
  }

  void _showMatchSeriesDialog(int categoryId, int allianceId, int matchNumber, VoidCallback onRefresh) async {
    final allResults = _bestOf3Results[categoryId] ?? {};
    final List<BestOf3MatchResult> entries = (allResults[allianceId] ?? []).where((r) => r.matchNumber == matchNumber).toList();

    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          width: 600,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF1A0A4A),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFFFD700).withOpacity(0.3)),
          ),
          child: StatefulBuilder(
            builder: (ctx, setState) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Match $matchNumber — Series for Alliance #$allianceId', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  if (entries.isEmpty) ...[
                    const Text('No recorded matches for this slot yet.', style: TextStyle(color: Colors.white54)),
                    const SizedBox(height: 12),
                  ],
                  ...entries.map((e) => FutureBuilder<String>(
                    future: _getAllianceDisplayName(categoryId, e.opponentAllianceId),
                    builder: (context, snap) {
                      final oppName = snap.hasData ? snap.data! : (e.opponentAllianceId > 0 ? 'Alliance ${e.opponentAllianceId}' : 'TBD');
                      final winner = e.isCompleted ? (e.winnerAllianceId == allianceId ? 'WIN' : 'LOSE') : 'PENDING';
                      return Container(
                        margin: const EdgeInsets.symmetric(vertical: 6),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: e.isCompleted ? (e.winnerAllianceId == allianceId ? Colors.green.withOpacity(0.12) : Colors.red.withOpacity(0.08)) : Colors.white.withOpacity(0.02),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.white10),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(oppName, style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.bold)),
                                  const SizedBox(height: 6),
                                  Text('Status: $winner', style: const TextStyle(color: Colors.white54)),
                                  if (e.isCompleted) ...[
                                    const SizedBox(height: 6),
                                    Text('Final: ${e.alliance1Final} — ${e.alliance2Final}', style: const TextStyle(color: Colors.white70)),
                                  ],
                                ],
                              ),
                            ),
                            TextButton(
                              onPressed: () {
                                Navigator.pop(ctx);
                                // open the editor for this specific match instance
                                _showBestOf3MatchDialog(
                                  categoryId: categoryId,
                                  allianceId: allianceId,
                                  opponentAllianceId: e.opponentAllianceId,
                                  matchNumber: e.matchNumber,
                                  roundNumber: e.matchRound,
                                  matchPosition: e.matchPosition,
                                  allianceName: '',
                                  opponentName: '',
                                  bracketSide: 'winners',
                                  existingResult: e.isCompleted ? e : null,
                                  onRefresh: () async { await _loadBestOf3Results(categoryId); await _loadChampionshipStandings(categoryId); onRefresh(); },
                                );
                              },
                              child: const Text('Edit', style: TextStyle(color: Color(0xFFFFD700))),
                            ),
                          ],
                        ),
                      );
                    },
                  )),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('CLOSE', style: TextStyle(color: Colors.white54))),
                    ],
                  )
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  // Load championship standings with win-based scoring
  Future<void> _loadChampionshipStandings(int categoryId) async {
    if (mounted) {
      setState(() {
        _isLoadingAllianceByCategory[categoryId] = true;
      });
    }
    
    try {
      // First load match pairings and results
      await _loadMatchPairings(categoryId);
      await _loadBestOf3Results(categoryId);
      
      final conn = await DBHelper.getConnection();
      
      // Get all alliances
      final alliancesResult = await conn.execute("""
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
      """, {"catId": categoryId});
      
      final alliances = alliancesResult.rows.map((r) => r.assoc()).toList();
      
      if (alliances.isEmpty) {
        if (mounted) {
          setState(() {
            _championshipStandingsByCategory[categoryId] = [];
            _isLoadingAllianceByCategory[categoryId] = false;
          });
        }
        return;
      }
      
      // Create standings with win-based scores
      final List<ChampionshipAllianceStanding> standings = [];
      
      for (final alliance in alliances) {
        final allianceId = int.parse(alliance['alliance_id'].toString());
        final allianceRank = int.parse(alliance['alliance_rank'].toString());
        
        // Get wins from Best-of-3 results
        final wins = _allianceWins[categoryId]?[allianceId] ?? 0;
        
        standings.add(ChampionshipAllianceStanding(
          allianceId: allianceId,
          allianceRank: allianceRank,
          captainName: alliance['captain_name'].toString(),
          partnerName: alliance['partner_name'].toString(),
          matchScores: {},
          totalScore: wins, // 1 point per win
        ));
      }
      
      // Sort by totalScore descending, then alliance rank
      standings.sort((a, b) {
        if (a.totalScore != b.totalScore) {
          return b.totalScore.compareTo(a.totalScore);
        }
        return a.allianceRank.compareTo(b.allianceRank);
      });
      
      if (mounted) {
        setState(() {
          _championshipStandingsByCategory[categoryId] = standings;
          _isLoadingAllianceByCategory[categoryId] = false;
        });
      }
      
    } catch (e) {
      print("Error loading championship standings: $e");
      if (mounted) {
        setState(() {
          _championshipStandingsByCategory[categoryId] = [];
          _isLoadingAllianceByCategory[categoryId] = false;
        });
      }
    }
  }

  // Build Best-of-3 match cell
  Widget _buildBestOf3MatchCell({
    required int categoryId,
    required int allianceId,
    required int opponentId,
    required int matchNumber,
    required int roundNumber,
    required int matchPosition,
    required String allianceName,
    required String opponentName,
    required String bracketSide,
    required BestOf3MatchResult? result,
    required VoidCallback onRefresh,
  }) {
    final isWinner = result != null && result.isCompleted && result.winnerAllianceId == allianceId;
    final isLoser = result != null && result.isCompleted && result.winnerAllianceId == opponentId && result.winnerAllianceId != 0;
    final isPending = result == null || !result.isCompleted;

    // Compute aggregated wins/losses for this alliance for the given `matchNumber`
    final allResults = _bestOf3Results[categoryId] ?? {};
    final allianceEntries = (allResults[allianceId] ?? []).where((r) => r.matchNumber == matchNumber && r.isCompleted).toList();
    final opponentEntries = (allResults[opponentId] ?? []).where((r) => r.matchNumber == matchNumber && r.isCompleted).toList();
    final int winsCount = allianceEntries.where((r) => r.winnerAllianceId == allianceId).length;
    final int losesCount = allianceEntries.where((r) => r.winnerAllianceId == opponentId).length;
    
    // If this is Winners Bracket Round 2, gate visibility/interaction until
    // Winners Bracket Round 1 matches 1-3 are completed.
    if (roundNumber == 2 && bracketSide == 'winners') {
      return Expanded(
        flex: 2,
        child: FutureBuilder<bool>(
          future: DBHelper.isRoundCompleted(categoryId, 'winners', 1, requiredPositions: [1,2,3]),
          builder: (context, snap) {
            final ready = snap.hasData && snap.data == true;
            if (!ready) {
              return Container(
                margin: const EdgeInsets.symmetric(horizontal: 4),
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.white12, width: 1),
                ),
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: const [
                      Icon(Icons.lock, color: Colors.orange, size: 18),
                      SizedBox(height: 6),
                      Text('Locked until Round 1 complete', style: TextStyle(color: Colors.white54, fontSize: 12)),
                    ],
                  ),
                ),
              );
            }
            // If ready, fall through to the normal interactive cell below
            return GestureDetector(
              onTap: () async {
                if (opponentId == 0) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Opponent not yet determined'),
                      backgroundColor: Colors.orange,
                      duration: Duration(seconds: 1),
                    ),
                  );
                  return;
                }
                _showBestOf3MatchDialog(
                  categoryId: categoryId,
                  allianceId: allianceId,
                  opponentAllianceId: opponentId,
                  matchNumber: matchNumber,
                  roundNumber: roundNumber,
                  matchPosition: matchPosition,
                  allianceName: allianceName,
                  opponentName: opponentName,
                  bracketSide: bracketSide,
                  existingResult: result != null && result.isCompleted ? result : null,
                  onRefresh: onRefresh,
                );
              },
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 4),
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                decoration: BoxDecoration(
                  color: isWinner
                      ? Colors.green.withOpacity(0.15)
                      : isLoser
                          ? Colors.red.withOpacity(0.1)
                          : Colors.white.withOpacity(0.03),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: isWinner
                        ? Colors.green
                        : isLoser
                            ? Colors.red
                            : Colors.white.withOpacity(0.15),
                    width: isWinner || isLoser ? 1.5 : 1,
                  ),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (result != null && result.isCompleted) ...[
                    // Show aggregated wins/losses for this alliance for the match number
                    Text(
                      '${winsCount} win${winsCount == 1 ? '' : 's'} - ${losesCount} lose${losesCount == 1 ? '' : 's'}',
                      style: TextStyle(
                        color: winsCount > losesCount ? Colors.greenAccent : Colors.white70,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                  ] else ...[
                    const Icon(Icons.videogame_asset, color: Colors.white24, size: 18),
                    const SizedBox(height: 6),
                    const Text('PENDING', style: TextStyle(color: Colors.white24, fontSize: 12)),
                  ],
                ],
              ),
            ),
            );
          },
        ),
      );
    }
    
    // Original interactive cell for rounds other than the gated Winners Round 2
    return Expanded(
      flex: 2,
      child: GestureDetector(
        onTap: () async {
          if (opponentId == 0) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Opponent not yet determined'),
                backgroundColor: Colors.orange,
                duration: Duration(seconds: 1),
              ),
            );
            return;
          }

          // Block opening round 2 scoring until Winners Bracket Round 1 matches 1-3 are complete
          if (roundNumber == 2 && bracketSide == 'winners') {
            final prevFinished = await DBHelper.isRoundCompleted(categoryId, 'winners', 1, requiredPositions: [1,2,3]);
            if (!prevFinished) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Cannot add score: Winners Bracket Round 1 matches are not finished'),
                  backgroundColor: Colors.orange,
                  duration: Duration(seconds: 2),
                ),
              );
              return;
            }
          }

          _showBestOf3MatchDialog(
            categoryId: categoryId,
            allianceId: allianceId,
            opponentAllianceId: opponentId,
            matchNumber: matchNumber,
            roundNumber: roundNumber,
            matchPosition: matchPosition,
            allianceName: allianceName,
            opponentName: opponentName,
            bracketSide: bracketSide,
            existingResult: result != null && result.isCompleted ? result : null,
            onRefresh: onRefresh,
          );
        },
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 4),
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
          decoration: BoxDecoration(
            color: isWinner
                ? Colors.green.withOpacity(0.15)
                : isLoser
                    ? Colors.red.withOpacity(0.1)
                    : Colors.white.withOpacity(0.03),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isWinner
                  ? Colors.green
                  : isLoser
                      ? Colors.red
                      : Colors.white.withOpacity(0.15),
              width: isWinner || isLoser ? 1.5 : 1,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (result != null && result.isCompleted) ...[
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      '${result.winnerAllianceId == allianceId ? 1 : 0}',
                      style: TextStyle(
                        color: isWinner ? Colors.green : Colors.white70,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    const Text(
                      ' - ',
                      style: TextStyle(color: Colors.white38, fontSize: 12),
                    ),
                    Text(
                      '${result.winnerAllianceId == opponentId ? 1 : 0}',
                      style: TextStyle(
                        color: isLoser ? Colors.red : Colors.white70,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: isWinner 
                        ? Colors.green.withOpacity(0.2)
                        : Colors.red.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    isWinner ? 'WIN' : 'LOSE',
                    style: TextStyle(
                      color: isWinner ? Colors.green : Colors.red,
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ] else ...[
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFD700).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Icon(
                    Icons.sports_esports_rounded,
                    color: Color(0xFFFFD700),
                    size: 16,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'PENDING',
                  style: TextStyle(
                    color: Colors.white38,
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  // Build championship table with Best-of-3 for Explorer categories
  Widget _buildChampionshipTable(int categoryId) {
    bool isLoading = _isLoadingAllianceByCategory[categoryId] ?? false;
    List<ChampionshipAllianceStanding> standings = _championshipStandingsByCategory[categoryId] ?? [];
    Map<int, List<BestOf3MatchResult>> results = _bestOf3Results[categoryId] ?? {};
    Map<int, int> wins = _allianceWins[categoryId] ?? {};
    Map<int, int> played = _allianceMatchesPlayed[categoryId] ?? {};
    Map<int, AllianceMatchPair> pairings = _allianceMatchPairings[categoryId] ?? {};

    // If pairings are missing, attempt to load them and show a loader until available
    if (pairings.isEmpty) {
      // kick off async load (will setState when done)
      _loadMatchPairings(categoryId);
      return const Expanded(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(color: Color(0xFFFFD700)),
              SizedBox(height: 12),
              Text('Loading championship schedule...', style: TextStyle(color: Colors.white54)),
            ],
          ),
        ),
      );
    }

    if (isLoading) {
      return const Expanded(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(color: Color(0xFFFFD700)),
              SizedBox(height: 16),
              Text('Loading championship standings...',
                  style: TextStyle(color: Colors.white54, fontSize: 14)),
            ],
          ),
        ),
      );
    }
    
    if (standings.isEmpty) {
      return Expanded(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.emoji_events, size: 64, color: Colors.white.withOpacity(0.2)),
              const SizedBox(height: 16),
              const Text('No Championship Data Yet',
                  style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              Text('Generate championship schedule first',
                  style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 14)),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: () {
                  _loadMatchPairings(categoryId);
                  _loadBestOf3Results(categoryId);
                },
                icon: const Icon(Icons.refresh, size: 16),
                label: const Text('Load Match Data'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFFD700),
                  foregroundColor: Colors.black,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Expanded(
      child: Column(
        children: [
          // Main header
          Container(
            color: const Color(0xFF5C2ECC),
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
            child: Row(
              children: [
                _headerCell('RANK', flex: 1),
                _headerCell('ALLIANCE', flex: 1),
                _headerCell('TEAMS', flex: 4),
                _headerCell('MATCH 1', flex: 2, center: true),
                _headerCell('MATCH 2', flex: 2, center: true),
                _headerCell('MATCH 3', flex: 2, center: true),
                _headerCell('MAX SCORE', flex: 2, center: true),
              ],
            ),
          ),
          
          // Rows
          Expanded(
            child: ListView.builder(
              itemCount: standings.length,
              itemBuilder: (context, index) {
                final standing = standings[index];
                final isEven = index % 2 == 0;
                final allianceResults = results[standing.allianceId] ?? [];
                final allianceWins = wins[standing.allianceId] ?? 0;
                final alliancePlayed = played[standing.allianceId] ?? 0;
                final opponentPair = _findPairingForAlliance(categoryId, standing.allianceId);

                final opponentId = opponentPair != null
                    ? (opponentPair.alliance1Id == standing.allianceId
                        ? opponentPair.alliance2Id
                        : opponentPair.alliance1Id)
                    : 0;

                final opponentName = opponentPair != null
                    ? (opponentPair.alliance1Id == standing.allianceId
                        ? opponentPair.alliance2Name
                        : opponentPair.alliance1Name)
                    : 'TBD';

                final opponentWins = wins[opponentId] ?? 0;
                final needMatch3 = (allianceWins == 1 && opponentWins == 1);
                final List<BestOf3MatchResult> _match3List = allianceResults.where((r) => r.matchNumber == 3).toList();
                final BestOf3MatchResult? match3Result = _match3List.isNotEmpty ? _match3List.first : null;

                return Container(
                  color: isEven ? const Color(0xFF1E0E5A) : const Color(0xFF160A42),
                  padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                  child: Row(
                    children: [
                      Expanded(
                        flex: 1,
                        child: Text(
                          '#${standing.allianceRank}',
                          style: const TextStyle(
                            color: Color(0xFFFFD700),
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                      ),

                      Expanded(
                        flex: 1,
                        child: Text(
                          'Alliance #${standing.allianceId}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                      ),

                      Expanded(
                        flex: 4,
                        child: Padding(
                          padding: const EdgeInsets.only(right: 12),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  const Color(0xFFFFD700).withOpacity(0.15),
                                  const Color(0xFF00CFFF).withOpacity(0.1),
                                ],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: const Color(0xFFFFD700).withOpacity(0.3),
                                width: 1.5,
                              ),
                            ),
                            child: Center(
                              child: Text(
                                '${standing.captainName.toUpperCase()} / ${standing.partnerName.toUpperCase()}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                                textAlign: TextAlign.center,
                                overflow: TextOverflow.ellipsis,
                                maxLines: 2,
                              ),
                            ),
                          ),
                        ),
                      ),

                      // Match 1
                      _buildBestOf3MatchCell(
                        categoryId: categoryId,
                        allianceId: standing.allianceId,
                        opponentId: opponentId,
                        matchNumber: 1,
                        roundNumber: opponentPair?.roundNumber ?? 1,
                        matchPosition: opponentPair?.matchPosition ?? 1,
                        allianceName: '${standing.captainName} / ${standing.partnerName}',
                        opponentName: opponentName,
                        bracketSide: opponentPair?.bracketSide ?? 'winners',
                        result: allianceResults.firstWhere(
                          (r) => r.matchNumber == 1,
                          orElse: () => BestOf3MatchResult(
                            matchNumber: 1,
                            alliance1Score: 0,
                            alliance1Violation: 0,
                            alliance2Score: 0,
                            alliance2Violation: 0,
                            winnerAllianceId: 0,
                            isCompleted: false,
                            opponentAllianceId: 0,
                            matchRound: 0,
                            matchPosition: 0,
                          ),
                        ),
                        onRefresh: () {
                          _loadBestOf3Results(categoryId);
                          _loadChampionshipStandings(categoryId);
                        },
                      ),

                      // Match 2
                      _buildBestOf3MatchCell(
                        categoryId: categoryId,
                        allianceId: standing.allianceId,
                        opponentId: opponentId,
                        matchNumber: 2,
                        roundNumber: opponentPair?.roundNumber ?? 1,
                        matchPosition: opponentPair?.matchPosition ?? 1,
                        allianceName: '${standing.captainName} / ${standing.partnerName}',
                        opponentName: opponentName,
                        bracketSide: opponentPair?.bracketSide ?? 'winners',
                        result: allianceResults.firstWhere(
                          (r) => r.matchNumber == 2,
                          orElse: () => BestOf3MatchResult(
                            matchNumber: 2,
                            alliance1Score: 0,
                            alliance1Violation: 0,
                            alliance2Score: 0,
                            alliance2Violation: 0,
                            winnerAllianceId: 0,
                            isCompleted: false,
                            opponentAllianceId: 0,
                            matchRound: 0,
                            matchPosition: 0,
                          ),
                        ),
                        onRefresh: () {
                          _loadBestOf3Results(categoryId);
                          _loadChampionshipStandings(categoryId);
                        },
                      ),

                      // Match 3 (always rendered as a Best-of-3 cell so it's clickable and styled like Match 1/2)
                      _buildBestOf3MatchCell(
                        categoryId: categoryId,
                        allianceId: standing.allianceId,
                        opponentId: opponentId,
                        matchNumber: 3,
                        roundNumber: opponentPair?.roundNumber ?? 1,
                        matchPosition: opponentPair?.matchPosition ?? 1,
                        allianceName: '${standing.captainName} / ${standing.partnerName}',
                        opponentName: opponentName,
                        bracketSide: opponentPair?.bracketSide ?? 'winners',
                        result: match3Result,
                        onRefresh: () {
                          _loadBestOf3Results(categoryId);
                          _loadChampionshipStandings(categoryId);
                        },
                      ),

                      // Max Score
                      Expanded(
                        flex: 2,
                        child: Center(
                          child: Column(
                            children: [
                              Text(
                                '${allianceWins * 10}',
                                style: const TextStyle(
                                  color: Color(0xFFFFD700),
                                  fontWeight: FontWeight.bold,
                                  fontSize: 18,
                                ),
                              ),
                              Text(
                                'pts',
                                style: TextStyle(
                                  color: Colors.white38,
                                  fontSize: 9,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // Original championship table for non-Explorer categories
  Widget _buildOriginalChampionshipTable(int categoryId) {
    bool isLoading = _isLoadingAllianceByCategory[categoryId] ?? false;
    List<ChampionshipAllianceStanding> standings = _championshipStandingsByCategory[categoryId] ?? [];
    int matchesPerAlliance = _championshipMatchesPerAlliance[categoryId] ?? 1;

    if (isLoading) {
      return const Expanded(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(color: Color(0xFFFFD700)),
              SizedBox(height: 16),
              Text('Loading championship standings...',
                  style: TextStyle(color: Colors.white54, fontSize: 14)),
            ],
          ),
        ),
      );
    }
    
    if (standings.isEmpty) {
      return Expanded(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.emoji_events, size: 64, color: Colors.white.withOpacity(0.2)),
              const SizedBox(height: 16),
              const Text('No Championship Data Yet',
                  style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              Text('Generate championship schedule first',
                  style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 14)),
            ],
          ),
        ),
      );
    }

    return Expanded(
      child: Column(
        children: [
          // Main header
          Container(
            color: const Color(0xFF5C2ECC),
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
            child: Row(
              children: [
                _headerCell('RANK', flex: 1),
                _headerCell('ALLIANCE', flex: 1),
                _headerCell('TEAMS', flex: 4),
                ...List.generate(matchesPerAlliance, (i) => 
                  Expanded(
                    flex: 3,
                    child: Center(
                      child: Text(
                        'MATCH ${i + 1}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ),
                ),
                _headerCell('MAX SCORE', flex: 2, center: true),
              ],
            ),
          ),
          
          // Sub-header with ALL and VIO
          Container(
            color: const Color(0xFF4A1A9C),
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
            child: Row(
              children: [
                const Expanded(flex: 1, child: SizedBox()),
                const Expanded(flex: 1, child: SizedBox()),
                const Expanded(flex: 4, child: SizedBox()),
                ...List.generate(matchesPerAlliance, (i) => 
                  Expanded(
                    flex: 3,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        Expanded(
                          child: Center(
                            child: Text('ALL',
                                style: TextStyle(
                                    color: const Color(0xFFFFD700).withOpacity(0.9),
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold)),
                          ),
                        ),
                        Expanded(
                          child: Center(
                            child: Text('VIO',
                                style: TextStyle(
                                    color: Colors.redAccent.withOpacity(0.9),
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold)),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const Expanded(flex: 2, child: SizedBox()),
              ],
            ),
          ),

          // Rows
          Expanded(
            child: ListView.builder(
              itemCount: standings.length,
              itemBuilder: (context, index) {
                final standing = standings[index];
                final isEven = index % 2 == 0;

                return Container(
                  color: isEven ? const Color(0xFF1E0E5A) : const Color(0xFF160A42),
                  padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                  child: Row(
                    children: [
                      Expanded(
                        flex: 1,
                        child: Text(
                          '${index + 1}',
                          style: TextStyle(
                            color: _rankColor(index + 1),
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                      ),
                      Expanded(
                        flex: 1,
                        child: Text(
                          '#${standing.allianceRank}',
                          style: const TextStyle(
                            color: Color(0xFFFFD700),
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                      ),
                      Expanded(
                        flex: 4,
                        child: Padding(
                          padding: const EdgeInsets.only(right: 12),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  const Color(0xFFFFD700).withOpacity(0.15),
                                  const Color(0xFF00CFFF).withOpacity(0.1),
                                ],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: const Color(0xFFFFD700).withOpacity(0.3),
                                width: 1.5,
                              ),
                            ),
                            child: Center(
                              child: Text(
                                '${standing.captainName.toUpperCase()} / ${standing.partnerName.toUpperCase()}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                                textAlign: TextAlign.center,
                                overflow: TextOverflow.ellipsis,
                                maxLines: 2,
                              ),
                            ),
                          ),
                        ),
                      ),
                      ...List.generate(matchesPerAlliance, (i) {
                        final matchScore = standing.getMatchScore(i + 1);
                        final hasScore = matchScore != null;
                        
                        return Expanded(
                          flex: 3,
                          child: Container(
                            margin: const EdgeInsets.symmetric(horizontal: 2),
                            decoration: BoxDecoration(
                              border: Border.all(
                                color: hasScore 
                                    ? const Color(0xFFFFD700).withOpacity(0.3)
                                    : Colors.white.withOpacity(0.1),
                                width: 1,
                              ),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                              children: [
                                Expanded(
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(vertical: 8),
                                    child: Center(
                                      child: Text(
                                        hasScore ? '${matchScore!['score']}' : '—',
                                        style: TextStyle(
                                          color: hasScore
                                              ? const Color(0xFFFFD700)
                                              : Colors.white24,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 14,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                Expanded(
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(vertical: 8),
                                    child: Center(
                                      child: Text(
                                        hasScore ? '${matchScore!['violation']}' : '—',
                                        style: TextStyle(
                                          color: hasScore
                                              ? Colors.redAccent
                                              : Colors.white24,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 14,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }),
                      Expanded(
                        flex: 2,
                        child: Center(
                          child: Column(
                            children: [
                              Text(
                                '${standing.totalScore}',
                                style: const TextStyle(
                                  color: Color(0xFFFFD700),
                                  fontWeight: FontWeight.bold,
                                  fontSize: 18,
                                ),
                              ),
                              const Text(
                                'MAX',
                                style: TextStyle(
                                  color: Colors.white38,
                                  fontSize: 9,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _loadAllianceStandings(int categoryId) async {
    setState(() {
      _isLoadingAllianceByCategory[categoryId] = true;
    });
    
    try {
      final conn = await DBHelper.getConnection();
      
      try {
        await conn.execute("SELECT 1 FROM tbl_alliance_selections LIMIT 1");
      } catch (e) {
        setState(() {
          _allianceStandingsByCategory[categoryId] = [];
          _isLoadingAllianceByCategory[categoryId] = false;
        });
        return;
      }
      
      final alliancesResult = await conn.execute("""
        SELECT 
          a.alliance_id,
          a.selection_round as alliance_rank,
          a.captain_team_id,
          a.partner_team_id,
          COALESCE(t1.team_name, 'Unknown') as captain_name,
          COALESCE(t2.team_name, 'Unknown') as partner_name
        FROM tbl_alliance_selections a
        LEFT JOIN tbl_team t1 ON a.captain_team_id = t1.team_id
        LEFT JOIN tbl_team t2 ON a.partner_team_id = t2.team_id
        WHERE a.category_id = :catId
        ORDER BY a.selection_round
      """, {"catId": categoryId});
      
      final alliances = alliancesResult.rows.map((r) => r.assoc()).toList();
      
      if (alliances.isEmpty) {
        setState(() {
          _allianceStandingsByCategory[categoryId] = [];
          _isLoadingAllianceByCategory[categoryId] = false;
        });
        return;
      }
      
      final List<AllianceStanding> standings = [];
      for (int i = 0; i < alliances.length; i++) {
        final alliance = alliances[i];
        
        standings.add(AllianceStanding(
          allianceId: int.parse(alliance['alliance_id'].toString()),
          allianceRank: i + 1,
          teams: [
            {
              'team_name': alliance['captain_name'].toString(),
              'role': 'Captain',
            },
            {
              'team_name': alliance['partner_name'].toString(),
              'role': 'Partner',
            },
          ],
          totalScore: 0,
          wins: 0,
          losses: 0,
          status: 'active',
        ));
      }
      
      setState(() {
        _allianceStandingsByCategory[categoryId] = standings;
        _isLoadingAllianceByCategory[categoryId] = false;
      });
      
    } catch (e) {
      print("Error loading alliance standings: $e");
      setState(() {
        _allianceStandingsByCategory[categoryId] = [];
        _isLoadingAllianceByCategory[categoryId] = false;
      });
    }
  }

  Future<void> _loadChampionStandings(int categoryId) async {
    setState(() {
      _isLoadingAllianceByCategory[categoryId] = true;
    });
    
    try {
      final conn = await DBHelper.getConnection();
      
      final result = await conn.execute("""
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
      """, {"catId": categoryId});
      
      final rows = result.rows.map((r) => r.assoc()).toList();
      
      if (rows.isEmpty) {
        setState(() {
          _championStandingsByCategory[categoryId] = [];
          _isLoadingAllianceByCategory[categoryId] = false;
        });
        return;
      }
      
      final List<ChampionStanding> standings = [];
      for (int i = 0; i < rows.length; i++) {
        final row = rows[i];
        
        String title = i == 0 ? 'Champion' : i == 1 ? 'Runner-up' : 'Semi-finalist';
        Color medalColor = i == 0 ? const Color(0xFFFFD700) : 
                           i == 1 ? const Color(0xFFC0C0C0) : 
                           const Color(0xFFCD7F32);
        
        standings.add(ChampionStanding(
          allianceId: int.parse(row['alliance_id'].toString()),
          allianceRank: int.parse(row['alliance_rank'].toString()),
          teams: [
            {'team_name': row['captain_name'].toString(), 'role': 'Captain'},
            {'team_name': row['partner_name'].toString(), 'role': 'Partner'},
          ],
          title: title,
          medalColor: medalColor,
        ));
      }
      
      setState(() {
        _championStandingsByCategory[categoryId] = standings;
        _isLoadingAllianceByCategory[categoryId] = false;
      });
      
    } catch (e) {
      print("Error loading champion standings: $e");
      setState(() {
        _championStandingsByCategory[categoryId] = [];
        _isLoadingAllianceByCategory[categoryId] = false;
      });
    }
  }

  Future<void> _initializeDefaultScores(int categoryId) async {
    setState(() => _isInitializingScores = true);
    
    try {
      final conn = await DBHelper.getConnection();
      final teams = await DBHelper.getTeamsByCategory(categoryId);
      
      if (teams.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('❌ No teams found in this category'),
              backgroundColor: Colors.orange,
            ),
          );
        }
        setState(() => _isInitializingScores = false);
        return;
      }
      
      final roundsResult = await conn.execute("""
        SELECT DISTINCT ts.round_id
        FROM tbl_teamschedule ts
        JOIN tbl_team t ON ts.team_id = t.team_id
        WHERE t.category_id = :catId
        ORDER BY ts.round_id
      """, {"catId": categoryId});
      
      final rounds = roundsResult.rows.map((r) => 
        int.tryParse(r.assoc()['round_id']?.toString() ?? '0') ?? 0
      ).where((r) => r > 0).toList();
      
      if (rounds.isEmpty) {
        final settingsResult = await conn.execute("""
          SELECT matches_per_team 
          FROM tbl_category_settings 
          WHERE category_id = :catId
        """, {"catId": categoryId});
        
        if (settingsResult.rows.isNotEmpty) {
          final matchesPerTeam = int.tryParse(
            settingsResult.rows.first.assoc()['matches_per_team']?.toString() ?? '0'
          ) ?? 0;
          
          for (int i = 1; i <= matchesPerTeam; i++) {
            rounds.add(i);
          }
        }
      }
      
      if (rounds.isEmpty) {
        rounds.addAll([1, 2, 3, 4]);
      }
      
      int scoresInserted = 0;
      int scoresSkipped = 0;
      
      for (final team in teams) {
        final teamId = int.tryParse(team['team_id'].toString()) ?? 0;
        if (teamId == 0) continue;
        
        for (final roundId in rounds) {
          final checkResult = await conn.execute("""
            SELECT COUNT(*) as cnt 
            FROM tbl_score 
            WHERE team_id = :teamId AND round_id = :roundId
          """, {"teamId": teamId, "roundId": roundId});
          
          final exists = int.tryParse(
            checkResult.rows.first.assoc()['cnt']?.toString() ?? '0'
          ) ?? 0;
          
          if (exists == 0) {
            await DBHelper.executeDual("""
              INSERT INTO tbl_score
                (team_id, round_id, score_totalscore, score_individual, score_alliance, score_violation, score_totalduration)
              VALUES
                (:teamId, :roundId, 0, 0, 0, 0, '00:00')
            """, {
              "teamId": teamId,
              "roundId": roundId,
            });
            scoresInserted++;
          } else {
            scoresSkipped++;
          }
        }
      }
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ Initialized $scoresInserted default scores (0)${scoresSkipped > 0 ? ', $scoresSkipped already existed' : ''}'),
            backgroundColor: Colors.green,
          ),
        );
      }
      
      await _loadData(initial: false);
      
    } catch (e) {
      print("Error initializing scores: $e");
    } finally {
      if (mounted) setState(() => _isInitializingScores = false);
    }
  }

  Future<void> _clearScores(int categoryId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF2D0E7A),
        title: const Text('Clear Scores?', 
            style: TextStyle(color: Colors.white)),
        content: const Text(
          'This will delete all scores for this category. This action cannot be undone.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('CANCEL', 
                style: TextStyle(color: Colors.white54)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('CLEAR', 
                style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
    
    if (confirm != true) return;
    
    try {
      final conn = await DBHelper.getConnection();
      await DBHelper.executeDual("""
        DELETE s FROM tbl_score s
        JOIN tbl_team t ON s.team_id = t.team_id
        WHERE t.category_id = :catId
      """, {"catId": categoryId});
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Scores cleared'),
            backgroundColor: Colors.orange,
          ),
        );
      }
      
      await _loadData(initial: false);
      
    } catch (e) {
      print("Error clearing scores: $e");
    }
  }

  Future<String> _getPartnerTeamName(int matchId, int teamId, int roundId) async {
    if (matchId <= 0) return '';
    
    try {
      final conn = await DBHelper.getConnection();
      
      final arenaResult = await conn.execute("""
        SELECT arena_number FROM tbl_teamschedule
        WHERE match_id = :matchId AND team_id = :teamId AND round_id = :roundId
        LIMIT 1
      """, {
        "matchId": matchId,
        "teamId": teamId,
        "roundId": roundId,
      });
      
      if (arenaResult.rows.isEmpty) return '';
      
      final arenaNumber = int.tryParse(arenaResult.rows.first.assoc()['arena_number']?.toString() ?? '0') ?? 0;
      if (arenaNumber == 0) return '';
      
      final partnerResult = await conn.execute("""
        SELECT t.team_name
        FROM tbl_teamschedule ts
        JOIN tbl_team t ON ts.team_id = t.team_id
        WHERE ts.match_id = :matchId 
          AND ts.arena_number = :arena
          AND ts.team_id != :teamId
        LIMIT 1
      """, {
        "matchId": matchId,
        "arena": arenaNumber,
        "teamId": teamId,
      });
      
      if (partnerResult.rows.isEmpty) return '';
      
      return partnerResult.rows.first.assoc()['team_name']?.toString() ?? '';
      
    } catch (e) {
      print("Error getting partner team: $e");
      return '';
    }
  }

  Future<String> _getOpponentTeamName(int matchId, int teamId, int roundId) async {
    if (matchId <= 0) return '';
    
    try {
      final conn = await DBHelper.getConnection();
      
      final opponentResult = await conn.execute("""
        SELECT t.team_name
        FROM tbl_teamschedule ts
        JOIN tbl_team t ON ts.team_id = t.team_id
        WHERE ts.match_id = :matchId 
          AND ts.team_id != :teamId
        LIMIT 1
      """, {
        "matchId": matchId,
        "teamId": teamId,
      });
      
      if (opponentResult.rows.isEmpty) return '';
      
      return opponentResult.rows.first.assoc()['team_name']?.toString() ?? '';
      
    } catch (e) {
      print("Error getting opponent team: $e");
      return '';
    }
  }

  void _showQualificationScoreDialog({
    required int teamId,
    required String teamName,
    required int roundId,
    required RoundScore? currentScore,
  }) async {
    print("\n🎯 Opening qualification score dialog");
    print("   Team ID: $teamId");
    print("   Round ID: $roundId");
    
    int matchId = 0;
    String partnerName = '';
    bool isOneVsOne = false;
    
    try {
      final conn = await DBHelper.getConnection();
      
      final categoryResult = await conn.execute("""
        SELECT c.category_type
        FROM tbl_team t
        JOIN tbl_category c ON t.category_id = c.category_id
        WHERE t.team_id = :teamId
      """, {"teamId": teamId});
      
      if (categoryResult.rows.isNotEmpty) {
        final categoryName = categoryResult.rows.first.assoc()['category_type']?.toString().toLowerCase() ?? '';
        isOneVsOne = categoryName.contains('starter');
      }
      
      final matchResult = await conn.execute("""
        SELECT ts.match_id, ts.arena_number, ts.round_id
        FROM tbl_teamschedule ts
        WHERE ts.team_id = :teamId AND ts.round_id = :roundId
        LIMIT 1
      """, {
        "teamId": teamId,
        "roundId": roundId,
      });
      
      if (matchResult.rows.isNotEmpty) {
        matchId = int.parse(matchResult.rows.first.assoc()['match_id']?.toString() ?? '0');
        
        if (isOneVsOne) {
          partnerName = await _getOpponentTeamName(matchId, teamId, roundId);
        } else {
          partnerName = await _getPartnerTeamName(matchId, teamId, roundId);
        }
      }
      
    } catch (e) {
      print("Error getting match info: $e");
    }
    
    final individualController = TextEditingController(
      text: currentScore?.individualScore.toString() ?? '0',
    );
    final allianceController = TextEditingController(
      text: currentScore?.allianceScore.toString() ?? '0',
    );
    final violationController = TextEditingController(
      text: currentScore?.violation.toString() ?? '0',
    );
    final durationController = TextEditingController(
      text: currentScore?.duration ?? '00:00',
    );

    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          width: 450,
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF2D0E7A), Color(0xFF1E0A5A)],
            ),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: const Color(0xFF00CFFF).withOpacity(0.4),
              width: 1.5,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF00CFFF).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.edit_note_rounded,
                      color: Color(0xFF00CFFF),
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          teamName,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          'Round $roundId • Enter Score',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.5),
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              if (partnerName.isNotEmpty)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF00CFFF).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFF00CFFF).withOpacity(0.3)),
                  ),
                  child: Row(
                    children: [
                      Icon(isOneVsOne ? Icons.sports_kabaddi : Icons.people_alt_rounded, 
                          color: const Color(0xFF00CFFF), size: 18),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              isOneVsOne 
                                  ? 'Opponent: $partnerName' 
                                  : 'Alliance Partner: $partnerName',
                              style: const TextStyle(
                                color: Color(0xFF00CFFF),
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              isOneVsOne
                                  ? 'Alliance score will be shared with opponent'
                                  : 'Alliance score will be automatically shared with your teammate',
                              style: const TextStyle(color: Colors.white70, fontSize: 10),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              if (partnerName.isNotEmpty) const SizedBox(height: 16),

              _buildScoreField(
                label: 'INDIVIDUAL SCORE',
                controller: individualController,
                color: const Color(0xFF00CFFF),
                hint: '0',
              ),
              const SizedBox(height: 16),

              _buildScoreField(
                label: 'ALLIANCE SCORE',
                controller: allianceController,
                color: const Color(0xFFFFD700),
                hint: '0',
              ),
              const SizedBox(height: 16),

              _buildScoreField(
                label: 'VIOLATION (-)',
                controller: violationController,
                color: Colors.redAccent,
                hint: '0',
              ),
              const SizedBox(height: 16),

              _buildScoreField(
                label: 'DURATION (MM:SS)',
                controller: durationController,
                color: const Color(0xFF00E5A0),
                hint: '00:00',
              ),
              const SizedBox(height: 8),

              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFD700).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Row(
                  children: [
                    Icon(
                      Icons.info_outline,
                      color: Color(0xFFFFD700),
                      size: 14,
                    ),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Total = Individual + Alliance - Violation',
                        style: TextStyle(color: Colors.white70, fontSize: 11),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: Text(
                        'CANCEL',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.5),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () async {
                        final individual = int.tryParse(individualController.text.trim()) ?? 0;
                        final alliance = int.tryParse(allianceController.text.trim()) ?? 0;
                        final violation = int.tryParse(violationController.text.trim()) ?? 0;
                        final duration = durationController.text.trim();

                        if (!RegExp(r'^\d{2}:\d{2}$').hasMatch(duration)) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Duration must be MM:SS format'),
                              backgroundColor: Colors.orange,
                            ),
                          );
                          return;
                        }

                        final total = individual + alliance - violation;

                        try {
                          final conn = await DBHelper.getConnection();

                          final refResult = await conn.execute(
                            "SELECT referee_id FROM tbl_referee LIMIT 1",
                          );
                          int? refereeId;
                          if (refResult.rows.isNotEmpty) {
                            refereeId = int.tryParse(
                                refResult.rows.first.assoc()['referee_id']?.toString() ?? '0');
                            if (refereeId == 0) refereeId = null;
                          }

                          int previousAlliance = 0;
                          try {
                            final prevRes = await conn.execute("""
                              SELECT score_alliance FROM tbl_score
                              WHERE team_id = :teamId AND round_id = :roundId
                              LIMIT 1
                            """, {"teamId": teamId, "roundId": roundId});
                            if (prevRes.rows.isNotEmpty) {
                              previousAlliance = int.tryParse(prevRes.rows.first.assoc()['score_alliance']?.toString() ?? '0') ?? 0;
                            }
                          } catch (e) {
                            print("⚠️ Could not read previous alliance score: $e");
                          }

                          await DBHelper.upsertScore(
                            teamId: teamId,
                            roundId: roundId,
                            matchId: matchId,
                            refereeId: refereeId,
                            independentScore: individual,
                            allianceScore: alliance,
                            violation: violation,
                            totalScore: total,
                            totalDuration: duration,
                          );

                          final allianceDelta = alliance - previousAlliance;
                          
                          if (matchId > 0 && allianceDelta != 0) {
                            await DBHelper.propagateAllianceScoreForMatch(
                              matchId: matchId,
                              roundId: roundId,
                              sourceTeamId: teamId,
                              allianceScore: allianceDelta,
                            );
                          }

                          if (mounted) {
                            Navigator.pop(ctx);
                            
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('✅ Score saved and propagated'),
                                backgroundColor: Colors.green,
                                duration: Duration(seconds: 2),
                              ),
                            );
                            
                            await _loadData(initial: false);
                            
                            if (mounted) {
                              setState(() {});
                            }
                          }
                        } catch (e, stackTrace) {
                          print("❌ Error saving score: $e");
                          print(stackTrace);
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('❌ Error: $e'),
                                backgroundColor: Colors.red,
                              ),
                            );
                          }
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFFFD700),
                        foregroundColor: Colors.black,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: const Text('SAVE'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildScoreField({
    required String label,
    required TextEditingController controller,
    required Color color,
    required String hint,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: TextStyle(
                color: color,
                fontWeight: FontWeight.bold,
                fontSize: 11,
                letterSpacing: 0.5)),
        const SizedBox(height: 4),
        TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          style: TextStyle(color: color, fontSize: 18, fontWeight: FontWeight.bold),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(color: color.withOpacity(0.3), fontSize: 18),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: color.withOpacity(0.3)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: color.withOpacity(0.3)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: color, width: 2),
            ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          ),
        ),
      ],
    );
  }

  Future<void> _loadData({bool initial = false}) async {
    if (initial) setState(() => _isLoading = true);

    try {
      print("🔄 Loading standings data...");
      final categories = await DBHelper.getCategories();
      final Map<int, List<Map<String, dynamic>>> standingsByCategory = {};

      for (final cat in categories) {
        final catId = int.tryParse(cat['category_id'].toString()) ?? 0;
        print("📊 Loading category $catId");
        
        final conn = await DBHelper.getConnection();
        
        final scoreResult = await conn.execute("""
          SELECT 
            s.team_id, 
            s.round_id, 
            s.score_totalscore,
            s.score_individual,
            s.score_alliance,
            s.score_violation,
            s.score_totalduration 
          FROM tbl_score s
          JOIN tbl_team t ON s.team_id = t.team_id
          WHERE t.category_id = :catId
          ORDER BY s.team_id, s.round_id
        """, {"catId": catId});
        
        final rows = scoreResult.rows.map((r) => r.assoc()).toList();
        print("   Found ${rows.length} score rows");

        final Map<int, Map<String, dynamic>> teamMap = {};
        
        final teams = await DBHelper.getTeamsByCategory(catId);
        print("   Found ${teams.length} teams");
        
        for (final team in teams) {
          final teamId = int.tryParse(team['team_id'].toString()) ?? 0;
          teamMap[teamId] = {
            'team_id': teamId,
            'team_name': team['team_name'] ?? '',
            'rounds': <int, RoundScore>{},
            'totalScore': 0,
          };
        }

        int maxRoundFound = 0;
        
        for (final row in rows) {
          final teamId = int.tryParse(row['team_id'].toString()) ?? 0;
          final roundId = int.tryParse(row['round_id']?.toString() ?? '0') ?? 0;
          final totalScore = int.tryParse(row['score_totalscore'].toString()) ?? 0;
          final individualScore = int.tryParse(row['score_individual']?.toString() ?? '0') ?? 0;
          final allianceScore = int.tryParse(row['score_alliance']?.toString() ?? '0') ?? 0;
          final violation = int.tryParse(row['score_violation']?.toString() ?? '0') ?? 0;
          final duration = row['score_totalduration']?.toString() ?? '00:00';

          if (teamMap.containsKey(teamId)) {
            final roundScore = RoundScore(
              individualScore: individualScore,
              allianceScore: allianceScore,
              violation: violation,
              duration: duration,
            );
            
            teamMap[teamId]!['rounds'][roundId] = roundScore;
            teamMap[teamId]!['totalScore'] = (teamMap[teamId]!['totalScore'] as int) + totalScore;
            
            if (roundId > maxRoundFound) maxRoundFound = roundId;
          }
        }

        int maxRounds = 0;
        try {
          final settingsResult = await conn.execute("""
            SELECT matches_per_team 
            FROM tbl_category_settings 
            WHERE category_id = :catId
          """, {"catId": catId});
          
          if (settingsResult.rows.isNotEmpty) {
            maxRounds = int.tryParse(settingsResult.rows.first.assoc()['matches_per_team']?.toString() ?? '0') ?? 0;
          }
        } catch (e) {
          print("⚠️ Could not load settings: $e");
        }
        
        if (maxRounds == 0 && maxRoundFound > 0) maxRounds = maxRoundFound;
        if (maxRounds == 0 && teams.isNotEmpty) maxRounds = 4;

        final standings = teamMap.values.map((teamData) {
          return {
            'team_id': teamData['team_id'],
            'team_name': teamData['team_name'],
            'rounds': teamData['rounds'],
            'totalScore': teamData['totalScore'],
            'maxRounds': maxRounds,
          };
        }).toList();

        standings.sort((a, b) => (b['totalScore'] as int).compareTo(a['totalScore'] as int));

        for (int i = 0; i < standings.length; i++) {
          standings[i]['rank'] = i + 1;
        }

        standingsByCategory[catId] = standings;
        print("✅ Category $catId: ${standings.length} teams processed");
        
        if (!_selectedTypeByCategory.containsKey(catId)) {
          _selectedTypeByCategory[catId] = StandingType.qualification;
        }
      }

      final previousTabIndex = _tabController?.index ?? 0;

      _tabController?.dispose();
      _tabController = TabController(
        length: categories.length,
        vsync: this,
        initialIndex: previousTabIndex.clamp(0, categories.length - 1),
      );

      print("✅ All data loaded, updating UI");
      setState(() {
        _categories = categories;
        _standingsByCategory = standingsByCategory;
        _isLoading = false;
        _lastUpdated = DateTime.now();
      });
      
    } catch (e, stackTrace) {
      print("❌ Error loading standings: $e");
      print(stackTrace);
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1A0A4A),
      body: Column(
        children: [
          _buildHeader(),
          if (_isLoading)
            const Expanded(
              child: Center(
                child: CircularProgressIndicator(color: Color(0xFF00CFFF)),
              ),
            )
          else if (_categories.isEmpty)
            const Expanded(
              child: Center(
                child: Text('No data found.',
                    style: TextStyle(color: Colors.white, fontSize: 16)),
              ),
            )
          else ...[
            Container(
              color: const Color(0xFF2D0E7A),
              child: TabBar(
                controller: _tabController,
                isScrollable: true,
                indicatorColor: const Color(0xFF00CFFF),
                indicatorWeight: 3,
                labelColor: const Color(0xFF00CFFF),
                unselectedLabelColor: Colors.white54,
                labelStyle: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    letterSpacing: 1),
                tabs: _categories.map((c) {
                  return Tab(
                      text: (c['category_type'] ?? '')
                          .toString()
                          .toUpperCase());
                }).toList(),
              ),
            ),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: _categories.map((cat) {
                  final catId = int.tryParse(cat['category_id'].toString()) ?? 0;
                  final rows = _standingsByCategory[catId] ?? [];
                  return _buildStandingsView(cat, catId, rows);
                }).toList(),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStandingsView(
    Map<String, dynamic> category,
    int categoryId,
    List<Map<String, dynamic>> rows,
  ) {
    final categoryName = (category['category_type'] ?? '').toString().toLowerCase();
    final isExplorer = categoryName.contains('explorer');
    
    final maxRounds = rows.isNotEmpty 
        ? (rows.first['maxRounds'] as int? ?? 4) 
        : 4;

    bool hasScores = false;
    for (final row in rows) {
      final rounds = row['rounds'] as Map<int, RoundScore>;
      for (final roundScore in rounds.values) {
        if (roundScore.totalScore > 0) {
          hasScores = true;
          break;
        }
      }
      if (hasScores) break;
    }

    StandingType selectedType = _selectedTypeByCategory[categoryId] ?? StandingType.qualification;

    return Column(
      children: [
        Container(
          width: double.infinity,
          color: const Color(0xFF2D0E7A),
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 32),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                constraints: const BoxConstraints(minWidth: 250),
                child: DropdownButton<StandingType>(
                  value: selectedType,
                  dropdownColor: const Color(0xFF2D0E7A),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                  icon: Icon(
                    Icons.keyboard_arrow_down_rounded,
                    color: selectedType.color,
                    size: 24,
                  ),
                  onChanged: (StandingType? newValue) {
                    if (newValue != null) {
                      setState(() {
                        _selectedTypeByCategory[categoryId] = newValue;
                      });
                      
                      if (newValue == StandingType.championship) {
                        if (isExplorer) {
                          _loadMatchPairings(categoryId);
                          _loadBestOf3Results(categoryId);
                          _loadChampionshipStandings(categoryId);
                        } else {
                          _loadChampionshipStandings(categoryId);
                        }
                      } else if (newValue == StandingType.battleOfChampions) {
                        _loadChampionStandings(categoryId);
                      }
                    }
                  },
                  items: StandingType.values.map((type) {
                    return DropdownMenuItem<StandingType>(
                      value: type,
                      child: Container(
                        width: 220,
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          children: [
                            Container(
                              width: 28,
                              height: 28,
                              decoration: BoxDecoration(
                                color: type.color.withOpacity(0.15),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Icon(
                                type.icon, 
                                color: type.color, 
                                size: 16
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                type.displayName,
                                style: TextStyle(
                                  color: type == selectedType ? type.color : Colors.white70,
                                  fontSize: 14,
                                  fontWeight: type == selectedType ? FontWeight.bold : FontWeight.normal,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
              
              Text(
                (category['category_type'] ?? '').toString().toUpperCase(),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 2,
                ),
              ),
              
              Row(
                children: [
                  if (selectedType == StandingType.qualification && rows.isNotEmpty && !hasScores)
                    Container(
                      margin: const EdgeInsets.only(right: 8),
                      child: ElevatedButton.icon(
                        onPressed: _isInitializingScores 
                            ? null 
                            : () => _initializeDefaultScores(categoryId),
                        icon: _isInitializingScores
                            ? const SizedBox(
                                width: 16, height: 16,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white))
                            : const Icon(Icons.auto_awesome_rounded, size: 16),
                        label: Text(_isInitializingScores ? '...' : 'INIT SCORES'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF00E5A0),
                          foregroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 6),
                          textStyle: const TextStyle(
                              fontSize: 11, fontWeight: FontWeight.bold),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8)),
                        ),
                      ),
                    ),
                  
                  if (selectedType == StandingType.qualification && hasScores)
                    Container(
                      margin: const EdgeInsets.only(right: 8),
                      child: OutlinedButton.icon(
                        onPressed: () => _clearScores(categoryId),
                        icon: const Icon(Icons.delete_sweep_rounded, size: 14),
                        label: const Text('CLEAR'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.redAccent,
                          side: const BorderSide(color: Colors.redAccent),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 6),
                          textStyle: const TextStyle(
                              fontSize: 11, fontWeight: FontWeight.bold),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8)),
                        ),
                      ),
                    ),
                  
                  _buildLiveIndicator(),
                  IconButton(
                    tooltip: 'Teams & Players',
                    icon: const Icon(Icons.groups_rounded,
                        color: Color(0xFF00E5A0)),
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => TeamsPlayers(
                            onBack: () => Navigator.of(context).pop(),
                          ),
                        ),
                      );
                    },
                  ),
                  IconButton(
                    tooltip: 'Back to Homepage',
                    icon: const Icon(Icons.arrow_back_ios_new,
                        color: Color(0xFF00CFFF)),
                    onPressed: widget.onBack,
                  ),
                  const SizedBox(width: 8),
                  if (selectedType == StandingType.qualification && maxRounds > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: const Color(0xFF00CFFF).withOpacity(0.15),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: const Color(0xFF00CFFF).withOpacity(0.3)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.sports_esports_rounded, 
                              color: Color(0xFF00CFFF), size: 14),
                          const SizedBox(width: 6),
                          Text(
                            '$maxRounds MATCHES PER TEAM',
                            style: const TextStyle(
                              color: Color(0xFF00CFFF),
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),

        if (selectedType == StandingType.qualification)
          _buildQualificationTable(rows, maxRounds)
        else if (selectedType == StandingType.championship)
          isExplorer 
              ? _buildChampionshipTable(categoryId)
              : _buildOriginalChampionshipTable(categoryId)
        else
          _buildBattleOfChampionsView(categoryId),
      ],
    );
  }

  Widget _buildQualificationTable(List<Map<String, dynamic>> rows, int maxRounds) {
    return Expanded(
      child: Column(
        children: [
          Container(
            color: const Color(0xFF5C2ECC),
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
            child: Row(
              children: [
                _headerCell('RANK', flex: 1),
                _headerCell('TEAM ID', flex: 2),
                _headerCell('TEAM NAME', flex: 3),
                ...List.generate(maxRounds, (i) => 
                  Expanded(
                    flex: 4,
                    child: Center(
                      child: Text(
                        'ROUND ${i + 1}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ),
                ),
                _headerCell('TOTAL', flex: 2, center: true),
              ],
            ),
          ),
          
          Container(
            color: const Color(0xFF4A1A9C),
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
            child: Row(
              children: [
                const Expanded(flex: 1, child: SizedBox()),
                const Expanded(flex: 2, child: SizedBox()),
                const Expanded(flex: 3, child: SizedBox()),
                ...List.generate(maxRounds, (i) => 
                  Expanded(
                    flex: 4,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        Expanded(
                          child: Center(
                            child: Text('IND',
                                style: TextStyle(
                                    color: const Color(0xFF00CFFF).withOpacity(0.9),
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold)),
                          ),
                        ),
                        Expanded(
                          child: Center(
                            child: Text('ALL',
                                style: TextStyle(
                                    color: const Color(0xFFFFD700).withOpacity(0.9),
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold)),
                          ),
                        ),
                        Expanded(
                          child: Center(
                            child: Text('VIO',
                                style: TextStyle(
                                    color: Colors.redAccent.withOpacity(0.9),
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold)),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const Expanded(flex: 2, child: SizedBox()),
              ],
            ),
          ),

          Expanded(
            child: rows.isEmpty
                ? const Center(
                    child: Text('No teams registered yet.',
                        style: TextStyle(color: Colors.white54, fontSize: 14)),
                  )
                : ListView.builder(
                    itemCount: rows.length,
                    itemBuilder: (context, index) {
                      final row = rows[index];
                      final rank = row['rank'] as int;
                      final teamId = row['team_id'] as int;
                      final teamName = row['team_name'] as String;
                      final rounds = row['rounds'] as Map<int, RoundScore>;
                      final total = row['totalScore'] as int;
                      final isEven = index % 2 == 0;

                      return Container(
                        color: isEven ? const Color(0xFF1E0E5A) : const Color(0xFF160A42),
                        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                        child: Row(
                          children: [
                            Expanded(flex: 1, child: Text('$rank', 
                                style: TextStyle(color: _rankColor(rank), fontWeight: FontWeight.bold))),
                            
                            Expanded(flex: 2, child: Text('C${teamId.toString().padLeft(3, '0')}R', 
                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
                            
                            Expanded(flex: 3, child: Text(teamName, 
                                style: const TextStyle(color: Colors.white), overflow: TextOverflow.ellipsis)),
                            
                            ...List.generate(maxRounds, (i) {
                              final roundScore = rounds.containsKey(i + 1) 
                                  ? rounds[i + 1]! 
                                  : RoundScore();
                              final hasScore = rounds.containsKey(i + 1);
                              
                              return Expanded(
                                flex: 4,
                                child: Container(
                                  margin: const EdgeInsets.symmetric(horizontal: 2),
                                  decoration: BoxDecoration(
                                    border: Border.all(
                                      color: hasScore 
                                          ? const Color(0xFFFFD700).withOpacity(0.3)
                                          : Colors.white.withOpacity(0.1),
                                      width: 1,
                                    ),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                                    children: [
                                      Expanded(
                                        child: GestureDetector(
                                          onTap: () => _showQualificationScoreDialog(
                                            teamId: teamId,
                                            teamName: teamName,
                                            roundId: i + 1,
                                            currentScore: roundScore,
                                          ),
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(vertical: 6),
                                            decoration: BoxDecoration(
                                              color: hasScore && roundScore.individualScore > 0
                                                  ? const Color(0xFF00CFFF).withOpacity(0.15)
                                                  : null,
                                              borderRadius: const BorderRadius.horizontal(
                                                  left: Radius.circular(3)),
                                            ),
                                            child: Center(
                                              child: Text(
                                                roundScore.individualScore > 0 
                                                    ? '${roundScore.individualScore}'
                                                    : (hasScore ? '0' : '—'),
                                                style: TextStyle(
                                                  color: roundScore.individualScore > 0 || hasScore
                                                      ? const Color(0xFF00CFFF)
                                                      : Colors.white24,
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 13,
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                      
                                      Expanded(
                                        child: GestureDetector(
                                          onTap: () => _showQualificationScoreDialog(
                                            teamId: teamId,
                                            teamName: teamName,
                                            roundId: i + 1,
                                            currentScore: roundScore,
                                          ),
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(vertical: 6),
                                            decoration: BoxDecoration(
                                              color: hasScore && roundScore.allianceScore > 0
                                                  ? const Color(0xFFFFD700).withOpacity(0.15)
                                                  : null,
                                              border: Border(
                                                left: BorderSide(color: Colors.white.withOpacity(0.1), width: 1),
                                                right: BorderSide(color: Colors.white.withOpacity(0.1), width: 1),
                                              ),
                                            ),
                                            child: Center(
                                              child: Text(
                                                roundScore.allianceScore > 0 
                                                    ? '${roundScore.allianceScore}'
                                                    : (hasScore ? '0' : '—'),
                                                style: TextStyle(
                                                  color: roundScore.allianceScore > 0 || hasScore
                                                      ? const Color(0xFFFFD700)
                                                      : Colors.white24,
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 13,
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                      
                                      Expanded(
                                        child: GestureDetector(
                                          onTap: () => _showQualificationScoreDialog(
                                            teamId: teamId,
                                            teamName: teamName,
                                            roundId: i + 1,
                                            currentScore: roundScore,
                                          ),
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(vertical: 6),
                                            decoration: BoxDecoration(
                                              color: roundScore.violation > 0
                                                  ? Colors.red.withOpacity(0.15)
                                                  : null,
                                              borderRadius: const BorderRadius.horizontal(
                                                  right: Radius.circular(3)),
                                            ),
                                            child: Center(
                                              child: Text(
                                                roundScore.violation > 0 
                                                    ? '${roundScore.violation}'
                                                    : (hasScore ? '0' : '—'),
                                                style: TextStyle(
                                                  color: roundScore.violation > 0
                                                      ? Colors.redAccent
                                                      : (hasScore ? Colors.white38 : Colors.white24),
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 13,
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            }),
                            
                            Expanded(
                              flex: 2,
                              child: Center(
                                child: Column(
                                  children: [
                                    Text('$total',
                                        style: const TextStyle(
                                            color: Color(0xFFFFD700),
                                            fontWeight: FontWeight.bold,
                                            fontSize: 18)),
                                    Text(_bestDuration(rounds),
                                        style: const TextStyle(
                                            color: Colors.white60, fontSize: 10)),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildBattleOfChampionsView(int categoryId) {
    bool isLoading = _isLoadingAllianceByCategory[categoryId] ?? false;
    List<ChampionStanding> standings = _championStandingsByCategory[categoryId] ?? [];

    if (isLoading) {
      return const Expanded(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(color: Color(0xFFFFD700)),
              SizedBox(height: 16),
              Text('Loading champion standings...',
                  style: TextStyle(color: Colors.white54)),
            ],
          ),
        ),
      );
    }
    
    if (standings.isEmpty) {
      return Expanded(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.military_tech_rounded, size: 64, color: Colors.white.withOpacity(0.2)),
              const SizedBox(height: 16),
              const Text('Battle of Champions Not Completed',
                  style: TextStyle(color: Colors.white, fontSize: 18)),
              const SizedBox(height: 8),
              Text('Complete the championship round first',
                  style: TextStyle(color: Colors.white.withOpacity(0.5))),
            ],
          ),
        ),
      );
    }
    
    return Expanded(
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: standings.length,
        itemBuilder: (context, index) {
          final standing = standings[index];
          return Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: standing.medalColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: standing.medalColor.withOpacity(0.3)),
            ),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: standing.medalColor.withOpacity(0.2),
                  ),
                  child: Center(
                    child: Icon(
                      index == 0 ? Icons.star : 
                      index == 1 ? Icons.emoji_events : 
                      Icons.military_tech,
                      color: standing.medalColor,
                      size: 24,
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        standing.title.toUpperCase(),
                        style: TextStyle(
                          color: standing.medalColor,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 4),
                      ...standing.teams.map((team) {
                        return Text(
                          '• ${team['team_name']} (${team['role']})',
                          style: const TextStyle(color: Colors.white70, fontSize: 12),
                        );
                      }),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: standing.medalColor.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    'Alliance #${standing.allianceRank}',
                    style: TextStyle(
                      color: standing.medalColor,
                      fontWeight: FontWeight.bold,
                      fontSize: 11,
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Color _rankColor(int rank) {
    switch (rank) {
      case 1: return const Color(0xFFFFD700);
      case 2: return const Color(0xFFC0C0C0);
      case 3: return const Color(0xFFCD7F32);
      default: return Colors.white;
    }
  }

  String _bestDuration(Map<int, RoundScore> rounds) {
    if (rounds.isEmpty) return '00:00';
    int bestScore = -1;
    String bestDuration = '00:00';
    for (final roundScore in rounds.values) {
      if (roundScore.totalScore > bestScore) {
        bestScore = roundScore.totalScore;
        bestDuration = roundScore.duration;
      }
    }
    return bestDuration;
  }

  Widget _headerCell(String text, {int flex = 1, bool center = false}) {
    return Expanded(
      flex: flex,
      child: Text(
        text,
        textAlign: center ? TextAlign.center : TextAlign.left,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
          fontSize: 12,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      width: double.infinity,
      color: const Color(0xFF2D0E7A),
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              RichText(
                text: const TextSpan(
                  children: [
                    TextSpan(text: 'Make', style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
                    TextSpan(text: 'bl', style: TextStyle(color: Color(0xFF00CFFF), fontSize: 22, fontWeight: FontWeight.bold)),
                    TextSpan(text: 'ock', style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
              const Text('Construct Your Dreams',
                  style: TextStyle(color: Colors.white54, fontSize: 10)),
            ],
          ),
          Image.asset('assets/images/CenterLogo.png', height: 80, fit: BoxFit.contain),
          const Text('CREOTEC',
              style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold, letterSpacing: 3)),
        ],
      ),
    );
  }

  Widget _buildLiveIndicator() {
    final timeStr = _lastUpdated == null
        ? 'Loading...'
        : '${_lastUpdated!.hour.toString().padLeft(2, '0')}:'
          '${_lastUpdated!.minute.toString().padLeft(2, '0')}:'
          '${_lastUpdated!.second.toString().padLeft(2, '0')}';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _PulsingDot(),
          const SizedBox(width: 6),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('LIVE',
                  style: TextStyle(color: Color(0xFF00FF88), fontSize: 9, fontWeight: FontWeight.bold, letterSpacing: 1)),
              Text(timeStr, style: const TextStyle(color: Colors.white54, fontSize: 9)),
            ],
          ),
        ],
      ),
    );
  }
}

class _PulsingDot extends StatefulWidget {
  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat(reverse: true);
    _anim = Tween<double>(begin: 0.3, end: 1.0).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _anim,
      child: Container(
        width: 8,
        height: 8,
        decoration: const BoxDecoration(
          color: Color(0xFF00FF88),
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}