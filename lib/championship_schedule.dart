// championship_schedule.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'db_helper.dart';
import 'championship_settings.dart';
import 'championship_settings_dialog.dart';
import 'double_elimination_bracket.dart';
import 'constants.dart';

enum ChampionshipView { schedule, bracket }

class ChampionshipSchedule extends StatefulWidget {
  final int categoryId;
  final String categoryName;

  const ChampionshipSchedule({
    super.key,
    required this.categoryId,
    required this.categoryName,
  });

  @override
  State<ChampionshipSchedule> createState() => _ChampionshipScheduleState();
}

class _ChampionshipScheduleState extends State<ChampionshipSchedule> {
  List<Map<String, dynamic>> _matches = [];
  bool _isLoading = true;
  String? _error;
  ChampionshipSettings? _settings;
  bool _isGenerating = false;
  int _allianceCount = 0;
  ChampionshipView _currentView = ChampionshipView.schedule;
  bool _isExplorer = false;
  int _refreshKey = 0;
  // Subscription to DBHelper bracket update events
  StreamSubscription<int>? _bracketSub;

  @override
  void initState() {
    super.initState();
    _checkCategoryType();
    _loadSettingsAndMatches();
    // Subscribe to bracket updates so UI reloads when winners are propagated
    try {
      _bracketSub = DBHelper.bracketUpdateController.stream.listen((catId) {
        if (catId == widget.categoryId) {
          print('ℹ️ ChampionshipSchedule: received bracket update for category $catId - reloading matches');
          _loadMatches();
        }
      });
    } catch (_) {}
  }

  @override
  void dispose() {
    _bracketSub?.cancel();
    super.dispose();
  }

  Future<void> _checkCategoryType() async {
    final categoryNameLower = widget.categoryName.toLowerCase();
    if (categoryNameLower.contains('explorer')) {
      setState(() {
        _isExplorer = true;
        _currentView = ChampionshipView.bracket;
      });
    }
  }

  Future<void> _loadSettingsAndMatches() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final settings = await DBHelper.loadChampionshipSettings(widget.categoryId);
      await _loadAllianceCount();
      
      setState(() {
        _settings = settings ?? ChampionshipSettings.defaults(widget.categoryId);
      });
      
