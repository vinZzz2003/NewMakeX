import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'db_helper.dart';
import 'teams_players.dart';

enum StandingType { qualification, championship, battleOfChampions }

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
  final String bracketSide;

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
    this.bracketSide = 'winners',
  });

  int get alliance1Final => alliance1Score - alliance1Violation;
  int get alliance2Final => alliance2Score - alliance2Violation;

  Map<String, dynamic> toMap() {
    return {
      'match_number': matchNumber,
      'alliance_score': alliance1Score,
      'alliance_violation': alliance1Violation,
      'opponent_score': alliance2Score,
      'opponent_violation': alliance2Violation,
      'winner_alliance_id': winnerAllianceId,
      'is_completed': isCompleted ? 1 : 0,
      'opponent_alliance_id': opponentAllianceId,
      'match_round': matchRound,
      'match_position': matchPosition,
      'bracket_side': bracketSide,
    };
  }

  factory BestOf3MatchResult.fromMap(Map<String, dynamic> map) {
    return BestOf3MatchResult(
      matchNumber: int.parse(map['match_number'].toString()),
      alliance1Score: int.parse(
        (map['alliance1_score'] ?? map['alliance_score'])?.toString() ?? '0',
      ),
      alliance1Violation: int.parse(
        (map['alliance1_violation'] ?? map['alliance_violation'])?.toString() ??
            '0',
      ),
      alliance2Score: int.parse(
        (map['alliance2_score'] ?? map['opponent_score'])?.toString() ?? '0',
      ),
      alliance2Violation: int.parse(
        (map['alliance2_violation'] ?? map['opponent_violation'])?.toString() ??
            '0',
      ),
      winnerAllianceId: int.parse(map['winner_alliance_id']?.toString() ?? '0'),
      isCompleted: (map['is_completed']?.toString() ?? '0') == '1',
      opponentAllianceId: int.parse(
        map['opponent_alliance_id']?.toString() ?? '0',
      ),
      matchRound: int.parse(map['match_round']?.toString() ?? '0'),
      matchPosition: int.parse(map['match_position']?.toString() ?? '0'),
      bracketSide: map['bracket_side']?.toString() ?? 'winners',
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

  const Standings({super.key, this.onBack});

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
  final Map<int, List<ChampionshipAllianceStanding>>
  _championshipStandingsByCategory = {};
  final Map<int, bool> _isLoadingAllianceByCategory = {};
  final Map<int, int> _championshipMatchesPerAlliance = {};
  // Championship pairings indexed by category -> matchId -> pairing
  final Map<int, Map<int, AllianceMatchPair>> _championshipPairingsByMatch = {};

  // Precomputed alliance losses per category (computed asynchronously)
  final Map<int, Map<int, int>> _allianceLossesByCategory = {};
  // Best-of-3 tracking
  final Map<int, Map<int, List<BestOf3MatchResult>>> _bestOf3Results = {};
  final Map<int, Map<int, int>> _allianceWins = {};
  final Map<int, Map<int, int>> _allianceMatchesPlayed = {};
  final Map<int, Map<int, AllianceMatchPair>> _allianceMatchPairings = {};

  bool _isLoading = true;
  bool _isInitializingScores = false;
  static const bool _debugCumulative = true;
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
        "SELECT score_id, team_id, round_id, score_totalscore, score_individual, score_alliance, score_violation FROM tbl_score ORDER BY score_id",
      );
      final rows = result.rows.map((r) => r.assoc()).toList();
      final signature = _buildSignature(rows);

      if (signature != _lastDataSignature) {
        _lastDataSignature = signature;
        await _loadData(initial: false);
      }
    } catch (_) {}
  }

  Future<void> _loadMatchPairings(int categoryId) async {
  try {
    final conn = await DBHelper.getConnection();

    // Try to prefer the double-elimination bracket table
    String? slug;
    try {
      final catRes = await conn.execute(
        "SELECT category_type FROM tbl_category WHERE category_id = :catId LIMIT 1",
        {"catId": categoryId},
      );
      if (catRes.rows.isNotEmpty) {
        slug = catRes.rows.first.assoc()['category_type']?.toString();
      }
    } catch (_) {}

    String doubleTable = 'tbl_double_elimination';
    if (slug != null && slug.trim().isNotEmpty) {
      var ctype = slug.replaceAll(RegExp(r"\(.*?\)"), '').toLowerCase();
      ctype = ctype
          .replaceAll(RegExp(r"[^a-z0-9]+"), '_')
          .replaceAll(RegExp(r"_+"), '_')
          .replaceAll(RegExp(r"^_+|_+$"), '')
          .trim();
      if (ctype.isNotEmpty) {
        final candidate = 'tbl_${ctype}_double_elimination';
        try {
          await conn.execute('SELECT 1 FROM $candidate LIMIT 1');
          doubleTable = candidate;
        } catch (_) {}
      }
    }

    // Execute the query and store the result
    final queryResult = await conn.execute(
      """
      SELECT 
        de.match_id,
        de.round_number,
        de.match_position,
        de.bracket_side,
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
    """,
      {"catId": categoryId},
    );

    final Map<int, AllianceMatchPair> pairings = {};
    final Map<int, AllianceMatchPair> pairByMatch = {};
    
    // Track seen matches by (round, position, side) to deduplicate
    final Set<String> seenMatches = {};

    // Use 'queryResult' instead of 'result'
    for (final row in queryResult.rows) {
      final data = row.assoc();
      final matchId = int.parse(data['match_id'].toString());
      final roundNumber = int.parse(data['round_number']?.toString() ?? '1');
      final matchPosition = int.parse(data['match_position']?.toString() ?? '1');
      final bracketSide = data['bracket_side']?.toString() ?? 'winners';
      
      // Create unique key
      final key = '${roundNumber}_${matchPosition}_${bracketSide}';
      
      // Get alliance IDs
      final alliance1Id = int.parse(data['alliance1_id']?.toString() ?? '0');
      final alliance2Id = int.parse(data['alliance2_id']?.toString() ?? '0');
      
      // If we've seen this match before, check if current entry is better
      if (seenMatches.contains(key)) {
        final existing = pairByMatch[matchId];
        
        // Keep the entry with actual alliances, skip TBD entries if we have a better one
        if ((alliance1Id == 0 || alliance2Id == 0) && 
            existing != null && 
            existing.alliance1Id != 0 && 
            existing.alliance2Id != 0) {
          continue; // Skip this TBD entry
        }
      }
      
      seenMatches.add(key);
      
      // Only store matches that have at least one alliance (for display purposes)
      if (alliance1Id != 0 && alliance2Id != 0) {
        final alliance1Rank = int.parse(data['alliance1_rank']?.toString() ?? '0');
        final alliance2Rank = int.parse(data['alliance2_rank']?.toString() ?? '0');
        final alliance1Name = '${data['captain1_name']} / ${data['partner1_name']}';
        final alliance2Name = '${data['captain2_name']} / ${data['partner2_name']}';
        
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
          bracketSide: bracketSide,
        );
        
        pairings[matchId] = pair;
        pairByMatch[matchId] = pair;
        
        print("📊 Loaded match: Round $roundNumber, Pos $matchPosition, Side $bracketSide, A1: $alliance1Id, A2: $alliance2Id");
      }
    }

    if (mounted) {
      setState(() {
        _allianceMatchPairings[categoryId] = pairings;
        _championshipPairingsByMatch[categoryId] = pairByMatch;
      });
    }

    print("✅ Loaded ${pairings.length} valid matches from double-elimination for category $categoryId (table: $doubleTable)");
  } catch (e) {
    print("❌ Error loading match pairings: $e");
  }
}

  AllianceMatchPair? _findPairingForAlliance(int categoryId, int allianceId) {
    final Map<int, AllianceMatchPair> pairings =
        _allianceMatchPairings[categoryId] ?? {};
    if (pairings.containsKey(allianceId)) return pairings[allianceId];
    final Map<int, AllianceMatchPair>? byMatch =
        _championshipPairingsByMatch[categoryId];
    if (byMatch != null) {
      for (final p in byMatch.values) {
        if (p.alliance1Id == allianceId || p.alliance2Id == allianceId)
          return p;
      }
    }
    return null;
  }

int _getAllianceLossCount(int categoryId, int allianceId) {
  final allResults = _bestOf3Results[categoryId] ?? {};
  final pairings = _allianceMatchPairings[categoryId] ?? {};
  
  int lossCount = 0;
  final Set<String> processedSeries = {}; // Track unique series to avoid double-counting
  
  for (final pair in pairings.values) {
    final seriesKey = '${pair.roundNumber}_${pair.matchPosition}_${pair.bracketSide}';
    if (processedSeries.contains(seriesKey)) continue;
    
    if (pair.alliance1Id == allianceId || pair.alliance2Id == allianceId) {
      if (pair.alliance1Id == 0 || pair.alliance2Id == 0) continue;
      
      processedSeries.add(seriesKey);
      
      final opponentId = pair.alliance1Id == allianceId ? pair.alliance2Id : pair.alliance1Id;
      
      // Get results for this specific series
      final allianceResults = (allResults[allianceId] ?? []).where(
        (r) => r.matchRound == pair.roundNumber && 
               r.matchPosition == pair.matchPosition &&
               r.bracketSide == pair.bracketSide
      ).toList();
      
      final opponentResults = (allResults[opponentId] ?? []).where(
        (r) => r.matchRound == pair.roundNumber && 
               r.matchPosition == pair.matchPosition &&
               r.bracketSide == pair.bracketSide
      ).toList();
      
      int allianceWins = 0;
      int opponentWins = 0;
      final Set<int> processedMatches = {};
      
      for (final r in allianceResults) {
        if (r.isCompleted && !processedMatches.contains(r.matchNumber)) {
          processedMatches.add(r.matchNumber);
          if (r.winnerAllianceId == allianceId) allianceWins++;
          else if (r.winnerAllianceId == opponentId) opponentWins++;
        }
      }
      
      for (final r in opponentResults) {
        if (r.isCompleted && !processedMatches.contains(r.matchNumber)) {
          processedMatches.add(r.matchNumber);
          if (r.winnerAllianceId == allianceId) allianceWins++;
          else if (r.winnerAllianceId == opponentId) opponentWins++;
        }
      }
      
      final bool seriesComplete = (allianceWins >= 2) || (opponentWins >= 2) || (processedMatches.length >= 3);
      
      // Only count loss if series is complete AND opponent has more wins
      if (seriesComplete && opponentWins > allianceWins) {
        lossCount++;
      }
    }
  }
  
  return lossCount;
}

