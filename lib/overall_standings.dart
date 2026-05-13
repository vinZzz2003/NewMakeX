// overall_standings.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'db_helper.dart';
import 'constants.dart';

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

class OverallStandings extends StatefulWidget {
  final VoidCallback? onBack;

  const OverallStandings({super.key, this.onBack});

  @override
  State<OverallStandings> createState() => _OverallStandingsState();
}

class _OverallStandingsState extends State<OverallStandings> with TickerProviderStateMixin {
  TabController? _tabController;
  List<Map<String, dynamic>> _categories = [];
  bool _isLoading = true;
  DateTime? _lastUpdated;
  Timer? _autoRefreshTimer;
  
  // Store selected type per category
  final Map<int, StandingType> _selectedTypeByCategory = {};

  @override
  void initState() {
    super.initState();
    _loadCategories();
    _autoRefreshTimer = Timer.periodic(
      const Duration(seconds: 15),
      (_) => setState(() => _lastUpdated = DateTime.now()),
    );
  }

  @override
  void dispose() {
    _autoRefreshTimer?.cancel();
    _tabController?.dispose();
    super.dispose();
  }

  Future<void> _loadCategories() async {
    setState(() => _isLoading = true);
    try {
      final categories = await DBHelper.getCategories();
      final prevIndex = _tabController?.index ?? 0;
      _tabController?.dispose();
      _tabController = TabController(
        length: categories.length,
        vsync: this,
        initialIndex: prevIndex.clamp(0, (categories.length - 1).clamp(0, 999)),
      );
      
      // Initialize selected type for each category
      for (final cat in categories) {
        final catId = int.tryParse(cat['category_id'].toString()) ?? 0;
        if (!_selectedTypeByCategory.containsKey(catId)) {
          _selectedTypeByCategory[catId] = StandingType.qualification;
        }
      }
      
      setState(() {
        _categories = categories;
        _isLoading = false;
        _lastUpdated = DateTime.now();
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0E0630),
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
                  'No categories found.',
                  style: TextStyle(color: Colors.white38, fontSize: 16),
                ),
              ),
            )
          else ...[
            _buildTabBar(),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: _categories.map((cat) {
                  final catId = int.tryParse(cat['category_id'].toString()) ?? 0;
                  return _buildCategoryContent(cat, catId);
                }).toList(),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTabBar() {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF130A30),
        border: Border(bottom: BorderSide(color: Color(0xFF2A1560), width: 1)),
      ),
      child: TabBar(
        controller: _tabController,
        isScrollable: true,
        indicatorWeight: 3,
        indicatorColor: const Color(0xFF00CFFF),
        labelColor: Colors.white,
        unselectedLabelColor: Colors.white38,
        labelStyle: const TextStyle(
          fontWeight: FontWeight.bold,
          fontSize: 12,
          letterSpacing: 1.2,
        ),
        tabs: _categories.map((cat) {
          final categoryName = (cat['category_type'] ?? '').toString().toUpperCase();
          return Tab(text: categoryName);
        }).toList(),
      ),
    );
  }

  Widget _buildCategoryContent(Map<String, dynamic> category, int categoryId) {
    final categoryName = (category['category_type'] ?? '').toString();
    final isExplorer = categoryName.toLowerCase().contains('explorer');
    
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
                categoryName.toUpperCase(),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 2,
                ),
              ),

              Row(
                children: [
                  _buildLiveIndicator(),
                  IconButton(
                    tooltip: 'Back',
                    icon: const Icon(
                      Icons.arrow_back_ios_new,
                      color: Color(0xFF00CFFF),
                    ),
                    onPressed: widget.onBack,
                  ),
                  const SizedBox(width: 8),
                ],
              ),
            ],
          ),
        ),
        Expanded(
          child: _buildTabContent(
            selectedType,
            categoryId,
            isExplorer,
            categoryName,
          ),
        ),
      ],
    );
  }

  Widget _buildTabContent(
    StandingType selectedType,
    int categoryId,
    bool isExplorer,
    String categoryName,
  ) {
    switch (selectedType) {
      case StandingType.qualification:
        if (isExplorer) {
          return _buildQualificationOverallStandings(categoryId, categoryName);
        }
        return _buildPlaceholderTab(
          title: 'QUALIFICATION ROUND',
          color: const Color(0xFF00CFFF),
          icon: Icons.calendar_today_rounded,
        );
      case StandingType.championship:
        return _buildPlaceholderTab(
          title: 'CHAMPIONSHIP ROUND',
          color: const Color(0xFFFFD700),
          icon: Icons.emoji_events_rounded,
        );
      case StandingType.battleOfChampions:
        return _buildPlaceholderTab(
          title: 'BATTLE OF CHAMPIONS',
          color: const Color(0xFF00FF88),
          icon: Icons.military_tech_rounded,
        );
    }
  }

  Widget _buildQualificationOverallStandings(
    int categoryId,
    String categoryName,
  ) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _loadQualificationOverallExplorer(categoryId),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: CircularProgressIndicator(color: Color(0xFF00CFFF)),
          );
        }

        if (snapshot.hasError) {
          return Center(
            child: Text(
              'Error loading standings: ${snapshot.error}',
              style: const TextStyle(color: Colors.white54),
            ),
          );
        }

        final rows = snapshot.data ?? [];
        if (rows.isEmpty) {
          return const Center(
            child: Text(
              'No qualification data yet.',
              style: TextStyle(color: Colors.white54),
            ),
          );
        }

        return Column(
          children: [
            Container(
              color: const Color(0xFF5C2ECC),
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
              child: Row(
                children: [
                  _overallHeaderCell('RANK', flex: 1),
                  _overallHeaderCell('TEAM ID', flex: 2),
                  _overallHeaderCell('TEAM NAME', flex: 3, alignLeft: true),
                  _overallHeaderCell('TOTAL WINS', flex: 2),
                  _overallHeaderCell('TOTAL LOSE', flex: 2),
                  _overallHeaderCell('TIE', flex: 1),
                  _overallHeaderCell('SCORE', flex: 2),
                  _overallHeaderCell('TOTAL POINT DIFF', flex: 3),
                ],
              ),
            ),
            Expanded(
              child: ListView.builder(
                itemCount: rows.length,
                itemBuilder: (context, index) {
                  final row = rows[index];
                  final isEven = index % 2 == 0;
                  final totalDiff = row['total_point_diff'] as int;

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
                        _overallDataCell(
                          '${row['rank']}',
                          flex: 1,
                          color: _rankColor(row['rank'] as int),
                        ),
                        _overallDataCell(
                          formatTeamId(row['team_id'], categoryName),
                          flex: 2,
                        ),
                        _overallDataCell(
                          row['team_name'] as String,
                          flex: 3,
                          isName: true,
                        ),
                        _overallStatCell(
                          '${row['total_wins']}',
                          flex: 2,
                          textColor: const Color(0xFF00FF88),
                          backgroundColor:
                              const Color(0xFF00FF88).withOpacity(0.12),
                          borderColor:
                              const Color(0xFF00FF88).withOpacity(0.35),
                        ),
                        _overallStatCell(
                          '${row['total_losses']}',
                          flex: 2,
                          textColor: Colors.redAccent,
                          backgroundColor: Colors.redAccent.withOpacity(0.12),
                          borderColor: Colors.redAccent.withOpacity(0.35),
                        ),
                        _overallStatCell(
                          '${row['total_ties']}',
                          flex: 1,
                          textColor: const Color(0xFFFFD700),
                          backgroundColor:
                            const Color(0xFFFFD700).withOpacity(0.12),
                          borderColor:
                            const Color(0xFFFFD700).withOpacity(0.35),
                        ),
                        _overallStatCell(
                          '${row['total_score']}',
                          flex: 2,
                          textColor: const Color(0xFF00CFFF),
                          backgroundColor:
                            const Color(0xFF00CFFF).withOpacity(0.12),
                          borderColor:
                            const Color(0xFF00CFFF).withOpacity(0.35),
                        ),
                        _overallStatCell(
                          _formatDiff(totalDiff),
                          flex: 3,
                          textColor:
                              totalDiff > 0 ? const Color(0xFF00FF88) :
                              (totalDiff < 0 ? Colors.redAccent : Colors.white70),
                          borderColor:
                              totalDiff > 0 ? const Color(0xFF00FF88).withOpacity(0.4) :
                              (totalDiff < 0 ? Colors.redAccent.withOpacity(0.4) : Colors.white10),
                          backgroundColor:
                              totalDiff > 0 ? const Color(0xFF00FF88).withOpacity(0.12) :
                              (totalDiff < 0 ? Colors.redAccent.withOpacity(0.12) : Colors.white.withOpacity(0.03)),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }

  Future<List<Map<String, dynamic>>> _loadQualificationOverallExplorer(
    int categoryId,
  ) async {
    final conn = await DBHelper.getConnection();

    final teamsRes = await conn.execute(
      "SELECT team_id, team_name FROM tbl_team WHERE category_id = :catId",
      {"catId": categoryId},
    );

    final Map<int, Map<String, dynamic>> teamStats = {};
    for (final row in teamsRes.rows) {
      final data = row.assoc();
      final teamId = int.tryParse(data['team_id']?.toString() ?? '0') ?? 0;
      if (teamId == 0) continue;
      teamStats[teamId] = {
        'team_id': teamId,
        'team_name': data['team_name']?.toString() ?? '',
        'total_auto': 0,
        'total_manual': 0,
        'total_violation': 0,
        'total_score': 0,
        'total_wins': 0,
        'total_losses': 0,
        'total_ties': 0,
        'total_point_diff': 0,
      };
    }

    final scoresRes = await conn.execute(
      """
      SELECT
        s.team_id,
        s.round_id,
        s.score_independentscore as auto_score,
        s.score_manualscore as manual_score,
        s.score_violation as violation_score
      FROM tbl_explorer_score s
      JOIN tbl_team t ON s.team_id = t.team_id
      WHERE t.category_id = :catId
    """,
      {"catId": categoryId},
    );

    final Map<String, int> totalByTeamRound = {};
    for (final row in scoresRes.rows) {
      final data = row.assoc();
      final teamId = int.tryParse(data['team_id']?.toString() ?? '0') ?? 0;
      final roundId = int.tryParse(data['round_id']?.toString() ?? '0') ?? 0;
      if (teamId == 0 || roundId == 0) continue;

      final autoScore =
          int.tryParse(data['auto_score']?.toString() ?? '0') ?? 0;
      final manualScore =
          int.tryParse(data['manual_score']?.toString() ?? '0') ?? 0;
      final violationScore =
          int.tryParse(data['violation_score']?.toString() ?? '0') ?? 0;
      final totalScore = autoScore + manualScore - violationScore;

      totalByTeamRound['$teamId:$roundId'] = totalScore;

      final stat = teamStats[teamId];
      if (stat != null) {
        stat['total_auto'] = (stat['total_auto'] as int) + autoScore;
        stat['total_manual'] = (stat['total_manual'] as int) + manualScore;
        stat['total_violation'] = (stat['total_violation'] as int) + violationScore;
        stat['total_score'] = (stat['total_score'] as int) + totalScore;
      }
    }

    final scheduleRes = await conn.execute(
      """
      SELECT ts.team_id, ts.round_id, ts.match_id, ts.arena_number
      FROM tbl_explorer_teamschedule ts
      JOIN tbl_team t ON ts.team_id = t.team_id
      WHERE t.category_id = :catId
    """,
      {"catId": categoryId},
    );

    final Map<String, List<int>> teamsByMatchArena = {};
    final List<Map<String, dynamic>> scheduleRows = [];
    for (final row in scheduleRes.rows) {
      final data = row.assoc();
      final teamId = int.tryParse(data['team_id']?.toString() ?? '0') ?? 0;
      final roundId = int.tryParse(data['round_id']?.toString() ?? '0') ?? 0;
      final matchId = int.tryParse(data['match_id']?.toString() ?? '0') ?? 0;
      final arena = int.tryParse(data['arena_number']?.toString() ?? '0') ?? 0;
      if (teamId == 0 || roundId == 0 || matchId == 0 || arena == 0) {
        continue;
      }
      final key = '$matchId:$roundId:$arena';
      teamsByMatchArena.putIfAbsent(key, () => []).add(teamId);
      scheduleRows.add({
        'team_id': teamId,
        'round_id': roundId,
        'match_id': matchId,
        'arena_number': arena,
      });
    }

    for (final row in scheduleRows) {
      final teamId = row['team_id'] as int;
      final roundId = row['round_id'] as int;
      final matchId = row['match_id'] as int;
      final arena = row['arena_number'] as int;
      final teamKey = '$teamId:$roundId';
      if (!totalByTeamRound.containsKey(teamKey)) {
        continue;
      }

      final opponentArena = arena == 1 ? 2 : 1;
      final opponentKey = '$matchId:$roundId:$opponentArena';
      final opponentTeams = teamsByMatchArena[opponentKey] ?? [];
      int? opponentTotal;
      for (final opponentId in opponentTeams) {
        final oppKey = '$opponentId:$roundId';
        if (totalByTeamRound.containsKey(oppKey)) {
          opponentTotal = totalByTeamRound[oppKey];
          break;
        }
      }

      if (opponentTotal == null) continue;

      final teamTotal = totalByTeamRound[teamKey] ?? 0;
      final diff = teamTotal - opponentTotal;
      final stat = teamStats[teamId];
      if (stat == null) continue;

      stat['total_point_diff'] =
          (stat['total_point_diff'] as int) + diff;

      if (diff > 0) {
        stat['total_wins'] = (stat['total_wins'] as int) + 1;
      } else if (diff < 0) {
        stat['total_losses'] = (stat['total_losses'] as int) + 1;
      } else {
        stat['total_ties'] = (stat['total_ties'] as int) + 1;
      }
    }

    final entries = teamStats.values.toList();
    entries.sort((a, b) {
      final totalA = a['total_score'] as int;
      final totalB = b['total_score'] as int;
      if (totalA != totalB) return totalB.compareTo(totalA);
      final diffA = a['total_point_diff'] as int;
      final diffB = b['total_point_diff'] as int;
      return diffB.compareTo(diffA);
    });

    for (var i = 0; i < entries.length; i++) {
      entries[i]['rank'] = i + 1;
    }

    return entries;
  }

  Widget _overallHeaderCell(
    String label, {
    int flex = 1,
    bool alignLeft = false,
  }) {
    return Expanded(
      flex: flex,
      child: Text(
        label,
        textAlign: alignLeft ? TextAlign.left : TextAlign.center,
        style: const TextStyle(
          color: Colors.white70,
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _overallDataCell(
    String value, {
    int flex = 1,
    bool isName = false,
    Color? color,
  }) {
    return Expanded(
      flex: flex,
      child: Text(
        value,
        overflow: isName ? TextOverflow.ellipsis : TextOverflow.visible,
        textAlign: isName ? TextAlign.left : TextAlign.center,
        style: TextStyle(
          color: color ?? Colors.white,
          fontWeight: isName ? FontWeight.w600 : FontWeight.w500,
          fontSize: 14,
        ),
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

  Widget _overallStatCell(
    String value, {
    int flex = 1,
    Color? textColor,
    Color? borderColor,
    Color? backgroundColor,
  }) {
    return Expanded(
      flex: flex,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 2),
        padding: const EdgeInsets.symmetric(vertical: 6),
        decoration: BoxDecoration(
          color: backgroundColor,
          border: Border.all(
            color: borderColor ?? Colors.white10.withOpacity(0.2),
            width: 0.8,
          ),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Center(
          child: Text(
            value,
            style: TextStyle(
              color: textColor ?? Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 13,
            ),
          ),
        ),
      ),
    );
  }

  String _formatDiff(int diff) {
    if (diff == 0) return '0';
    return diff > 0 ? '+$diff' : '$diff';
  }

  Widget _buildPlaceholderTab({
    required String title,
    required Color color,
    required IconData icon,
  }) {
    return Center(
      child: Container(
        margin: const EdgeInsets.all(32),
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              const Color(0xFF2D0E7A).withOpacity(0.5),
              const Color(0xFF1A0A4A).withOpacity(0.5),
            ],
          ),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: color.withOpacity(0.3),
            width: 2,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: color.withOpacity(0.1),
                border: Border.all(
                  color: color.withOpacity(0.4),
                  width: 2,
                ),
              ),
              child: Icon(
                icon,
                color: color,
                size: 64,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              title,
              style: TextStyle(
                color: color,
                fontSize: 22,
                fontWeight: FontWeight.w900,
                letterSpacing: 2,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Standings will be displayed here',
              style: TextStyle(
                color: Colors.white.withOpacity(0.6),
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                'COMING SOON',
                style: TextStyle(
                  color: color,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1A0550), Color(0xFF2D0E7A), Color(0xFF1A0A4A)],
        ),
        border: Border(bottom: BorderSide(color: Color(0xFF00CFFF), width: 1.5)),
      ),
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
        ? '--:--:--'
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