      await _loadMatches();
      
    } catch (e, stackTrace) {
      print("❌ ChampionshipSchedule error: $e");
      print(stackTrace);
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _loadAllianceCount() async {
    try {
      final conn = await DBHelper.getConnection();
      final result = await conn.execute("""
        SELECT COUNT(*) as cnt 
        FROM tbl_alliance_selections 
        WHERE category_id = :catId
      """, {"catId": widget.categoryId});
      
      if (result.rows.isNotEmpty) {
        setState(() {
          _allianceCount = int.parse(result.rows.first.assoc()['cnt']?.toString() ?? '0');
        });
      }
    } catch (e) {
      print("Error getting alliance count: $e");
    }
  }

  Future<void> _loadMatches() async {
    try {
      print("🏆 ChampionshipSchedule: Loading matches for category ${widget.categoryId}");
      
      final conn = await DBHelper.getConnection();
      bool hasBracketData = false;

      try {
        // Check multiple possible bracket table names: canonical, explorer mirror,
        // and category-specific slug-based table (e.g. tbl_<slug>_double_elimination).
        final List<String> tablesToCheck = [
          'tbl_double_elimination',
          'tbl_explorer_double_elimination',
        ];

        // Try to resolve a category slug to check category-specific mirrored tables
        try {
          final cres = await conn.execute(
            "SELECT category_type FROM tbl_category WHERE category_id = :id LIMIT 1",
            {"id": widget.categoryId},
          );
          if (cres.rows.isNotEmpty) {
            String? slug = cres.rows.first.assoc()['category_type']?.toString();
            if (slug != null && slug.trim().isNotEmpty) {
              slug = slug.replaceAll(RegExp(r"\(.*?\)"), '').toLowerCase();
              slug = slug.replaceAll(RegExp(r"[^a-z0-9]+"), '_').replaceAll(RegExp(r"_+"), '_');
              slug = slug.replaceAll(RegExp(r"^_+|_+"), '').trim();
              if (slug.isNotEmpty) tablesToCheck.add('tbl_' + slug + '_double_elimination');
            }
          }
        } catch (_) {}

        for (final tbl in tablesToCheck) {
          try {
            final bracketCheck = await conn.execute(
              "SELECT COUNT(*) as cnt FROM $tbl WHERE category_id = :catId",
              {"catId": widget.categoryId},
            );
            if (bracketCheck.rows.isNotEmpty) {
              if (int.parse(bracketCheck.rows.first.assoc()['cnt']?.toString() ?? '0') > 0) {
                hasBracketData = true;
                break;
              }
            }
          } catch (_) {
            // ignore missing table or errors for this candidate table
          }
        }
      } catch (e) {
        print("⚠️ No bracket table yet: $e");
      }
      
      List<Map<String, dynamic>> matches;
      
      if (hasBracketData) {
        matches = await _getMatchesFromBracket();
      } else {
        matches = await _getMatchesFromSchedule();
      }
      
      setState(() {
        _matches = matches;
        _isLoading = false;
      });
      
      print("🏆 ChampionshipSchedule: Loaded ${matches.length} matches");
      
    } catch (e, stackTrace) {
      print("❌ ChampionshipSchedule error: $e");
      print(stackTrace);
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<List<Map<String, dynamic>>> _getMatchesFromBracket() async {
    final conn = await DBHelper.getConnection();
    // Determine which bracket table actually contains data: canonical, explorer, or category-specific
    String bracketTable = 'tbl_double_elimination';
    try {
      final candidates = ['tbl_double_elimination', 'tbl_explorer_double_elimination'];
      // try resolve category slug
      try {
        final cres = await conn.execute(
          "SELECT category_type FROM tbl_category WHERE category_id = :id LIMIT 1",
          {"id": widget.categoryId},
        );
        if (cres.rows.isNotEmpty) {
          String? slug = cres.rows.first.assoc()['category_type']?.toString();
          if (slug != null && slug.trim().isNotEmpty) {
            slug = slug.replaceAll(RegExp(r"\(.*?\)"), '').toLowerCase();
            slug = slug.replaceAll(RegExp(r"[^a-z0-9]+"), '_').replaceAll(RegExp(r"_+"), '_');
            slug = slug.replaceAll(RegExp(r"^_+|_+"), '').trim();
            if (slug.isNotEmpty) candidates.add('tbl_' + slug + '_double_elimination');
          }
        }
      } catch (_) {}

      for (final tbl in candidates) {
        try {
          final cnt = await conn.execute("SELECT COUNT(*) as cnt FROM $tbl WHERE category_id = :catId", {"catId": widget.categoryId});
          if (cnt.rows.isNotEmpty && int.parse(cnt.rows.first.assoc()['cnt']?.toString() ?? '0') > 0) {
            bracketTable = tbl;
            break;
          }
        } catch (_) {}
      }
    } catch (e) {
      print('⚠️ bracket table detection failed: $e');
    }

    print('🏁 Using bracket table: $bracketTable');

    final result = await conn.execute("""
      SELECT 
        match_id,
        round_name,
        match_position,
        bracket_side,
        round_number,
        alliance1_id,
        alliance2_id,
        winner_alliance_id,
        status,
        schedule_time,
        next_match_id_winner,
        next_match_id_loser
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
    """, {"catId": widget.categoryId});
    
    final rows = <Map<String, dynamic>>[];
    
    for (final row in result.rows) {
      final data = row.assoc();
      
      if (data['alliance1_id'] != null && int.parse(data['alliance1_id'].toString()) > 0) {
        final alliance = await _getAllianceById(int.parse(data['alliance1_id'].toString()));
        data['alliance1_name'] = alliance != null 
            ? '${alliance['captain_name']} / ${alliance['partner_name']}'
            : 'Unknown';
        data['alliance1_rank'] = alliance != null ? '#${alliance['alliance_rank']}' : '#?';
      } else {
        data['alliance1_name'] = 'TBD';
        data['alliance1_rank'] = '?';
      }
      
      if (data['alliance2_id'] != null && int.parse(data['alliance2_id'].toString()) > 0) {
        final alliance = await _getAllianceById(int.parse(data['alliance2_id'].toString()));
        data['alliance2_name'] = alliance != null 
            ? '${alliance['captain_name']} / ${alliance['partner_name']}'
            : 'Unknown';
        data['alliance2_rank'] = alliance != null ? '#${alliance['alliance_rank']}' : '#?';
      } else {
        data['alliance2_name'] = 'TBD';
        data['alliance2_rank'] = '?';
      }
      
      String displayRound = '';
      final side = data['bracket_side'] as String;
      final roundNum = int.parse(data['round_number'].toString());
      
      if (side == 'winners') {
        if (roundNum == 1) displayRound = 'QUARTER-FINAL';
        else if (roundNum == 2) displayRound = 'SEMI-FINAL';
        else if (roundNum == 3) displayRound = 'WINNER\'S FINAL';
        else displayRound = 'ROUND $roundNum';
      } else if (side == 'losers') {
        if (roundNum == 1) displayRound = 'LOSER\'S ROUND 1';
        else if (roundNum == 2) displayRound = 'LOSER\'S ROUND 2';
        else if (roundNum >= _getMaxLoserRound() - 1) displayRound = 'LOSER\'S FINAL';
        else displayRound = 'LOSER\'S ROUND $roundNum';
      } else if (side == 'grand') {
        displayRound = data['round_name'] == 'GF1' ? 'GRAND FINAL' : 'GRAND FINAL (RESET)';
      }
      
      data['display_round'] = displayRound;
      
      rows.add(data);
    }
    
    return rows;
  }

  Future<List<Map<String, dynamic>>> _getMatchesFromSchedule() async {
    final conn = await DBHelper.getConnection();
    
    try {
      await conn.execute("SELECT 1 FROM tbl_championship_schedule LIMIT 1");
    } catch (e) {
      print("⚠️ tbl_championship_schedule doesn't exist yet");
      return [];
    }
    
    final result = await conn.execute("""
      SELECT 
        cs.match_id,
        cs.category_id,
        cs.match_round,
        cs.match_position,
        cs.schedule_time,
        cs.status,
        cs.alliance1_id,
        cs.alliance2_id,
        a1.alliance_id as a1_id,
        a2.alliance_id as a2_id,
        t1.team_name as captain1_name,
        t2.team_name as partner1_name,
        t3.team_name as captain2_name,
        t4.team_name as partner2_name,
        a1.selection_round as alliance1_rank,
        a2.selection_round as alliance2_rank
      FROM tbl_championship_schedule cs
      LEFT JOIN tbl_alliance_selections a1 ON cs.alliance1_id = a1.alliance_id
      LEFT JOIN tbl_alliance_selections a2 ON cs.alliance2_id = a2.alliance_id
      LEFT JOIN tbl_team t1 ON a1.captain_team_id = t1.team_id
      LEFT JOIN tbl_team t2 ON a1.partner_team_id = t2.team_id
      LEFT JOIN tbl_team t3 ON a2.captain_team_id = t3.team_id
      LEFT JOIN tbl_team t4 ON a2.partner_team_id = t4.team_id
      WHERE cs.category_id = :categoryId
      ORDER BY cs.match_round, cs.match_position
    """, {"categoryId": widget.categoryId});
    
    final rows = result.rows.map((r) {
      final data = r.assoc();
      
      if (data['alliance1_id'] != null && data['alliance1_id'] != '0') {
        final captain = data['captain1_name'] ?? '???';
        final partner = data['partner1_name'] ?? '???';
        data['alliance1_name'] = '$captain + $partner';
        data['alliance1_rank'] = data['alliance1_rank'] ?? '?';
      } else {
        data['alliance1_name'] = 'TBD';
        data['alliance1_rank'] = '?';
      }
      
      if (data['alliance2_id'] != null && data['alliance2_id'] != '0') {
        final captain = data['captain2_name'] ?? '???';
        final partner = data['partner2_name'] ?? '???';
        data['alliance2_name'] = '$captain + $partner';
        data['alliance2_rank'] = data['alliance2_rank'] ?? '?';
      } else {
        data['alliance2_name'] = 'TBD';
        data['alliance2_rank'] = '?';
      }
      
      data['display_round'] = _getRoundName(
        int.parse(data['match_round'].toString()), 
        int.parse(data['match_position'].toString())
      );
      
      return data;
    }).toList();
    
    return rows;
  }

  Future<Map<String, dynamic>?> _getAllianceById(int allianceId) async {
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
        WHERE a.alliance_id = :allianceId AND a.category_id = :catId
      """, {
        "allianceId": allianceId,
        "catId": widget.categoryId,
      });
      
      if (result.rows.isNotEmpty) {
        return result.rows.first.assoc();
      }
    } catch (e) {
      print("Error getting alliance: $e");
    }
    return null;
  }

  int _getMaxLoserRound() {
    if (_allianceCount == 4) return 2;
    if (_allianceCount == 8) return 4;
    return 3;
  }

  void _refreshMatches() {
    setState(() {
      _refreshKey++;
    });
    _loadMatches();
  }

  String _getRoundName(int round, int position) {
    if (_allianceCount == 2) {
      return 'FINAL';
    } else {
      if (round == 1) {
        if (_allianceCount >= 8) return 'QUARTER-FINAL';
        if (_allianceCount >= 4) return 'SEMI-FINAL';
        return 'FINAL';
      } else if (round == 2) {
        return 'SEMI-FINAL';
      } else if (round == 3) {
        return 'FINAL';
      }
      return 'ROUND $round';
    }
  }

  Widget _buildViewToggle() {
    if (!_isExplorer) return const SizedBox.shrink();
    
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF1A0A4A),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: const Color(0xFFFFD700).withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _toggleButton(
            label: 'SCHEDULE',
            isSelected: _currentView == ChampionshipView.schedule,
            onTap: () => setState(() => _currentView = ChampionshipView.schedule),
          ),
          _toggleButton(
            label: 'BRACKET',
            isSelected: _currentView == ChampionshipView.bracket,
            onTap: () => setState(() => _currentView = ChampionshipView.bracket),
          ),
        ],
      ),
    );
  }

  Widget _toggleButton({
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFFFFD700) : Colors.transparent,
          borderRadius: BorderRadius.circular(30),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.black : const Color(0xFFFFD700),
            fontWeight: FontWeight.bold,
            fontSize: 12,
          ),
        ),
      ),
    );
  }

  Widget _buildScheduleView() {
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
                Icons.emoji_events,
                size: 64,
                color: Color(0xFFFFD700),
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'No Championship Schedule Yet',
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w800,
                letterSpacing: 1,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Click GENERATE BRACKET to create the championship bracket',
              style: TextStyle(
                color: Colors.white.withOpacity(0.5),
                fontSize: 14,
              ),
            ),
          ],
        ),
      );
    }

    final Map<String, List<Map<String, dynamic>>> matchesByRound = {};
    for (var match in _matches) {
      final roundKey = match['display_round'] as String;
      matchesByRound.putIfAbsent(roundKey, () => []).add(match);
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        ...matchesByRound.entries.map((entry) {
          final roundName = entry.key;
          final roundMatches = entry.value;

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Round Header
              Container(
                margin: const EdgeInsets.only(top: 8, bottom: 12),
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      const Color(0xFFFFD700).withOpacity(0.2),
                      const Color(0xFFFFD700).withOpacity(0.05),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(30),
                  border: Border.all(
                    color: const Color(0xFFFFD700).withOpacity(0.4),
                    width: 1.5,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      roundName.contains('FINAL') ? Icons.star : Icons.emoji_events,
                      color: const Color(0xFFFFD700),
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      roundName,
                      style: const TextStyle(
                        color: Color(0xFFFFD700),
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        letterSpacing: 1.5,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        '${roundMatches.length} MATCH${roundMatches.length > 1 ? 'ES' : ''}',
                        style: const TextStyle(
                          color: Colors.white60,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // Matches
              ...roundMatches.map((match) {
                final isCompleted = match['status'] == 'completed';
                final alliance1Name = match['alliance1_name'] ?? 'TBD';
                final alliance2Name = match['alliance2_name'] ?? 'TBD';
                final alliance1Rank = match['alliance1_rank'] ?? '#?';
                final alliance2Rank = match['alliance2_rank'] ?? '#?';
                final winnerId = match['winner_alliance_id'];
                final isWinner1 = winnerId != null && winnerId.toString() == match['alliance1_id']?.toString();
                final isWinner2 = winnerId != null && winnerId.toString() == match['alliance2_id']?.toString();

                return Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        const Color(0xFF1A0A4A),
                        const Color(0xFF2D0E7A).withOpacity(0.5),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: isCompleted
                          ? Colors.green.withOpacity(0.5)
                          : const Color(0xFFFFD700).withOpacity(0.3),
                      width: isCompleted ? 2 : 1.5,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.2),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      // Time and Status Bar
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0F0630).withOpacity(0.6),
                          borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(14),
                          ),
                          border: Border(
                            bottom: BorderSide(
                              color: isCompleted ? Colors.green.withOpacity(0.3) : const Color(0xFFFFD700).withOpacity(0.2),
                              width: 1,
                            ),
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            // Time
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(4),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFFFD700).withOpacity(0.15),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: const Icon(
                                    Icons.access_time,
                                    color: Color(0xFFFFD700),
                                    size: 14,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  match['schedule_time'] ?? '--:--',
                                  style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                            
                            // Status Badge
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                              decoration: BoxDecoration(
                                color: isCompleted
                                    ? Colors.green.withOpacity(0.15)
                                    : Colors.orange.withOpacity(0.15),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: isCompleted
                                      ? Colors.green.withOpacity(0.5)
                                      : Colors.orange.withOpacity(0.5),
                                  width: 1,
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    isCompleted ? Icons.check_circle : Icons.schedule,
                                    color: isCompleted ? Colors.green : Colors.orange,
                                    size: 12,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    isCompleted ? 'COMPLETED' : 'PENDING',
                                    style: TextStyle(
                                      color: isCompleted ? Colors.green : Colors.orange,
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      
                      // Match Content
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          children: [
                            // Alliance 1
                            Expanded(
                              child: Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                    colors: [
                                      isWinner1
                                          ? Colors.green.withOpacity(0.25)
                                          : const Color(0xFF00CFFF).withOpacity(0.1),
                                      isWinner1
                                          ? Colors.green.withOpacity(0.1)
                                          : const Color(0xFF00CFFF).withOpacity(0.05),
                                    ],
                                  ),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: isWinner1
                                        ? Colors.green
                                        : const Color(0xFF00CFFF).withOpacity(0.4),
                                    width: isWinner1 ? 2 : 1.5,
                                  ),
                                  boxShadow: isWinner1
                                      ? [
                                          BoxShadow(
                                            color: Colors.green.withOpacity(0.3),
                                            blurRadius: 8,
                                            spreadRadius: 1,
                                          )
                                        ]
                                      : [],
                                ),
                                child: Column(
                                  children: [
                                    // Rank Badge
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF00CFFF).withOpacity(0.2),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const Icon(
                                            Icons.flag,
                                            color: Color(0xFF00CFFF),
                                            size: 10,
                                          ),
                                          const SizedBox(width: 4),
                                          Text(
                                            alliance1Rank,
                                            style: const TextStyle(
                                              color: Color(0xFF00CFFF),
                                              fontSize: 10,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      alliance1Name,
                                      style: TextStyle(
                                        color: isWinner1 ? Colors.green : Colors.white,
                                        fontWeight: isWinner1 ? FontWeight.bold : FontWeight.w600,
                                        fontSize: 13,
                                        height: 1.3,
                                      ),
                                      textAlign: TextAlign.center,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    if (isWinner1) ...[
                                      const SizedBox(height: 6),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                        decoration: BoxDecoration(
                                          color: Colors.green.withOpacity(0.2),
                                          borderRadius: BorderRadius.circular(12),
                                        ),
                                        child: const Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(
                                              Icons.emoji_events,
                                              color: Colors.green,
                                              size: 12,
                                            ),
                                            SizedBox(width: 4),
                                            Text(
                                              'WINNER',
                                              style: TextStyle(
                                                color: Colors.green,
                                                fontSize: 9,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                            
                            // VS Divider
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 12),
                              child: Container(
                                width: 50,
                                height: 50,
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                    colors: isCompleted
                                        ? [Colors.green.withOpacity(0.3), Colors.green.withOpacity(0.1)]
                                        : [const Color(0xFFFFD700).withOpacity(0.3), const Color(0xFFFFD700).withOpacity(0.1)],
                                  ),
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: isCompleted ? Colors.green : const Color(0xFFFFD700),
                                    width: 2,
                                  ),
                                ),
                                child: Center(
                                  child: Text(
                                    isCompleted ? 'WIN' : 'VS',
                                    style: TextStyle(
                                      color: isCompleted ? Colors.green : const Color(0xFFFFD700),
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
                                      letterSpacing: 1,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            
                            // Alliance 2
                            Expanded(
                              child: Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                    colors: [
                                      isWinner2
                                          ? Colors.green.withOpacity(0.25)
                                          : const Color(0xFF00FF88).withOpacity(0.1),
                                      isWinner2
                                          ? Colors.green.withOpacity(0.1)
                                          : const Color(0xFF00FF88).withOpacity(0.05),
                                    ],
                                  ),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: isWinner2
                                        ? Colors.green
                                        : const Color(0xFF00FF88).withOpacity(0.4),
                                    width: isWinner2 ? 2 : 1.5,
                                  ),
                                  boxShadow: isWinner2
                                      ? [
                                          BoxShadow(
                                            color: Colors.green.withOpacity(0.3),
                                            blurRadius: 8,
                                            spreadRadius: 1,
                                          )
                                        ]
                                      : [],
                                ),
                                child: Column(
                                  children: [
                                    // Rank Badge
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF00FF88).withOpacity(0.2),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const Icon(
                                            Icons.flag,
                                            color: Color(0xFF00FF88),
                                            size: 10,
                                          ),
                                          const SizedBox(width: 4),
                                          Text(
                                            alliance2Rank,
                                            style: const TextStyle(
                                              color: Color(0xFF00FF88),
                                              fontSize: 10,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      alliance2Name,
                                      style: TextStyle(
                                        color: isWinner2 ? Colors.green : Colors.white,
                                        fontWeight: isWinner2 ? FontWeight.bold : FontWeight.w600,
                                        fontSize: 13,
                                        height: 1.3,
                                      ),
                                      textAlign: TextAlign.center,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    if (isWinner2) ...[
                                      const SizedBox(height: 6),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                        decoration: BoxDecoration(
                                          color: Colors.green.withOpacity(0.2),
                                          borderRadius: BorderRadius.circular(12),
                                        ),
                                        child: const Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(
                                              Icons.emoji_events,
                                              color: Colors.green,
                                              size: 12,
                                            ),
                                            SizedBox(width: 4),
                                            Text(
                                              'WINNER',
                                              style: TextStyle(
                                                color: Colors.green,
                                                fontSize: 9,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      
                      // Round Info Footer
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0F0630).withOpacity(0.4),
                          borderRadius: const BorderRadius.vertical(
                            bottom: Radius.circular(14),
                          ),
                          border: Border(
                            top: BorderSide(
                              color: isCompleted ? Colors.green.withOpacity(0.2) : const Color(0xFFFFD700).withOpacity(0.1),
                              width: 1,
                            ),
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              match['bracket_side'] == 'grand' ? Icons.star : Icons.sports_esports,
                              color: const Color(0xFFFFD700).withOpacity(0.6),
                              size: 12,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              match['bracket_side'] == 'grand' 
                                  ? 'CHAMPIONSHIP MATCH' 
                                  : (match['display_round'] ?? 'MATCH'),
                              style: TextStyle(
                                color: const Color(0xFFFFD700).withOpacity(0.7),
                                fontSize: 10,
                                fontWeight: FontWeight.w500,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              }),
            ],
          );
        }),
      ],
    );
  }

  Widget _buildBracketView() {
    return DoubleEliminationBracket(
      key: ValueKey('bracket-${widget.categoryId}-$_refreshKey'),
      categoryId: widget.categoryId,
      categoryName: widget.categoryName,
      onMatchUpdated: () {
        _refreshMatches();
      },
    );
  }

  Future<void> _showSettingsDialog() async {
    if (_settings == null) return;
    
    final result = await showDialog<ChampionshipSettings>(
      context: context,
      builder: (context) => ChampionshipSettingsDialog(
        settings: _settings!,
        onSave: (updatedSettings) async {
          await DBHelper.saveChampionshipSettings(updatedSettings);
          
          setState(() {
            _settings = updatedSettings;
          });
          
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

  Future<void> _generateSchedule() async {
    if (_settings == null) return;
    
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF2D0E7A),
        title: Text('Generate Championship Schedule?', 
            style: const TextStyle(color: Colors.white)),
        content: Text(
          'This will generate ${_settings!.matchesPerAlliance} match(es) between the alliances for ${widget.categoryName}.\n\n'
          'Start: ${_settings!.startTime.format(context)}\n'
          'End: ${_settings!.endTime.format(context)}\n'
          'Duration: ${_settings!.durationMinutes} min per match\n'
          'Interval: ${_settings!.intervalMinutes} min between matches',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('CANCEL', style: TextStyle(color: Colors.white54)),
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
      await Future.delayed(const Duration(milliseconds: 100));
      
      await DBHelper.generateChampionshipScheduleWithSettings(
        widget.categoryId,
        _settings!,
      );
      
      await _loadAllianceCount();
      await _loadMatches();
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ Championship schedule generated for ${widget.categoryName}'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isGenerating = false);
    }
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
            Text(
              'Loading championship schedule...',
              style: TextStyle(color: Colors.white54),
            ),
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
              'Error loading championship schedule',
              style: TextStyle(color: Colors.redAccent),
            ),
            const SizedBox(height: 8),
            Text(
              _error!,
              style: TextStyle(color: Colors.white38, fontSize: 12),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loadSettingsAndMatches,
              child: const Text('RETRY'),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: const Color(0xFF1A0A4A),
            border: Border(
              bottom: BorderSide(color: const Color(0xFFFFD700).withOpacity(0.3)),
            ),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFD700).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFFFFD700).withOpacity(0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.timer, color: Color(0xFFFFD700), size: 14),
                    const SizedBox(width: 6),
                    Text(
                      '${_settings?.matchesPerAlliance ?? 1} match${(_settings?.matchesPerAlliance ?? 1) > 1 ? 'es' : ''} per alliance',
                      style: const TextStyle(color: Color(0xFFFFD700), fontSize: 12),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.white.withOpacity(0.1)),
                ),
                child: Text(
                  '${_settings?.durationMinutes} min matches',
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
              ),
              const Spacer(),
              
              _buildViewToggle(),
              const SizedBox(width: 10),
              
              IconButton(
                icon: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFFFFD700).withOpacity(0.1),
                  ),
                  child: const Icon(Icons.settings_rounded,
                      color: Color(0xFFFFD700), size: 18),
                ),
                onPressed: _showSettingsDialog,
                tooltip: 'Settings',
              ),
              IconButton(
                icon: _isGenerating
                    ? const SizedBox(
                        width: 18, height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Color(0xFFFFD700)))
                    : const Icon(Icons.refresh, color: Color(0xFFFFD700), size: 18),
                onPressed: _isGenerating ? null : _generateSchedule,
                tooltip: 'Regenerate Schedule',
              ),
            ],
          ),
        ),

        Expanded(
          child: _currentView == ChampionshipView.bracket
              ? _buildBracketView()
              : _buildScheduleView(),
        ),
      ],
    );
  }
}