Future<void> _reorderChampionshipStandings(int categoryId) async {
  final standings = _championshipStandingsByCategory[categoryId];
  if (standings == null || standings.isEmpty) return;
  
  // CRITICAL: Get fresh wins directly from database to ensure accuracy
  Map<int, int> freshWins = {};
  
  try {
    final conn = await DBHelper.getConnection();
    final result = await conn.execute(
      """
      SELECT winner_alliance_id, COUNT(DISTINCT CONCAT(match_round, ':', match_position, ':', match_number, ':', bracket_side)) as win_count
      FROM tbl_championship_bestof3
      WHERE category_id = :catId AND is_completed = 1 AND winner_alliance_id != 0
      GROUP BY winner_alliance_id
      """,
      {"catId": categoryId},
    );
    
    for (final row in result.rows) {
      final data = row.assoc();
      final winnerId = int.parse(data['winner_alliance_id'].toString());
      final winCount = int.parse(data['win_count'].toString());
      freshWins[winnerId] = winCount;
    }
  } catch (e) {
    print("⚠️ Could not get fresh wins from DB: $e");
    // Fallback to cached wins
    freshWins = _allianceWins[categoryId] ?? {};
  }
  
  // Create a NEW list with updated scores
  final updatedStandings = <ChampionshipAllianceStanding>[];
  
  for (final standing in standings) {
    // Get wins from fresh data
    final wins = freshWins[standing.allianceId] ?? 0;
    
    // Create a new standing object with updated totalScore
    updatedStandings.add(
      ChampionshipAllianceStanding(
        allianceId: standing.allianceId,
        allianceRank: standing.allianceRank,
        captainName: standing.captainName,
        partnerName: standing.partnerName,
        matchScores: standing.matchScores,
        totalScore: wins * 10,
      ),
    );
  }
  
  // Sort by totalScore (highest first)
  updatedStandings.sort((a, b) {
    if (a.totalScore != b.totalScore) {
      return b.totalScore.compareTo(a.totalScore);
    }
    return a.allianceRank.compareTo(b.allianceRank);
  });
  
  // Update the UI
  if (mounted) {
    setState(() {
      _championshipStandingsByCategory[categoryId] = updatedStandings;
    });
    print("🔄 Reordered: ${updatedStandings.map((s) => '#${s.allianceRank} (${s.totalScore} pts)').join(' → ')}");
  }
}

  // Helper to get the winner of a specific match pair
  int? _getMatchWinnerForPair(
    int categoryId,
    AllianceMatchPair pair,
    Map<int, List<BestOf3MatchResult>> results,
  ) {
    if (pair.alliance1Id == 0 || pair.alliance2Id == 0) return null;
    
    final alliance1Results = results[pair.alliance1Id] ?? [];
    final alliance2Results = results[pair.alliance2Id] ?? [];
    
    final Set<int> completedMatches = {};
    int winsA = 0;
    int winsB = 0;
    
    for (final r in alliance1Results) {
      if (r.matchRound == pair.roundNumber &&
          r.matchPosition == pair.matchPosition &&
          r.bracketSide == pair.bracketSide &&
          r.isCompleted) {
        completedMatches.add(r.matchNumber);
        if (r.winnerAllianceId == pair.alliance1Id) winsA++;
        else if (r.winnerAllianceId == pair.alliance2Id) winsB++;
      }
    }
    
    for (final r in alliance2Results) {
      if (r.matchRound == pair.roundNumber &&
          r.matchPosition == pair.matchPosition &&
          r.bracketSide == pair.bracketSide &&
          r.isCompleted) {
        if (!completedMatches.contains(r.matchNumber)) {
          completedMatches.add(r.matchNumber);
          if (r.winnerAllianceId == pair.alliance1Id) winsA++;
          else if (r.winnerAllianceId == pair.alliance2Id) winsB++;
        }
      }
    }
    
    final bool seriesComplete = (winsA >= 2) || (winsB >= 2) || (completedMatches.length >= 3);
    
    if (seriesComplete) {
      if (winsA > winsB) return pair.alliance1Id;
      if (winsB > winsA) return pair.alliance2Id;
    }
    
    return null;
  }

  // Load Best-of-3 results from database
  Future<void> _loadBestOf3Results(int categoryId) async {
    try {
      final conn = await DBHelper.getConnection();

      // Create table if it doesn't exist with bracket_side column
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
    bracket_side VARCHAR(20) NOT NULL DEFAULT 'winners',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (category_id) REFERENCES tbl_category(category_id) ON DELETE CASCADE,
    FOREIGN KEY (alliance_id) REFERENCES tbl_alliance_selections(alliance_id) ON DELETE CASCADE,
    FOREIGN KEY (opponent_alliance_id) REFERENCES tbl_alliance_selections(alliance_id) ON DELETE CASCADE,
    UNIQUE KEY unique_match (category_id, alliance_id, opponent_alliance_id, match_number, match_round, match_position, bracket_side)
  )
""");

      // Load existing results
      final result = await conn.execute(
        """
        SELECT * FROM tbl_championship_bestof3
        WHERE category_id = :catId
        ORDER BY match_round, match_position, match_number
      """,
        {"catId": categoryId},
      );

      final Map<int, List<BestOf3MatchResult>> resultsByAlliance = {};
      final Map<int, int> playedByAlliance = {};

      for (final row in result.rows) {
        final data = row.assoc();
        final allianceId = int.parse(data['alliance_id'].toString());
        final resultObj = BestOf3MatchResult.fromMap(data);

        resultsByAlliance.putIfAbsent(allianceId, () => []).add(resultObj);
        playedByAlliance[allianceId] = (playedByAlliance[allianceId] ?? 0) + 1;
      }

      // Compute wins by counting completed rows grouped by winner_alliance_id
      final Map<int, int> winsByAlliance = {};
      try {
        final winRes = await conn.execute(
  """
  SELECT winner_alliance_id, COUNT(DISTINCT CONCAT(match_round, ':', match_position, ':', match_number, ':', bracket_side)) as cnt
  FROM tbl_championship_bestof3
  WHERE category_id = :catId AND is_completed = 1 AND winner_alliance_id IS NOT NULL AND winner_alliance_id != 0
  GROUP BY winner_alliance_id
""",
  {"catId": categoryId},
);

        for (final wrow in winRes.rows) {
          final w = wrow.assoc();
          final wid =
              int.tryParse(w['winner_alliance_id']?.toString() ?? '0') ?? 0;
          final cnt = int.tryParse(w['cnt']?.toString() ?? '0') ?? 0;
          if (wid > 0) winsByAlliance[wid] = cnt;
        }
      } catch (e) {
        // Fallback: compute distinct wins from loaded rows if the grouped query fails
        final Map<int, Set<String>> seenWins = {};
        for (final entry in resultsByAlliance.entries) {
          final list = entry.value;
          for (final r in list) {
            if (!r.isCompleted || r.winnerAllianceId == 0) continue;
            final key = '${r.matchRound}:${r.matchPosition}:${r.matchNumber}';
            seenWins.putIfAbsent(r.winnerAllianceId, () => <String>{}).add(key);
          }
        }
        for (final e in seenWins.entries) {
          winsByAlliance[e.key] = e.value.length;
        }
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
    required String bracketSide,
  }) async {
    try {
      final allianceFinal = allianceScore - allianceViolation;
      final opponentFinal = opponentScore - opponentViolation;
      final winnerId = allianceFinal > opponentFinal
          ? allianceId
          : opponentAllianceId;

      print(
        "📝 Saving match $matchNumber: Alliance $allianceId ($allianceFinal) vs Opponent $opponentAllianceId ($opponentFinal) -> Winner: $winnerId",
      );

      // Save the result for the first alliance
      await DBHelper.executeDual(
        """
        INSERT INTO tbl_championship_bestof3 
          (category_id, alliance_id, opponent_alliance_id, match_number, 
           alliance_score, alliance_violation, opponent_score, opponent_violation,
           winner_alliance_id, is_completed, match_round, match_position, bracket_side)
        VALUES
          (:catId, :allianceId, :opponentId, :matchNum,
           :allianceScore, :allianceViolation, :opponentScore, :opponentViolation,
           :winnerId, 1, :roundNum, :matchPos, :bracketSide)
        ON DUPLICATE KEY UPDATE
          alliance_score = :allianceScore,
          alliance_violation = :allianceViolation,
          opponent_score = :opponentScore,
          opponent_violation = :opponentViolation,
          winner_alliance_id = :winnerId,
          is_completed = 1,
          match_round = :roundNum,
          match_position = :matchPos,
          bracket_side = :bracketSide
      """,
        {
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
          "bracketSide": bracketSide,
        },
      );

      // Save mirrored result for the opponent
      await DBHelper.executeDual(
        """
        INSERT INTO tbl_championship_bestof3 
          (category_id, alliance_id, opponent_alliance_id, match_number, 
           alliance_score, alliance_violation, opponent_score, opponent_violation,
           winner_alliance_id, is_completed, match_round, match_position, bracket_side)
        VALUES
          (:catId, :opponentId, :allianceId, :matchNum,
           :opponentScore, :opponentViolation, :allianceScore, :allianceViolation,
           :winnerId, 1, :roundNum, :matchPos, :bracketSide)
        ON DUPLICATE KEY UPDATE
          alliance_score = :opponentScore,
          alliance_violation = :opponentViolation,
          opponent_score = :allianceScore,
          opponent_violation = :allianceViolation,
          winner_alliance_id = :winnerId,
          is_completed = 1,
          match_round = :roundNum,
          match_position = :matchPos,
          bracket_side = :bracketSide
      """,
        {
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
          "bracketSide": bracketSide,
        },
      );

      print(
        "✅ Saved Best-of-3 match $matchNumber result for category $categoryId",
      );

// Reload data to get updated results
// Reload data to get updated results
await _loadBestOf3Results(categoryId);
await _loadChampionshipStandings(categoryId);

await _reorderChampionshipStandings(categoryId);

// Force UI refresh with a microtask delay
if (mounted) {
  await Future.microtask(() {
    setState(() {});
  });
}

      // Now check if the series is finished after this save
      try {
        final conn = await DBHelper.getConnection();

        // Get all completed matches for this series
        final seriesRes = await conn.execute(
  """
  SELECT
    COUNT(DISTINCT CASE WHEN winner_alliance_id = :aId AND is_completed = 1 THEN match_number END) AS wins_a,
    COUNT(DISTINCT CASE WHEN winner_alliance_id = :oId AND is_completed = 1 THEN match_number END) AS wins_o,
    COUNT(DISTINCT CASE WHEN is_completed = 1 THEN match_number END) AS completed
  FROM tbl_championship_bestof3
  WHERE category_id = :catId 
    AND match_round = :roundNum 
    AND match_position = :matchPos
    AND bracket_side = :bracketSide
""",
  {
    "aId": allianceId,
    "oId": opponentAllianceId,
    "catId": categoryId,
    "roundNum": roundNumber,
    "matchPos": matchPosition,
    "bracketSide": bracketSide,  // Add this!
  },
);

        int winsA = 0;
        int winsO = 0;
        int completed = 0;
        if (seriesRes.rows.isNotEmpty) {
          final row = seriesRes.rows.first.assoc();
          winsA = int.tryParse(row['wins_a']?.toString() ?? '0') ?? 0;
          winsO = int.tryParse(row['wins_o']?.toString() ?? '0') ?? 0;
          completed = int.tryParse(row['completed']?.toString() ?? '0') ?? 0;
        }

        print("🔍 SERIES CHECK: winsA=$winsA, winsO=$winsO, completed=$completed");

        final bool seriesFinished = (winsA >= 2) || (winsO >= 2) || (completed >= 3);
        print("🔍 SERIES FINISHED: $seriesFinished");
        try {
          print("🔍 BEFORE SERIES CHECK: seriesFinished = ${seriesFinished}, winsA=$winsA, winsO=$winsO, completed=$completed");
        } catch (_) {}

        if (seriesFinished) {
          int seriesWinner = 0;
          if (winsA > winsO)
            seriesWinner = allianceId;
          else if (winsO > winsA) seriesWinner = opponentAllianceId;

          if (seriesWinner > 0) {
            print("🎯 Series finished! Winner: $seriesWinner");

            // Make sure we have the correct match_id for this series
            final sel = await conn.execute(
              """
      SELECT match_id FROM tbl_double_elimination
      WHERE category_id = :catId 
        AND round_number = :roundNum 
        AND match_position = :matchPos
        AND bracket_side = :bracketSide 
      LIMIT 1
      """,
              {
                "catId": categoryId,
                "roundNum": roundNumber,
                "matchPos": matchPosition,
                "bracketSide": bracketSide,
              },
            );

            if (sel.rows.isNotEmpty) {
              final matchId = int.parse(sel.rows.first.assoc()['match_id']?.toString() ?? '0');
              if (matchId > 0) {
                print("🎯 Calling updateBracketWinner for match $matchId with winner $seriesWinner");
                await DBHelper.updateBracketWinner(matchId, seriesWinner);
                print("✅ Propagated winner $seriesWinner to match $matchId");

                await _loadChampionshipStandings(categoryId);

if (mounted) {
  setState(() {});
}
              }
            } else {
              print("⚠️ Could not find match_id for series R${roundNumber}P${matchPosition} $bracketSide");
            }
          }
        } else {
          print("📊 Series not finished yet ($winsA-$winsO), waiting for more matches");
        }
      } catch (e) {
        print('ℹ️ Could not propagate winner to bracket: $e');
      }
    } catch (e) {
      print("❌ Error saving Best-of-3 result: $e");
      rethrow;
    }
  }

  // Show Best-of-3 match dialog
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
    bool readOnly = false,
  }) {
    try {
      print('🔵 DIALOG OPEN: match $matchNumber (R${roundNumber}P${matchPosition} $bracketSide)');
      print('   readOnly = $readOnly');
      print('   existingResult = ${existingResult != null}');
    } catch (_) {}
    // FIX: Only pre-fill scores if the result is valid for THIS EXACT match
    // (same round, position, bracket side, and match number)
    final bool isValidResult =
        existingResult != null &&
        existingResult.isCompleted &&
        existingResult.matchRound == roundNumber &&
        existingResult.matchPosition == matchPosition &&
        existingResult.matchNumber == matchNumber &&
        existingResult.bracketSide == bracketSide;

    final allianceScoreController = TextEditingController(
      text: isValidResult ? existingResult!.alliance1Score.toString() : '0',
    );
    final allianceViolationController = TextEditingController(
      text: isValidResult ? existingResult!.alliance1Violation.toString() : '0',
    );
    final opponentScoreController = TextEditingController(
      text: isValidResult ? existingResult!.alliance2Score.toString() : '0',
    );
    final opponentViolationController = TextEditingController(
      text: isValidResult ? existingResult!.alliance2Violation.toString() : '0',
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

    final allResults = _bestOf3Results[categoryId] ?? {};

        final allianceEntries = (allResults[allianceId] ?? [])
        .where(
          (r) =>
              r.matchRound == roundNumber &&
              r.matchPosition == matchPosition &&
              r.bracketSide == bracketSide,
        )
        .toList();
    final opponentEntries = (allResults[opponentAllianceId] ?? [])
        .where(
          (r) =>
              r.matchRound == roundNumber &&
              r.matchPosition == matchPosition &&
              r.bracketSide == bracketSide,
        )
        .toList();

    final Map<String, BestOf3MatchResult> uniqueResults = {};

    for (final result in allianceEntries) {
      if (result.isCompleted) {
        final key =
            '${result.matchRound}:${result.matchPosition}:${result.matchNumber}';
        uniqueResults[key] = result;
      }
    }
    for (final result in opponentEntries) {
      if (result.isCompleted) {
        final key =
            '${result.matchRound}:${result.matchPosition}:${result.matchNumber}';
        if (!uniqueResults.containsKey(key)) uniqueResults[key] = result;
      }
    }

    int winsA = 0;
    int winsO = 0;
    for (final result in uniqueResults.values) {
      if (result.winnerAllianceId == allianceId) {
        winsA++;
      } else if (result.winnerAllianceId == opponentAllianceId) {
        winsO++;
      }
    }

    final int completedCount = uniqueResults.length;
    final bool seriesCompleted =
        (winsA >= 2) || (winsO >= 2) || (completedCount >= 3);
    final bool seriesTied = (winsA == 1 && winsO == 1 && completedCount == 2);

    final Map<int, BestOf3MatchResult> matchResults = {};
    // Get ALL results for this alliance in this specific round/position/bracketSide
    final allResultsForAlliance =
        _bestOf3Results[categoryId]?[allianceId] ?? [];
    for (final result in allResultsForAlliance) {
      if (result.matchRound == roundNumber &&
          result.matchPosition == matchPosition &&
          result.bracketSide == bracketSide &&
          result.isCompleted) {
        matchResults[result.matchNumber] = result;
      }
    }
    // Also get opponent results for the same criteria
    final allResultsForOpponent =
        _bestOf3Results[categoryId]?[opponentAllianceId] ?? [];
    for (final result in allResultsForOpponent) {
      if (result.matchRound == roundNumber &&
          result.matchPosition == matchPosition &&
          result.bracketSide == bracketSide &&
          result.isCompleted) {
        if (!matchResults.containsKey(result.matchNumber)) {
          matchResults[result.matchNumber] = result;
        }
      }
    }

    final bool match3Needed = seriesTied;
    final bool match3Disabled =
        (matchNumber == 3) && ((winsA >= 2) || (winsO >= 2) || seriesCompleted);

    final int prevMatchNumber = matchNumber - 1;
    final int nextMatchNumber = matchNumber + 1;

    final bool hasPrevMatch =
        prevMatchNumber >= 1 &&
        (matchResults.containsKey(prevMatchNumber) ||
            prevMatchNumber <= completedCount);
    final bool hasNextMatch =
        nextMatchNumber <= 3 &&
        ((nextMatchNumber == 3
            ? match3Needed || matchResults.containsKey(3)
            : true));

    final Map<int, AllianceMatchPair> pairings =
        _allianceMatchPairings[categoryId] ?? {};

    // Get ALL rounds for this alliance, using a unique key that includes bracket side
    final List<Map<String, dynamic>> allRoundsData = [];
    for (final pair in pairings.values) {
      if (pair.alliance1Id == allianceId || pair.alliance2Id == allianceId) {
        // Create a unique key that includes bracket side to differentiate same round numbers
        final roundKey = '${pair.roundNumber}_${pair.bracketSide}';
        final exists = allRoundsData.any((r) => r['key'] == roundKey);
        if (!exists) {
          allRoundsData.add({
            'roundNumber': pair.roundNumber,
            'bracketSide': pair.bracketSide,
            'key': roundKey,
          });
        }
      }
    }
    // Sort by round number, then by bracket side (winners first, then losers)
    // Define order: winners first, then losers, then grand finals
final sideOrder = {'winners': 1, 'losers': 2, 'grand': 3};

allRoundsData.sort((a, b) {
  final orderA = sideOrder[a['bracketSide']] ?? 4;
  final orderB = sideOrder[b['bracketSide']] ?? 4;
  
  if (orderA != orderB) {
    return orderA.compareTo(orderB);
  }
  
  // Within the same bracket, sort by round number
  return (a['roundNumber'] as int).compareTo(b['roundNumber'] as int);
});

    final int currentRoundIndex = allRoundsData.indexWhere(
      (r) => r['roundNumber'] == roundNumber && r['bracketSide'] == bracketSide,
    );
    final bool hasPrevRound = currentRoundIndex > 0;
    final bool hasNextRound = currentRoundIndex < allRoundsData.length - 1;

    void navigateToRound(Map<String, dynamic> targetRoundData) {
      final targetRound = targetRoundData['roundNumber'];
      final targetSide = targetRoundData['bracketSide'];

      AllianceMatchPair? targetPair;
      for (final pair in pairings.values) {
        if (pair.roundNumber == targetRound &&
            pair.bracketSide == targetSide &&
            (pair.alliance1Id == allianceId ||
                pair.alliance2Id == allianceId)) {
          targetPair = pair;
          break;
        }
      }

      if (targetPair != null) {
        final targetAllianceId = allianceId;
        final targetOpponentId = (targetPair.alliance1Id == allianceId)
            ? targetPair.alliance2Id
            : targetPair.alliance1Id;
        final targetAllianceName = (targetPair.alliance1Id == allianceId)
            ? targetPair.alliance1Name
            : targetPair.alliance2Name;
        final targetOpponentName = (targetPair.alliance1Id == allianceId)
            ? targetPair.alliance2Name
            : targetPair.alliance1Name;
        final targetMatchPosition = targetPair.matchPosition;
        final targetBracketSide = targetPair.bracketSide;

        // Get the match results for this round
        final targetResults = (allResults[targetAllianceId] ?? [])
            .where(
              (r) =>
                  r.matchRound == targetRound &&
                  r.matchPosition == targetMatchPosition &&
                  r.bracketSide == targetBracketSide,
            )
            .toList();

        // Get the first match result (Match 1) for this round - only if completed
        BestOf3MatchResult? existing;
        for (final r in targetResults) {
          if (r.matchNumber == 1 && r.isCompleted) {
            existing = r;
            break;
          }
        }

        Navigator.pop(context);
        _showBestOf3MatchDialog(
          categoryId: categoryId,
          allianceId: targetAllianceId,
          opponentAllianceId: targetOpponentId,
          matchNumber: 1,
          roundNumber: targetRound,
          matchPosition: targetMatchPosition,
          bracketSide: targetBracketSide,
          allianceName: targetAllianceName,
          opponentName: targetOpponentName,
          existingResult: existing,
          onRefresh: onRefresh,
          readOnly: existing != null && existing.isCompleted,
        );
      }
    }

    void navigateToMatchInSeries(int newMatchNumber) {
      // Get the specific result for the new match number from the database
      // Must match: roundNumber, matchPosition, bracketSide, AND matchNumber
      final allResultsForAlliance =
          _bestOf3Results[categoryId]?[allianceId] ?? [];
      BestOf3MatchResult? specificExisting;
      for (final r in allResultsForAlliance) {
        if (r.matchNumber == newMatchNumber &&
            r.matchRound == roundNumber &&
            r.matchPosition == matchPosition &&
            r.bracketSide == bracketSide) {
          specificExisting = r;
          break;
        }
      }

      // Also check opponent results (though they should be mirrored)
      if (specificExisting == null) {
        final allResultsForOpponent =
            _bestOf3Results[categoryId]?[opponentAllianceId] ?? [];
        for (final r in allResultsForOpponent) {
          if (r.matchNumber == newMatchNumber &&
              r.matchRound == roundNumber &&
              r.matchPosition == matchPosition &&
              r.bracketSide == bracketSide) {
            specificExisting = r;
            break;
          }
        }
      }

      // Determine if this specific match is completed
      final bool matchIsCompleted =
          specificExisting != null && specificExisting.isCompleted;

      Navigator.pop(context);
      _showBestOf3MatchDialog(
        categoryId: categoryId,
        allianceId: allianceId,
        opponentAllianceId: opponentAllianceId,
        matchNumber: newMatchNumber,
        roundNumber: roundNumber,
        matchPosition: matchPosition,
        bracketSide: bracketSide,
        allianceName: allianceName,
        opponentName: opponentName,
        existingResult: specificExisting,
        onRefresh: onRefresh,
        readOnly:
            matchIsCompleted, // Only read-only if this specific match is completed
      );
    }

    String getMatchDisplay(int matchNum) {
      // Use aggregated counts for display across rounds for this match number
      final agg = _countWinsForMatchNumberAcrossRounds(
        categoryId,
        allianceId,
        opponentAllianceId,
        matchPosition,
        matchNum,
      );
      final a = agg['winsA'] ?? 0;
      final o = agg['winsB'] ?? 0;
      final completed = agg['completed'] ?? 0;

      if (a > 0 || o > 0) return '$a-$o';
      if (matchNum == 3 && (winsA >= 2 || winsO >= 2)) return 'N/A';
      if (matchNum == 3 && seriesTied && !seriesCompleted) return 'Ready';
      return 'Pending';
    }

    String getRoundDisplayName(int round, String side) {
      if (side == 'winners') {
        switch (round) {
          case 1:
            return "Winner's Bracket Round 1";
          case 2:
            return "Winner's Bracket Round 2";
          case 3:
            return "Winner's Bracket Round 3";
          case 4:
            return "Winner's Bracket Semi-Final";
          case 5:
            return "Winner's Bracket Final";
          default:
            return "Winner's Bracket Round $round";
        }
      } else if (side == 'losers') {
        switch (round) {
          case 1:
            return "Loser's Bracket Round 1";
          case 2:
            return "Loser's Bracket Round 2";
          case 3:
            return "Loser's Bracket Round 3";
          case 4:
            return "Loser's Bracket Final";
          default:
            return "Loser's Bracket Round $round";
        }
      } else if (side == 'grand') {
        if (round == 1) return "Grand Final - Match 1";
        if (round == 2) return "Grand Final - Match 2 (Reset)";
        return "Grand Final";
      }
      return "Match";
    }

    final titleText = '${getRoundDisplayName(roundNumber, bracketSide)}';

    // Use aggregated series wins across rounds for status
    final aggSeries = _countSeriesWins(
      categoryId,
      allianceId,
      opponentAllianceId,
      matchPosition,
    );
    final aggWinsA = aggSeries['winsA'] ?? 0;
    final aggWinsO = aggSeries['winsB'] ?? 0;
    final aggCompleted = aggSeries['completed'] ?? 0;

    String seriesStatus;
    if (aggWinsA >= 2) {
      seriesStatus =
          'Series Complete: $aggWinsA - $aggWinsO ($allianceName wins)';
    } else if (aggWinsO >= 2) {
      seriesStatus =
          'Series Complete: $aggWinsA - $aggWinsO ($opponentName wins)';
    } else if (aggCompleted >= 3) {
      seriesStatus = 'Series Complete: $aggWinsA - $aggWinsO';
    } else if (aggWinsA == 1 && aggWinsO == 1 && aggCompleted == 2) {
      seriesStatus = 'Series Tied: $aggWinsA - $aggWinsO (Match 3 Available)';
    } else {
      seriesStatus = 'Series Status: $aggWinsA - $aggWinsO (Best of 3)';
    }

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

                    // Determine editability using aggregated series completion for THIS specific round
          final aggSeriesForEdit = _countSeriesWinsForRound(
            categoryId,
            allianceId,
            opponentAllianceId,
            roundNumber,
            matchPosition,
            bracketSide,
          );
          final aggWinsAForEdit = aggSeriesForEdit['winsA'] ?? 0;
          final aggWinsOForEdit = aggSeriesForEdit['winsB'] ?? 0;
          final aggCompletedForEdit = aggSeriesForEdit['completed'] ?? 0;

          final bool aggSeriesCompleted =
              (aggWinsAForEdit >= 2) ||
              (aggWinsOForEdit >= 2) ||
              (aggCompletedForEdit >= 3);

          final bool canEditMatch3 =
              (matchNumber == 3) &&
              (aggWinsAForEdit == 1 && aggWinsOForEdit == 1) &&
              !aggSeriesCompleted &&
              !matchResults.containsKey(3);
          final bool canEdit =
              !readOnly &&
              !aggSeriesCompleted &&
              !(matchNumber == 3 &&
                  (aggWinsAForEdit >= 2 || aggWinsOForEdit >= 2));

          return Dialog(
            backgroundColor: Colors.transparent,
            child: Container(
              width: 550,
              constraints: const BoxConstraints(maxHeight: 750),
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
                  Container(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            GestureDetector(
                              onTap: hasPrevRound
                                  ? () => navigateToRound(
                                      allRoundsData[currentRoundIndex - 1],
                                    )
                                  : null,
                              child: Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: hasPrevRound
                                      ? const Color(0xFFFFD700).withOpacity(0.2)
                                      : Colors.white.withOpacity(0.05),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: hasPrevRound
                                        ? const Color(0xFFFFD700)
                                        : Colors.white.withOpacity(0.1),
                                    width: hasPrevRound ? 1.5 : 1,
                                  ),
                                ),
                                child: Icon(
                                  Icons.chevron_left,
                                  color: hasPrevRound
                                      ? const Color(0xFFFFD700)
                                      : Colors.white24,
                                  size: 28,
                                ),
                              ),
                            ),
                            const SizedBox(width: 16),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 20,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(
                                  0xFFFFD700,
                                ).withOpacity(0.15),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: const Color(
                                    0xFFFFD700,
                                  ).withOpacity(0.4),
                                ),
                              ),
                              child: Column(
                                children: [
                                  Text(
                                    titleText,
                                    style: const TextStyle(
                                      color: Color(0xFFFFD700),
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                      letterSpacing: 1.5,
                                    ),
                                  ),
                                  Text(
                                    'Match $matchNumber of 3 in this series',
                                    style: const TextStyle(
                                      color: Color(0xFFFFD700),
                                      fontSize: 11,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 16),
                            GestureDetector(
                              onTap: hasNextRound
                                  ? () => navigateToRound(
                                      allRoundsData[currentRoundIndex + 1],
                                    )
                                  : null,
                              child: Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: hasNextRound
                                      ? const Color(0xFFFFD700).withOpacity(0.2)
                                      : Colors.white.withOpacity(0.05),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: hasNextRound
                                        ? const Color(0xFFFFD700)
                                        : Colors.white.withOpacity(0.1),
                                    width: hasNextRound ? 1.5 : 1,
                                  ),
                                ),
                                child: Icon(
                                  Icons.chevron_right,
                                  color: hasNextRound
                                      ? const Color(0xFFFFD700)
                                      : Colors.white24,
                                  size: 28,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: allRoundsData.map((roundData) {
                            final round = roundData['roundNumber'];
                            final side = roundData['bracketSide'];

                            final isCurrent =
                                (round == roundNumber && side == bracketSide);
                            final sideColor = side == 'winners'
                                ? const Color(0xFF00CFFF)
                                : (side == 'losers'
                                      ? const Color(0xFFFF6B6B)
                                      : const Color(0xFFFFD700));

                            String roundLabel = '';
                            if (side == 'winners') {
                              roundLabel = 'W$round';
                            } else if (side == 'losers') {
                              roundLabel = 'L$round';
                            } else {
                              roundLabel = 'GF$round';
                            }

                            return GestureDetector(
                              onTap: isCurrent
                                  ? null
                                  : () => navigateToRound(roundData),
                              child: Container(
                                margin: const EdgeInsets.symmetric(
                                  horizontal: 4,
                                ),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: isCurrent
                                      ? sideColor.withOpacity(0.2)
                                      : Colors.transparent,
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                    color: isCurrent
                                        ? sideColor
                                        : Colors.white.withOpacity(0.2),
                                    width: isCurrent ? 1.5 : 1,
                                  ),
                                ),
                                child: Text(
                                  roundLabel,
                                  style: TextStyle(
                                    color: isCurrent
                                        ? sideColor
                                        : Colors.white54,
                                    fontSize: 11,
                                    fontWeight: isCurrent
                                        ? FontWeight.bold
                                        : FontWeight.normal,
                                  ),
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            GestureDetector(
                              onTap: hasPrevMatch
                                  ? () =>
                                        navigateToMatchInSeries(prevMatchNumber)
                                  : null,
                              child: Container(
                                padding: const EdgeInsets.all(6),
                                decoration: BoxDecoration(
                                  color: hasPrevMatch
                                      ? const Color(
                                          0xFFFFD700,
                                        ).withOpacity(0.15)
                                      : Colors.white.withOpacity(0.05),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Icon(
                                  Icons.chevron_left,
                                  color: hasPrevMatch
                                      ? const Color(0xFFFFD700)
                                      : Colors.white24,
                                  size: 20,
                                ),
                              ),
                            ),
                            ...['1', '2', '3'].map((num) {
                              final status = getMatchDisplay(int.parse(num));
                              final isCurrent = matchNumber == int.parse(num);
                              return Container(
                                margin: const EdgeInsets.symmetric(
                                  horizontal: 4,
                                ),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: isCurrent
                                      ? const Color(0xFFFFD700).withOpacity(0.2)
                                      : Colors.transparent,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: isCurrent
                                        ? const Color(0xFFFFD700)
                                        : Colors.white.withOpacity(0.2),
                                    width: isCurrent ? 1.5 : 1,
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      'M$num',
                                      style: TextStyle(
                                        color: isCurrent
                                            ? const Color(0xFFFFD700)
                                            : Colors.white54,
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      status,
                                      style: TextStyle(
                                        color: status == '1-0'
                                            ? Colors.green
                                            : status == '0-1'
                                            ? Colors.red
                                            : status == 'Ready'
                                            ? const Color(0xFFFFD700)
                                            : status == 'N/A'
                                            ? Colors.orange
                                            : Colors.white38,
                                        fontSize: 9,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }).toList(),
                            GestureDetector(
                              onTap: hasNextMatch
                                  ? () =>
                                        navigateToMatchInSeries(nextMatchNumber)
                                  : null,
                              child: Container(
                                padding: const EdgeInsets.all(6),
                                decoration: BoxDecoration(
                                  color: hasNextMatch
                                      ? const Color(
                                          0xFFFFD700,
                                        ).withOpacity(0.15)
                                      : Colors.white.withOpacity(0.05),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Icon(
                                  Icons.chevron_right,
                                  color: hasNextMatch
                                      ? const Color(0xFFFFD700)
                                      : Colors.white24,
                                  size: 20,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: seriesCompleted
                                ? Colors.green.withOpacity(0.15)
                                : (seriesTied
                                      ? const Color(
                                          0xFFFFD700,
                                        ).withOpacity(0.15)
                                      : Colors.white.withOpacity(0.05)),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            seriesStatus,
                            style: TextStyle(
                              color: seriesCompleted
                                  ? Colors.green
                                  : (seriesTied
                                        ? const Color(0xFFFFD700)
                                        : Colors.white70),
                              fontSize: 11,
                              fontWeight: (seriesCompleted || seriesTied)
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 8),

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
                            color: isWinnerAlliance
                                ? Colors.green
                                : Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                          textAlign: TextAlign.center,
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
                                readOnly:
                                    readOnly ||
                                    seriesCompleted ||
                                    (matchNumber == 3 && !canEditMatch3),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _buildBestOf3ScoreField(
                                label: 'Violation (-)',
                                controller: allianceViolationController,
                                color: Colors.redAccent,
                                onChanged: (_) => setDialogState(() {}),
                                readOnly:
                                    readOnly ||
                                    seriesCompleted ||
                                    (matchNumber == 3 && !canEditMatch3),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            const Text(
                              'Final Score: ',
                              style: TextStyle(color: Colors.white70),
                            ),
                            Text(
                              '${getAllianceFinal()}',
                              style: TextStyle(
                                color: isWinnerAlliance
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

                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: !isWinnerAlliance && opponentFinal > allianceFinal
                          ? Colors.green.withOpacity(0.1)
                          : Colors.white.withOpacity(0.05),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color:
                            !isWinnerAlliance && opponentFinal > allianceFinal
                            ? Colors.green.withOpacity(0.5)
                            : Colors.white.withOpacity(0.1),
                      ),
                    ),
                    child: Column(
                      children: [
                        Text(
                          opponentName,
                          style: TextStyle(
                            color:
                                !isWinnerAlliance &&
                                    opponentFinal > allianceFinal
                                ? Colors.green
                                : Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                          textAlign: TextAlign.center,
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
                                readOnly:
                                    readOnly ||
                                    seriesCompleted ||
                                    (matchNumber == 3 && !canEditMatch3),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _buildBestOf3ScoreField(
                                label: 'Violation (-)',
                                controller: opponentViolationController,
                                color: Colors.redAccent,
                                onChanged: (_) => setDialogState(() {}),
                                readOnly:
                                    readOnly ||
                                    seriesCompleted ||
                                    (matchNumber == 3 && !canEditMatch3),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            const Text(
                              'Final Score: ',
                              style: TextStyle(color: Colors.white70),
                            ),
                            Text(
                              '${getOpponentFinal()}',
                              style: TextStyle(
                                color:
                                    !isWinnerAlliance &&
                                        opponentFinal > allianceFinal
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
                      border: Border.all(
                        color: const Color(0xFFFFD700).withOpacity(0.3),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.emoji_events,
                          color: Color(0xFFFFD700),
                          size: 20,
                        ),
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

                  // Dialog button debug: show aggregated and edit permissions
                  (() {
                    try {
                      print("   BUTTON DEBUG: readOnly=$readOnly, seriesCompleted=$seriesCompleted, matchNumber=$matchNumber, winsA=$winsA, winsO=$winsO, seriesTied=$seriesTied");
                      print("   aggWinsAForEdit=$aggWinsAForEdit, aggWinsOForEdit=$aggWinsOForEdit, aggSeriesCompleted=$aggSeriesCompleted");
                      print("   canEditMatch3=$canEditMatch3");
                      print("   canEdit=$canEdit");
                    } catch (_) {}
                    return SizedBox.shrink();
                  })(),

                  Row(
                    children: [
                      Expanded(
                        child: TextButton(
                          onPressed: () => Navigator.pop(ctx),
                          style: TextButton.styleFrom(
                            side: BorderSide(
                              color: Colors.white.withOpacity(0.2),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
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
                            try {
                              print('   BUTTON PRESSED - readOnly=$readOnly, seriesCompleted=$seriesCompleted');
                            } catch (_) {}
                            try {
                              print('   BUTTON CHECK: readOnly=$readOnly, seriesCompleted=$seriesCompleted, matchNumber=$matchNumber, winsA=$winsA, winsO=$winsO, seriesTied=$seriesTied');
                            } catch (_) {}
                            if (readOnly ||
                                seriesCompleted ||
                                (matchNumber == 3 &&
                                    (winsA >= 2 || winsO >= 2) &&
                                    !seriesTied)) {
                              Navigator.pop(ctx);
                              return;
                            }
                            try {
                              await _saveBestOf3MatchResult(
                                categoryId: categoryId,
                                allianceId: allianceId,
                                opponentAllianceId: opponentAllianceId,
                                matchNumber: matchNumber,
                                allianceScore:
                                    int.tryParse(
                                      allianceScoreController.text,
                                    ) ??
                                    0,
                                allianceViolation:
                                    int.tryParse(
                                      allianceViolationController.text,
                                    ) ??
                                    0,
                                opponentScore:
                                    int.tryParse(
                                      opponentScoreController.text,
                                    ) ??
                                    0,
                                opponentViolation:
                                    int.tryParse(
                                      opponentViolationController.text,
                                    ) ??
                                    0,
                                roundNumber: roundNumber,
                                matchPosition: matchPosition,
                                bracketSide: bracketSide,
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
                            backgroundColor:
                                (readOnly ||
                                    seriesCompleted ||
                                    (matchNumber == 3 &&
                                        (winsA >= 2 || winsO >= 2) &&
                                        !seriesTied))
                                ? Colors.white24
                                : const Color(0xFFFFD700),
                            foregroundColor: Colors.black,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                          child: Text(
                            (readOnly ||
                                    seriesCompleted ||
                                    (matchNumber == 3 &&
                                        (winsA >= 2 || winsO >= 2) &&
                                        !seriesTied))
                                ? 'CLOSE'
                                : 'SAVE RESULT',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
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
    bool readOnly = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: color,
            fontSize: 10,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 4),
        TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          style: TextStyle(
            color: color,
            fontSize: 14,
            fontWeight: FontWeight.bold,
          ),
          onChanged: readOnly ? (_) {} : onChanged,
          readOnly: readOnly,
          decoration: InputDecoration(
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 8,
              vertical: 8,
            ),
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

  // Helper method to check if a specific match's series is completed
  bool _isMatchSeriesCompleted(
    int categoryId,
    int roundNumber,
    int matchPosition,
  ) {
    final allResults = _bestOf3Results[categoryId] ?? {};

    final pairings = _allianceMatchPairings[categoryId] ?? {};
    int? alliance1Id;
    int? alliance2Id;

    for (final pair in pairings.values) {
      if (pair.roundNumber == roundNumber &&
          pair.matchPosition == matchPosition) {
        alliance1Id = pair.alliance1Id;
        alliance2Id = pair.alliance2Id;
        break;
      }
    }

    if (alliance1Id == null || alliance2Id == null) return false;

    final alliance1Results = allResults[alliance1Id] ?? [];
    final alliance2Results = allResults[alliance2Id] ?? [];

    final Set<int> completedMatches = {};
    int winsA = 0;
    int winsO = 0;

    for (final r in alliance1Results) {
      if (r.matchRound == roundNumber &&
          r.matchPosition == matchPosition &&
          r.isCompleted) {
        completedMatches.add(r.matchNumber);
        if (r.winnerAllianceId == alliance1Id) {
          winsA++;
        } else if (r.winnerAllianceId == alliance2Id) {
          winsO++;
        }
      }
    }
    for (final r in alliance2Results) {
      if (r.matchRound == roundNumber &&
          r.matchPosition == matchPosition &&
          r.isCompleted) {
        if (!completedMatches.contains(r.matchNumber)) {
          completedMatches.add(r.matchNumber);
          if (r.winnerAllianceId == alliance1Id) {
            winsA++;
          } else if (r.winnerAllianceId == alliance2Id) {
            winsO++;
          }
        }
      }
    }

    return (winsA >= 2) || (winsO >= 2) || (completedMatches.length >= 3);
  }

  // Count aggregated series wins across all rounds for a pairing (by matchPosition)
  Map<String, int> _countSeriesWins(
    int categoryId,
    int allianceAId,
    int allianceBId,
    int matchPosition,
  ) {
    final allResults = _bestOf3Results[categoryId] ?? {};
    final allianceAResults = allResults[allianceAId] ?? [];
    final allianceBResults = allResults[allianceBId] ?? [];

    final Set<String> completedKeys = {};
    int winsA = 0;
    int winsB = 0;

    for (final r in allianceAResults) {
      if (r.matchPosition == matchPosition &&
          r.isCompleted &&
          r.opponentAllianceId == allianceBId) {
        final key = '${r.matchRound}:${r.matchPosition}:${r.matchNumber}';
        if (!completedKeys.contains(key)) {
          completedKeys.add(key);
          if (r.winnerAllianceId == allianceAId)
            winsA++;
          else if (r.winnerAllianceId == allianceBId)
            winsB++;
        }
      }
    }
    for (final r in allianceBResults) {
      if (r.matchPosition == matchPosition &&
          r.isCompleted &&
          r.opponentAllianceId == allianceAId) {
        final key = '${r.matchRound}:${r.matchPosition}:${r.matchNumber}';
        if (!completedKeys.contains(key)) {
          completedKeys.add(key);
          if (r.winnerAllianceId == allianceAId)
            winsA++;
          else if (r.winnerAllianceId == allianceBId)
            winsB++;
        }
      }
    }

    return {'winsA': winsA, 'winsB': winsB, 'completed': completedKeys.length};
  }

    // Count series wins for a specific round only
  Map<String, int> _countSeriesWinsForRound(
    int categoryId,
    int allianceAId,
    int allianceBId,
    int roundNumber,
    int matchPosition,
    String bracketSide,
  ) {
    final allResults = _bestOf3Results[categoryId] ?? {};
    final allianceAResults = allResults[allianceAId] ?? [];
    final allianceBResults = allResults[allianceBId] ?? [];

    final Set<String> completedKeys = {};
    int winsA = 0;
    int winsB = 0;

    for (final r in allianceAResults) {
      if (r.matchRound == roundNumber &&
          r.matchPosition == matchPosition &&
          r.bracketSide == bracketSide &&
          r.isCompleted &&
          r.opponentAllianceId == allianceBId) {
        final key = '${r.matchRound}:${r.matchPosition}:${r.matchNumber}';
        if (!completedKeys.contains(key)) {
          completedKeys.add(key);
          if (r.winnerAllianceId == allianceAId)
            winsA++;
          else if (r.winnerAllianceId == allianceBId)
            winsB++;
        }
      }
    }
    for (final r in allianceBResults) {
      if (r.matchRound == roundNumber &&
          r.matchPosition == matchPosition &&
          r.bracketSide == bracketSide &&
          r.isCompleted &&
          r.opponentAllianceId == allianceAId) {
        final key = '${r.matchRound}:${r.matchPosition}:${r.matchNumber}';
        if (!completedKeys.contains(key)) {
          completedKeys.add(key);
          if (r.winnerAllianceId == allianceAId)
            winsA++;
          else if (r.winnerAllianceId == allianceBId)
            winsB++;
        }
      }
    }

    return {'winsA': winsA, 'winsB': winsB, 'completed': completedKeys.length};
  }

  Map<String, int> _countWinsForMatchNumberAcrossRounds(
  int categoryId,
  int allianceAId,
  int allianceBId,
  int matchPosition,
  int matchNumber,
  [String? bracketSide]  // Add this parameter
) {
  final allResults = _bestOf3Results[categoryId] ?? {};
  
  int winsA = 0;
  int lossesA = 0;
  int completedCount = 0;
  
  final allianceAResults = allResults[allianceAId] ?? [];
  
  for (final r in allianceAResults) {
    // Add bracketSide filter
    if (bracketSide != null && r.bracketSide != bracketSide) continue;
    
    if (r.matchNumber == matchNumber && r.isCompleted) {
      completedCount++;
      if (r.winnerAllianceId == allianceAId) {
        winsA++;
      } else {
        lossesA++;
      }
    }
  }
  
  return {'winsA': winsA, 'winsB': lossesA, 'completed': completedCount};
}

  // Helper to get Grand Final 1 winner
  int? _getGrandFinal1Winner(int categoryId) {
    final allResults = _bestOf3Results[categoryId] ?? {};
    final pairings = _allianceMatchPairings[categoryId] ?? {};

    AllianceMatchPair? gf1Pair;
    for (final pair in pairings.values) {
      if (pair.bracketSide == 'grand' && pair.roundNumber == 1) {
        gf1Pair = pair;
        break;
      }
    }

    if (gf1Pair == null) return null;

    final alliance1Results = allResults[gf1Pair.alliance1Id] ?? [];
    final alliance2Results = allResults[gf1Pair.alliance2Id] ?? [];

    for (final r in alliance1Results) {
      if (r.matchRound == 1 && r.matchPosition == 1 && r.isCompleted) {
        return r.winnerAllianceId;
      }
    }
    for (final r in alliance2Results) {
      if (r.matchRound == 1 && r.matchPosition == 1 && r.isCompleted) {
        return r.winnerAllianceId;
      }
    }

    return null;
  }

  // Helper to get Loser's Bracket champion (L4 winner)
  int? _getLosersBracketChampion(int categoryId) {
    final allResults = _bestOf3Results[categoryId] ?? {};
    final pairings = _allianceMatchPairings[categoryId] ?? {};

    AllianceMatchPair? l4Pair;
    for (final pair in pairings.values) {
      if (pair.bracketSide == 'losers' && pair.roundNumber == 4) {
        l4Pair = pair;
        break;
      }
    }

    if (l4Pair == null) return null;

    final alliance1Results = allResults[l4Pair.alliance1Id] ?? [];
    final alliance2Results = allResults[l4Pair.alliance2Id] ?? [];

    for (final r in alliance1Results) {
      if (r.matchRound == 4 && r.matchPosition == 1 && r.isCompleted) {
        return r.winnerAllianceId;
      }
    }
    for (final r in alliance2Results) {
      if (r.matchRound == 4 && r.matchPosition == 1 && r.isCompleted) {
        return r.winnerAllianceId;
      }
    }

    return null;
  }

  Future<String> _getAllianceDisplayName(int categoryId, int allianceId) async {
    try {
      final conn = await DBHelper.getConnection();
      final res = await conn.execute(
        """
        SELECT COALESCE(t1.team_name, 'Unknown') as captain_name, COALESCE(t2.team_name, 'Unknown') as partner_name
        FROM tbl_alliance_selections a
        LEFT JOIN tbl_team t1 ON a.captain_team_id = t1.team_id
        LEFT JOIN tbl_team t2 ON a.partner_team_id = t2.team_id
        WHERE a.alliance_id = :aid
        LIMIT 1
      """,
        {"aid": allianceId},
      );
      if (res.rows.isNotEmpty) {
        final d = res.rows.first.assoc();
        return '${d['captain_name']} / ${d['partner_name']}';
      }
    } catch (e) {}
    return 'Alliance $allianceId';
  }

  // Load championship standings with win-based scoring
  Future<void> _loadChampionshipStandings(int categoryId) async {
    if (mounted) {
      setState(() {
        _isLoadingAllianceByCategory[categoryId] = true;
      });
    }

    try {
      await _loadMatchPairings(categoryId);
      await _loadBestOf3Results(categoryId);

      final conn = await DBHelper.getConnection();

      final alliancesResult = await conn.execute(
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
        {"catId": categoryId},
      );

      final alliances = alliancesResult.rows.map((r) => r.assoc()).toList();

      final Map<int, int> freshLosses = {};
    for (final alliance in alliances) {
      final allianceId = int.parse(alliance['alliance_id'].toString());
      freshLosses[allianceId] = _getAllianceLossCount(categoryId, allianceId);
    }
    
    if (mounted) {
      setState(() {
        _allianceLossesByCategory[categoryId] = freshLosses;
      });
    }

      if (alliances.isEmpty) {
        if (mounted) {
          setState(() {
            _championshipStandingsByCategory[categoryId] = [];
            _isLoadingAllianceByCategory[categoryId] = false;
          });
        }
        return;
      }

      // Create standings list
final List<ChampionshipAllianceStanding> standings = [];

for (final alliance in alliances) {
  final allianceId = int.parse(alliance['alliance_id'].toString());
  final allianceRank = int.parse(alliance['alliance_rank'].toString());
  
  // Calculate total match wins across all match numbers (M1, M2, M3)
  final match1Wins = _countWinsForMatchNumberAcrossRounds(categoryId, allianceId, 0, 0, 1)['winsA'] ?? 0;
  final match2Wins = _countWinsForMatchNumberAcrossRounds(categoryId, allianceId, 0, 0, 2)['winsA'] ?? 0;
  final match3Wins = _countWinsForMatchNumberAcrossRounds(categoryId, allianceId, 0, 0, 3)['winsA'] ?? 0;
  final totalMatchWins = match1Wins + match2Wins + match3Wins;

  standings.add(
    ChampionshipAllianceStanding(
      allianceId: allianceId,
      allianceRank: allianceRank,
      captainName: alliance['captain_name'].toString(),
      partnerName: alliance['partner_name'].toString(),
      matchScores: {},
      totalScore: totalMatchWins * 10,
    ),
  );
}


// Set the standings FIRST (unsorted)
if (mounted) {
  setState(() {
    _championshipStandingsByCategory[categoryId] = List.from(standings);
    _isLoadingAllianceByCategory[categoryId] = false;
  });
}

// NOW reorder based on current scores (this will recalculate totals and sort)
await _reorderChampionshipStandings(categoryId);


      try {
        final Map<int, AllianceMatchPair> pairings =
            _allianceMatchPairings[categoryId] ?? {};

        // Deduplicate pairings by round/position/side
        final Set<String> processedSeries = {};
        final List<AllianceMatchPair> uniquePairings = [];
        for (final pair in pairings.values) {
          final key = '${pair.roundNumber}_${pair.matchPosition}_${pair.bracketSide}';
          if (!processedSeries.contains(key)) {
            processedSeries.add(key);
            uniquePairings.add(pair);
          }
        }

        final Map<int, int> allianceLosses = {};
        for (final s in standings) {
          allianceLosses[s.allianceId] = 0;
        }

        // Use Best-of-3 results exclusively
        final matchResults = _bestOf3Results[categoryId] ?? {};

        print("📊 Processing ${uniquePairings.length} series for loss calculation (category $categoryId)");

        for (final pair in uniquePairings) {
          final roundNumber = pair.roundNumber;
          final matchPosition = pair.matchPosition;
          final bracketSide = pair.bracketSide;
          
          // Skip if either alliance is 0 (TBD)
          if (pair.alliance1Id == 0 || pair.alliance2Id == 0) {
            print("  ⏭️ Skipping series R${roundNumber}P${matchPosition} ($bracketSide): TBD alliance");
            continue;
          }
          
          // Get Best-of-3 results for this specific series
          final alliance1Results = matchResults[pair.alliance1Id] ?? [];
          final alliance2Results = matchResults[pair.alliance2Id] ?? [];
          
          final Set<int> completedMatches = {};
          int winsA = 0;
          int winsB = 0;
          
          // Count wins from alliance 1 results
          for (final r in alliance1Results) {
            if (r.matchRound == roundNumber && 
                r.matchPosition == matchPosition && 
                r.bracketSide == bracketSide &&
                r.isCompleted) {
              completedMatches.add(r.matchNumber);
              if (r.winnerAllianceId == pair.alliance1Id) winsA++;
              else if (r.winnerAllianceId == pair.alliance2Id) winsB++;
            }
          }
          
          // Count wins from alliance 2 results
          for (final r in alliance2Results) {
            if (r.matchRound == roundNumber && 
                r.matchPosition == matchPosition && 
                r.bracketSide == bracketSide &&
                r.isCompleted) {
              if (!completedMatches.contains(r.matchNumber)) {
                completedMatches.add(r.matchNumber);
                if (r.winnerAllianceId == pair.alliance1Id) winsA++;
                else if (r.winnerAllianceId == pair.alliance2Id) winsB++;
              }
            }
          }
          
          // Determine if series is complete (2 wins or 3 matches played)
          final bool seriesComplete = (winsA >= 2) || (winsB >= 2) || (completedMatches.length >= 3);
          
          if (seriesComplete) {
            // Determine loser based on series results
            final int loserId;
            if (winsA > winsB) {
              loserId = pair.alliance2Id;
              print("  ✅ Series R${roundNumber}P${matchPosition} ($bracketSide): "
                    "Winner: A${pair.alliance1Id} ($winsA-$winsB), Loser: A$loserId");
            } else if (winsB > winsA) {
              loserId = pair.alliance1Id;
              print("  ✅ Series R${roundNumber}P${matchPosition} ($bracketSide): "
                    "Winner: A${pair.alliance2Id} ($winsA-$winsB), Loser: A$loserId");
            } else {
              // If tie (shouldn't happen with 3 matches), don't count loss
              print("  ⚠️ Series R${roundNumber}P${matchPosition} ($bracketSide): "
                    "Tie $winsA-$winsB, no loss assigned");
              continue;
            }
            allianceLosses[loserId] = (allianceLosses[loserId] ?? 0) + 1;
          } else {
            print("  ⏭️ Series R${roundNumber}P${matchPosition} ($bracketSide): "
                  "Not complete ($winsA-$winsB, ${completedMatches.length}/3 matches)");
          }
        }

        print("📊 Final alliance losses for category $categoryId: $allianceLosses");

        if (mounted) {
          setState(() {
            _allianceLossesByCategory[categoryId] = allianceLosses;
          });
        }
      } catch (e) {
        print('❌ Error computing alliance losses: $e');
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

  // Build Best-of-3 match cell - shows win/loss counts
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
    final bool matchPlayed = result != null && result.isCompleted;
    final bool matchWon = matchPlayed && result!.winnerAllianceId == allianceId;

    final allResults = _bestOf3Results[categoryId] ?? {};
    final seriesAllianceEntries = (allResults[allianceId] ?? [])
        .where(
          (r) =>
              r.matchRound == roundNumber && r.matchPosition == matchPosition,
        )
        .toList();
    final seriesOpponentEntries = (allResults[opponentId] ?? [])
        .where(
          (r) =>
              r.matchRound == roundNumber && r.matchPosition == matchPosition,
        )
        .toList();

    final Map<String, BestOf3MatchResult> uniqueResults = {};

    for (final r in seriesAllianceEntries) {
      if (r.isCompleted) {
        final key = '${r.matchRound}:${r.matchPosition}:${r.matchNumber}';
        uniqueResults[key] = r;
      }
    }
    for (final r in seriesOpponentEntries) {
      if (r.isCompleted) {
        final key = '${r.matchRound}:${r.matchPosition}:${r.matchNumber}';
        if (!uniqueResults.containsKey(key)) uniqueResults[key] = r;
      }
    }

    int winsA = 0;
    int winsO = 0;
    for (final r in uniqueResults.values) {
      if (r.winnerAllianceId == allianceId) {
        winsA++;
      } else if (r.winnerAllianceId == opponentId) {
        winsO++;
      }
    }

    final int completedCount = uniqueResults.length;
    final bool seriesCompleted =
        (winsA >= 2) || (winsO >= 2) || (completedCount >= 3);
    final bool seriesTied = (winsA == 1 && winsO == 1 && completedCount == 2);
    final bool match3Available =
        (matchNumber == 3) && seriesTied && !seriesCompleted;
    final bool match3NotNeeded =
        (matchNumber == 3) && (winsA >= 2 || winsO >= 2);

    try {
      print("   UNIQUE RESULTS for R\$roundNumberP\$matchPosition \\$bracketSide: \\${uniqueResults.length} results");
      for (final entry in uniqueResults.entries) {
        try {
          print("      \\${entry.key}: winner=\\${entry.value.winnerAllianceId}");
        } catch (_) {}
      }
      print("   winsA=\$winsA, winsO=\$winsO, completedCount=\$completedCount, seriesCompleted=\$seriesCompleted");
    } catch (_) {}

    // If the match is already played, show read-only
    if (matchPlayed) {
      return _buildMatchCellContent(
        categoryId: categoryId,
        allianceId: allianceId,
        opponentId: opponentId,
        matchNumber: matchNumber,
        roundNumber: roundNumber,
        matchPosition: matchPosition,
        allianceName: allianceName,
        opponentName: opponentName,
        bracketSide: bracketSide,
        result: result,
        onRefresh: onRefresh,
        matchPlayed: matchPlayed,
        matchWon: matchWon,
        seriesCompleted: seriesCompleted,
        match3Available: match3Available,
        match3NotNeeded: match3NotNeeded,
        winsA: winsA,
        winsO: winsO,
        seriesTied: seriesTied,
        readOnly: true,
      );
    }

    return _buildMatchCellContent(
      categoryId: categoryId,
      allianceId: allianceId,
      opponentId: opponentId,
      matchNumber: matchNumber,
      roundNumber: roundNumber,
      matchPosition: matchPosition,
      allianceName: allianceName,
      opponentName: opponentName,
      bracketSide: bracketSide,
      result: result,
      onRefresh: onRefresh,
      matchPlayed: matchPlayed,
      matchWon: matchWon,
      seriesCompleted: seriesCompleted,
      match3Available: match3Available,
      match3NotNeeded: match3NotNeeded,
      winsA: winsA,
      winsO: winsO,
      seriesTied: seriesTied,
      readOnly: false,
    );
  }

  Widget _buildMatchCellContent({
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
    required bool matchPlayed,
    required bool matchWon,
    required bool seriesCompleted,
    required bool match3Available,
    required bool match3NotNeeded,
    required int winsA,
    required int winsO,
    required bool seriesTied,
    bool readOnly = false,
  }) {
    // CRITICAL FIX: Check for the SPECIFIC match result, not just any result
    final allResults = _bestOf3Results[categoryId] ?? {};
    final allianceResults = allResults[allianceId] ?? [];

    // Find the specific match result for THIS EXACT match
    BestOf3MatchResult? specificMatchResult;
    for (final r in allianceResults) {
      if (r.matchNumber == matchNumber &&
          r.matchRound == roundNumber &&
          r.matchPosition == matchPosition &&
          r.bracketSide == bracketSide) {
        specificMatchResult = r;
        break;
      }
    }

    final bool thisMatchPlayed =
        specificMatchResult != null && specificMatchResult.isCompleted;
    final bool thisMatchWon =
        thisMatchPlayed && specificMatchResult!.winnerAllianceId == allianceId;

    // Get cumulative wins for display across all brackets (for information only)
    int cumWins = 0;
    int cumLosses = 0;
    if (bracketSide == 'grand') {
  // For Grand Finals, show cumulative wins across ALL brackets
  final cumulativeWins = _countWinsForMatchNumberAcrossRounds(
    categoryId,
    allianceId,
    opponentId,
    matchPosition,
    matchNumber,
  );
  cumWins = cumulativeWins['winsA'] ?? 0;
  cumLosses = cumulativeWins['winsB'] ?? 0;
} else {
  final cumulativeWins = _countWinsForMatchNumberAcrossRounds(
    categoryId,
    allianceId,
    opponentId,
    matchPosition,
    matchNumber,
  );
  cumWins = cumulativeWins['winsA'] ?? 0;
  cumLosses = cumulativeWins['winsB'] ?? 0;
}

    // For series status, use the current round's series stats - but only for THIS SPECIFIC round
final seriesWins = _countSeriesWinsForRound(
  categoryId,
  allianceId,
  opponentId,
  roundNumber,
  matchPosition,
  bracketSide,
);
final int seriesWinsA = seriesWins['winsA'] ?? 0;
final int seriesWinsB = seriesWins['winsB'] ?? 0;
    final int completedCount = seriesWins['completed'] ?? 0;
    final bool seriesFinishedInThisRound =
        (seriesWinsA >= 2) || (seriesWinsB >= 2) || (completedCount >= 3);
    try {
      print("🔍 DEBUG: Match ${matchNumber} (R${roundNumber}P${matchPosition} ${bracketSide}):");
      print("   seriesWinsA = $seriesWinsA, seriesWinsB = $seriesWinsB, completedCount = $completedCount");
      print("   seriesFinishedInThisRound = $seriesFinishedInThisRound");
      print("   thisMatchPlayed = $thisMatchPlayed");
      print("   match3Available = $match3Available");
      print("   seriesTied = $seriesTied");
    } catch (_) {}

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

          // If THIS SPECIFIC match is already played, show read-only
          if (thisMatchPlayed) {
            _showBestOf3MatchDialog(
              categoryId: categoryId,
              allianceId: allianceId,
              opponentAllianceId: opponentId,
              matchNumber: matchNumber,
              roundNumber: roundNumber,
              matchPosition: matchPosition,
              bracketSide: bracketSide,
              allianceName: allianceName,
              opponentName: opponentName,
              existingResult: specificMatchResult,
              onRefresh: onRefresh,
              readOnly: true,
            );
            return;
          }

          // If series in this round is already finished, show read-only
          if (seriesFinishedInThisRound) {
            _showBestOf3MatchDialog(
              categoryId: categoryId,
              allianceId: allianceId,
              opponentAllianceId: opponentId,
              matchNumber: matchNumber,
              roundNumber: roundNumber,
              matchPosition: matchPosition,
              bracketSide: bracketSide,
              allianceName: allianceName,
              opponentName: opponentName,
              existingResult: specificMatchResult,
              onRefresh: onRefresh,
              readOnly: true,
            );
            return;
          }

          // If series is tied 1-1 and this is Match 3, allow editing
          if (matchNumber == 3 &&
              seriesTied &&
              !seriesFinishedInThisRound &&
              !thisMatchPlayed) {
            _showBestOf3MatchDialog(
              categoryId: categoryId,
              allianceId: allianceId,
              opponentAllianceId: opponentId,
              matchNumber: matchNumber,
              roundNumber: roundNumber,
              matchPosition: matchPosition,
              bracketSide: bracketSide,
              allianceName: allianceName,
              opponentName: opponentName,
              existingResult: specificMatchResult,
              onRefresh: onRefresh,
              readOnly: false,
            );
            return;
          }

          // Normal match - allow editing (Match 1 or 2)
          _showBestOf3MatchDialog(
            categoryId: categoryId,
            allianceId: allianceId,
            opponentAllianceId: opponentId,
            matchNumber: matchNumber,
            roundNumber: roundNumber,
            matchPosition: matchPosition,
            bracketSide: bracketSide,
            allianceName: allianceName,
            opponentName: opponentName,
            existingResult: specificMatchResult,
            onRefresh: onRefresh,
            readOnly: false,
          );
        },
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 4),
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.03),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.white.withOpacity(0.15), width: 1),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Show cumulative wins across all brackets for information
              if (cumWins > 0 || cumLosses > 0) ...[
                Text(
                  '$cumWins-$cumLosses',
                  style: TextStyle(
                    color: cumWins > cumLosses
                        ? Colors.green
                        : (cumLosses > cumWins ? Colors.red : Colors.white),
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Total in M$matchNumber',
                  style: TextStyle(color: Colors.white38, fontSize: 8),
                ),
              ] else if (thisMatchPlayed) ...[
                Text(
                  thisMatchWon ? '1-0' : '0-1',
                  style: TextStyle(
                    color: thisMatchWon ? Colors.green : Colors.red,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'This Match',
                  style: TextStyle(color: Colors.white38, fontSize: 8),
                ),
              ] else if (match3Available && !seriesFinishedInThisRound) ...[
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFD700).withOpacity(0.2),
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
                  'READY',
                  style: TextStyle(
                    color: Color(0xFFFFD700),
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Text(
                  'Match 3',
                  style: TextStyle(color: Colors.white38, fontSize: 8),
                ),
              ] else if (match3NotNeeded ||
                  (matchNumber == 3 && seriesFinishedInThisRound)) ...[
                const Text(
                  'N/A',
                  style: TextStyle(
                    color: Colors.orange,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Series ended',
                  style: TextStyle(color: Colors.white38, fontSize: 9),
                ),
              ] else if (matchNumber == 3 &&
                  !seriesTied &&
                  !thisMatchPlayed &&
                  !seriesFinishedInThisRound) ...[
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
                const Text(
                  'Need 1-1',
                  style: TextStyle(color: Colors.white24, fontSize: 7),
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
    List<ChampionshipAllianceStanding> standings =
        _championshipStandingsByCategory[categoryId] ?? [];
    Map<int, List<BestOf3MatchResult>> results =
        _bestOf3Results[categoryId] ?? {};
    Map<int, int> wins = _allianceWins[categoryId] ?? {};
    Map<int, AllianceMatchPair> pairings =
        _allianceMatchPairings[categoryId] ?? {};

    if (pairings.isEmpty) {
      _loadMatchPairings(categoryId);
      return const Expanded(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(color: Color(0xFFFFD700)),
              SizedBox(height: 12),
              Text(
                'Loading championship schedule...',
                style: TextStyle(color: Colors.white54),
              ),
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
              Text(
                'Loading championship standings...',
                style: TextStyle(color: Colors.white54, fontSize: 14),
              ),
            ],
          ),
        ),
      );
    }

    // Debug: print per-alliance cumulative match counts
    if (_debugCumulative) {
      for (final standing in standings) {
        final aId = standing.allianceId;
        final opp = _findPairingForAlliance(categoryId, aId);
        final pos = opp?.matchPosition ?? 1;
        final m1 = _countWinsForMatchNumberAcrossRounds(
          categoryId,
          aId,
          opp?.alliance1Id == aId
              ? (opp?.alliance2Id ?? 0)
              : (opp?.alliance1Id ?? 0),
          pos,
          1,
        );
        final m2 = _countWinsForMatchNumberAcrossRounds(
          categoryId,
          aId,
          opp?.alliance1Id == aId
              ? (opp?.alliance2Id ?? 0)
              : (opp?.alliance1Id ?? 0),
          pos,
          2,
        );
        final m3 = _countWinsForMatchNumberAcrossRounds(
          categoryId,
          aId,
          opp?.alliance1Id == aId
              ? (opp?.alliance2Id ?? 0)
              : (opp?.alliance1Id ?? 0),
          pos,
          3,
        );
        print(
          'DEBUG cumulative for alliance $aId -> M1:${m1['winsA']}-${m1['winsB']}, M2:${m2['winsA']}-${m2['winsB']}, M3:${m3['winsA']}-${m3['winsB']}',
        );
      }
    }

    if (standings.isEmpty) {
      return Expanded(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.emoji_events,
                size: 64,
                color: Colors.white.withOpacity(0.2),
              ),
              const SizedBox(height: 16),
              const Text(
                'No Championship Data Yet',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Generate championship schedule first',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.5),
                  fontSize: 14,
                ),
              ),
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

    // Deduplicate pairings by using a Set with a unique key
    final Set<String> processedSeries = {};
    final List<AllianceMatchPair> uniquePairings = [];

    for (final pair in pairings.values) {
      final key =
          '${pair.roundNumber}_${pair.matchPosition}_${pair.bracketSide}';
      if (!processedSeries.contains(key)) {
        processedSeries.add(key);
        uniquePairings.add(pair);
      }
    }

    print(
      "📊 Unique pairings: ${uniquePairings.length} (should be 15 for 8-team bracket)",
    );

// CORRECTED BRACKET LOGIC - Proper categorization for double-elimination
final Map<int, int> allianceLosses = Map<int, int>.from(_allianceLossesByCategory[categoryId] ?? {});

// If we don't have precomputed losses yet, fall back to deriving from Best-of-3 results
if (allianceLosses.isEmpty) {
  for (final standing in standings) {
    allianceLosses[standing.allianceId] = _getAllianceLossCount(categoryId, standing.allianceId);
  }
}

// Create a map of allianceId -> standing for quick lookup
final Map<int, ChampionshipAllianceStanding> allianceIdToStanding = {
  for (final s in standings) s.allianceId: s
};

// CORRECTED: Categorize purely by loss count (0 = Winners, 1 = Losers, 2+ = Eliminated)
final List<ChampionshipAllianceStanding> winnersStandings = [];
final List<ChampionshipAllianceStanding> losersStandings = [];
final List<ChampionshipAllianceStanding> eliminatedStandings = [];
final List<ChampionshipAllianceStanding> grandFinalStandings = [];

// First, separate by loss count ONLY (don't use bracketSide from pairings)
for (final standing in standings) {
  final int allianceId = standing.allianceId;
  final int losses = allianceLosses[allianceId] ?? 0;
  
  if (losses == 0) {
    winnersStandings.add(standing);
  } else if (losses == 1) {
    losersStandings.add(standing);
  } else {
    eliminatedStandings.add(standing);
  }
}

// Sort by totalScore (points) within each bracket - highest first
winnersStandings.sort((a, b) {
  if (a.totalScore != b.totalScore) {
    return b.totalScore.compareTo(a.totalScore);
  }
  return a.allianceRank.compareTo(b.allianceRank);
});
losersStandings.sort((a, b) {
  if (a.totalScore != b.totalScore) {
    return b.totalScore.compareTo(a.totalScore);
  }
  return a.allianceRank.compareTo(b.allianceRank);
});
eliminatedStandings.sort((a, b) {
  if (a.totalScore != b.totalScore) {
    return b.totalScore.compareTo(a.totalScore);
  }
  return a.allianceRank.compareTo(b.allianceRank);
});

// Determine Grand Finals participants:
// - Winner's Bracket champion: The LAST remaining undefeated alliance (should be only 1)
// - Loser's Bracket champion: The LAST remaining alliance with 1 loss (should be only 1)
// 
// Key insight: In double-elimination, Grand Finals happen when:
// - Winner's Bracket has 1 alliance left (they won all matches)
// - Loser's Bracket has 1 alliance left (they won through loser's bracket)
//
// For now, if we have multiple alliances with 0 losses, they are still in Winner's Bracket
// If we have multiple with 1 loss, they are still in Loser's Bracket

// Check if Winner's Bracket final is complete (only 1 undefeated alliance left)
final bool winnersFinalComplete = winnersStandings.length == 1;

// Check if Loser's Bracket final is complete (only 1 alliance with 1 loss left)
final bool losersFinalComplete = losersStandings.length == 1;

// Move alliances to Grand Finals ONLY when both brackets have exactly 1 alliance each
if (winnersFinalComplete && losersFinalComplete) {
  // Both brackets have their champions - move them to Grand Finals
  grandFinalStandings.addAll(winnersStandings);
  grandFinalStandings.addAll(losersStandings);
  winnersStandings.clear();
  losersStandings.clear();
} else if (winnersStandings.length == 1 && losersStandings.isEmpty && eliminatedStandings.isNotEmpty) {
  // Special case: Winner's bracket champion is waiting for Loser's bracket champion to be determined
  // Keep them in winnersStandings for now (they will show as "Winner's Bracket Champion - Waiting")
  // Don't move to Grand Finals yet
}

// Debug output - show alliance IDs and ranks
print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");
print("🏆 FINAL BRACKET STANDINGS (CORRECTED):");
print("Winner's Bracket Active (${winnersStandings.length}): ${winnersStandings.map((s) => '#${s.allianceRank} (ID:${s.allianceId})').join(', ')}");
print("Loser's Bracket Active (${losersStandings.length}): ${losersStandings.map((s) => '#${s.allianceRank} (ID:${s.allianceId})').join(', ')}");
print("Grand Finals (${grandFinalStandings.length}): ${grandFinalStandings.map((s) => '#${s.allianceRank} (ID:${s.allianceId})').join(', ')}");
print("Eliminated (${eliminatedStandings.length}): ${eliminatedStandings.map((s) => '#${s.allianceRank} (ID:${s.allianceId})').join(', ')}");
print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");

    return Expanded(
  child: SingleChildScrollView(
    scrollDirection: Axis.vertical,
    child: Column(
      key: ValueKey('championship_${DateTime.now().millisecondsSinceEpoch}_${standings.length}'),
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

            // Winners Bracket Section Header
            if (winnersStandings.isNotEmpty)
              Container(
                padding: const EdgeInsets.symmetric(
                  vertical: 8,
                  horizontal: 16,
                ),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      const Color(0xFF00CFFF).withOpacity(0.3),
                      const Color(0xFF00CFFF).withOpacity(0.1),
                    ],
                  ),
                  border: const Border(
                    bottom: BorderSide(color: Color(0xFF00CFFF), width: 1),
                    top: BorderSide(color: Color(0xFF00CFFF), width: 1),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF00CFFF).withOpacity(0.2),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.emoji_events,
                            color: Color(0xFF00CFFF),
                            size: 16,
                          ),
                          const SizedBox(width: 8),
                          const Text(
                            'WINNER\'S BRACKET',
                            style: TextStyle(
                              color: Color(0xFF00CFFF),
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                              letterSpacing: 1.5,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              '${winnersStandings.length} ALLIANCES',
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

            // Winners Bracket Rows
            ...winnersStandings.asMap().entries.map((entry) {
              final index = entry.key;
              final standing = entry.value;
              return _buildChampionshipRow(
                standing: standing,
                categoryId: categoryId,
                results: results,
                wins: wins,
                pairings: pairings,
                index: index,
              );
            }),

            // Divider between brackets
            if (winnersStandings.isNotEmpty && losersStandings.isNotEmpty)
              Container(
                height: 2,
                margin: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Colors.transparent,
                      Colors.white.withOpacity(0.2),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),

            // Losers Bracket Section Header
            if (losersStandings.isNotEmpty)
              Container(
                padding: const EdgeInsets.symmetric(
                  vertical: 8,
                  horizontal: 16,
                ),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      const Color(0xFFFF6B6B).withOpacity(0.3),
                      const Color(0xFFFF6B6B).withOpacity(0.1),
                    ],
                  ),
                  border: const Border(
                    bottom: BorderSide(color: Color(0xFFFF6B6B), width: 1),
                    top: BorderSide(color: Color(0xFFFF6B6B), width: 1),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFF6B6B).withOpacity(0.2),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.arrow_downward,
                            color: Color(0xFFFF6B6B),
                            size: 16,
                          ),
                          const SizedBox(width: 8),
                          const Text(
                            'LOSER\'S BRACKET',
                            style: TextStyle(
                              color: Color(0xFFFF6B6B),
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                              letterSpacing: 1.5,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              '${losersStandings.length} ALLIANCES',
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

            // Losers Bracket Rows
            ...losersStandings.asMap().entries.map((entry) {
              final index = entry.key;
              final standing = entry.value;
              return _buildChampionshipRow(
                standing: standing,
                categoryId: categoryId,
                results: results,
                wins: wins,
                pairings: pairings,
                index: index,
              );
            }),
            // Grand Finals Section Header
            if (grandFinalStandings.isNotEmpty)
              Container(
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      const Color(0xFFFFD700).withOpacity(0.3),
                      const Color(0xFFFFD700).withOpacity(0.1),
                    ],
                  ),
                  border: const Border(
                    bottom: BorderSide(color: Color(0xFFFFD700), width: 1),
                    top: BorderSide(color: Color(0xFFFFD700), width: 1),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFD700).withOpacity(0.2),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.emoji_events,
                            color: Color(0xFFFFD700),
                            size: 16,
                          ),
                          const SizedBox(width: 8),
                          const Text(
                            'GRAND FINALS',
                            style: TextStyle(
                              color: Color(0xFFFFD700),
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                              letterSpacing: 1.5,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              '${grandFinalStandings.length}  ALLIANCES',
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

            // Grand Finals Rows
            ...grandFinalStandings.asMap().entries.map((entry) {
              final idx = entry.key;
              final standing = entry.value;
              return _buildChampionshipRow(
                standing: standing,
                categoryId: categoryId,
                results: results,
                wins: wins,
                pairings: pairings,
                index: idx,
              );
            }),
            // Eliminated Section Header
            if (eliminatedStandings.isNotEmpty)
              Container(
                padding: const EdgeInsets.symmetric(
                  vertical: 8,
                  horizontal: 16,
                ),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Colors.grey.withOpacity(0.2),
                      Colors.grey.withOpacity(0.08),
                    ],
                  ),
                  border: const Border(
                    bottom: BorderSide(color: Colors.grey, width: 1),
                    top: BorderSide(color: Colors.grey, width: 1),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.grey.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.clear, color: Colors.grey, size: 16),
                          const SizedBox(width: 8),
                          const Text(
                            'ELIMINATED',
                            style: TextStyle(
                              color: Colors.grey,
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                              letterSpacing: 1.5,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.06),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              '${eliminatedStandings.length} ALLIANCES',
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

            // Eliminated Rows
            ...eliminatedStandings.asMap().entries.map((entry) {
              final index = entry.key;
              final standing = entry.value;
              return _buildChampionshipRow(
                standing: standing,
                categoryId: categoryId,
                results: results,
                wins: wins,
                pairings: pairings,
                index: index,
              );
            }),

            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildChampionshipRow({
    required ChampionshipAllianceStanding standing,
    required int categoryId,
    required Map<int, List<BestOf3MatchResult>> results,
    required Map<int, int> wins,
    required Map<int, AllianceMatchPair> pairings,
    required int index,
  }) {
    final isEven = index % 2 == 0;
    final allianceResults = results[standing.allianceId] ?? [];
    final allianceWins = wins[standing.allianceId] ?? 0;

        // Get the alliance's loss count to determine if they're in Winners or Losers bracket
        // Get the alliance's loss count to determine if they're in Winners or Losers bracket
    final losses = _getAllianceLossCount(categoryId, standing.allianceId);
    
    // Get all results for this alliance
    final allResultsForAlliance = _bestOf3Results[categoryId] ?? {};
    final allianceCompletedResults = allResultsForAlliance[standing.allianceId] ?? [];

    // Find ALL pairings for this alliance
    final List<AllianceMatchPair> alliancePairings = [];
    for (final pair in pairings.values) {
      if (pair.alliance1Id == standing.allianceId ||
          pair.alliance2Id == standing.allianceId) {
        alliancePairings.add(pair);
      }
    }
    
    // Sort by round number (ascending for Loser's bracket)
    alliancePairings.sort((a, b) => a.roundNumber.compareTo(b.roundNumber));
    
    AllianceMatchPair? currentPair;
    
    if (losses >= 1) {
      // For Loser's Bracket, find the NEXT match that is NOT yet completed
      // Start from the lowest round and go up
      for (final pair in alliancePairings) {
        if (pair.bracketSide == 'losers') {
          // Check if this match is already completed for this alliance
          final matchResults = allianceCompletedResults.where((r) => 
              r.matchRound == pair.roundNumber && 
              r.matchPosition == pair.matchPosition &&
              r.bracketSide == pair.bracketSide).toList();
          
          // Count wins for this alliance in this match
          int wins = 0;
          for (final r in matchResults) {
            if (r.winnerAllianceId == standing.allianceId) {
              wins++;
            }
          }
          
          // Check if the series is complete (2 wins or 3 matches played)
          final bool seriesComplete = (wins >= 2) || (matchResults.length >= 3);
          
          // If this match is NOT complete, it's the current match
          if (!seriesComplete) {
            currentPair = pair;
            break;
          }
        }
      }
      
      // If all matches are complete, use the highest round match (shouldn't happen for active alliance)
      if (currentPair == null && alliancePairings.isNotEmpty) {
        for (final pair in alliancePairings.reversed) {
          if (pair.bracketSide == 'losers') {
            currentPair = pair;
            break;
          }
        }
      }
    } else {
      // For Winner's Bracket, find the next incomplete match
      for (final pair in alliancePairings) {
        if (pair.bracketSide == 'winners') {
          final matchResults = allianceCompletedResults.where((r) => 
              r.matchRound == pair.roundNumber && 
              r.matchPosition == pair.matchPosition &&
              r.bracketSide == pair.bracketSide).toList();
          
          int wins = 0;
          for (final r in matchResults) {
            if (r.winnerAllianceId == standing.allianceId) {
              wins++;
            }
          }
          
          final bool seriesComplete = (wins >= 2) || (matchResults.length >= 3);
          
          if (!seriesComplete) {
            currentPair = pair;
            break;
          }
        }
      }
      
      if (currentPair == null && alliancePairings.isNotEmpty) {
        currentPair = alliancePairings.last;
      }
    }
    
    // If still no pair found, use the most recent
    if (currentPair == null && alliancePairings.isNotEmpty) {
      currentPair = alliancePairings.last;
    }

    final opponentId = currentPair != null
        ? (currentPair.alliance1Id == standing.allianceId
              ? currentPair.alliance2Id
              : currentPair.alliance1Id)
        : 0;

    final opponentName = currentPair != null
        ? (currentPair.alliance1Id == standing.allianceId
              ? currentPair.alliance2Name
              : currentPair.alliance1Name)
        : 'TBD';

    final roundNumber = currentPair?.roundNumber ?? 1;
    final matchPosition = currentPair?.matchPosition ?? 1;
    final bracketSide =
        currentPair?.bracketSide ?? (losses >= 1 ? 'losers' : 'winners');

    // Get match results for the current round
    final match1Result = allianceResults.firstWhere(
      (r) =>
          r.matchNumber == 1 &&
          r.matchRound == roundNumber &&
          r.matchPosition == matchPosition,
      orElse: () => BestOf3MatchResult(
        matchNumber: 1,
        alliance1Score: 0,
        alliance1Violation: 0,
        alliance2Score: 0,
        alliance2Violation: 0,
        winnerAllianceId: 0,
        isCompleted: false,
      ),
    );

    final match2Result = allianceResults.firstWhere(
      (r) =>
          r.matchNumber == 2 &&
          r.matchRound == roundNumber &&
          r.matchPosition == matchPosition,
      orElse: () => BestOf3MatchResult(
        matchNumber: 2,
        alliance1Score: 0,
        alliance1Violation: 0,
        alliance2Score: 0,
        alliance2Violation: 0,
        winnerAllianceId: 0,
        isCompleted: false,
      ),
    );

    final match3Result = allianceResults.firstWhere(
      (r) =>
          r.matchNumber == 3 &&
          r.matchRound == roundNumber &&
          r.matchPosition == matchPosition,
      orElse: () => BestOf3MatchResult(
        matchNumber: 3,
        alliance1Score: 0,
        alliance1Violation: 0,
        alliance2Score: 0,
        alliance2Violation: 0,
        winnerAllianceId: 0,
        isCompleted: false,
      ),
    );

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
          _buildBestOf3MatchCell(
  categoryId: categoryId,
  allianceId: standing.allianceId,
  opponentId: opponentId,
  matchNumber: 1,
  roundNumber: roundNumber,
  matchPosition: matchPosition,
  allianceName: '${standing.captainName} / ${standing.partnerName}',
  opponentName: opponentName,
  bracketSide: bracketSide,
  result: match1Result,
  onRefresh: () async {
    await _loadBestOf3Results(categoryId);
    await _loadChampionshipStandings(categoryId);
    await _reorderChampionshipStandings(categoryId);
    if (mounted) setState(() {});
  },
),

          _buildBestOf3MatchCell(
            categoryId: categoryId,
            allianceId: standing.allianceId,
            opponentId: opponentId,
            matchNumber: 2,
            roundNumber: roundNumber,
            matchPosition: matchPosition,
            allianceName: '${standing.captainName} / ${standing.partnerName}',
            opponentName: opponentName,
            bracketSide: bracketSide,
            result: match2Result,
             onRefresh: () async {
  await _loadBestOf3Results(categoryId);
  await _loadChampionshipStandings(categoryId);
  await _reorderChampionshipStandings(categoryId);
  if (mounted) setState(() {});
},
          ),
          _buildBestOf3MatchCell(
            categoryId: categoryId,
            allianceId: standing.allianceId,
            opponentId: opponentId,
            matchNumber: 3,
            roundNumber: roundNumber,
            matchPosition: matchPosition,
            allianceName: '${standing.captainName} / ${standing.partnerName}',
            opponentName: opponentName,
            bracketSide: bracketSide,
            result: match3Result,
             onRefresh: () async {
  await _loadBestOf3Results(categoryId);
  await _loadChampionshipStandings(categoryId);
  await _reorderChampionshipStandings(categoryId);
  if (mounted) setState(() {});
},
          ),
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
  }

  // Original championship table for non-Explorer categories
  Widget _buildOriginalChampionshipTable(int categoryId) {
    bool isLoading = _isLoadingAllianceByCategory[categoryId] ?? false;
    List<ChampionshipAllianceStanding> standings =
        _championshipStandingsByCategory[categoryId] ?? [];
    int matchesPerAlliance = _championshipMatchesPerAlliance[categoryId] ?? 1;

    if (isLoading) {
      return const Expanded(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(color: Color(0xFFFFD700)),
              SizedBox(height: 16),
              Text(
                'Loading championship standings...',
                style: TextStyle(color: Colors.white54, fontSize: 14),
              ),
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
              Icon(
                Icons.emoji_events,
                size: 64,
                color: Colors.white.withOpacity(0.2),
              ),
              const SizedBox(height: 16),
              const Text(
                'No Championship Data Yet',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Generate championship schedule first',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.5),
                  fontSize: 14,
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
          Container(
            color: const Color(0xFF5C2ECC),
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
            child: Row(
              children: [
                _headerCell('RANK', flex: 1),
                _headerCell('ALLIANCE', flex: 1),
                _headerCell('TEAMS', flex: 4),
                ...List.generate(
                  matchesPerAlliance,
                  (i) => Expanded(
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

          Container(
            color: const Color(0xFF4A1A9C),
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
            child: Row(
              children: [
                const Expanded(flex: 1, child: SizedBox()),
                const Expanded(flex: 1, child: SizedBox()),
                const Expanded(flex: 4, child: SizedBox()),
                ...List.generate(
                  matchesPerAlliance,
                  (i) => Expanded(
                    flex: 3,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        Expanded(
                          child: Center(
                            child: Text(
                              'ALL',
                              style: TextStyle(
                                color: const Color(0xFFFFD700).withOpacity(0.9),
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                        Expanded(
                          child: Center(
                            child: Text(
                              'VIO',
                              style: TextStyle(
                                color: Colors.redAccent.withOpacity(0.9),
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
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
            child: ListView.builder(
              itemCount: standings.length,
              itemBuilder: (context, index) {
                final standing = standings[index];
                final isEven = index % 2 == 0;

                return Container(
                  color: isEven
                      ? const Color(0xFF1E0E5A)
                      : const Color(0xFF160A42),
                  padding: const EdgeInsets.symmetric(
                    vertical: 12,
                    horizontal: 16,
                  ),
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
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 6,
                            ),
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
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 8,
                                    ),
                                    child: Center(
                                      child: Text(
                                        hasScore
                                            ? '${matchScore!['score']}'
                                            : '—',
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
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 8,
                                    ),
                                    child: Center(
                                      child: Text(
                                        hasScore
                                            ? '${matchScore!['violation']}'
                                            : '—',
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

      final alliancesResult = await conn.execute(
        """
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
      """,
        {"catId": categoryId},
      );

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

        standings.add(
          AllianceStanding(
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
          ),
        );
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
        {"catId": categoryId},
      );

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

        String title = i == 0
            ? 'Champion'
            : i == 1
            ? 'Runner-up'
            : 'Semi-finalist';
        Color medalColor = i == 0
            ? const Color(0xFFFFD700)
            : i == 1
            ? const Color(0xFFC0C0C0)
            : const Color(0xFFCD7F32);

        standings.add(
          ChampionStanding(
            allianceId: int.parse(row['alliance_id'].toString()),
            allianceRank: int.parse(row['alliance_rank'].toString()),
            teams: [
              {'team_name': row['captain_name'].toString(), 'role': 'Captain'},
              {'team_name': row['partner_name'].toString(), 'role': 'Partner'},
            ],
            title: title,
            medalColor: medalColor,
          ),
        );
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

      final roundsResult = await conn.execute(
        """
        SELECT DISTINCT ts.round_id
        FROM tbl_teamschedule ts
        JOIN tbl_team t ON ts.team_id = t.team_id
        WHERE t.category_id = :catId
        ORDER BY ts.round_id
      """,
        {"catId": categoryId},
      );

      final rounds = roundsResult.rows
          .map(
            (r) => int.tryParse(r.assoc()['round_id']?.toString() ?? '0') ?? 0,
          )
          .where((r) => r > 0)
          .toList();

      if (rounds.isEmpty) {
        final settingsResult = await conn.execute(
          """
          SELECT matches_per_team 
          FROM tbl_category_settings 
          WHERE category_id = :catId
        """,
          {"catId": categoryId},
        );

        if (settingsResult.rows.isNotEmpty) {
          final matchesPerTeam =
              int.tryParse(
                settingsResult.rows.first
                        .assoc()['matches_per_team']
                        ?.toString() ??
                    '0',
              ) ??
              0;

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
          final checkResult = await conn.execute(
            """
            SELECT COUNT(*) as cnt 
            FROM tbl_score 
            WHERE team_id = :teamId AND round_id = :roundId
          """,
            {"teamId": teamId, "roundId": roundId},
          );

          final exists =
              int.tryParse(
                checkResult.rows.first.assoc()['cnt']?.toString() ?? '0',
              ) ??
              0;

          if (exists == 0) {
            await DBHelper.executeDual(
              """
              INSERT INTO tbl_score
                (team_id, round_id, score_totalscore, score_individual, score_alliance, score_violation, score_totalduration)
              VALUES
                (:teamId, :roundId, 0, 0, 0, 0, '00:00')
            """,
              {"teamId": teamId, "roundId": roundId},
            );
            scoresInserted++;
          } else {
            scoresSkipped++;
          }
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '✅ Initialized $scoresInserted default scores (0)${scoresSkipped > 0 ? ', $scoresSkipped already existed' : ''}',
            ),
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
        title: const Text(
          'Clear Scores?',
          style: TextStyle(color: Colors.white),
        ),
        content: const Text(
          'This will delete all scores for this category. This action cannot be undone.',
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
              'CLEAR',
              style: TextStyle(color: Colors.redAccent),
            ),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      final conn = await DBHelper.getConnection();
      await DBHelper.executeDual(
        """
        DELETE s FROM tbl_score s
        JOIN tbl_team t ON s.team_id = t.team_id
        WHERE t.category_id = :catId
      """,
        {"catId": categoryId},
      );

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

  Future<String> _getPartnerTeamName(
    int matchId,
    int teamId,
    int roundId,
  ) async {
    if (matchId <= 0) return '';

    try {
      final conn = await DBHelper.getConnection();

      final arenaResult = await conn.execute(
        """
        SELECT arena_number FROM tbl_teamschedule
        WHERE match_id = :matchId AND team_id = :teamId AND round_id = :roundId
        LIMIT 1
      """,
        {"matchId": matchId, "teamId": teamId, "roundId": roundId},
      );

      if (arenaResult.rows.isEmpty) return '';

      final arenaNumber =
          int.tryParse(
            arenaResult.rows.first.assoc()['arena_number']?.toString() ?? '0',
          ) ??
          0;
      if (arenaNumber == 0) return '';

      final partnerResult = await conn.execute(
        """
        SELECT t.team_name
        FROM tbl_teamschedule ts
        JOIN tbl_team t ON ts.team_id = t.team_id
        WHERE ts.match_id = :matchId 
          AND ts.arena_number = :arena
          AND ts.team_id != :teamId
        LIMIT 1
      """,
        {"matchId": matchId, "arena": arenaNumber, "teamId": teamId},
      );

      if (partnerResult.rows.isEmpty) return '';

      return partnerResult.rows.first.assoc()['team_name']?.toString() ?? '';
    } catch (e) {
      print("Error getting partner team: $e");
      return '';
    }
  }

  Future<String> _getOpponentTeamName(
    int matchId,
    int teamId,
    int roundId,
  ) async {
    if (matchId <= 0) return '';

    try {
      final conn = await DBHelper.getConnection();

      final opponentResult = await conn.execute(
        """
        SELECT t.team_name
        FROM tbl_teamschedule ts
        JOIN tbl_team t ON ts.team_id = t.team_id
        WHERE ts.match_id = :matchId 
          AND ts.team_id != :teamId
        LIMIT 1
      """,
        {"matchId": matchId, "teamId": teamId},
      );

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

      final categoryResult = await conn.execute(
        """
        SELECT c.category_type
        FROM tbl_team t
        JOIN tbl_category c ON t.category_id = c.category_id
        WHERE t.team_id = :teamId
      """,
        {"teamId": teamId},
      );

      if (categoryResult.rows.isNotEmpty) {
        final categoryName =
            categoryResult.rows.first
                .assoc()['category_type']
                ?.toString()
                .toLowerCase() ??
            '';
        isOneVsOne = categoryName.contains('starter');
      }

      final matchResult = await conn.execute(
        """
        SELECT ts.match_id, ts.arena_number, ts.round_id
        FROM tbl_teamschedule ts
        WHERE ts.team_id = :teamId AND ts.round_id = :roundId
        LIMIT 1
      """,
        {"teamId": teamId, "roundId": roundId},
      );

      if (matchResult.rows.isNotEmpty) {
        matchId = int.parse(
          matchResult.rows.first.assoc()['match_id']?.toString() ?? '0',
        );

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
                    border: Border.all(
                      color: const Color(0xFF00CFFF).withOpacity(0.3),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        isOneVsOne
                            ? Icons.sports_kabaddi
                            : Icons.people_alt_rounded,
                        color: const Color(0xFF00CFFF),
                        size: 18,
                      ),
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
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 10,
                              ),
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
                        style: TextStyle(color: Colors.white.withOpacity(0.5)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () async {
                        final individual =
                            int.tryParse(individualController.text.trim()) ?? 0;
                        final alliance =
                            int.tryParse(allianceController.text.trim()) ?? 0;
                        final violation =
                            int.tryParse(violationController.text.trim()) ?? 0;
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
                              refResult.rows.first
                                      .assoc()['referee_id']
                                      ?.toString() ??
                                  '0',
                            );
                            if (refereeId == 0) refereeId = null;
                          }

                          int previousAlliance = 0;
                          try {
                            final prevRes = await conn.execute(
                              """
                              SELECT score_alliance FROM tbl_score
                              WHERE team_id = :teamId AND round_id = :roundId
                              LIMIT 1
                            """,
                              {"teamId": teamId, "roundId": roundId},
                            );
                            if (prevRes.rows.isNotEmpty) {
                              previousAlliance =
                                  int.tryParse(
                                    prevRes.rows.first
                                            .assoc()['score_alliance']
                                            ?.toString() ??
                                        '0',
                                  ) ??
                                  0;
                            }
                          } catch (e) {
                            print(
                              "⚠️ Could not read previous alliance score: $e",
                            );
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
        Text(
          label,
          style: TextStyle(
            color: color,
            fontWeight: FontWeight.bold,
            fontSize: 11,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 4),
        TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          style: TextStyle(
            color: color,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
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
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 12,
            ),
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

        final scoreResult = await conn.execute(
          """
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
        """,
          {"catId": catId},
        );

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
          final totalScore =
              int.tryParse(row['score_totalscore'].toString()) ?? 0;
          final individualScore =
              int.tryParse(row['score_individual']?.toString() ?? '0') ?? 0;
          final allianceScore =
              int.tryParse(row['score_alliance']?.toString() ?? '0') ?? 0;
          final violation =
              int.tryParse(row['score_violation']?.toString() ?? '0') ?? 0;
          final duration = row['score_totalduration']?.toString() ?? '00:00';

          if (teamMap.containsKey(teamId)) {
            final roundScore = RoundScore(
              individualScore: individualScore,
              allianceScore: allianceScore,
              violation: violation,
              duration: duration,
            );

            teamMap[teamId]!['rounds'][roundId] = roundScore;
            teamMap[teamId]!['totalScore'] =
                (teamMap[teamId]!['totalScore'] as int) + totalScore;

            if (roundId > maxRoundFound) maxRoundFound = roundId;
          }
        }

        int maxRounds = 0;
        try {
          final settingsResult = await conn.execute(
            """
            SELECT matches_per_team 
            FROM tbl_category_settings 
            WHERE category_id = :catId
          """,
            {"catId": catId},
          );

          if (settingsResult.rows.isNotEmpty) {
            maxRounds =
                int.tryParse(
                  settingsResult.rows.first
                          .assoc()['matches_per_team']
                          ?.toString() ??
                      '0',
                ) ??
                0;
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

        standings.sort(
          (a, b) => (b['totalScore'] as int).compareTo(a['totalScore'] as int),
        );

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
                child: Text(
                  'No data found.',
                  style: TextStyle(color: Colors.white, fontSize: 16),
                ),
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
                  letterSpacing: 1,
                ),
                tabs: _categories.map((c) {
                  return Tab(
                    text: (c['category_type'] ?? '').toString().toUpperCase(),
                  );
                }).toList(),
              ),
            ),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: _categories.map((cat) {
                  final catId =
                      int.tryParse(cat['category_id'].toString()) ?? 0;
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
    final categoryName = (category['category_type'] ?? '')
        .toString()
        .toLowerCase();
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

    StandingType selectedType =
        _selectedTypeByCategory[categoryId] ?? StandingType.qualification;

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
                                size: 16,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                type.displayName,
                                style: TextStyle(
                                  color: type == selectedType
                                      ? type.color
                                      : Colors.white70,
                                  fontSize: 14,
                                  fontWeight: type == selectedType
                                      ? FontWeight.bold
                                      : FontWeight.normal,
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
                  if (selectedType == StandingType.qualification &&
                      rows.isNotEmpty &&
                      !hasScores)
                    Container(
                      margin: const EdgeInsets.only(right: 8),
                      child: ElevatedButton.icon(
                        onPressed: _isInitializingScores
                            ? null
                            : () => _initializeDefaultScores(categoryId),
                        icon: _isInitializingScores
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.auto_awesome_rounded, size: 16),
                        label: Text(
                          _isInitializingScores ? '...' : 'INIT SCORES',
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF00E5A0),
                          foregroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          textStyle: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
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
                            horizontal: 12,
                            vertical: 6,
                          ),
                          textStyle: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                    ),

                  _buildLiveIndicator(),
                  IconButton(
                    tooltip: 'Teams & Players',
                    icon: const Icon(
                      Icons.groups_rounded,
                      color: Color(0xFF00E5A0),
                    ),
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
                    icon: const Icon(
                      Icons.arrow_back_ios_new,
                      color: Color(0xFF00CFFF),
                    ),
                    onPressed: widget.onBack,
                  ),
                  const SizedBox(width: 8),
                  if (selectedType == StandingType.qualification &&
                      maxRounds > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF00CFFF).withOpacity(0.15),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: const Color(0xFF00CFFF).withOpacity(0.3),
                        ),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.sports_esports_rounded,
                            color: Color(0xFF00CFFF),
                            size: 14,
                          ),
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

  Widget _buildQualificationTable(
    List<Map<String, dynamic>> rows,
    int maxRounds,
  ) {
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
                ...List.generate(
                  maxRounds,
                  (i) => Expanded(
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
                ...List.generate(
                  maxRounds,
                  (i) => Expanded(
                    flex: 4,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        Expanded(
                          child: Center(
                            child: Text(
                              'IND',
                              style: TextStyle(
                                color: const Color(0xFF00CFFF).withOpacity(0.9),
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                        Expanded(
                          child: Center(
                            child: Text(
                              'ALL',
                              style: TextStyle(
                                color: const Color(0xFFFFD700).withOpacity(0.9),
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                        Expanded(
                          child: Center(
                            child: Text(
                              'VIO',
                              style: TextStyle(
                                color: Colors.redAccent.withOpacity(0.9),
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
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
                    child: Text(
                      'No teams registered yet.',
                      style: TextStyle(color: Colors.white54, fontSize: 14),
                    ),
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
                        color: isEven
                            ? const Color(0xFF1E0E5A)
                            : const Color(0xFF160A42),
                        padding: const EdgeInsets.symmetric(
                          vertical: 8,
                          horizontal: 16,
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              flex: 1,
                              child: Text(
                                '$rank',
                                style: TextStyle(
                                  color: _rankColor(rank),
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            Expanded(
                              flex: 2,
                              child: Text(
                                'C${teamId.toString().padLeft(3, '0')}R',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            Expanded(
                              flex: 3,
                              child: Text(
                                teamName,
                                style: const TextStyle(color: Colors.white),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            ...List.generate(maxRounds, (i) {
                              final roundScore = rounds.containsKey(i + 1)
                                  ? rounds[i + 1]!
                                  : RoundScore();
                              final hasScore = rounds.containsKey(i + 1);

                              return Expanded(
                                flex: 4,
                                child: Container(
                                  margin: const EdgeInsets.symmetric(
                                    horizontal: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    border: Border.all(
                                      color: hasScore
                                          ? const Color(
                                              0xFFFFD700,
                                            ).withOpacity(0.3)
                                          : Colors.white.withOpacity(0.1),
                                      width: 1,
                                    ),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceEvenly,
                                    children: [
                                      Expanded(
                                        child: GestureDetector(
                                          onTap: () =>
                                              _showQualificationScoreDialog(
                                                teamId: teamId,
                                                teamName: teamName,
                                                roundId: i + 1,
                                                currentScore: roundScore,
                                              ),
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(
                                              vertical: 6,
                                            ),
                                            decoration: BoxDecoration(
                                              color:
                                                  hasScore &&
                                                      roundScore
                                                              .individualScore >
                                                          0
                                                  ? const Color(
                                                      0xFF00CFFF,
                                                    ).withOpacity(0.15)
                                                  : null,
                                              borderRadius:
                                                  const BorderRadius.horizontal(
                                                    left: Radius.circular(3),
                                                  ),
                                            ),
                                            child: Center(
                                              child: Text(
                                                roundScore.individualScore > 0
                                                    ? '${roundScore.individualScore}'
                                                    : (hasScore ? '0' : '—'),
                                                style: TextStyle(
                                                  color:
                                                      roundScore.individualScore >
                                                              0 ||
                                                          hasScore
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
                                          onTap: () =>
                                              _showQualificationScoreDialog(
                                                teamId: teamId,
                                                teamName: teamName,
                                                roundId: i + 1,
                                                currentScore: roundScore,
                                              ),
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(
                                              vertical: 6,
                                            ),
                                            decoration: BoxDecoration(
                                              color:
                                                  hasScore &&
                                                      roundScore.allianceScore >
                                                          0
                                                  ? const Color(
                                                      0xFFFFD700,
                                                    ).withOpacity(0.15)
                                                  : null,
                                              border: Border(
                                                left: BorderSide(
                                                  color: Colors.white
                                                      .withOpacity(0.1),
                                                  width: 1,
                                                ),
                                                right: BorderSide(
                                                  color: Colors.white
                                                      .withOpacity(0.1),
                                                  width: 1,
                                                ),
                                              ),
                                            ),
                                            child: Center(
                                              child: Text(
                                                roundScore.allianceScore > 0
                                                    ? '${roundScore.allianceScore}'
                                                    : (hasScore ? '0' : '—'),
                                                style: TextStyle(
                                                  color:
                                                      roundScore.allianceScore >
                                                              0 ||
                                                          hasScore
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
                                          onTap: () =>
                                              _showQualificationScoreDialog(
                                                teamId: teamId,
                                                teamName: teamName,
                                                roundId: i + 1,
                                                currentScore: roundScore,
                                              ),
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(
                                              vertical: 6,
                                            ),
                                            decoration: BoxDecoration(
                                              color: roundScore.violation > 0
                                                  ? Colors.red.withOpacity(0.15)
                                                  : null,
                                              borderRadius:
                                                  const BorderRadius.horizontal(
                                                    right: Radius.circular(3),
                                                  ),
                                            ),
                                            child: Center(
                                              child: Text(
                                                roundScore.violation > 0
                                                    ? '${roundScore.violation}'
                                                    : (hasScore ? '0' : '—'),
                                                style: TextStyle(
                                                  color:
                                                      roundScore.violation > 0
                                                      ? Colors.redAccent
                                                      : (hasScore
                                                            ? Colors.white38
                                                            : Colors.white24),
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
                                    Text(
                                      '$total',
                                      style: const TextStyle(
                                        color: Color(0xFFFFD700),
                                        fontWeight: FontWeight.bold,
                                        fontSize: 18,
                                      ),
                                    ),
                                    Text(
                                      _bestDuration(rounds),
                                      style: const TextStyle(
                                        color: Colors.white60,
                                        fontSize: 10,
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

  Widget _buildBattleOfChampionsView(int categoryId) {
    bool isLoading = _isLoadingAllianceByCategory[categoryId] ?? false;
    List<ChampionStanding> standings =
        _championStandingsByCategory[categoryId] ?? [];

    if (isLoading) {
      return const Expanded(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(color: Color(0xFFFFD700)),
              SizedBox(height: 16),
              Text(
                'Loading champion standings...',
                style: TextStyle(color: Colors.white54),
              ),
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
              Icon(
                Icons.military_tech_rounded,
                size: 64,
                color: Colors.white.withOpacity(0.2),
              ),
              const SizedBox(height: 16),
              const Text(
                'Battle of Champions Not Completed',
                style: TextStyle(color: Colors.white, fontSize: 18),
              ),
              const SizedBox(height: 8),
              Text(
                'Complete the championship round first',
                style: TextStyle(color: Colors.white.withOpacity(0.5)),
              ),
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
                      index == 0
                          ? Icons.star
                          : index == 1
                          ? Icons.emoji_events
                          : Icons.military_tech,
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
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                          ),
                        );
                      }),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
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
      case 1:
        return const Color(0xFFFFD700);
      case 2:
        return const Color(0xFFC0C0C0);
      case 3:
        return const Color(0xFFCD7F32);
      default:
        return Colors.white;
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
                    TextSpan(
                      text: 'Make',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    TextSpan(
                      text: 'bl',
                      style: TextStyle(
                        color: Color(0xFF00CFFF),
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    TextSpan(
                      text: 'ock',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              const Text(
                'Construct Your Dreams',
                style: TextStyle(color: Colors.white54, fontSize: 10),
              ),
            ],
          ),
          Image.asset(
            'assets/images/CenterLogo.png',
            height: 80,
            fit: BoxFit.contain,
          ),
          const Text(
            'CREOTEC',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
              letterSpacing: 3,
            ),
          ),
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
              const Text(
                'LIVE',
                style: TextStyle(
                  color: Color(0xFF00FF88),
                  fontSize: 9,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1,
                ),
              ),
              Text(
                timeStr,
                style: const TextStyle(color: Colors.white54, fontSize: 9),
              ),
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

class _PulsingDotState extends State<_PulsingDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _anim = Tween<double>(
      begin: 0.3,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
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