import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'db_helper.dart';
import 'teams_players.dart';

class Standings extends StatefulWidget {
  final VoidCallback? onBack;

  const Standings({
    super.key,
    this.onBack,
  });

  @override
  State<Standings> createState() => _StandingsState();
}

class _StandingsState extends State<Standings>
    with TickerProviderStateMixin {
  TabController? _tabController;
  List<Map<String, dynamic>> _categories = [];

  // category_id → list of standing rows
  Map<int, List<Map<String, dynamic>>> _standingsByCategory = {};

  bool _isLoading = true;
  bool _isInitializingScores = false;
  DateTime? _lastUpdated;
  Timer?    _autoRefreshTimer;

  // Track changes using a data signature
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

  // ── Build a signature string to detect any data change ──────────────────
  String _buildSignature(List rows) {
    return rows.map((r) => r.toString()).join('|');
  }

  // ── Silent refresh — only rebuilds UI if data actually changed ───────────
  Future<void> _silentRefresh() async {
    try {
      final conn   = await DBHelper.getConnection();
      final result = await conn.execute(
          "SELECT score_id, team_id, round_id, score_totalscore FROM tbl_score ORDER BY score_id");
      final rows = result.rows.map((r) => r.assoc()).toList();
      final signature = _buildSignature(rows);

      if (signature != _lastDataSignature) {
        _lastDataSignature = signature;
        await _loadData(initial: false);
      }
    } catch (_) {}
  }

  // ── Initialize default scores (zeros) for all teams in a category ───────
  Future<void> _initializeDefaultScores(int categoryId) async {
    setState(() => _isInitializingScores = true);
    
    try {
      final conn = await DBHelper.getConnection();
      
      // Get all teams in this category
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
      
      // Get all rounds from schedule for this category
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
        // If no rounds in schedule, use matches_per_team from settings
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
        // Default to 4 rounds if nothing else found
        rounds.addAll([1, 2, 3, 4]);
      }
      
      int scoresInserted = 0;
      int scoresSkipped = 0;
      
      // For each team, insert default scores for each round
      for (final team in teams) {
        final teamId = int.tryParse(team['team_id'].toString()) ?? 0;
        if (teamId == 0) continue;
        
        for (final roundId in rounds) {
          // Check if score already exists
          final checkResult = await conn.execute("""
            SELECT COUNT(*) as cnt 
            FROM tbl_score 
            WHERE team_id = :teamId AND round_id = :roundId
          """, {"teamId": teamId, "roundId": roundId});
          
          final exists = int.tryParse(
            checkResult.rows.first.assoc()['cnt']?.toString() ?? '0'
          ) ?? 0;
          
          if (exists == 0) {
            // Insert default score (0) with '00:00' duration
            await conn.execute("""
              INSERT INTO tbl_score
                (team_id, round_id, score_totalscore, score_totalduration)
              VALUES
                (:teamId, :roundId, 0, '00:00')
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
            duration: const Duration(seconds: 3),
          ),
        );
      }
      
      // Reload data to show new scores
      await _loadData(initial: false);
      
    } catch (e) {
      print("Error initializing scores: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Failed to initialize scores: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isInitializingScores = false);
      }
    }
  }

  // ── Clear all scores for a category ─────────────────────────────────────
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
      
      // Delete scores for teams in this category
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
      
      // Reload data
      await _loadData(initial: false);
      
    } catch (e) {
      print("Error clearing scores: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Failed to clear scores: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // ── Update individual score ─────────────────────────────────────────────
  Future<void> _updateScore(int teamId, int roundId, int newScore) async {
    try {
      final conn = await DBHelper.getConnection();
      
      // Check if score record exists
      final checkResult = await conn.execute("""
        SELECT COUNT(*) as cnt 
        FROM tbl_score 
        WHERE team_id = :teamId AND round_id = :roundId
      """, {"teamId": teamId, "roundId": roundId});
      
      final exists = int.tryParse(
        checkResult.rows.first.assoc()['cnt']?.toString() ?? '0'
      ) ?? 0;
      
      if (exists > 0) {
        // Update existing score
        await conn.execute("""
          UPDATE tbl_score 
          SET score_totalscore = :score
          WHERE team_id = :teamId AND round_id = :roundId
        """, {
          "score": newScore,
          "teamId": teamId,
          "roundId": roundId,
        });
      } else {
        // Insert new score record
        await conn.execute("""
          INSERT INTO tbl_score
            (team_id, round_id, score_totalscore, score_totalduration)
          VALUES
            (:teamId, :roundId, :score, '00:00')
        """, {
          "teamId": teamId,
          "roundId": roundId,
          "score": newScore,
        });
      }
      
      // Update local data
      setState(() {
        for (final catStandings in _standingsByCategory.values) {
          for (final team in catStandings) {
            if (team['team_id'] == teamId) {
              final rounds = team['rounds'] as Map<int, Map<String, dynamic>>;
              if (rounds.containsKey(roundId)) {
                rounds[roundId]!['score'] = newScore;
              } else {
                // Create round data if it doesn't exist
                rounds[roundId] = {
                  'score': newScore,
                  'duration': '00:00',
                };
              }
              // Recalculate total
              int total = 0;
              rounds.forEach((_, data) {
                total += (data['score'] as int? ?? 0);
              });
              team['totalScore'] = total;
            }
          }
        }
      });
      
    } catch (e) {
      print("Error updating score: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Failed to update score: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // ── Show score edit dialog ──────────────────────────────────────────────
  void _showScoreEditDialog(
    int teamId, 
    String teamName, 
    int roundId, 
    int currentScore
  ) {
    final controller = TextEditingController(text: currentScore.toString());
    
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          width: 320,
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF2D0E7A), Color(0xFF1E0A5A)],
            ),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
                color: const Color(0xFF00CFFF).withOpacity(0.4), width: 1.5),
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
                    child: const Icon(Icons.edit_note_rounded,
                        color: Color(0xFF00CFFF), size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(teamName,
                            style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 14),
                            overflow: TextOverflow.ellipsis),
                        Text('Round $roundId',
                            style: TextStyle(
                                color: Colors.white.withOpacity(0.5),
                                fontSize: 11)),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              TextField(
                controller: controller,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: Color(0xFF00CFFF),
                    fontSize: 32,
                    fontWeight: FontWeight.bold),
                decoration: InputDecoration(
                  labelText: 'SCORE',
                  labelStyle: TextStyle(
                      color: Colors.white.withOpacity(0.5), fontSize: 12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(
                        color: const Color(0xFF00CFFF).withOpacity(0.3)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(
                        color: const Color(0xFF00CFFF).withOpacity(0.3)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(
                        color: Color(0xFF00CFFF), width: 2),
                  ),
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
                        final newScore = int.tryParse(controller.text.trim()) ?? 0;
                        _updateScore(teamId, roundId, newScore);
                        Navigator.pop(ctx);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF00CFFF),
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

  // ── Load data ─────────────────────────────────────────────────────────────
  Future<void> _loadData({bool initial = false}) async {
    if (initial) {
      setState(() => _isLoading = true);
    }

    try {
      final categories = await DBHelper.getCategories();
      final Map<int, List<Map<String, dynamic>>> standingsByCategory = {};

      for (final cat in categories) {
        final catId = int.tryParse(cat['category_id'].toString()) ?? 0;
        final rows  = await DBHelper.getScoresByCategory(catId);

        final Map<int, Map<String, dynamic>> teamMap = {};
        
        // First, get all teams in this category (even those without scores)
        final teams = await DBHelper.getTeamsByCategory(catId);
        for (final team in teams) {
          final teamId = int.tryParse(team['team_id'].toString()) ?? 0;
          teamMap[teamId] = {
            'team_id': teamId,
            'team_name': team['team_name'] ?? '',
            'rounds': <int, Map<String, dynamic>>{},
            'totalScore': 0,
          };
        }

        // Then populate scores where they exist
        int maxRoundFound = 0;
        for (final row in rows) {
          final teamId   = int.tryParse(row['team_id'].toString()) ?? 0;
          final roundId  = int.tryParse(row['round_id']?.toString() ?? '0') ?? 0;
          final score    = int.tryParse(row['score_totalscore'].toString()) ?? 0;
          final duration = row['score_totalduration']?.toString() ?? '00:00';

          if (teamMap.containsKey(teamId)) {
            final roundData = {
              'score': score,
              'duration': duration,
            };
            teamMap[teamId]!['rounds'][roundId] = roundData;
            
            // Update total score for this team
            teamMap[teamId]!['totalScore'] = (teamMap[teamId]!['totalScore'] as int) + score;
            
            if (roundId > maxRoundFound) {
              maxRoundFound = roundId;
            }
          }
        }

        // Determine the number of rounds
        int maxRounds = 0;
        
        // Method 1: Get from category settings
        try {
          final settingsResult = await (await DBHelper.getConnection()).execute("""
            SELECT matches_per_team 
            FROM tbl_category_settings 
            WHERE category_id = :catId
          """, {"catId": catId});
          
          if (settingsResult.rows.isNotEmpty) {
            maxRounds = int.tryParse(settingsResult.rows.first.assoc()['matches_per_team']?.toString() ?? '0') ?? 0;
          }
        } catch (e) {}
        
        // Method 2: If no settings, use max round found
        if (maxRounds == 0 && maxRoundFound > 0) {
          maxRounds = maxRoundFound;
        }
        
        // Method 3: If there are teams but no rounds yet, check schedule
        if (maxRounds == 0 && teams.isNotEmpty) {
          final roundCheck = await (await DBHelper.getConnection()).execute("""
            SELECT COUNT(DISTINCT round_id) as round_count
            FROM tbl_teamschedule ts
            JOIN tbl_team t ON ts.team_id = t.team_id
            WHERE t.category_id = :catId
          """, {"catId": catId});
          
          if (roundCheck.rows.isNotEmpty) {
            final roundCount = int.tryParse(roundCheck.rows.first.assoc()['round_count']?.toString() ?? '0') ?? 0;
            if (roundCount > 0) {
              maxRounds = roundCount;
            }
          }
        }
        
        // Method 4: Default to 4
        if (maxRounds == 0 && teams.isNotEmpty) {
          maxRounds = 4;
        }

        // Convert to list and sort by total score
        final standings = teamMap.values.map((teamData) {
          return {
            'team_id': teamData['team_id'],
            'team_name': teamData['team_name'],
            'rounds': teamData['rounds'],
            'totalScore': teamData['totalScore'],
            'maxRounds': maxRounds,
          };
        }).toList();

        // Sort by total score (highest first)
        standings.sort((a, b) =>
            (b['totalScore'] as int).compareTo(a['totalScore'] as int));

        // Add rank
        for (int i = 0; i < standings.length; i++) {
          standings[i]['rank'] = i + 1;
        }

        standingsByCategory[catId] = standings;
      }

      // Preserve current tab index
      final previousTabIndex = _tabController?.index ?? 0;

      _tabController?.dispose();
      _tabController = TabController(
        length: categories.length,
        vsync: this,
        initialIndex: previousTabIndex.clamp(0, (categories.length - 1).clamp(0, 9999)),
      );

      setState(() {
        _categories          = categories;
        _standingsByCategory = standingsByCategory;
        _isLoading           = false;
        _lastUpdated         = DateTime.now();
      });
      
      // Update signature
      final conn = await DBHelper.getConnection();
      final result = await conn.execute(
          "SELECT score_id, team_id, round_id, score_totalscore FROM tbl_score ORDER BY score_id");
      final rows = result.rows.map((r) => r.assoc()).toList();
      _lastDataSignature = _buildSignature(rows);
      
    } catch (e) {
      print("Error loading standings: $e");
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Failed to load standings: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────
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

  // ── Standings view per category ───────────────────────────────────────────
  Widget _buildStandingsView(
    Map<String, dynamic> category,
    int categoryId,
    List<Map<String, dynamic>> rows,
  ) {
    final categoryName =
        (category['category_type'] ?? '').toString().toUpperCase();

    // Get the maximum number of rounds from the data
    final maxRounds = rows.isNotEmpty 
        ? (rows.first['maxRounds'] as int? ?? 4) 
        : 4;

    // Check if any scores exist
    bool hasScores = false;
    for (final row in rows) {
      final rounds = row['rounds'] as Map<int, Map<String, dynamic>>;
      for (final roundData in rounds.values) {
        if ((roundData['score'] as int? ?? 0) > 0) {
          hasScores = true;
          break;
        }
      }
      if (hasScores) break;
    }

    return Column(
      children: [
        // ── Category title bar with score actions ─────────────────────
        Container(
          width: double.infinity,
          color: const Color(0xFF2D0E7A),
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 32),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'ROBOVENTURE',
                style: TextStyle(
                  color: Colors.white54,
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 2,
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
                  // Initialize scores button
                  if (rows.isNotEmpty && !hasScores)
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
                        label: Text(
                            _isInitializingScores ? '...' : 'INIT SCORES'),
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
                  
                  // Clear scores button (if scores exist)
                  if (hasScores)
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
                  if (maxRounds > 0)
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

        // ── Table header ─────────────────────────────────────────────
        Container(
          color: const Color(0xFF5C2ECC),
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 24),
          child: Row(
            children: [
              _headerCell('RANK',       flex: 1),
              _headerCell('TEAM ID',    flex: 2),
              _headerCell('TEAM NAME',  flex: 3),
              ...List.generate(
                maxRounds,
                (i) => _headerCell('ROUND ${i + 1}', flex: 2, center: true),
              ),
              _headerCell('TOTAL', flex: 2, center: true),
            ],
          ),
        ),

        // ── Rows ─────────────────────────────────────────────────────
        Expanded(
          child: rows.isEmpty
              ? const Center(
                  child: Text('No teams registered yet.',
                      style: TextStyle(color: Colors.white54, fontSize: 14)),
                )
              : ListView.builder(
                  itemCount: rows.length,
                  itemBuilder: (context, index) {
                    final row      = rows[index];
                    final rank     = row['rank'] as int;
                    final teamId   = row['team_id'];
                    final teamName = row['team_name'] as String;
                    final rounds   = row['rounds']
                        as Map<int, Map<String, dynamic>>;
                    final total    = row['totalScore'] as int;
                    final isEven   = index % 2 == 0;

                    return Container(
                      color: isEven
                          ? const Color(0xFF1E0E5A)
                          : const Color(0xFF160A42),
                      padding: const EdgeInsets.symmetric(
                          vertical: 16, horizontal: 24),
                      child: Row(
                        children: [
                          // Rank
                          Expanded(
                            flex: 1,
                            child: Text(
                              '$rank',
                              style: TextStyle(
                                color: _rankColor(rank),
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                          ),
                          // Team ID
                          Expanded(
                            flex: 2,
                            child: Text(
                              'C${teamId.toString().padLeft(3, '0')}R',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                          ),
                          // Team Name
                          Expanded(
                            flex: 3,
                            child: Text(
                              teamName.toUpperCase(),
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          // Scores for each round (tap to edit)
                          ...List.generate(maxRounds, (i) {
                            final roundData = rounds[i + 1];
                            final score = roundData?['score'] ?? 0;
                            final hasScore = rounds.containsKey(i + 1);
                            
                            return Expanded(
                              flex: 2,
                              child: GestureDetector(
                                onTap: () {
                                  _showScoreEditDialog(
                                    teamId, 
                                    teamName, 
                                    i + 1, 
                                    score
                                  );
                                },
                                child: Container(
                                  margin: const EdgeInsets.symmetric(horizontal: 4),
                                  padding: const EdgeInsets.symmetric(
                                      vertical: 8, horizontal: 4),
                                  decoration: BoxDecoration(
                                    color: hasScore
                                        ? const Color(0xFF00CFFF).withOpacity(0.1)
                                        : Colors.transparent,
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(
                                      color: hasScore
                                          ? const Color(0xFF00CFFF).withOpacity(0.2)
                                          : Colors.transparent,
                                    ),
                                  ),
                                  child: Column(
                                    children: [
                                      Text(
                                        score > 0 ? '$score' : (hasScore ? '0' : '—'),
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          color: score > 0 || hasScore
                                              ? Colors.white 
                                              : Colors.white24,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 18,
                                        ),
                                      ),
                                      if (hasScore)
                                        const Icon(Icons.edit_note_rounded,
                                            color: Color(0xFF00CFFF), size: 12),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          }),
                          // Total Score
                          Expanded(
                            flex: 2,
                            child: Column(
                              children: [
                                Text(
                                  '$total',
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    color: Color(0xFFFFD700),
                                    fontWeight: FontWeight.bold,
                                    fontSize: 20,
                                  ),
                                ),
                                Text(
                                  _bestDuration(rounds),
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    color: Colors.white60,
                                    fontSize: 11,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  Color _rankColor(int rank) {
    switch (rank) {
      case 1:  return const Color(0xFFFFD700); // Gold
      case 2:  return const Color(0xFFC0C0C0); // Silver
      case 3:  return const Color(0xFFCD7F32); // Bronze
      default: return Colors.white;
    }
  }

  String _bestDuration(Map<int, Map<String, dynamic>> rounds) {
    if (rounds.isEmpty) return '00:00';
    int    bestScore    = -1;
    String bestDuration = '00:00';
    for (final r in rounds.values) {
      final s = r['score'] as int? ?? 0;
      if (s > bestScore) {
        bestScore    = s;
        bestDuration = r['duration'] as String? ?? '00:00';
      }
    }
    return bestDuration;
  }

  // ── Widgets ───────────────────────────────────────────────────────────────

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
          height: 1.3,
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
                            fontWeight: FontWeight.bold)),
                    TextSpan(
                        text: 'bl',
                        style: TextStyle(
                            color: Color(0xFF00CFFF),
                            fontSize: 22,
                            fontWeight: FontWeight.bold)),
                    TextSpan(
                        text: 'ock',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
              const Text('Construct Your Dreams',
                  style: TextStyle(color: Colors.white54, fontSize: 10)),
            ],
          ),
          Image.asset('assets/images/CenterLogo.png',
              height: 80, fit: BoxFit.contain),
          const Text('CREOTEC',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 3)),
        ],
      ),
    );
  }

  // ── Live indicator ────────────────────────────────────────────────────────
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
                  style: TextStyle(
                      color: Color(0xFF00FF88),
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1)),
              Text(timeStr,
                  style: const TextStyle(color: Colors.white54, fontSize: 9)),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Pulsing dot animation ─────────────────────────────────────────────────────
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
    _anim = Tween<double>(begin: 0.3, end: 1.0).animate(
        CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
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