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
}

// Championship alliance standing model
class ChampionshipAllianceStanding {
  final int allianceId;
  final int allianceRank;
  final String captainName;
  final String partnerName;
  final Map<int, Map<String, int>> matchScores; // match position -> {score, violation}
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

  Future<void> _loadChampionshipStandings(int categoryId) async {
    setState(() {
      _isLoadingAllianceByCategory[categoryId] = true;
    });
    
    try {
      final conn = await DBHelper.getConnection();
      
      // Check if tables exist
      try {
        await conn.execute("SELECT 1 FROM tbl_alliance_selections LIMIT 1");
      } catch (e) {
        setState(() {
          _championshipStandingsByCategory[categoryId] = [];
          _isLoadingAllianceByCategory[categoryId] = false;
        });
        return;
      }
      
      // Get championship settings to know matches per alliance
      int matchesPerAlliance = 1;
      try {
        final settingsResult = await conn.execute("""
          SELECT matches_per_alliance 
          FROM tbl_championship_settings 
          WHERE category_id = :catId
        """, {"catId": categoryId});
        
        if (settingsResult.rows.isNotEmpty) {
          matchesPerAlliance = int.parse(settingsResult.rows.first.assoc()['matches_per_alliance']?.toString() ?? '1');
        }
      } catch (e) {
        print("⚠️ Could not load championship settings: $e");
      }
      
      setState(() {
        _championshipMatchesPerAlliance[categoryId] = matchesPerAlliance;
      });
      
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
        setState(() {
          _championshipStandingsByCategory[categoryId] = [];
          _isLoadingAllianceByCategory[categoryId] = false;
        });
        return;
      }
      
      // Get championship matches
      final matchesResult = await conn.execute("""
        SELECT 
          match_id,
          match_round,
          match_position,
          alliance1_id,
          alliance2_id,
          status
        FROM tbl_championship_schedule
        WHERE category_id = :catId
        ORDER BY match_round, match_position
      """, {"catId": categoryId});
      
      final matches = matchesResult.rows.map((r) => r.assoc()).toList();
      
      // Create standings map
      final Map<int, ChampionshipAllianceStanding> standingMap = {};
      
      for (final alliance in alliances) {
        final allianceId = int.parse(alliance['alliance_id'].toString());
        final allianceRank = int.parse(alliance['alliance_rank'].toString());
        
        standingMap[allianceId] = ChampionshipAllianceStanding(
          allianceId: allianceId,
          allianceRank: allianceRank,
          captainName: alliance['captain_name'].toString(),
          partnerName: alliance['partner_name'].toString(),
          matchScores: {},
          totalScore: 0,
        );
      }
      
      // For now, initialize with zero scores
      // In the future, this will come from actual score entry
      for (final match in matches) {
        final position = int.parse(match['match_position'].toString());
        final alliance1Id = int.parse(match['alliance1_id'].toString());
        final alliance2Id = int.parse(match['alliance2_id'].toString());
        
        if (standingMap.containsKey(alliance1Id) && alliance1Id != 0) {
          standingMap[alliance1Id]!.matchScores[position] = {
            'score': 0,
            'violation': 0,
            'total': 0,
          };
        }
        
        if (standingMap.containsKey(alliance2Id) && alliance2Id != 0) {
          standingMap[alliance2Id]!.matchScores[position] = {
            'score': 0,
            'violation': 0,
            'total': 0,
          };
        }
      }
      
      // Convert to list and sort by alliance rank
      final standings = standingMap.values.toList()
        ..sort((a, b) => a.allianceRank.compareTo(b.allianceRank));
      
      setState(() {
        _championshipStandingsByCategory[categoryId] = standings;
        _isLoadingAllianceByCategory[categoryId] = false;
      });
      
    } catch (e) {
      print("Error loading championship standings: $e");
      setState(() {
        _championshipStandingsByCategory[categoryId] = [];
        _isLoadingAllianceByCategory[categoryId] = false;
      });
    }
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
            await conn.execute("""
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
      await conn.execute("""
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

  // Dialog for championship match scores
  void _showChampionshipScoreDialog({
    required ChampionshipAllianceStanding standing,
    required int matchPosition,
    required Map<String, int>? currentScore,
  }) {
    final scoreController = TextEditingController(text: currentScore?['score']?.toString() ?? '0');
    final violationController = TextEditingController(text: currentScore?['violation']?.toString() ?? '0');
    
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          width: 400,
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF2D0E7A), Color(0xFF1E0A5A)],
            ),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
                color: const Color(0xFFFFD700).withOpacity(0.4), width: 1.5),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFD700).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.emoji_events,
                        color: Color(0xFFFFD700), size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(standing.allianceName,
                            style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 14)),
                        Text('Match $matchPosition • Championship',
                            style: TextStyle(
                                color: Colors.white.withOpacity(0.5),
                                fontSize: 11)),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              
              _buildScoreField(
                label: 'ALLIANCE SCORE',
                controller: scoreController,
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
              const SizedBox(height: 8),
              
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFD700).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.info_outline, color: Color(0xFFFFD700), size: 14),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Total = Alliance Score - Violation',
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
                      child: Text('CANCEL',
                          style: TextStyle(
                              color: Colors.white.withOpacity(0.5))),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        final score = int.tryParse(scoreController.text.trim()) ?? 0;
                        final violation = int.tryParse(violationController.text.trim()) ?? 0;
                        
                        setState(() {
                          standing.matchScores[matchPosition] = {
                            'score': score,
                            'violation': violation,
                            'total': score - violation,
                          };
                          
                          standing.totalScore = 0;
                          standing.matchScores.forEach((_, data) {
                            standing.totalScore += (data['score']! - data['violation']!);
                          });
                        });
                        
                        Navigator.pop(ctx);
                        
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('✅ Score saved'),
                            backgroundColor: Colors.green,
                            duration: Duration(seconds: 1),
                          ),
                        );
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFFFD700),
                        foregroundColor: Colors.black,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8)),
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
      final categories = await DBHelper.getCategories();
      final Map<int, List<Map<String, dynamic>>> standingsByCategory = {};

      for (final cat in categories) {
        final catId = int.tryParse(cat['category_id'].toString()) ?? 0;
        
        final conn = await DBHelper.getConnection();
        final scoreResult = await conn.execute("""
          SELECT 
            team_id, 
            round_id, 
            score_totalscore,
            score_individual,
            score_alliance,
            score_violation,
            score_totalduration 
          FROM tbl_score 
          WHERE team_id IN (
            SELECT team_id FROM tbl_team WHERE category_id = :catId
          )
        """, {"catId": catId});
        
        final rows = scoreResult.rows.map((r) => r.assoc()).toList();

        final Map<int, Map<String, dynamic>> teamMap = {};
        
        final teams = await DBHelper.getTeamsByCategory(catId);
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
        } catch (e) {}
        
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

      setState(() {
        _categories = categories;
        _standingsByCategory = standingsByCategory;
        _isLoading = false;
        _lastUpdated = DateTime.now();
      });
      
      final conn = await DBHelper.getConnection();
      final result = await conn.execute(
          "SELECT score_id, team_id, round_id, score_totalscore, score_individual, score_alliance, score_violation FROM tbl_score ORDER BY score_id");
      final rows = result.rows.map((r) => r.assoc()).toList();
      _lastDataSignature = _buildSignature(rows);
      
    } catch (e) {
      print("Error loading standings: $e");
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
    final categoryName = (category['category_type'] ?? '').toString().toUpperCase();

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
                        _loadChampionshipStandings(categoryId);
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
                categoryName,
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
          _buildChampionshipTable(categoryId)
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
                              final roundScore = rounds[i + 1] ?? RoundScore();
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
                                      
                                      Expanded(
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
                                      
                                      Expanded(
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

  Widget _buildChampionshipTable(int categoryId) {
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
              _headerCell('ALLIANCE', flex: 1), // Reduced from 2 to 1
              _headerCell('TEAMS', flex: 4), // Increased from 4 to 4.5 to compensate
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
              _headerCell('TOTAL', flex: 2, center: true),
            ],
          ),
        ),
        
        // Sub-header with ALL and VIO
        Container(
          color: const Color(0xFF4A1A9C),
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
          child: Row(
            children: [
              const Expanded(flex: 1, child: SizedBox()), // RANK
              const Expanded(flex: 1, child: SizedBox()), // ALLIANCE (reduced from 2 to 1)
              const Expanded(flex: 4, child: SizedBox()), // TEAMS (increased from 4 to 4.5)
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
              const Expanded(flex: 2, child: SizedBox()), // TOTAL
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
                    // Rank
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
                    
                    // Alliance - Reduced width
                    Expanded(
                      flex: 1, // Reduced from 2 to 1
                      child: Text(
                        '#${standing.allianceRank}',
                        style: const TextStyle(
                          color: Color(0xFFFFD700),
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                    ),
                    
                    // Teams - Displayed as "CAPTAIN/PARTNER" with rounded square container
                    // Now with more space to compensate
                    Expanded(
                      flex: 4, // Increased from 4 to 4.5
                      child: Padding(
                        padding: const EdgeInsets.only(right: 12), // Reduced from 16 to 12
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
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFFFFD700).withOpacity(0.1),
                                blurRadius: 6,
                                spreadRadius: 0.5,
                              ),
                            ],
                          ),
                          child: Center(
                            child: Text(
                              '${standing.captainName.toUpperCase()} / ${standing.partnerName.toUpperCase()}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 0.3,
                              ),
                              textAlign: TextAlign.center,
                              overflow: TextOverflow.ellipsis,
                              maxLines: 2,
                            ),
                          ),
                        ),
                      ),
                    ),
                    
                    // Match scores
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
                              // Alliance Score (ALL)
                              Expanded(
                                child: GestureDetector(
                                  onTap: () => _showChampionshipScoreDialog(
                                    standing: standing,
                                    matchPosition: i + 1,
                                    currentScore: matchScore,
                                  ),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(vertical: 8),
                                    decoration: BoxDecoration(
                                      color: hasScore && (matchScore?['score'] ?? 0) > 0
                                          ? const Color(0xFFFFD700).withOpacity(0.15)
                                          : null,
                                      borderRadius: const BorderRadius.horizontal(
                                          left: Radius.circular(3)),
                                    ),
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
                              ),
                              
                              // Violation (VIO)
                              Expanded(
                                child: GestureDetector(
                                  onTap: () => _showChampionshipScoreDialog(
                                    standing: standing,
                                    matchPosition: i + 1,
                                    currentScore: matchScore,
                                  ),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(vertical: 8),
                                    decoration: BoxDecoration(
                                      color: hasScore && (matchScore?['violation'] ?? 0) > 0
                                          ? Colors.red.withOpacity(0.15)
                                          : null,
                                      borderRadius: const BorderRadius.horizontal(
                                          right: Radius.circular(3)),
                                    ),
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
                              ),
                            ],
                          ),
                        ),
                      );
                    }),
                    
                    // Total Score
                    Expanded(
                      flex: 2,
                      child: Center(
                        child: Text(
                          '${standing.totalScore}',
                          style: const TextStyle(
                            color: Color(0xFFFFD700),
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                          ),
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