import 'championship_schedule.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'db_helper.dart';
import 'generate_schedule.dart';
import 'alliance_selection.dart';
import 'dart:math' as math;
import 'dart:convert';
import 'constants.dart';
import 'package:flutter/scheduler.dart';

// ── Match status enum ────────────────────────────────────────────────────────
enum MatchStatus { pending, inProgress, done }

extension MatchStatusExt on MatchStatus {
  String get label {
    switch (this) {
      case MatchStatus.pending:
        return 'Pending';
      case MatchStatus.inProgress:
        return 'In Progress';
      case MatchStatus.done:
        return 'Done';
    }
  }

  Color get color {
    switch (this) {
      case MatchStatus.pending:
        return const Color(0xFFAAAAAA);
      case MatchStatus.inProgress:
        return const Color(0xFF00CFFF);
      case MatchStatus.done:
        return Colors.green;
    }
  }

  IconData get icon {
    switch (this) {
      case MatchStatus.pending:
        return Icons.schedule;
      case MatchStatus.inProgress:
        return Icons.play_circle_outline;
      case MatchStatus.done:
        return Icons.check_circle;
    }
  }
}

// ── Enhanced Match Card Widget (Compact version) ────────────────────────
class _EnhancedMatchCard extends StatefulWidget {
  final Map<String, dynamic> match;
  final int matchNumber;
  final String schedule;
  final List<Map<String, String>> redTeam;
  final List<Map<String, String>> blueTeam;
  final VoidCallback onStatusTap;
  final MatchStatus status;

  const _EnhancedMatchCard({
    required this.match,
    required this.matchNumber,
    required this.schedule,
    required this.redTeam,
    required this.blueTeam,
    required this.onStatusTap,
    required this.status,
  });

  @override
  State<_EnhancedMatchCard> createState() => _EnhancedMatchCardState();
}

class _EnhancedMatchCardState extends State<_EnhancedMatchCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _hoverController;
  late Animation<double> _scaleAnimation;
  bool _isHovered = false;

  @override
  void initState() {
    super.initState();
    _hoverController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 1.01).animate(
      CurvedAnimation(parent: _hoverController, curve: Curves.easeOut),
    );
  }

  @override
  void dispose() {
    _hoverController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) {
        setState(() => _isHovered = true);
        _hoverController.forward();
      },
      onExit: (_) {
        setState(() => _isHovered = false);
        _hoverController.reverse();
      },
      child: AnimatedBuilder(
        animation: _scaleAnimation,
        builder: (context, child) {
          return Transform.scale(
            scale: _scaleAnimation.value,
            child: Container(
              margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 12),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    const Color(0xFF2D0E7A).withOpacity(0.9),
                    const Color(0xFF1A0A4A).withOpacity(0.9),
                  ],
                ),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: _isHovered
                      ? const Color(0xFFFFD700).withOpacity(0.6)
                      : const Color(0xFFFFD700).withOpacity(0.2),
                  width: 1,
                ),
                boxShadow: _isHovered
                    ? [
                        BoxShadow(
                          color: const Color(0xFFFFD700).withOpacity(0.15),
                          blurRadius: 8,
                          spreadRadius: 1,
                        ),
                      ]
                    : [],
              ),
              child: Column(
                children: [
                  // Compact Header
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          const Color(0xFFFFD700).withOpacity(0.15),
                          Colors.transparent,
                        ],
                      ),
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        // Match Number Badge
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFD700).withOpacity(0.15),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.sports_esports_rounded,
                                  size: 12, color: Color(0xFFFFD700)),
                              const SizedBox(width: 4),
                              Text(
                                'MATCH ${widget.matchNumber}',
                                style: const TextStyle(
                                  color: Color(0xFFFFD700),
                                  fontWeight: FontWeight.bold,
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                        ),
                        // Time Badge
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.05),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.access_time,
                                  size: 10, color: Colors.white54),
                              const SizedBox(width: 4),
                              Text(
                                widget.schedule,
                                style: const TextStyle(
                                    color: Colors.white70, fontSize: 10),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Match Content - Compact Row
                  Padding(
                    padding: const EdgeInsets.all(10),
                    child: Row(
                      children: [
                        // RED Alliance
                        Expanded(
                          child: _buildCompactAllianceCard(
                            name: 'RED',
                            teams: widget.redTeam,
                            color: Colors.redAccent,
                          ),
                        ),

                        // VS Badge
                        Container(
                          margin: const EdgeInsets.symmetric(horizontal: 8),
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFFFFD700), Color(0xFFCCAC00)],
                            ),
                            shape: BoxShape.circle,
                          ),
                          child: const Center(
                            child: Text(
                              'VS',
                              style: TextStyle(
                                color: Colors.black,
                                fontWeight: FontWeight.bold,
                                fontSize: 10,
                              ),
                            ),
                          ),
                        ),

                        // BLUE Alliance
                        Expanded(
                          child: _buildCompactAllianceCard(
                            name: 'BLUE',
                            teams: widget.blueTeam,
                            color: Colors.blue,
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Status Footer - Compact
                  GestureDetector(
                    onTap: widget.onStatusTap,
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      decoration: BoxDecoration(
                        color: widget.status.color.withOpacity(0.1),
                        borderRadius: const BorderRadius.vertical(
                            bottom: Radius.circular(12)),
                        border: Border(
                          top: BorderSide(
                            color: widget.status.color.withOpacity(0.2),
                            width: 0.5,
                          ),
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            widget.status.icon,
                            color: widget.status.color,
                            size: 12,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            widget.status.label.toUpperCase(),
                            style: TextStyle(
                              color: widget.status.color,
                              fontWeight: FontWeight.bold,
                              fontSize: 9,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildCompactAllianceCard({
    required String name,
    required List<Map<String, String>> teams,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            color.withOpacity(0.12),
            color.withOpacity(0.04),
          ],
        ),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: color.withOpacity(0.25),
          width: 0.5,
        ),
      ),
      child: Column(
        children: [
          Text(
            name,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.bold,
              fontSize: 9,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 4),
          ...teams.take(2).map((team) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 1),
                child: Column(
                  children: [
                    Text(
                      team['team_name']!,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w500,
                        fontSize: 10,
                      ),
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      'ID: ${team['team_id']}',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.4),
                        fontSize: 7,
                      ),
                    ),
                  ],
                ),
              )),
          if (teams.isEmpty)
            const Text(
              '—',
              style: TextStyle(color: Colors.white24, fontSize: 12),
            ),
        ],
      ),
    );
  }
}

// ── Soccer match score model ─────────────────────────────────────────────────
class SoccerScore {
  int? home;
  int? away;
  bool get isFinished => home != null && away != null;
  bool get isHomeWin => isFinished && home! > away!;
  bool get isAwayWin => isFinished && away! > home!;
  bool get isDraw => isFinished && home! == away!;
}

// ── Bracket data models ──────────────────────────────────────────────────────
class BracketTeam {
  final int teamId;
  final String teamName;
  bool isBye;
  int? score;

  BracketTeam({
    required this.teamId,
    required this.teamName,
    this.isBye = false,
    this.score,
  });
}

class BracketMatch {
  final String id;
  BracketTeam team1;
  BracketTeam team2;
  BracketTeam? winner;
  final int round;
  final int position;
  String? scheduleTime;

  BracketMatch({
    required this.id,
    required this.team1,
    required this.team2,
    required this.round,
    required this.position,
    this.winner,
    this.scheduleTime,
  });
}

// ── Main widget ──────────────────────────────────────────────────────────────
class ScheduleViewer extends StatefulWidget {
  final VoidCallback? onRegister;
  final VoidCallback? onStandings;

  const ScheduleViewer({super.key, this.onRegister, this.onStandings});

  @override
  State<ScheduleViewer> createState() => _ScheduleViewerState();
}

class _ScheduleViewerState extends State<ScheduleViewer>
    with TickerProviderStateMixin {
  TabController? _tabController;
  List<Map<String, dynamic>> _categories = [];
  Map<int, List<Map<String, dynamic>>> _scheduleByCategory = {};
  final Map<int, int> _championshipRefreshVersionByCategory = {};
  final Map<int, BuildContext> _categoryTabContexts = {};
  final Map<String, MatchStatus> _statusMap = {};
  bool _isLoading = true;
  DateTime? _lastUpdated;
  Timer? _autoRefreshTimer;
  String _lastDataSignature = '';

  int? _soccerCategoryId;

  // Soccer group-stage scores  key = match_id.toString()
  final Map<String, SoccerScore> _soccerScores = {};

  // Whether the bracket has been seeded from standings
  bool _bracketSeeded = false;

  List<List<BracketMatch>> _bracketRounds = [];

  // Soccer teams from DB
  List<Map<String, dynamic>> _soccerTeams = [];

  // Last schedule_end from soccer group stage — bracket starts after this
  String? _lastSoccerEndTime;

  @override
  void initState() {
    super.initState();
    _loadData(initial: true);
    _autoRefreshTimer = Timer.periodic(
        const Duration(seconds: 10), (_) => _silentRefresh());
  }

  @override
  void dispose() {
    _categoryTabContexts.clear();
    _autoRefreshTimer?.cancel();
    _tabController?.dispose();
    super.dispose();
  }

  // ── helpers ────────────────────────────────────────────────────────────────
  String _buildSignature(List rows) {
    return rows.map((r) => jsonEncode(r)).join('|');
  }

  String _fmt(String? t) {
    if (t == null || t.isEmpty) return '--:--';
    final parts = t.split(':');
    return parts.length < 2 ? t : '${parts[0]}:${parts[1]}';
  }

  String _statusKey(int catId, int matchNumber) => '$catId-$matchNumber';
  MatchStatus _getStatus(int catId, int matchNumber) =>
      _statusMap[_statusKey(catId, matchNumber)] ?? MatchStatus.pending;

  void _cycleStatus(int catId, int matchNumber) {
    final key = _statusKey(catId, matchNumber);
    final current = _statusMap[key] ?? MatchStatus.pending;
    setState(() {
      switch (current) {
        case MatchStatus.pending:
          _statusMap[key] = MatchStatus.inProgress;
          break;
        case MatchStatus.inProgress:
          _statusMap[key] = MatchStatus.done;
          break;
        case MatchStatus.done:
          _statusMap[key] = MatchStatus.pending;
          break;
      }
    });
  }

  // Check if every group-stage match for a category is Done
  bool _allMatchesDone(int catId, List<Map<String, dynamic>> matches) {
    if (matches.isEmpty) return false;
    return matches.every((m) {
      final matchNum = m['matchNumber'] as int? ?? 0;
      return _getStatus(catId, matchNum) == MatchStatus.done;
    });
  }

  // Get qualified teams for alliance selection
  Future<List<Map<String, dynamic>>> _getQualifiedTeams(int categoryId) async {
    try {
      print("🎯 Getting qualified teams for category: $categoryId");

      // Get all teams in this category first
      final teams = await DBHelper.getTeamsByCategory(categoryId);
      print("🔍 DEBUG: Found ${teams.length} teams in category");

      if (teams.isEmpty) {
        print("⚠️ No teams found in category");
        return [];
      }

      // Get standings (scores)
      final standings = await DBHelper.getScoresByCategory(categoryId);
      print("🔍 DEBUG: Found ${standings.length} score entries");

      final Map<int, Map<String, dynamic>> teamMap = {};

      // Initialize all teams with zero scores
      for (final team in teams) {
        final teamIdObj = team['team_id'];
        if (teamIdObj == null) {
          print("⚠️ Team has null team_id: $team");
          continue;
        }

        final teamId = int.tryParse(teamIdObj.toString());
        if (teamId == null || teamId == 0) {
          print("⚠️ Invalid team_id: $teamIdObj");
          continue;
        }

        final teamName = team['team_name']?.toString() ?? 'Unknown Team';

        teamMap[teamId] = {
          'team_id': teamId,
          'team_name': teamName,
          'totalScore': 0,
        };
        print("✅ Added team: $teamName (ID: $teamId)");
      }

      if (teamMap.isEmpty) {
        print("⚠️ No valid teams found after filtering");
        return [];
      }

      // Sum scores from each round
      for (final row in standings) {
        final teamIdObj = row['team_id'];
        if (teamIdObj == null) {
          print("⚠️ Score row has null team_id: $row");
          continue;
        }

        final teamId = int.tryParse(teamIdObj.toString());
        if (teamId == null || teamId == 0) {
          print("⚠️ Invalid team_id in score: $teamIdObj");
          continue;
        }

        int score = 0;
        if (row.containsKey('score_totalscore') &&
            row['score_totalscore'] != null) {
          final scoreObj = row['score_totalscore'];
          score = int.tryParse(scoreObj.toString()) ?? 0;
        }
        print("➕ Score for team $teamId: $score");

        if (teamMap.containsKey(teamId)) {
          teamMap[teamId]!['totalScore'] =
              (teamMap[teamId]!['totalScore'] as int) + score;
        } else {
          print("⚠️ Score for unknown team $teamId, skipping");
        }
      }

      // Filter teams with scores > 0 and sort
      final qualified = <Map<String, dynamic>>[];
      for (final entry in teamMap.entries) {
        final team = entry.value;
        final score = team['totalScore'] as int;
        if (score > 0) {
          qualified.add(team);
          print("🏆 Qualified: ${team['team_name']} with $score pts");
        } else {
          print("❌ Not qualified: ${team['team_name']} has 0 pts");
        }
      }

      // Sort by score descending
      qualified.sort((a, b) =>
          (b['totalScore'] as int).compareTo(a['totalScore'] as int));

      print("🎯 Final qualified teams count: ${qualified.length}");
      return qualified;
    } catch (e, stackTrace) {
      print("❌ CRITICAL ERROR in _getQualifiedTeams: $e");
      print(stackTrace);
      return [];
    }
  }

  // Show alliance selection ceremony
  void _showAllianceSelection(int categoryId, String categoryName) async {
    try {
      print("🎯 Starting alliance selection for $categoryName");

      if (!mounted) return;

      // Get real scores from standings (keep your existing code for this part)
      final standings = await DBHelper.getScoresByCategory(categoryId);
      final teams = await DBHelper.getTeamsByCategory(categoryId);

      if (teams.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No teams found in this category'),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }

      // Calculate total scores per team
      final Map<int, Map<String, dynamic>> teamScores = {};

      for (final team in teams) {
        final teamId = int.tryParse(team['team_id'].toString()) ?? 0;
        final teamName = team['team_name']?.toString() ?? '';

        teamScores[teamId] = {
          'team_id': teamId,
          'team_name': teamName,
          'totalScore': 0,
        };
      }

      for (final row in standings) {
        final teamId = int.tryParse(row['team_id'].toString()) ?? 0;
        final score =
            int.tryParse(row['score_totalscore']?.toString() ?? '0') ?? 0;

        if (teamScores.containsKey(teamId)) {
          teamScores[teamId]!['totalScore'] =
              (teamScores[teamId]!['totalScore'] as int) + score;
        }
      }

      final qualifiedTeams = teamScores.values
          .where((t) => (t['totalScore'] as int) > 0)
          .toList()
        ..sort((a, b) =>
            (b['totalScore'] as int).compareTo(a['totalScore'] as int));

      if (qualifiedTeams.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                'No qualified teams found. Enter scores in Standings first.'),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }

      if (!mounted) return;

      // Navigate to alliance selection page and wait for result
      final result = await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (context) => AllianceSelectionPage(
            categoryId: categoryId,
            categoryName: categoryName,
            qualifiedTeams: qualifiedTeams,
            onComplete: () {
              // This won't be used anymore since we're using pop result
              print("onComplete called");
            },
            onCancel: () {
              print("❌ Alliance selection cancelled");
              Navigator.of(context).pop(false);
            },
          ),
          fullscreenDialog: true,
        ),
      );

      // If alliance formation was successful, show the proceed dialog
      if (result == true && mounted) {
        print("✅ Alliance selection completed - showing proceed dialog");

        // Refresh championship data
        setState(() {
          _championshipRefreshVersionByCategory[categoryId] =
              (_championshipRefreshVersionByCategory[categoryId] ?? 0) + 1;
        });

        // Show the proceed dialog immediately
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => Dialog(
            backgroundColor: Colors.transparent,
            child: Container(
              width: 500,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF2D0E7A), Color(0xFF1E0A5A)],
                ),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                    color: const Color(0xFF00E5A0).withOpacity(0.5), width: 2),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: const Color(0xFF00E5A0).withOpacity(0.15),
                    ),
                    child: const Icon(Icons.emoji_events,
                        color: Color(0xFF00E5A0), size: 48),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'CHAMPIONSHIP ROUND',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 2),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Alliances are now formed for $categoryName',
                    style: TextStyle(
                        color: Colors.white.withOpacity(0.7), fontSize: 14),
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    'Proceed to Championship Round?',
                    style: TextStyle(color: Colors.white, fontSize: 16),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () {
                            Navigator.pop(ctx);
                            // Stay on current tab
                          },
                          style: OutlinedButton.styleFrom(
                            side: BorderSide(
                                color: Colors.white.withOpacity(0.3)),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                          child: const Text('CANCEL',
                              style: TextStyle(color: Colors.white54)),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () {
                            Navigator.pop(ctx);
                            // Switch to championship tab
                            final tabContext = _categoryTabContexts[categoryId];
                            final controller = tabContext == null
                                ? null
                                : DefaultTabController.maybeOf(tabContext);
                            if (controller != null) {
                              controller.animateTo(1);
                            }
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF00E5A0),
                            foregroundColor: Colors.black,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                          child: const Text('PROCEED',
                              style: TextStyle(fontWeight: FontWeight.bold)),
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
    } catch (e, stackTrace) {
      print("❌ Error in _showAllianceSelection: $e");
      print(stackTrace);

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _showChampionshipRoundPrompt(int categoryId, String categoryName) {
    showDialog(
      context: context,
      barrierDismissible: false, // Prevent dismissing by tapping outside
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          width: 500,
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF2D0E7A), Color(0xFF1E0A5A)],
            ),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
                color: const Color(0xFF00E5A0).withOpacity(0.5), width: 2),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFF00E5A0).withOpacity(0.15),
                ),
                child:
                    const Icon(Icons.emoji_events, color: Color(0xFF00E5A0), size: 48),
              ),
              const SizedBox(height: 16),
              const Text(
                'CHAMPIONSHIP ROUND',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 2),
              ),
              const SizedBox(height: 8),
              Text(
                'Alliances are now formed for $categoryName',
                style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 14),
              ),
              const SizedBox(height: 20),
              const Text(
                'Open the Championship tab to review alliances and generate the schedule.',
                style: TextStyle(color: Colors.white, fontSize: 16),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () {
                        Navigator.pop(ctx);
                        // Optionally switch to championship tab
                        _openChampionshipTab(categoryId);
                      },
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: Colors.white.withOpacity(0.3)),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: const Text('OPEN TAB',
                          style: TextStyle(color: Colors.white54)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.pop(ctx);
                        // Navigate to championship tab
                        _openChampionshipTab(categoryId);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF00E5A0),
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: const Text('GENERATE',
                          style: TextStyle(fontWeight: FontWeight.bold)),
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

  void _openChampionshipTab(int categoryId) {
    final tabContext = _categoryTabContexts[categoryId];
    final controller = tabContext == null
        ? null
        : DefaultTabController.maybeOf(tabContext);
    if (controller != null) {
      controller.animateTo(1);
      return;
    }

    // Just show a snackbar, not a dialog
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Switched to Championship tab'),
          backgroundColor: Colors.blue,
          duration: const Duration(seconds: 1),
        ),
      );
    }
  }

  Future<void> _generateChampionshipSchedule(int categoryId) async {
    try {
      print("🏆 _generateChampionshipSchedule called for category $categoryId");

      print("🏆 Generating championship schedule for category $categoryId");

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Generating championship schedule...'),
          backgroundColor: Colors.blue,
        ),
      );

      final conn = await DBHelper.getConnection();

      // Get the formed alliances from the database
      final alliancesResult = await conn.execute("""
        SELECT 
          alliance_id,
          captain_team_id,
          partner_team_id,
          selection_round
        FROM tbl_alliance_selections 
        WHERE category_id = :catId
        ORDER BY selection_round
      """, {"catId": categoryId});

      final alliances = alliancesResult.rows.map((r) => r.assoc()).toList();

      if (alliances.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                'No alliances found. Please complete alliance selection first.'),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }

      print("📊 Found ${alliances.length} alliances");

      // Clear existing championship schedule for this category (also explorer variant)
      await DBHelper.executeDual("""
        DELETE FROM tbl_championship_schedule 
        WHERE category_id = :catId
      """, {"catId": categoryId});

      // Generate bracket based on number of alliances
      final numAlliances = alliances.length;

      if (numAlliances == 4) {
        // Standard 4-team bracket
        // Semifinal 1: Alliance 1 vs Alliance 4
        // Semifinal 2: Alliance 2 vs Alliance 3
        // Final: Winners of semifinals

        // Semifinals
        await DBHelper.executeDual("""
          INSERT INTO tbl_championship_schedule 
            (category_id, alliance1_id, alliance2_id, match_round, match_position, schedule_time)
          VALUES
            (:catId, :a1, :a4, 1, 1, '13:00'),
            (:catId, :a2, :a3, 1, 2, '13:10')
        """, {
          "catId": categoryId,
          "a1": alliances[0]['alliance_id'],
          "a2": alliances[1]['alliance_id'],
          "a3": alliances[2]['alliance_id'],
          "a4": alliances[3]['alliance_id'],
        });

        // Final (to be filled after semifinals)
        await DBHelper.executeDual("""
          INSERT INTO tbl_championship_schedule 
            (category_id, alliance1_id, alliance2_id, match_round, match_position, schedule_time, status)
          VALUES
            (:catId, 0, 0, 2, 1, '13:30', 'pending')
        """, {"catId": categoryId});
      } else if (numAlliances == 8) {
        // 8-team bracket
        // Quarterfinals, Semifinals, Final
        for (int i = 0; i < 4; i++) {
          await DBHelper.executeDual("""
            INSERT INTO tbl_championship_schedule 
              (category_id, alliance1_id, alliance2_id, match_round, match_position, schedule_time)
            VALUES
              (:catId, :a1, :a2, 1, :pos, :time)
          """, {
            "catId": categoryId,
            "a1": alliances[i * 2]['alliance_id'],
            "a2": alliances[i * 2 + 1]['alliance_id'],
            "pos": i + 1,
            "time": '${13 + i * 10}:00',
          });
        }

        // Semifinals and final placeholders
        for (int i = 0; i < 2; i++) {
          await DBHelper.executeDual("""
            INSERT INTO tbl_championship_schedule 
              (category_id, alliance1_id, alliance2_id, match_round, match_position, schedule_time, status)
            VALUES
              (:catId, 0, 0, 2, :pos, :time, 'pending')
          """, {
            "catId": categoryId,
            "pos": i + 1,
            "time": '${14 + i * 10}:00',
          });
        }

        // Final placeholder
        await DBHelper.executeDual("""
          INSERT INTO tbl_championship_schedule 
            (category_id, alliance1_id, alliance2_id, match_round, match_position, schedule_time, status)
          VALUES
            (:catId, 0, 0, 3, 1, '15:00', 'pending')
        """, {"catId": categoryId});
      } else if (numAlliances == 2) {
        // Direct final
        await DBHelper.executeDual("""
          INSERT INTO tbl_championship_schedule 
            (category_id, alliance1_id, alliance2_id, match_round, match_position, schedule_time)
          VALUES
            (:catId, :a1, :a2, 1, 1, '13:00')
        """, {
          "catId": categoryId,
          "a1": alliances[0]['alliance_id'],
          "a2": alliances[1]['alliance_id'],
        });
      }

      print("✅ Championship schedule generated");

      // Verify the matches were inserted
      final verifyResult = await conn.execute("""
        SELECT COUNT(*) as cnt 
        FROM tbl_championship_schedule
        WHERE category_id = :catId
      """, {"catId": categoryId});

      final count = verifyResult.rows.first.assoc()['cnt'];
      print("🔍 Verification: Found $count championship matches in database");
      print("✅ Championship schedule generated with $count matches");

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('✅ Championship schedule generated with $count matches!'),
          backgroundColor: Colors.green,
        ),
      );

      // Refresh schedule data to show the new championship tab
      _loadData(initial: true);
    } catch (e, stackTrace) {
      print("❌ Error generating championship schedule: $e");
      print(stackTrace);

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error generating championship schedule: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  // ── silent background refresh ─────────────────────────────────────────────
  Future<void> _silentRefresh() async {
    try {
      final conn = await DBHelper.getConnection();
      final result = await conn.execute("""
        SELECT c.category_id, ts.match_id, t.team_name, s.schedule_start
        FROM tbl_teamschedule ts
        JOIN tbl_team t ON ts.team_id = t.team_id
        JOIN tbl_category c ON t.category_id = c.category_id
        JOIN tbl_match m ON ts.match_id = m.match_id
        JOIN tbl_schedule s ON m.schedule_id = s.schedule_id
        ORDER BY c.category_id, s.schedule_start, ts.match_id
      """);
      final rows = result.rows.map((r) => r.assoc()).toList();
      final signature = _buildSignature(rows);
      if (signature != _lastDataSignature) {
        _lastDataSignature = signature;
        await _loadData(initial: false);
      }
    } catch (_) {}
  }

  // ── main data load ────────────────────────────────────────────────────────
  Future<void> _loadData({bool initial = false}) async {
    if (initial) setState(() => _isLoading = true);
    try {
      final categories = await DBHelper.getCategories();

      if (categories.isEmpty) {
        setState(() {
          _categories = [];
          _scheduleByCategory = {};
          _isLoading = false;
          _lastUpdated = DateTime.now();
        });
        return;
      }

      final conn = await DBHelper.getConnection();

      final result = await conn.execute("""
        SELECT 
          c.category_id, 
          c.category_type,
          ts.match_id, 
          ts.round_id,
          s.schedule_id,
          s.schedule_start,
          s.schedule_end,
          ts.arena_number,
          t.team_id,
          t.team_name
        FROM tbl_teamschedule ts
        JOIN tbl_team t ON ts.team_id = t.team_id
        JOIN tbl_category c ON t.category_id = c.category_id
        JOIN tbl_match m ON ts.match_id = m.match_id
        JOIN tbl_schedule s ON m.schedule_id = s.schedule_id
        ORDER BY c.category_id, s.schedule_start, ts.match_id, ts.arena_number
      """);

      final rows = result.rows.map((r) => r.assoc()).toList();
      _lastDataSignature = _buildSignature(rows);

      final Map<int, List<Map<String, dynamic>>> rowsByCategory = {};
      for (final row in rows) {
        final catId = int.tryParse(row['category_id'].toString()) ?? 0;
        rowsByCategory.putIfAbsent(catId, () => []).add(row);
      }

      final Map<int, List<Map<String, dynamic>>> scheduleByCategory = {};

      for (final cat in categories) {
        final catId = int.tryParse(cat['category_id'].toString()) ?? 0;
        if (catId == 0) continue;

        final catRows = rowsByCategory[catId] ?? [];

        if (catRows.isEmpty) {
          scheduleByCategory[catId] = [];
          continue;
        }

        final Map<int, Map<String, dynamic>> matchesByMatchId = {};

        for (final row in catRows) {
          final matchId = int.tryParse(row['match_id'].toString()) ?? 0;
          if (matchId == 0) continue;

          final arenaNum =
              int.tryParse(row['arena_number']?.toString() ?? '1') ?? 1;
          final teamId = row['team_id']?.toString() ?? '';
          final teamName = row['team_name']?.toString() ?? '';
          final scheduleStart = row['schedule_start']?.toString() ?? '';
          final scheduleEnd = row['schedule_end']?.toString() ?? '';
          final roundId = int.tryParse(row['round_id'].toString()) ?? 0;
          final scheduleId = int.tryParse(row['schedule_id'].toString()) ?? 0;

          if (!matchesByMatchId.containsKey(matchId)) {
            matchesByMatchId[matchId] = {
              'match_id': matchId,
              'schedule_id': scheduleId,
              'round_id': roundId,
              'schedule_start': scheduleStart,
              'schedule_end': scheduleEnd,
              'schedule': '${_fmt(scheduleStart)} - ${_fmt(scheduleEnd)}',
              'arena1_teams': <Map<String, String>>[],
              'arena2_teams': <Map<String, String>>[],
            };
          }

          final match = matchesByMatchId[matchId]!;
          final teamInfo = {
            'team_id': teamId,
            'team_name': teamName,
          };

          if (arenaNum == 1) {
            (match['arena1_teams'] as List).add(teamInfo);
          } else {
            (match['arena2_teams'] as List).add(teamInfo);
          }
        }

        var matchesList = matchesByMatchId.values.toList();

        matchesList.sort((a, b) {
          final aTime = a['schedule_start'] as String;
          final bTime = b['schedule_start'] as String;
          return aTime.compareTo(bTime);
        });

        for (int i = 0; i < matchesList.length; i++) {
          matchesList[i]['matchNumber'] = i + 1;
        }

        scheduleByCategory[catId] = matchesList;
      }

      int? soccerCatId;
      for (final cat in categories) {
        final type = (cat['category_type'] ?? '').toString().toLowerCase();
        if (type.contains('soccer')) {
          soccerCatId = int.tryParse(cat['category_id'].toString());
          break;
        }
      }

      List<Map<String, dynamic>> soccerTeams = [];
      String? lastSoccerEndTime;
      if (soccerCatId != null) {
        soccerTeams = await DBHelper.getTeamsByCategory(soccerCatId);
        final soccerMatches = scheduleByCategory[soccerCatId] ?? [];
        if (soccerMatches.isNotEmpty) {
          final lastMatch = soccerMatches.last;
          lastSoccerEndTime = lastMatch['schedule_end'] as String?;
        }
      }

      final prevIdx = _tabController?.index ?? 0;
      _tabController?.dispose();
      _tabController = TabController(
        length: categories.length,
        vsync: this,
        initialIndex: prevIdx.clamp(0, categories.length - 1),
      );

      setState(() {
        _categories = categories;
        _scheduleByCategory = scheduleByCategory;
        _soccerCategoryId = soccerCatId;
        _soccerTeams = soccerTeams;
        _lastSoccerEndTime = lastSoccerEndTime;
        _isLoading = false;
        _lastUpdated = DateTime.now();
      });
    } catch (e) {
      print("Error loading schedule: $e");
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Failed to load: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  int _bracketSize(int teamCount) {
    if (teamCount >= 16) return 16;
    if (teamCount >= 8) return 8;
    if (teamCount >= 4) return 4;
    return teamCount.clamp(2, 4);
  }

  void _assignBracketTimes(
      List<List<BracketMatch>> rounds, int durationMinutes) {
    if (_lastSoccerEndTime == null) return;
    final parts = _lastSoccerEndTime!.split(':');
    if (parts.length < 2) return;
    int h = int.tryParse(parts[0]) ?? 9;
    int m = int.tryParse(parts[1]) ?? 0;

    String fmt(int hour, int min) =>
        '${hour.toString().padLeft(2, '0')}:${min.toString().padLeft(2, '0')}';

    for (final round in rounds) {
      for (final match in round) {
        match.scheduleTime = fmt(h, m);
        m += durationMinutes;
        while (m >= 60) {
          m -= 60;
          h++;
        }
        if (h == 12) {
          h = 13;
          m = 0;
        }
      }
    }
  }

  void _seedBracketFromStandings(List<Map<String, dynamic>> matches) {
    final size = _bracketSize(_soccerTeams.length);
    final topN = _soccerTeams.take(size).toList();

    final List<BracketTeam> bracketTeams = [];
    for (int i = 0; i < topN.length ~/ 2; i++) {
      final a = topN[i];
      final b = topN[topN.length - 1 - i];
      bracketTeams.add(BracketTeam(
          teamId: int.parse(a['team_id'].toString()),
          teamName: a['team_name'].toString()));
      bracketTeams.add(BracketTeam(
          teamId: int.parse(b['team_id'].toString()),
          teamName: b['team_name'].toString()));
    }
    int byeN = 0;
    while (bracketTeams.length < size) {
      bracketTeams
          .add(BracketTeam(teamId: -(++byeN), teamName: 'BYE', isBye: true));
    }

    final rounds = _buildBracketFromTeams(bracketTeams);
    _assignBracketTimes(rounds, 10);
    setState(() {
      _bracketRounds = rounds;
      _bracketSeeded = true;
    });
  }

  List<List<BracketMatch>> _buildBracketFromTeams(List<BracketTeam> teams) {
    List<BracketMatch> firstRound = [];
    for (int i = 0; i < teams.length; i += 2) {
      final m = BracketMatch(
          id: 'r0m${i ~/ 2}',
          team1: teams[i],
          team2: teams[i + 1],
          round: 0,
          position: i ~/ 2);
      if (!teams[i].isBye && teams[i + 1].isBye) m.winner = teams[i];
      if (teams[i].isBye && !teams[i + 1].isBye) m.winner = teams[i + 1];
      firstRound.add(m);
    }
    List<List<BracketMatch>> rounds = [firstRound];
    int roundNum = 1;
    List<BracketMatch> prev = firstRound;
    while (prev.length > 1) {
      List<BracketMatch> current = [];
      for (int i = 0; i < prev.length; i += 2) {
        current.add(BracketMatch(
            id: 'r${roundNum}m${i ~/ 2}',
            team1: prev[i].winner ?? BracketTeam(teamId: -99, teamName: 'TBD'),
            team2: prev[i + 1].winner ??
                BracketTeam(teamId: -99, teamName: 'TBD'),
            round: roundNum,
            position: i ~/ 2));
      }
      rounds.add(current);
      prev = current;
      roundNum++;
    }
    return rounds;
  }

  void _rebuildBracket(List<Map<String, dynamic>> matches) {
    setState(() {
      _bracketSeeded = false;
      _bracketRounds = [];
    });
    _seedBracketFromStandings(matches);
  }

  void _setMatchResult(BracketMatch match, BracketTeam winner) {
    setState(() {
      match.winner = winner;
      _propagateWinner(match);
    });
  }

  void _propagateWinner(BracketMatch match) {
    if (match.winner == null || match.winner!.isBye) return;
    final nextRoundIdx = match.round + 1;
    if (nextRoundIdx >= _bracketRounds.length) return;
    final nextRound = _bracketRounds[nextRoundIdx];
    final nextMatchIdx = match.position ~/ 2;
    if (nextMatchIdx >= nextRound.length) return;
    final nextMatch = nextRound[nextMatchIdx];
    if (match.position % 2 == 0) {
      nextMatch.team1 = match.winner!;
    } else {
      nextMatch.team2 = match.winner!;
    }
  }

  void _clearMatchResult(BracketMatch match) {
    void resetDownstream(BracketMatch m) {
      final nextRoundIdx = m.round + 1;
      if (nextRoundIdx >= _bracketRounds.length) return;
      final nextRound = _bracketRounds[nextRoundIdx];
      final nextMatchIdx = m.position ~/ 2;
      if (nextMatchIdx >= nextRound.length) return;
      final nextMatch = nextRound[nextMatchIdx];
      final feedsTeam1 = m.position % 2 == 0;
      if (feedsTeam1 && nextMatch.team1.teamId == m.winner?.teamId) {
        nextMatch.team1 = BracketTeam(teamId: -99, teamName: 'TBD');
      } else if (!feedsTeam1 && nextMatch.team2.teamId == m.winner?.teamId)
        nextMatch.team2 = BracketTeam(teamId: -99, teamName: 'TBD');
      if (nextMatch.winner != null) {
        resetDownstream(nextMatch);
        nextMatch.winner = null;
      }
    }
    setState(() {
      resetDownstream(match);
      match.winner = null;
    });
  }

  void _showScoreDialog(String matchId, String team1Name, String team2Name,
      List<Map<String, dynamic>> allMatches) {
    final existing = _soccerScores[matchId];
    final c1 = TextEditingController(text: existing?.home?.toString() ?? '');
    final c2 = TextEditingController(text: existing?.away?.toString() ?? '');

    showDialog(
      context: context,
      barrierColor: Colors.black.withOpacity(0.7),
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          width: 360,
          decoration: BoxDecoration(
            color: const Color(0xFF14093A),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFF3D1E88), width: 1.5),
            boxShadow: [
              BoxShadow(
                  color: const Color(0xFF6B2FD9).withOpacity(0.35),
                  blurRadius: 40,
                  spreadRadius: 2)
            ],
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              padding: const EdgeInsets.fromLTRB(20, 14, 14, 14),
              decoration: const BoxDecoration(
                color: Color(0xFF0F0628),
                borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
              ),
              child: Row(children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                      color: const Color(0xFF3D1E88).withOpacity(0.5),
                      borderRadius: BorderRadius.circular(8)),
                  child: const Icon(Icons.sports_soccer,
                      color: Color(0xFF9B6FE8), size: 18),
                ),
                const SizedBox(width: 10),
                const Text('ENTER MATCH SCORE',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.5)),
                const Spacer(),
                GestureDetector(
                  onTap: () => Navigator.pop(ctx),
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.06),
                        borderRadius: BorderRadius.circular(6)),
                    child: Icon(Icons.close,
                        color: Colors.white.withOpacity(0.4), size: 18),
                  ),
                ),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Row(children: [
                Expanded(
                    child: Column(children: [
                  Text(team1Name,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.bold)),
                  const SizedBox(height: 10),
                  _scoreField(c1, const Color(0xFF00CFFF)),
                ])),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                          colors: [Color(0xFF8B3FE8), Color(0xFF5218A8)]),
                      borderRadius: BorderRadius.circular(6),
                      boxShadow: [
                        BoxShadow(
                            color: const Color(0xFF7B2FD8).withOpacity(0.5),
                            blurRadius: 12)
                      ],
                    ),
                    child: const Text('VS',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 2,
                            fontStyle: FontStyle.italic)),
                  ),
                ),
                Expanded(
                    child: Column(children: [
                  Text(team2Name,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.bold)),
                  const SizedBox(height: 10),
                  _scoreField(c2, const Color(0xFF00FF88)),
                ])),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Row(children: [
                if (existing?.isFinished == true) ...[
                  Expanded(
                      child: OutlinedButton.icon(
                    onPressed: () {
                      setState(() => _soccerScores.remove(matchId));
                      Navigator.pop(ctx);
                    },
                    icon: const Icon(Icons.delete_outline,
                        color: Colors.redAccent, size: 16),
                    label: const Text('Clear',
                        style: TextStyle(color: Colors.redAccent, fontSize: 13)),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Colors.redAccent),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8)),
                    ),
                  )),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  flex: 2,
                  child: ElevatedButton(
                    onPressed: () {
                      final h = int.tryParse(c1.text.trim());
                      final a = int.tryParse(c2.text.trim());
                      if (h == null || a == null) {
                        ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                                content: Text('Please enter valid scores'),
                                backgroundColor: Colors.orange));
                        return;
                      }
                      setState(() {
                        _soccerScores[matchId] =
                            SoccerScore()..home = h..away = a;
                      });
                      Navigator.pop(ctx);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF5B2CC0),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: const Text('Save Score',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.bold)),
                  ),
                ),
              ]),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _scoreField(TextEditingController ctrl, Color accentColor) {
    return Container(
      height: 58,
      decoration: BoxDecoration(
        color: const Color(0xFF1C0F4A),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: accentColor.withOpacity(0.5), width: 1.5),
      ),
      child: Center(
        child: TextField(
          controller: ctrl,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          textAlign: TextAlign.center,
          style: TextStyle(
              color: accentColor, fontSize: 26, fontWeight: FontWeight.bold),
          decoration: const InputDecoration(
            border: InputBorder.none,
            contentPadding: EdgeInsets.zero,
            hintText: '0',
            hintStyle: TextStyle(color: Colors.white12, fontSize: 26),
          ),
        ),
      ),
    );
  }

  Future<void> _exportPdf(Map<String, dynamic> category,
      List<Map<String, dynamic>> matches) async {
    final doc = pw.Document();
    final categoryName =
        (category['category_type'] ?? '').toString().toUpperCase();
    int maxArenas = 1;
    for (final m in matches) {
      final count = m['arenaCount'] as int? ?? 1;
      if (count > maxArenas) maxArenas = count;
    }
    doc.addPage(pw.Page(
      pageFormat: PdfPageFormat.a4.landscape,
      build: (pw.Context ctx) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          pw.Container(
            color: const PdfColor.fromInt(0xFF3D1A8C),
            padding: const pw.EdgeInsets.symmetric(vertical: 12, horizontal: 16),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text('ROBOVENTURE',
                    style: pw.TextStyle(
                        color: PdfColors.white,
                        fontSize: 14,
                        fontWeight: pw.FontWeight.bold)),
                pw.Text(categoryName,
                    style: pw.TextStyle(
                        color: PdfColors.white,
                        fontSize: 20,
                        fontWeight: pw.FontWeight.bold)),
                pw.Text('4TH ROBOTICS COMPETITION',
                    style: const pw.TextStyle(color: PdfColors.white, fontSize: 10)),
              ],
            ),
          ),
          pw.SizedBox(height: 8),
          pw.Container(
            color: const PdfColor.fromInt(0xFF5C2ECC),
            padding: const pw.EdgeInsets.symmetric(vertical: 8, horizontal: 8),
            child: pw.Row(children: [
              pw.Expanded(
                  flex: 1,
                  child: pw.Text('MATCH',
                      style: pw.TextStyle(
                          color: PdfColors.white,
                          fontWeight: pw.FontWeight.bold,
                          fontSize: 11))),
              pw.Expanded(
                  flex: 2,
                  child: pw.Text('SCHEDULE',
                      style: pw.TextStyle(
                          color: PdfColors.white,
                          fontWeight: pw.FontWeight.bold,
                          fontSize: 11))),
              ...List.generate(maxArenas, (i) => pw.Expanded(
                    flex: 2,
                    child: pw.Text('ARENA ${i + 1}',
                        textAlign: pw.TextAlign.center,
                        style: pw.TextStyle(
                            color: PdfColors.white,
                            fontWeight: pw.FontWeight.bold,
                            fontSize: 11)),
                  )),
            ]),
          ),
          ...matches.asMap().entries.map((entry) {
            final i = entry.key;
            final m = entry.value;
            final arenas = m['arenas'] as List;
            return pw.Container(
              color: i % 2 == 0
                  ? PdfColors.white
                  : const PdfColor.fromInt(0xFFF3EEFF),
              padding: const pw.EdgeInsets.symmetric(vertical: 10, horizontal: 8),
              child: pw.Row(children: [
                pw.Expanded(
                    flex: 1,
                    child: pw.Text('${m['matchNumber']}',
                        style: const pw.TextStyle(fontSize: 11))),
                pw.Expanded(
                    flex: 2,
                    child: pw.Text('${m['schedule']}',
                        style: const pw.TextStyle(fontSize: 11))),
                ...List.generate(maxArenas, (ai) {
                  final team = ai < arenas.length ? arenas[ai] as Map? : null;
                  if (team != null) {
                    return pw.Expanded(
                      flex: 2,
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.center,
                        children: [
                          pw.Text(team['team_id']?.toString() ?? '',
                              textAlign: pw.TextAlign.center,
                              style: pw.TextStyle(
                                  fontSize: 10, fontWeight: pw.FontWeight.bold)),
                          pw.Text(team['team_name']?.toString() ?? '',
                              textAlign: pw.TextAlign.center,
                              style: const pw.TextStyle(fontSize: 9)),
                        ],
                      ),
                    );
                  }
                  return pw.Expanded(
                      flex: 2,
                      child: pw.Text('—',
                          textAlign: pw.TextAlign.center,
                          style: const pw.TextStyle(color: PdfColors.grey400)));
                }),
              ]),
            );
          }),
        ],
      ),
    ));
    await Printing.layoutPdf(onLayout: (fmt) async => doc.save());
  }

  void _goToGenerateSchedule() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => GenerateSchedule(
          onBack: () => Navigator.of(context).pop(),
          onGenerated: () {
            Navigator.of(context).pop();
            _loadData(initial: true);
          },
        ),
      ),
    );
  }

  // Build alliance selection button for categories
  Widget _buildAllianceSelectionButton(int catId, String categoryName) {
    final matches = _scheduleByCategory[catId] ?? [];
    final allDone = _allMatchesDone(catId, matches);

    if (!allDone) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 10),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF4A1A8C), Color(0xFF2D0E7A)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color: const Color(0xFFFFD700).withOpacity(0.45), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFFFD700).withOpacity(0.14),
            blurRadius: 14,
            spreadRadius: 1,
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: const Color(0xFFFFD700).withOpacity(0.12),
              shape: BoxShape.circle,
            ),
            child:
                const Icon(Icons.celebration, color: Color(0xFFFFD700), size: 20),
          ),
          const SizedBox(width: 14),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'QUALIFICATION COMPLETE!',
                  style: TextStyle(
                    color: Color(0xFFFFD700),
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.1,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'All matches are done. Start the alliance ceremony to move teams into Championship.',
                  style: TextStyle(color: Colors.white70, fontSize: 12.5, height: 1.25),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          ElevatedButton(
            onPressed: () => _showAllianceSelection(catId, categoryName),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFFD700),
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text(
              'START CEREMONY',
              style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQualificationActions(int catId, String categoryName) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          ElevatedButton.icon(
            onPressed: () => _goToGenerateScheduleForCategory(catId, categoryName),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF00CFFF),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            icon: const Icon(Icons.auto_awesome_rounded, size: 18),
            label: Text(
              'GENERATE $categoryName SCHEDULE',
              style: const TextStyle(fontWeight: FontWeight.bold, letterSpacing: 0.8),
            ),
          ),
          OutlinedButton.icon(
            onPressed: () => _confirmClearCategorySchedule(catId, categoryName),
            icon: const Icon(Icons.delete_sweep_rounded, size: 16),
            label: Text('CLEAR $categoryName SCHEDULE'),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.redAccent,
              side: BorderSide(color: Colors.redAccent.withOpacity(0.5)),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Helper method to get category name by ID
  String categoryName(int catId) {
    for (final cat in _categories) {
      final id = int.tryParse(cat['category_id'].toString()) ?? 0;
      if (id == catId) {
        return (cat['category_type'] ?? '').toString();
      }
    }
    return 'Category $catId';
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // Championship tab that uses the ChampionshipSchedule widget
  // ═══════════════════════════════════════════════════════════════════════════
  Widget _buildChampionshipTab(int catId) {
    // Simply return the ChampionshipSchedule widget which now handles everything
    return ChampionshipSchedule(
      key: ValueKey(
          'championship-$catId-${_championshipRefreshVersionByCategory[catId] ?? 0}'),
      categoryId: catId,
      categoryName: categoryName(catId),
    );
  }

  // Add this helper method to check for alliances
  Future<bool> _checkForAlliances(int categoryId) async {
    try {
      final conn = await DBHelper.getConnection();
      final result = await conn.execute(
        "SELECT COUNT(*) as cnt FROM tbl_alliance_selections WHERE category_id = :catId",
        {"catId": categoryId},
      );
      final count =
          int.tryParse(result.rows.first.assoc()['cnt']?.toString() ?? '0') ?? 0;
      return count > 0;
    } catch (e) {
      return false;
    }
  }

 Widget _buildBattleOfChampionsTab(int categoryId, String categoryName) {
  return FutureBuilder<List<Map<String, dynamic>>>(
    future: _getBattleOfChampionsSchedule(categoryId),
    builder: (context, snapshot) {
      if (snapshot.connectionState == ConnectionState.waiting) {
        return const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(color: Color(0xFFFFD700)),
              SizedBox(height: 16),
              Text(
                'Loading Battle of Champions...',
                style: TextStyle(color: Colors.white54),
              ),
            ],
          ),
        );
      }

      if (snapshot.hasError) {
        return Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, color: Colors.redAccent, size: 48),
              const SizedBox(height: 16),
              Text(
                'Error: ${snapshot.error}',
                style: const TextStyle(color: Colors.white54),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => _generateBattleOfChampions(categoryId),
                child: const Text('GENERATE BATTLE'),
              ),
            ],
          ),
        );
      }

      final matches = snapshot.data ?? [];
      
      if (matches.isEmpty) {
        // NO AUTO-GENERATION - Just show the generate button
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
                  Icons.military_tech,
                  size: 64,
                  color: Color(0xFFFFD700),
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'BATTLE OF CHAMPIONS',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 2,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Generate Best of 3 match between Captain and Partner',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.5),
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: () => _generateBattleOfChampions(categoryId),
                icon: const Icon(Icons.auto_awesome),
                label: const Text('GENERATE BATTLE OF CHAMPIONS'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFFD700),
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                ),
              ),
            ],
          ),
        );
      }

      return _buildBattleOfChampionsSchedule(matches, categoryId);
    },
  );
}

Future<List<Map<String, dynamic>>> _getBattleOfChampionsSchedule(int categoryId) async {
  try {
    final matches = await DBHelper.getBattleOfChampionsMatches(categoryId);
    print("📊 Battle of Champions matches for category $categoryId: ${matches.length}");
    for (final match in matches) {
      print("   Match ${match['match_number']}: ${match['captain1_name']} vs ${match['captain2_name']}");
    }
    return matches;
  } catch (e) {
    print("Error getting battle schedule: $e");
    return [];
  }
}

Future<void> _generateBattleOfChampions(int categoryId) async {
  final confirm = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: const Color(0xFF2D0E7A),
      title: const Text('Generate Battle of Champions?', style: TextStyle(color: Colors.white)),
      content: Text(
        'This will create a Best of 3 match between:\n\n'
        '🏆 Captain vs Partner of the Champion Alliance\n\n'
        'This will generate 3 matches (Best of 3).',
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
  
  try {
    await DBHelper.generateBattleOfChampionsSchedule(categoryId);
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ Battle of Champions schedule generated!'),
          backgroundColor: Colors.green,
        ),
      );
      setState(() {});
    }
  } catch (e) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('❌ Error: $e'), backgroundColor: Colors.red),
      );
    }
  }
}

Widget _buildBattleOfChampionsSchedule(List<Map<String, dynamic>> matches, int categoryId) {
  return Column(
    children: [
      // Header with match info
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFFFFD700), Color(0xFFCCAC00)],
          ),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'BATTLE OF CHAMPIONS',
              style: TextStyle(
                color: Colors.black,
                fontWeight: FontWeight.bold,
                fontSize: 16,
                letterSpacing: 2,
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.2),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Text(
                'BEST OF 3',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ),
      ),
      
      // Match cards
      Expanded(
        child: ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: matches.length,
          itemBuilder: (context, index) {
            final match = matches[index];
            final matchNumber = match['match_number'] as int;
            final isCompleted = match['is_completed'] == 1 || match['is_completed'] == true;
            final scheduleTime = match['schedule_time']?.toString() ?? '--:--';
            
            final team1Name = match['team1_name']?.toString() ?? 'Unknown';
            final team2Name = match['team2_name']?.toString() ?? 'Unknown';
            final team1Rank = match['team1_rank']?.toString() ?? '#?';
            final team2Rank = match['team2_rank']?.toString() ?? '#?';
            
            final team1Score = int.parse(match['team1_score']?.toString() ?? '0');
            final team1Violation = int.parse(match['team1_violation']?.toString() ?? '0');
            final team2Score = int.parse(match['team2_score']?.toString() ?? '0');
            final team2Violation = int.parse(match['team2_violation']?.toString() ?? '0');
            final team1Final = team1Score - team1Violation;
            final team2Final = team2Score - team2Violation;
            final winnerId = match['winner_team_id'];
            final isWinner1 = winnerId != null && winnerId.toString() == match['team1_id'].toString();
            
            return Container(
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    const Color(0xFF2D0E7A).withOpacity(0.9),
                    const Color(0xFF1A0A4A).withOpacity(0.9),
                  ],
                ),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: isCompleted ? Colors.green.withOpacity(0.5) : const Color(0xFFFFD700).withOpacity(0.3),
                  width: 1.5,
                ),
              ),
              child: Column(
                children: [
                  // Header
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: isCompleted ? Colors.green.withOpacity(0.1) : const Color(0xFFFFD700).withOpacity(0.1),
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFD700).withOpacity(0.2),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            'MATCH $matchNumber OF 3',
                            style: const TextStyle(
                              color: Color(0xFFFFD700),
                              fontWeight: FontWeight.bold,
                              fontSize: 11,
                            ),
                          ),
                        ),
                        Row(
                          children: [
                            Icon(
                              Icons.access_time,
                              color: Colors.white54,
                              size: 12,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              scheduleTime,
                              style: const TextStyle(color: Colors.white54, fontSize: 11),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  
                  // Match content
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        // Team 1
                        Expanded(
                          child: GestureDetector(
                            onTap: isCompleted ? null : () => _showBattleScoreDialog(match, index),
                            child: Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    isWinner1 ? Colors.green.withOpacity(0.2) : const Color(0xFF00CFFF).withOpacity(0.1),
                                    isWinner1 ? Colors.green.withOpacity(0.1) : const Color(0xFF00CFFF).withOpacity(0.05),
                                  ],
                                ),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: isWinner1 ? Colors.green : const Color(0xFF00CFFF).withOpacity(0.4),
                                  width: isWinner1 ? 2 : 1.5,
                                ),
                              ),
                              child: Column(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF00CFFF).withOpacity(0.2),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(Icons.flag, color: Color(0xFF00CFFF), size: 10),
                                        const SizedBox(width: 4),
                                        Text(
                                          team1Rank,
                                          style: const TextStyle(color: Color(0xFF00CFFF), fontSize: 10, fontWeight: FontWeight.bold),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    team1Name,
                                    style: TextStyle(
                                      color: isWinner1 ? Colors.green : Colors.white,
                                      fontWeight: isWinner1 ? FontWeight.bold : FontWeight.w600,
                                      fontSize: 12,
                                    ),
                                    textAlign: TextAlign.center,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  if (isCompleted) ...[
                                    const SizedBox(height: 8),
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFFFFD700).withOpacity(0.15),
                                            borderRadius: BorderRadius.circular(4),
                                          ),
                                          child: Text(
                                            '$team1Score pts',
                                            style: const TextStyle(color: Color(0xFFFFD700), fontSize: 11, fontWeight: FontWeight.bold),
                                          ),
                                        ),
                                        const SizedBox(width: 4),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: Colors.red.withOpacity(0.15),
                                            borderRadius: BorderRadius.circular(4),
                                          ),
                                          child: Text(
                                            '-$team1Violation',
                                            style: const TextStyle(color: Colors.redAccent, fontSize: 11, fontWeight: FontWeight.bold),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'FINAL: $team1Final',
                                      style: TextStyle(
                                        color: isWinner1 ? Colors.green : Colors.white70,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        ),
                        
                        // VS Divider
                        Container(
                          margin: const EdgeInsets.symmetric(horizontal: 12),
                          width: 50,
                          height: 50,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
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
                              ),
                            ),
                          ),
                        ),
                        
                        // Team 2
                        Expanded(
                          child: GestureDetector(
                            onTap: isCompleted ? null : () => _showBattleScoreDialog(match, index),
                            child: Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    !isWinner1 && isCompleted ? Colors.green.withOpacity(0.2) : const Color(0xFF00FF88).withOpacity(0.1),
                                    !isWinner1 && isCompleted ? Colors.green.withOpacity(0.1) : const Color(0xFF00FF88).withOpacity(0.05),
                                  ],
                                ),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: !isWinner1 && isCompleted ? Colors.green : const Color(0xFF00FF88).withOpacity(0.4),
                                  width: !isWinner1 && isCompleted ? 2 : 1.5,
                                ),
                              ),
                              child: Column(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF00FF88).withOpacity(0.2),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(Icons.flag, color: Color(0xFF00FF88), size: 10),
                                        const SizedBox(width: 4),
                                        Text(
                                          team2Rank,
                                          style: const TextStyle(color: Color(0xFF00FF88), fontSize: 10, fontWeight: FontWeight.bold),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    team2Name,
                                    style: TextStyle(
                                      color: !isWinner1 && isCompleted ? Colors.green : Colors.white,
                                      fontWeight: !isWinner1 && isCompleted ? FontWeight.bold : FontWeight.w600,
                                      fontSize: 12,
                                    ),
                                    textAlign: TextAlign.center,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  if (isCompleted) ...[
                                    const SizedBox(height: 8),
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFFFFD700).withOpacity(0.15),
                                            borderRadius: BorderRadius.circular(4),
                                          ),
                                          child: Text(
                                            '$team2Score pts',
                                            style: const TextStyle(color: Color(0xFFFFD700), fontSize: 11, fontWeight: FontWeight.bold),
                                          ),
                                        ),
                                        const SizedBox(width: 4),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: Colors.red.withOpacity(0.15),
                                            borderRadius: BorderRadius.circular(4),
                                          ),
                                          child: Text(
                                            '-$team2Violation',
                                            style: const TextStyle(color: Colors.redAccent, fontSize: 11, fontWeight: FontWeight.bold),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'FINAL: $team2Final',
                                      style: TextStyle(
                                        color: !isWinner1 && isCompleted ? Colors.green : Colors.white70,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  
                  // Status footer
                  Container(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    decoration: BoxDecoration(
                      color: isCompleted ? Colors.green.withOpacity(0.1) : const Color(0xFFFFD700).withOpacity(0.1),
                      borderRadius: const BorderRadius.vertical(bottom: Radius.circular(14)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          isCompleted ? Icons.check_circle : Icons.schedule,
                          color: isCompleted ? Colors.green : const Color(0xFFFFD700),
                          size: 14,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          isCompleted ? 'COMPLETED' : 'PENDING',
                          style: TextStyle(
                            color: isCompleted ? Colors.green : const Color(0xFFFFD700),
                            fontWeight: FontWeight.bold,
                            fontSize: 11,
                            letterSpacing: 1,
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

void _showBattleScoreDialog(Map<String, dynamic> match, int matchIndex) {
  final matchId = match['match_id'];
  final matchNumber = match['match_number'] as int;
  
  // Safely get values with proper type conversion
  final team1Name = match['team1_name']?.toString() ?? 'Unknown';
  final team2Name = match['team2_name']?.toString() ?? 'Unknown';
  
  // Convert to int safely
  final team1Id = int.tryParse(match['team1_id']?.toString() ?? '0') ?? 0;
  final team2Id = int.tryParse(match['team2_id']?.toString() ?? '0') ?? 0;
  
  final team1Rank = match['team1_rank']?.toString() ?? '#?';
  final team2Rank = match['team2_rank']?.toString() ?? '#?';
  
  final team1ScoreController = TextEditingController(
    text: match['team1_score']?.toString() ?? '0',
  );
  final team1ViolationController = TextEditingController(
    text: match['team1_violation']?.toString() ?? '0',
  );
  final team2ScoreController = TextEditingController(
    text: match['team2_score']?.toString() ?? '0',
  );
  final team2ViolationController = TextEditingController(
    text: match['team2_violation']?.toString() ?? '0',
  );
  
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setDialogState) {
        final team1Score = int.tryParse(team1ScoreController.text) ?? 0;
        final team1Violation = int.tryParse(team1ViolationController.text) ?? 0;
        final team2Score = int.tryParse(team2ScoreController.text) ?? 0;
        final team2Violation = int.tryParse(team2ViolationController.text) ?? 0;
        final team1Final = team1Score - team1Violation;
        final team2Final = team2Score - team2Violation;
        final winnerName = team1Final > team2Final 
            ? team1Name 
            : (team2Final > team1Final ? team2Name : 'Draw');
        
        return Dialog(
          backgroundColor: Colors.transparent,
          child: Container(
            width: 500,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF2D0E7A), Color(0xFF1E0A5A)],
              ),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFFFFD700).withOpacity(0.4), width: 1.5),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Header
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFD700).withOpacity(0.15),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.military_tech, color: Color(0xFFFFD700), size: 24),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'BATTLE OF CHAMPIONS',
                            style: TextStyle(color: Color(0xFFFFD700), fontSize: 14, fontWeight: FontWeight.bold, letterSpacing: 1),
                          ),
                          Text(
                            'Match $matchNumber of 3',
                            style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white54),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                
                // Team 1
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFF00CFFF).withOpacity(0.3)),
                  ),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            width: 30,
                            height: 30,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: const Color(0xFFFFD700).withOpacity(0.2),
                            ),
                            child: Center(
                              child: Text(
                                team1Rank.replaceAll('#', ''),
                                style: const TextStyle(color: Color(0xFFFFD700), fontWeight: FontWeight.bold, fontSize: 12),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              team1Name,
                              style: const TextStyle(color: Color(0xFF00CFFF), fontWeight: FontWeight.bold, fontSize: 14),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: _buildScoreField(
                              label: 'SCORE',
                              controller: team1ScoreController,
                              color: const Color(0xFFFFD700),
                              onChanged: (_) => setDialogState(() {}),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _buildScoreField(
                              label: 'VIOLATION (-)',
                              controller: team1ViolationController,
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
                          const Text('FINAL: ', style: TextStyle(color: Colors.white70)),
                          Text(
                            '$team1Final',
                            style: const TextStyle(color: Color(0xFFFFD700), fontWeight: FontWeight.bold, fontSize: 16),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                
                const SizedBox(height: 16),
                
                // VS
                Container(
                  margin: const EdgeInsets.symmetric(vertical: 4),
                  child: const Center(
                    child: Text('VS', style: TextStyle(color: Color(0xFFFFD700), fontSize: 18, fontWeight: FontWeight.bold)),
                  ),
                ),
                
                const SizedBox(height: 16),
                
                // Team 2
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFF00FF88).withOpacity(0.3)),
                  ),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            width: 30,
                            height: 30,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: const Color(0xFFFFD700).withOpacity(0.2),
                            ),
                            child: Center(
                              child: Text(
                                team2Rank.replaceAll('#', ''),
                                style: const TextStyle(color: Color(0xFFFFD700), fontWeight: FontWeight.bold, fontSize: 12),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              team2Name,
                              style: const TextStyle(color: Color(0xFF00FF88), fontWeight: FontWeight.bold, fontSize: 14),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: _buildScoreField(
                              label: 'SCORE',
                              controller: team2ScoreController,
                              color: const Color(0xFFFFD700),
                              onChanged: (_) => setDialogState(() {}),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _buildScoreField(
                              label: 'VIOLATION (-)',
                              controller: team2ViolationController,
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
                          const Text('FINAL: ', style: TextStyle(color: Colors.white70)),
                          Text(
                            '$team2Final',
                            style: const TextStyle(color: Color(0xFFFFD700), fontWeight: FontWeight.bold, fontSize: 16),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                
                const SizedBox(height: 20),
                
                // Winner preview
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFD700).withOpacity(0.1),
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
                        style: const TextStyle(color: Color(0xFFFFD700), fontWeight: FontWeight.bold, fontSize: 14),
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
                        style: TextButton.styleFrom(
                          side: BorderSide(color: Colors.white.withOpacity(0.2)),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        child: Text('CANCEL', style: TextStyle(color: Colors.white.withOpacity(0.5))),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () async {
                          final winnerId = team1Final > team2Final ? team1Id : team2Id;
                          
                          if (team1Final == team2Final) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Cannot determine winner - scores are tied'), backgroundColor: Colors.orange),
                            );
                            return;
                          }
                          
                          try {
                            await DBHelper.saveBattleOfChampionsResult(
                              matchId: int.parse(matchId.toString()),
                              team1Score: team1Score,
                              team1Violation: team1Violation,
                              team2Score: team2Score,
                              team2Violation: team2Violation,
                              winnerId: winnerId,
                            );
                            
                            if (ctx.mounted) Navigator.pop(ctx);
                            
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('✅ Match result saved!'), backgroundColor: Colors.green),
                            );
                            
                            setState(() {});
                          } catch (e) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('❌ Error: $e'), backgroundColor: Colors.red),
                            );
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


Widget _buildScoreField({
  required String label,
  required TextEditingController controller,
  required Color color,
  required Function(String) onChanged,
}) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold)),
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

Future<bool> _isChampionshipComplete(int categoryId) async {
  try {
    final conn = await DBHelper.getConnection();
    
    // Check if there's a champion determined
    // For double elimination, check if Grand Finals are complete
    final result = await conn.execute("""
      SELECT COUNT(*) as cnt FROM tbl_double_elimination
      WHERE category_id = :catId 
        AND bracket_side = 'grand'
        AND (round_name = 'GF1' OR round_name = 'GF2')
        AND status = 'completed'
        AND winner_alliance_id IS NOT NULL
        AND winner_alliance_id != 0
    """, {"catId": categoryId});
    
    if (result.rows.isNotEmpty) {
      final count = int.parse(result.rows.first.assoc()['cnt']?.toString() ?? '0');
      return count > 0;
    }
    
    // Alternative: Check if there's a champion in alliance standings
    final allianceResult = await conn.execute("""
      SELECT COUNT(*) as cnt FROM tbl_alliance_selections
      WHERE category_id = :catId
    """, {"catId": categoryId});
    
    return int.parse(allianceResult.rows.first.assoc()['cnt']?.toString() ?? '0') > 0;
  } catch (e) {
    print("Error checking championship complete: $e");
    return false;
  }
}

Widget _buildLockedBattleChampionsScreen(String categoryName) {
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
          color: const Color(0xFFFFD700).withOpacity(0.3),
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
              color: const Color(0xFFFFD700).withOpacity(0.1),
              border: Border.all(
                color: const Color(0xFFFFD700).withOpacity(0.4),
                width: 2,
              ),
            ),
            child: const Icon(
              Icons.lock_outline_rounded,
              color: Color(0xFFFFD700),
              size: 64,
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            'BATTLE OF CHAMPIONS',
            style: TextStyle(
              color: Color(0xFFFFD700),
              fontSize: 22,
              fontWeight: FontWeight.w900,
              letterSpacing: 2,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Complete the Championship Round first',
            style: TextStyle(
              color: Colors.white.withOpacity(0.6),
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'The champion will be crowned here after all\nchampionship matches are complete',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white.withOpacity(0.4),
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFFFFD700).withOpacity(0.1),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              categoryName.toUpperCase(),
              style: const TextStyle(
                color: Color(0xFFFFD700),
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

Widget _buildBattleChampionsContent(int categoryId, String categoryName) {
  return FutureBuilder<List<Map<String, dynamic>>>(
    future: _getBattleChampionsData(categoryId),
    builder: (context, snapshot) {
      if (snapshot.connectionState == ConnectionState.waiting) {
        return const Center(
          child: CircularProgressIndicator(color: Color(0xFFFFD700)),
        );
      }

      if (snapshot.hasError) {
        return Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, color: Colors.redAccent, size: 48),
              const SizedBox(height: 16),
              Text(
                'Error loading champions: ${snapshot.error}',
                style: const TextStyle(color: Colors.white54),
              ),
            ],
          ),
        );
      }

      final champions = snapshot.data ?? [];
      
      if (champions.isEmpty) {
        return Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.emoji_events, size: 64, color: Colors.white24),
              const SizedBox(height: 16),
              const Text(
                'No Champions Yet',
                style: TextStyle(color: Colors.white38, fontSize: 18),
              ),
              const SizedBox(height: 8),
              Text(
                'Complete the championship round for $categoryName',
                style: const TextStyle(color: Colors.white24, fontSize: 14),
              ),
            ],
          ),
        );
      }

      return _buildChampionsDisplay(champions, categoryName);
    },
  );
}

Future<List<Map<String, dynamic>>> _getBattleChampionsData(int categoryId) async {
  final List<Map<String, dynamic>> champions = [];
  
  try {
    final conn = await DBHelper.getConnection();
    
    // Get all alliances for this category
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
    
    // Determine the champion from Grand Finals results
    final gfResult = await conn.execute("""
      SELECT winner_alliance_id, round_name, status
      FROM tbl_double_elimination
      WHERE category_id = :catId 
        AND bracket_side = 'grand'
        AND status = 'completed'
        AND winner_alliance_id IS NOT NULL
        AND winner_alliance_id != 0
      ORDER BY round_number DESC, match_id DESC
      LIMIT 1
    """, {"catId": categoryId});
    
    int championId = 0;
    if (gfResult.rows.isNotEmpty) {
      championId = int.parse(gfResult.rows.first.assoc()['winner_alliance_id'].toString());
    } else {
      // Fallback: champion is alliance #1 by rank
      if (alliancesResult.rows.isNotEmpty) {
        championId = int.parse(alliancesResult.rows.first.assoc()['alliance_id'].toString());
      }
    }
    
    // Get champion details
    for (final row in alliancesResult.rows) {
      final data = row.assoc();
      final allianceId = int.parse(data['alliance_id'].toString());
      final isChampion = (allianceId == championId);
      
      // Calculate wins for this alliance
      final winsResult = await conn.execute("""
        SELECT COUNT(DISTINCT CONCAT(match_round, ':', match_position, ':', match_number)) as wins
        FROM tbl_championship_bestof3
        WHERE category_id = :catId 
          AND winner_alliance_id = :allianceId
          AND is_completed = 1
      """, {"catId": categoryId, "allianceId": allianceId});
      
      int wins = 0;
      if (winsResult.rows.isNotEmpty) {
        wins = int.parse(winsResult.rows.first.assoc()['wins']?.toString() ?? '0');
      }
      
      champions.add({
        'alliance_id': allianceId,
        'alliance_rank': int.parse(data['alliance_rank'].toString()),
        'captain_name': data['captain_name'].toString(),
        'partner_name': data['partner_name'].toString(),
        'is_champion': isChampion,
        'wins': wins,
      });
    }
    
    // Sort: champion first, then by wins descending
    champions.sort((a, b) {
      if (a['is_champion'] == true && b['is_champion'] == false) return -1;
      if (a['is_champion'] == false && b['is_champion'] == true) return 1;
      return (b['wins'] as int).compareTo(a['wins'] as int);
    });
    
  } catch (e) {
    print("Error getting battle champions data: $e");
  }
  
  return champions;
}

Widget _buildChampionsDisplay(List<Map<String, dynamic>> champions, String categoryName) {
  final champion = champions.firstWhere((c) => c['is_champion'] == true, orElse: () => champions.first);
  final runnerUp = champions.length > 1 ? champions[1] : null;
  final semiFinalists = champions.skip(2).take(2).toList();
  
  return SingleChildScrollView(
    padding: const EdgeInsets.all(24),
    child: Column(
      children: [
        // Category Header
        Container(
          margin: const EdgeInsets.only(bottom: 24),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFFFFD700), Color(0xFFCCAC00)],
            ),
            borderRadius: BorderRadius.circular(30),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFFFD700).withOpacity(0.3),
                blurRadius: 20,
                spreadRadius: 2,
              ),
            ],
          ),
          child: Text(
            categoryName.toUpperCase(),
            style: const TextStyle(
              color: Colors.black,
              fontWeight: FontWeight.bold,
              fontSize: 18,
              letterSpacing: 2,
            ),
          ),
        ),
        
        // CHAMPION CARD
        _buildMedalCard(
          title: 'CHAMPION',
          medalIcon: Icons.emoji_events,
          medalColor: const Color(0xFFFFD700),
          allianceRank: champion['alliance_rank'],
          captainName: champion['captain_name'],
          partnerName: champion['partner_name'],
          wins: champion['wins'],
          isChampion: true,
        ),
        
        const SizedBox(height: 20),
        
        // RUNNER-UP CARD
        if (runnerUp != null)
          _buildMedalCard(
            title: 'RUNNER-UP',
            medalIcon: Icons.military_tech,
            medalColor: const Color(0xFFC0C0C0),
            allianceRank: runnerUp['alliance_rank'],
            captainName: runnerUp['captain_name'],
            partnerName: runnerUp['partner_name'],
            wins: runnerUp['wins'],
            isChampion: false,
          ),
        
        const SizedBox(height: 20),
        
        // SEMI-FINALISTS SECTION
        if (semiFinalists.isNotEmpty) ...[
          Container(
            margin: const EdgeInsets.only(bottom: 16),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFFCD7F32).withOpacity(0.15),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: const Color(0xFFCD7F32).withOpacity(0.3),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: const [
                Icon(Icons.star_half, color: Color(0xFFCD7F32), size: 16),
                SizedBox(width: 8),
                Text(
                  'SEMI-FINALISTS',
                  style: TextStyle(
                    color: Color(0xFFCD7F32),
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                    letterSpacing: 1.5,
                  ),
                ),
              ],
            ),
          ),
          
          Row(
            children: semiFinalists.asMap().entries.map((entry) {
              final idx = entry.key;
              final finalist = entry.value;
              return Expanded(
                child: Padding(
                  padding: EdgeInsets.only(
                    right: idx == 0 ? 8 : 0,
                    left: idx == 1 ? 8 : 0,
                  ),
                  child: _buildMedalCard(
                    title: 'SEMI-FINALIST ${idx + 1}',
                    medalIcon: Icons.star_half,
                    medalColor: const Color(0xFFCD7F32),
                    allianceRank: finalist['alliance_rank'],
                    captainName: finalist['captain_name'],
                    partnerName: finalist['partner_name'],
                    wins: finalist['wins'],
                    isChampion: false,
                    compact: true,
                  ),
                ),
              );
            }).toList(),
          ),
        ],
        
        const SizedBox(height: 20),
        
        // ALL PARTICIPANTS SECTION
        if (champions.length > 4) ...[
          Container(
            margin: const EdgeInsets.only(top: 8, bottom: 12),
            child: const Text(
              'ALL PARTICIPANTS',
              style: TextStyle(
                color: Colors.white38,
                fontSize: 11,
                fontWeight: FontWeight.bold,
                letterSpacing: 2,
              ),
            ),
          ),
          Container(
            decoration: BoxDecoration(
              color: const Color(0xFF130840),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white.withOpacity(0.1)),
            ),
            child: ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: champions.length,
              separatorBuilder: (_, __) => const Divider(
                color: Colors.white10,
                height: 0,
              ),
              itemBuilder: (context, index) {
                final alliance = champions[index];
                final isTop3 = index < 3;
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Row(
                    children: [
                      Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: isTop3
                              ? (index == 0
                                  ? const Color(0xFFFFD700).withOpacity(0.2)
                                  : index == 1
                                      ? const Color(0xFFC0C0C0).withOpacity(0.2)
                                      : const Color(0xFFCD7F32).withOpacity(0.2))
                              : Colors.white.withOpacity(0.05),
                          border: Border.all(
                            color: isTop3
                                ? (index == 0
                                    ? const Color(0xFFFFD700)
                                    : index == 1
                                        ? const Color(0xFFC0C0C0)
                                        : const Color(0xFFCD7F32))
                                : Colors.white.withOpacity(0.1),
                            width: 1.5,
                          ),
                        ),
                        child: Center(
                          child: Text(
                            '${index + 1}',
                            style: TextStyle(
                              color: isTop3
                                  ? (index == 0
                                      ? const Color(0xFFFFD700)
                                      : index == 1
                                          ? const Color(0xFFC0C0C0)
                                          : const Color(0xFFCD7F32))
                                  : Colors.white38,
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Alliance #${alliance['alliance_rank']}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${alliance['captain_name']} / ${alliance['partner_name']}',
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.5),
                                fontSize: 10,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFD700).withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          '${alliance['wins']} wins',
                          style: const TextStyle(
                            color: Color(0xFFFFD700),
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
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
      ],
    ),
  );
}

Widget _buildMedalCard({
  required String title,
  required IconData medalIcon,
  required Color medalColor,
  required int allianceRank,
  required String captainName,
  required String partnerName,
  required int wins,
  required bool isChampion,
  bool compact = false,
}) {
  return Container(
    decoration: BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: isChampion
            ? [medalColor.withOpacity(0.15), medalColor.withOpacity(0.05)]
            : [const Color(0xFF2D0E7A), const Color(0xFF1E0A5A)],
      ),
      borderRadius: BorderRadius.circular(compact ? 12 : 16),
      border: Border.all(
        color: medalColor.withOpacity(isChampion ? 0.5 : 0.3),
        width: isChampion ? 2 : 1.5,
      ),
      boxShadow: isChampion
          ? [
              BoxShadow(
                color: medalColor.withOpacity(0.3),
                blurRadius: 20,
                spreadRadius: 2,
              ),
            ]
          : [],
    ),
    child: Column(
      children: [
        // Header
        Container(
          padding: EdgeInsets.symmetric(vertical: compact ? 8 : 12, horizontal: 16),
          decoration: BoxDecoration(
            color: medalColor.withOpacity(0.15),
            borderRadius: BorderRadius.vertical(top: Radius.circular(compact ? 12 : 16)),
            border: Border(
              bottom: BorderSide(color: medalColor.withOpacity(0.3)),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(medalIcon, color: medalColor, size: compact ? 20 : 24),
              const SizedBox(width: 8),
              Text(
                title,
                style: TextStyle(
                  color: medalColor,
                  fontWeight: FontWeight.w900,
                  fontSize: compact ? 12 : 14,
                  letterSpacing: 1.5,
                ),
              ),
            ],
          ),
        ),
        
        // Content
        Padding(
          padding: EdgeInsets.all(compact ? 12 : 16),
          child: Row(
            children: [
              // Alliance Rank Badge
              Container(
                width: compact ? 40 : 48,
                height: compact ? 40 : 48,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: [medalColor, medalColor.withOpacity(0.7)],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: medalColor.withOpacity(0.3),
                      blurRadius: 8,
                    ),
                  ],
                ),
                child: Center(
                  child: Text(
                    '#$allianceRank',
                    style: TextStyle(
                      color: Colors.black,
                      fontWeight: FontWeight.bold,
                      fontSize: compact ? 12 : 14,
                    ),
                  ),
                ),
              ),
              
              const SizedBox(width: 16),
              
              // Teams
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 24,
                          height: 24,
                          decoration: BoxDecoration(
                            color: medalColor.withOpacity(0.2),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.person, size: 14, color: Colors.white70),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            captainName,
                            style: TextStyle(
                              color: isChampion ? medalColor : Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: compact ? 12 : 13,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: medalColor.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text(
                            'CAPTAIN',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 8,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Container(
                          width: 24,
                          height: 24,
                          decoration: BoxDecoration(
                            color: medalColor.withOpacity(0.2),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.group, size: 14, color: Colors.white70),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            partnerName,
                            style: TextStyle(
                              color: isChampion ? medalColor : Colors.white70,
                              fontSize: compact ? 11 : 12,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: medalColor.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text(
                            'PARTNER',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 8,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              
              // Wins Badge
              if (!compact)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: medalColor.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: medalColor.withOpacity(0.3)),
                  ),
                  child: Column(
                    children: [
                      Text(
                        '$wins',
                        style: TextStyle(
                          color: medalColor,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      const Text(
                        'WINS',
                        style: TextStyle(
                          color: Colors.white38,
                          fontSize: 8,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    ),
  );
}

  // ═══════════════════════════════════════════════════════════════════════════
  // BUILD
  // ═══════════════════════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0E0730),
      body: Column(children: [
        _buildHeader(),
        if (_isLoading)
          const Expanded(
              child: Center(
                  child: CircularProgressIndicator(color: Color(0xFF00CFFF))))
        else if (_categories.isEmpty)
          const Expanded(
              child: Center(
                  child: Text('No schedule data found.',
                      style: TextStyle(color: Colors.white, fontSize: 18))))
        else ...[
          Container(
            color: const Color(0xFF180850),
            child: TabBar(
              controller: _tabController,
              isScrollable: true,
              indicatorColor: const Color(0xFF00CFFF),
              indicatorWeight: 3,
              labelColor: const Color(0xFF00CFFF),
              unselectedLabelColor: Colors.white38,
              labelStyle: const TextStyle(
                  fontWeight: FontWeight.bold, fontSize: 14, letterSpacing: 1),
              tabs: _categories
                  .map((c) => Tab(
                      text: (c['category_type'] ?? '').toString().toUpperCase()))
                  .toList(),
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: _categories.map((cat) {
                final catId = int.tryParse(cat['category_id'].toString()) ?? 0;
                final matches = _scheduleByCategory[catId] ?? [];
                final isSoccer = catId == _soccerCategoryId;
                return isSoccer
                    ? _buildSoccerView(cat, catId, matches)
                    : _buildCategoryView(cat, catId, matches);
              }).toList(),
            ),
          ),
        ],
      ]),
    );
  }

  Widget _buildSoccerView(Map<String, dynamic> category, int catId,
      List<Map<String, dynamic>> matches) {
    final bracketSize = _bracketSize(_soccerTeams.length);
    final canSeed = !_bracketSeeded;
    final allDone = _allMatchesDone(catId, matches);

    return DefaultTabController(
      length: 3, // Make sure this is 3
      child: Column(children: [
        _buildCategoryTitleBar(category, 'SOCCER', matches),
        Container(
          color: const Color(0xFF130742),
          child: TabBar(
            onTap: (index) {
              if (index == 1 && !allDone) {
                DefaultTabController.of(context).animateTo(0);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    backgroundColor: const Color(0xFF2D0E7A),
                    behavior: SnackBarBehavior.floating,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                    content: Row(children: const [
                      Icon(Icons.lock, color: Color(0xFFFFD700), size: 18),
                      SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Complete all group-stage matches first.\nSet every match status to "Done" to unlock the bracket.',
                          style: TextStyle(color: Colors.white, fontSize: 13),
                        ),
                      ),
                    ]),
                    duration: const Duration(seconds: 3),
                  ),
                );
              }
            },
            indicatorColor: const Color(0xFF00FF88),
            indicatorWeight: 3,
            labelColor: const Color(0xFF00FF88),
            unselectedLabelColor: Colors.white30,
            labelStyle: const TextStyle(
                fontWeight: FontWeight.bold, fontSize: 14, letterSpacing: 1.2),
            tabs: [
              const Tab(
                icon: Icon(Icons.calendar_today, size: 16),
                text: 'QUALIFICATION',
              ),
              Tab(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      allDone ? Icons.account_tree : Icons.lock,
                      size: 16,
                      color: allDone ? const Color(0xFF00FF88) : Colors.white24,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'PLAYOFF BRACKET',
                      style: TextStyle(
                        color: allDone ? const Color(0xFF00FF88) : Colors.white24,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ],
                ),
              ),
              const Tab(
                icon: Icon(Icons.emoji_events, size: 16),
                text: 'CHAMPIONSHIP',
              ),
            ],
          ),
        ),
        Expanded(
          child: TabBarView(
            children: [
              _buildSoccerScheduleTab(catId, matches, bracketSize, canSeed),
              allDone
                  ? _buildBracketTab(matches)
                  : _buildBracketLockedScreen(matches),
              _buildChampionshipTab(catId), // This now uses the fixed method
            ],
          ),
        ),
      ]),
    );
  }

  // Locked bracket placeholder screen
  Widget _buildBracketLockedScreen(List<Map<String, dynamic>> matches) {
    final total = matches.length;
    final doneCount = matches.where((m) {
      final matchNum = m['matchNumber'] as int? ?? 0;
      return _getStatus(_soccerCategoryId ?? 0, matchNum) == MatchStatus.done;
    }).length;
    final remaining = total - doneCount;

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFF1A0A4A),
              border: Border.all(
                  color: const Color(0xFFFFD700).withOpacity(0.3), width: 2),
              boxShadow: [
                BoxShadow(
                    color: const Color(0xFFFFD700).withOpacity(0.1),
                    blurRadius: 30,
                    spreadRadius: 5),
              ],
            ),
            child: const Icon(Icons.lock, color: Color(0xFFFFD700), size: 52),
          ),
          const SizedBox(height: 24),
          const Text(
            'BRACKET LOCKED',
            style: TextStyle(
                color: Color(0xFFFFD700),
                fontSize: 22,
                fontWeight: FontWeight.w900,
                letterSpacing: 3),
          ),
          const SizedBox(height: 10),
          Text(
            'Complete all group-stage matches to unlock.',
            style: TextStyle(color: Colors.white.withOpacity(0.45), fontSize: 15),
          ),
          const SizedBox(height: 20),
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 48),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            decoration: BoxDecoration(
              color: const Color(0xFF130742),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                  color: const Color(0xFF3D1E88).withOpacity(0.5), width: 1),
            ),
            child: Column(children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Matches Done',
                      style: TextStyle(
                          color: Colors.white.withOpacity(0.5), fontSize: 13)),
                  Text('$doneCount / $total',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.bold)),
                ],
              ),
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: total > 0 ? doneCount / total : 0,
                  minHeight: 8,
                  backgroundColor: Colors.white.withOpacity(0.08),
                  valueColor:
                      const AlwaysStoppedAnimation<Color>(Color(0xFF00FF88)),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                remaining > 0
                    ? '$remaining match${remaining > 1 ? 'es' : ''} remaining'
                    : 'All matches complete!',
                style: TextStyle(
                    color: remaining > 0
                        ? Colors.white38
                        : const Color(0xFF00FF88),
                    fontSize: 13),
              ),
            ]),
          ),
        ],
      ),
    );
  }

  // Soccer Schedule sub-tab
  Widget _buildSoccerScheduleTab(int catId, List<Map<String, dynamic>> matches,
      int bracketSize, bool canSeed) {
    final List<Map<String, dynamic>> rows = [];
    int i = 0;
    while (i < matches.length) {
      final m = matches[i];
      final arenas = m['arenas'] as List? ?? [];
      if (arenas.length >= 2 && arenas[1] != null) {
        rows.add(m);
        i++;
      } else {
        final t1 = arenas.isNotEmpty ? arenas[0] as Map<String, dynamic>? : null;
        Map<String, dynamic>? t2;
        if (i + 1 < matches.length) {
          final next = matches[i + 1];
          final nextArenas = next['arenas'] as List? ?? [];
          t2 = nextArenas.isNotEmpty ? nextArenas[0] as Map<String, dynamic>? : null;
        }
        rows.add({
          'matchNumber': m['matchNumber'],
          'match_id': m['match_id'],
          'schedule': m['schedule'],
          'schedule_start': m['schedule_start'],
          'team1': t1,
          'team2': t2,
        });
        i += t2 != null ? 2 : 1;
      }
    }

    return Column(children: [
      if (canSeed)
        Container(
          margin: const EdgeInsets.fromLTRB(12, 10, 12, 0),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
                colors: [Color(0xFF00803A), Color(0xFF005728)]),
            borderRadius: BorderRadius.circular(10),
            boxShadow: [
              BoxShadow(
                  color: const Color(0xFF00FF88).withOpacity(0.2), blurRadius: 16)
            ],
          ),
          child: Row(children: [
            const Icon(Icons.emoji_events, color: Color(0xFFFFD700), size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Top $bracketSize teams ready to advance to the bracket.',
                style: const TextStyle(
                    color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600),
              ),
            ),
            const SizedBox(width: 10),
            ElevatedButton.icon(
              onPressed: () => _seedBracketFromStandings(matches),
              icon: const Icon(Icons.account_tree, size: 16),
              label: const Text('Seed Bracket',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF00CFFF),
                foregroundColor: const Color(0xFF0E0730),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              ),
            ),
          ]),
        ),

      // Add Alliance Selection button when all matches are done
      _buildAllianceSelectionButton(catId, categoryName(catId)),

      Container(
        decoration: const BoxDecoration(
            gradient: LinearGradient(
                colors: [Color(0xFF4A22AA), Color(0xFF3A1880)])),
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 24),
        child: Row(children: [
          _headerCell('#', flex: 1),
          _headerCell('TIME', flex: 2),
          _headerCell('HOME', flex: 4, center: true),
          _headerCell('SCORE', flex: 2, center: true),
          _headerCell('AWAY', flex: 4, center: true),
          _headerCell('STATUS', flex: 2, center: true),
        ]),
      ),

      Expanded(
        child: rows.isEmpty
            ? const Center(
                child: Text('No matches scheduled.',
                    style: TextStyle(color: Colors.white38, fontSize: 16)))
            : ListView.builder(
                itemCount: rows.length,
                itemBuilder: (context, idx) {
                  final row = rows[idx];
                  final matchId = row['match_id'].toString();
                  final matchNum = row['matchNumber'] as int;
                  final schedule = row['schedule'] as String;
                  final isEven = idx % 2 == 0;
                  final status = _getStatus(catId, matchNum);
                  final score = _soccerScores[matchId];

                  Map<String, dynamic>? t1 =
                      row['team1'] as Map<String, dynamic>?;
                  Map<String, dynamic>? t2 =
                      row['team2'] as Map<String, dynamic>?;
                  if (t1 == null && row.containsKey('arenas')) {
                    final arenas = row['arenas'] as List? ?? [];
                    t1 = arenas.isNotEmpty
                        ? arenas[0] as Map<String, dynamic>?
                        : null;
                    t2 = arenas.length > 1
                        ? arenas[1] as Map<String, dynamic>?
                        : null;
                  }

                  final team1Name = t1?['team_name']?.toString() ?? '—';
                  final team2Name = t2?['team_name']?.toString() ?? '—';
                  final t1raw = t1?['team_id']?.toString() ?? '';
                  final t2raw = t2?['team_id']?.toString() ?? '';
                  final team1Id = t1raw.isNotEmpty ? 'C${t1raw}R' : '';
                  final team2Id = t2raw.isNotEmpty ? 'C${t2raw}R' : '';
                  final bothReal = team1Name != '—' && team2Name != '—';

                  final bool t1Wins = score?.isHomeWin == true;
                  final bool t2Wins = score?.isAwayWin == true;
                  final bool isDraw = score?.isDraw == true;

                  return Container(
                    decoration: BoxDecoration(
                      color: isEven
                          ? const Color(0xFF160C40)
                          : const Color(0xFF100830),
                      border: const Border(
                          bottom: BorderSide(color: Color(0xFF1A1050), width: 1)),
                    ),
                    child: IntrinsicHeight(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(
                              flex: 1,
                              child: Center(
                                child: Text('$matchNum',
                                    style: TextStyle(
                                        color: Colors.white.withOpacity(0.4),
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16)),
                              )),
                          Expanded(
                              flex: 2,
                              child: Center(
                                child: Text(schedule,
                                    style: TextStyle(
                                        color: Colors.white.withOpacity(0.55),
                                        fontSize: 15)),
                              )),
                          Expanded(
                              flex: 4,
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                    vertical: 14, horizontal: 8),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    if (team1Id.isNotEmpty)
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 7, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFF00CFFF)
                                              .withOpacity(0.15),
                                          borderRadius:
                                              BorderRadius.circular(4),
                                          border: Border.all(
                                              color: const Color(0xFF00CFFF)
                                                  .withOpacity(0.5),
                                              width: 1),
                                        ),
                                        child: Text(team1Id,
                                            style: const TextStyle(
                                                color: Color(0xFF00CFFF),
                                                fontSize: 11,
                                                fontWeight: FontWeight.bold,
                                                letterSpacing: 1.2)),
                                      ),
                                    const SizedBox(height: 4),
                                    Text(team1Name,
                                        textAlign: TextAlign.right,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                            color: t1Wins
                                                ? const Color(0xFF00FF88)
                                                : isDraw
                                                    ? const Color(0xFFFFD700)
                                                    : team1Name == '—'
                                                        ? Colors.white24
                                                        : Colors.white,
                                            fontSize: 16,
                                            fontWeight: t1Wins
                                                ? FontWeight.bold
                                                : FontWeight.w700)),
                                  ],
                                ),
                              )),
                          Expanded(
                              flex: 2,
                              child: Center(
                                child: GestureDetector(
                                  onTap: bothReal
                                      ? () => _showScoreDialog(
                                          matchId, team1Name, team2Name, matches)
                                      : null,
                                  child: Container(
                                    margin: const EdgeInsets.symmetric(
                                        horizontal: 4, vertical: 10),
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 10, vertical: 6),
                                    decoration: BoxDecoration(
                                      gradient: score?.isFinished == true
                                          ? const LinearGradient(
                                              colors: [
                                                Color(0xFF3D1E88),
                                                Color(0xFF1A0850)
                                              ])
                                          : null,
                                      color: score?.isFinished == true
                                          ? null
                                          : bothReal
                                              ? const Color(0xFF1A0F38)
                                              : const Color(0xFF0D0722),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                        color: score?.isFinished == true
                                            ? const Color(0xFF7B50D8)
                                            : bothReal
                                                ? const Color(0xFF3D1E88)
                                                : Colors.white12,
                                        width: 1.5,
                                      ),
                                      boxShadow: score?.isFinished == true
                                          ? [
                                              BoxShadow(
                                                  color: const Color(0xFF5B2CC0)
                                                      .withOpacity(0.3),
                                                  blurRadius: 8)
                                            ]
                                          : [],
                                    ),
                                    child: score?.isFinished == true
                                        ? Text('${score!.home}  –  ${score.away}',
                                            textAlign: TextAlign.center,
                                            style: const TextStyle(
                                                color: Colors.white,
                                                fontSize: 16,
                                                fontWeight: FontWeight.bold,
                                                letterSpacing: 1))
                                        : Text(bothReal ? 'TAP\nSCORE' : '—',
                                            textAlign: TextAlign.center,
                                            style: TextStyle(
                                                color: bothReal
                                                    ? Colors.white38
                                                    : Colors.white12,
                                                fontSize: 10,
                                                fontWeight: FontWeight.bold,
                                                letterSpacing: 0.5)),
                                  ),
                                ),
                              )),
                          Expanded(
                              flex: 4,
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                    vertical: 14, horizontal: 8),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    if (team2Id.isNotEmpty)
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 7, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFF00CFFF)
                                              .withOpacity(0.15),
                                          borderRadius:
                                              BorderRadius.circular(4),
                                          border: Border.all(
                                              color: const Color(0xFF00CFFF)
                                                  .withOpacity(0.5),
                                              width: 1),
                                        ),
                                        child: Text(team2Id,
                                            style: const TextStyle(
                                                color: Color(0xFF00CFFF),
                                                fontSize: 11,
                                                fontWeight: FontWeight.bold,
                                                letterSpacing: 1.2)),
                                      ),
                                    const SizedBox(height: 4),
                                    Text(team2Name,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                            color: t2Wins
                                                ? const Color(0xFF00FF88)
                                                : isDraw
                                                    ? const Color(0xFFFFD700)
                                                    : team2Name == '—'
                                                        ? Colors.white24
                                                        : Colors.white,
                                            fontSize: 16,
                                            fontWeight: t2Wins
                                                ? FontWeight.bold
                                                : FontWeight.w700)),
                                  ],
                                ),
                              )),
                          Expanded(
                              flex: 2,
                              child: Center(
                                child: GestureDetector(
                                  onTap: () => _cycleStatus(catId, matchNum),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 10, vertical: 7),
                                    decoration: BoxDecoration(
                                      color: status.color.withOpacity(0.12),
                                      borderRadius: BorderRadius.circular(20),
                                      border:
                                          Border.all(color: status.color, width: 1.5),
                                    ),
                                    child: Text(status.label,
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                            color: status.color,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 12)),
                                  ),
                                ),
                              )),
                        ],
                      ),
                    ),
                  );
                },
              ),
      ),
    ]);
  }

  // Bracket sub-tab
  Widget _buildBracketTab(List<Map<String, dynamic>> matches) {
    if (!_bracketSeeded || _bracketRounds.isEmpty) {
      final totalTeams = _soccerTeams.length;
      final bracketSize = _bracketSize(totalTeams);
      return Center(
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(Icons.account_tree, size: 64,
              color: Colors.white.withOpacity(0.08)),
          const SizedBox(height: 16),
          const Text('Bracket not seeded yet.',
              style: TextStyle(color: Colors.white38, fontSize: 18)),
          const SizedBox(height: 6),
          Text(
            totalTeams == 0
                ? 'Register teams first.'
                : 'Enter scores in the Schedule tab,\nthen seed the bracket with the Top $bracketSize teams.',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white24, fontSize: 15),
          ),
          if (totalTeams >= 4) ...[
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: () => _seedBracketFromStandings(matches),
              icon: const Icon(Icons.account_tree, size: 16),
              label: Text('Seed Top $bracketSize Bracket',
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF5B2CC0),
                foregroundColor: Colors.white,
                shape:
                    RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              ),
            ),
          ],
        ]),
      );
    }

    final totalRounds = _bracketRounds.length;
    final champion = _bracketRounds.last.first.winner;
    final bracketSize = _bracketRounds[0].length * 2;

    return Column(children: [
      Container(
        color: const Color(0xFF0D0628),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        child: Row(children: [
          const Icon(Icons.emoji_events, color: Color(0xFFFFD700), size: 18),
          const SizedBox(width: 6),
          Text('Top $bracketSize · $totalRounds Rounds',
              style: const TextStyle(color: Color(0xFF7C6AAA), fontSize: 14)),
          if (champion != null) ...[
            const SizedBox(width: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
              decoration: BoxDecoration(
                color: const Color(0xFFFFD700).withOpacity(0.1),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                    color: const Color(0xFFFFD700).withOpacity(0.6)),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.star, color: Color(0xFFFFD700), size: 14),
                const SizedBox(width: 4),
                Text('Champion: ${champion.teamName}',
                    style: const TextStyle(
                        color: Color(0xFFFFD700),
                        fontSize: 13,
                        fontWeight: FontWeight.bold)),
              ]),
            ),
          ],
          const Spacer(),
          Text('Tap a card to set winner',
              style: TextStyle(color: Colors.white.withOpacity(0.2), fontSize: 13)),
          const SizedBox(width: 12),
          TextButton.icon(
            onPressed: () => _rebuildBracket(matches),
            icon: const Icon(Icons.refresh, size: 14, color: Color(0xFF00CFFF)),
            label: const Text('Reseed',
                style: TextStyle(color: Color(0xFF00CFFF), fontSize: 13)),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              side: const BorderSide(color: Color(0xFF00CFFF), width: 1),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
            ),
          ),
        ]),
      ),
      Expanded(
        child: LayoutBuilder(builder: (context, constraints) {
          final availW = constraints.maxWidth - 40;
          final availH = constraints.maxHeight - 40;
          final numRounds = _bracketRounds.length;
          final firstRoundCnt = _bracketRounds[0].length;

          const double kGapWFrac = 0.08;
          const double kGapHFrac = 0.12;

          final double gapW = availW * kGapWFrac / numRounds;
          final double matchW = (availW - gapW * (numRounds - 1)) / numRounds;
          final double gapH = availH * kGapHFrac / firstRoundCnt;
          final double matchH = (availH - gapH * (firstRoundCnt - 1)) / firstRoundCnt;

          return Padding(
            padding: const EdgeInsets.all(20),
            child: SizedBox(
              width: availW,
              height: availH,
              child: _BracketCanvas(
                rounds: _bracketRounds,
                onMatchTap: _showMatchDialog,
                matchW: matchW,
                matchH: matchH,
                gapW: gapW,
                gapH: gapH,
              ),
            ),
          );
        }),
      ),
    ]);
  }

  void _showMatchDialog(BracketMatch match) {
    final bool t1Real = !match.team1.isBye && match.team1.teamName != 'TBD';
    final bool t2Real = !match.team2.isBye && match.team2.teamName != 'TBD';
    if (!t1Real && !t2Real) return;
    if (t1Real && !t2Real) {
      _setMatchResult(match, match.team1);
      return;
    }
    if (t2Real && !t1Real) {
      _setMatchResult(match, match.team2);
      return;
    }

    showDialog(
      context: context,
      barrierColor: Colors.black.withOpacity(0.7),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) => Dialog(
          backgroundColor: Colors.transparent,
          child: Container(
            width: 420,
            decoration: BoxDecoration(
              color: const Color(0xFF14093A),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFF3D1E88), width: 1.5),
              boxShadow: [
                BoxShadow(
                    color: const Color(0xFF6B2FD9).withOpacity(0.35),
                    blurRadius: 40,
                    spreadRadius: 2)
              ],
            ),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Container(
                padding: const EdgeInsets.fromLTRB(20, 14, 14, 14),
                decoration: const BoxDecoration(
                  color: Color(0xFF0F0628),
                  borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
                ),
                child: Row(children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                        color: const Color(0xFF3D1E88).withOpacity(0.5),
                        borderRadius: BorderRadius.circular(8)),
                    child: const Icon(Icons.sports_soccer,
                        color: Color(0xFF9B6FE8), size: 18),
                  ),
                  const SizedBox(width: 10),
                  const Text('SELECT MATCH WINNER',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.5)),
                  const Spacer(),
                  GestureDetector(
                    onTap: () => Navigator.pop(ctx),
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.06),
                          borderRadius: BorderRadius.circular(6)),
                      child: Icon(Icons.close,
                          color: Colors.white.withOpacity(0.4), size: 18),
                    ),
                  ),
                ]),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 6),
                child: Column(children: [
                  _dialogTeamButton(ctx, setDlgState, match, match.team1),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Row(children: [
                      Expanded(
                          child: Container(
                              height: 1,
                              decoration: BoxDecoration(
                                  gradient: LinearGradient(colors: [
                                Colors.transparent,
                                Colors.white.withOpacity(0.12)
                              ])))),
                      Container(
                        margin: const EdgeInsets.symmetric(horizontal: 14),
                        padding:
                            const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                              colors: [Color(0xFF8B3FE8), Color(0xFF5218A8)]),
                          borderRadius: BorderRadius.circular(6),
                          boxShadow: [
                            BoxShadow(
                                color: const Color(0xFF7B2FD8).withOpacity(0.6),
                                blurRadius: 14)
                          ],
                        ),
                        child: const Text('VS',
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 17,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 3,
                                fontStyle: FontStyle.italic)),
                      ),
                      Expanded(
                          child: Container(
                              height: 1,
                              decoration: BoxDecoration(
                                  gradient: LinearGradient(colors: [
                                Colors.white.withOpacity(0.12),
                                Colors.transparent
                              ])))),
                    ]),
                  ),
                  _dialogTeamButton(ctx, setDlgState, match, match.team2),
                ]),
              ),
              if (match.winner != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: TextButton.icon(
                    onPressed: () {
                      _clearMatchResult(match);
                      Navigator.pop(ctx);
                    },
                    icon: const Icon(Icons.restart_alt,
                        color: Colors.redAccent, size: 16),
                    label: const Text('Clear result',
                        style: TextStyle(color: Colors.redAccent, fontSize: 14)),
                  ),
                ),
              const SizedBox(height: 8),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _dialogTeamButton(BuildContext ctx, StateSetter setDlgState,
      BracketMatch match, BracketTeam team) {
    final isWinner = match.winner?.teamId == team.teamId;
    final initial = team.teamName.isNotEmpty ? team.teamName[0].toUpperCase() : '?';
    return GestureDetector(
      onTap: () {
        _setMatchResult(match, team);
        setDlgState(() {});
        Navigator.pop(ctx);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          gradient: isWinner
              ? const LinearGradient(
                  colors: [Color(0xFF00B86A), Color(0xFF006B3E)])
              : null,
          color: isWinner ? null : const Color(0xFF1C0F4A),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
              color: isWinner ? const Color(0xFF00FF88) : const Color(0xFF2E1A5E),
              width: isWinner ? 2 : 1),
          boxShadow: isWinner
              ? [
                  BoxShadow(
                      color: const Color(0xFF00FF88).withOpacity(0.28),
                      blurRadius: 16)
                ]
              : [],
        ),
        child: Row(children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: isWinner
                  ? LinearGradient(colors: [
                      Colors.white.withOpacity(0.25),
                      Colors.white.withOpacity(0.10)
                    ])
                  : const LinearGradient(
                      colors: [Color(0xFF2E1A62), Color(0xFF1C0F42)]),
              border: Border.all(
                  color: isWinner
                      ? Colors.white.withOpacity(0.5)
                      : const Color(0xFF3E2878),
                  width: 1.5),
            ),
            child: Center(
                child: Text(initial,
                    style: TextStyle(
                        color: isWinner ? Colors.white : Colors.white54,
                        fontWeight: FontWeight.bold,
                        fontSize: 17))),
          ),
          const SizedBox(width: 12),
          Expanded(
              child: Text(team.teamName,
                  style: TextStyle(
                      color: isWinner ? Colors.white : Colors.white70,
                      fontWeight: isWinner ? FontWeight.bold : FontWeight.w500,
                      fontSize: 16),
                  overflow: TextOverflow.ellipsis)),
          if (isWinner) ...[
            const Icon(Icons.emoji_events, color: Color(0xFFFFD700), size: 19),
            const SizedBox(width: 4),
            const Icon(Icons.check_circle, color: Colors.white, size: 19),
          ] else
            Icon(Icons.chevron_right, color: Colors.white.withOpacity(0.15), size: 20),
        ]),
      ),
    );
  }

  // In _buildCategoryView method (around line 1800 in schedule_viewer.dart)
// Change from length: 2 to length: 3

Widget _buildCategoryView(Map<String, dynamic> category, int catId,
    List<Map<String, dynamic>> matches) {
  final categoryName = (category['category_type'] ?? '').toString().toUpperCase();
  final isSoccer = catId == _soccerCategoryId;

  return DefaultTabController(
    length: 3,  // Change from 2 to 3 for Battle of Champions
    child: Builder(
      builder: (tabContext) {
        _categoryTabContexts[catId] = tabContext;
        return Column(
          children: [
            _buildCategoryTitleBar(category, categoryName, matches),

            Container(
              color: const Color(0xFF130742),
              child: TabBar(
                indicatorColor: const Color(0xFFFFD700),
                indicatorWeight: 3,
                labelColor: const Color(0xFFFFD700),
                unselectedLabelColor: Colors.white30,
                labelStyle: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    letterSpacing: 1.2),
                tabs: const [
                  Tab(
                    icon: Icon(Icons.calendar_today, size: 16),
                    text: 'QUALIFICATION',
                  ),
                  Tab(
                    icon: Icon(Icons.emoji_events, size: 16),
                    text: 'CHAMPIONSHIP',
                  ),
                  Tab(
                    icon: Icon(Icons.military_tech, size: 16),
                    text: 'BATTLE OF CHAMPIONS',
                  ),
                ],
              ),
            ),

            Expanded(
              child: TabBarView(
                children: [
                  // Tab 0: Qualification
                  Column(
                    children: [
                      _buildQualificationActions(catId, categoryName),
                      _buildAllianceSelectionButton(catId, categoryName),
                      Expanded(
                        child: isSoccer
                            ? _buildSoccerScheduleTab(catId, matches,
                                _bracketSize(_soccerTeams.length), !_bracketSeeded)
                            : _buildScheduleTable(category, catId, matches),
                      ),
                    ],
                  ),
                  // Tab 1: Championship
                  ChampionshipSchedule(
                    key: ValueKey(
                        'championship-$catId-${_championshipRefreshVersionByCategory[catId] ?? 0}'),
                    categoryId: catId,
                    categoryName: categoryName,
                  ),
                  // Tab 2: Battle of Champions (NEW)
                  _buildBattleOfChampionsTab(catId, categoryName),
                ],
              ),
            ),
          ],
        );
      },
    ),
  );
}

  // Add these new methods to _ScheduleViewerState:

  Future<void> _goToGenerateScheduleForCategory(
      int categoryId, String categoryName) async {
    // Navigate to generate schedule page with pre-selected category
    final result = await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => GenerateSchedule(
          preSelectedCategoryId: categoryId,
          categoryName: categoryName,
          onBack: () => Navigator.of(context).pop(),
          onGenerated: () {
            Navigator.of(context).pop();
            _loadData(initial: true);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('✅ Schedule generated for $categoryName'),
                backgroundColor: Colors.green,
                duration: const Duration(seconds: 2),
              ),
            );
          },
        ),
      ),
    );
  }

  Future<void> _confirmClearCategorySchedule(
      int categoryId, String categoryName) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF2D0E7A),
        title: Text('Clear $categoryName Schedule?',
            style: const TextStyle(color: Colors.white)),
        content: Text(
          'This will delete ALL matches for $categoryName. This action cannot be undone.',
          style: const TextStyle(color: Colors.white70),
        ),
                  actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('CANCEL', style: TextStyle(color: Colors.white54)),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text('GENERATE', style: TextStyle(color: kAccentGold)),
            ),
          ],
      ),
    );

    if (confirm == true) {
      await _clearCategorySchedule(categoryId);
    }
  }

  Future<void> _clearCategorySchedule(int categoryId) async {
    try {
      final conn = await DBHelper.getConnection();

      // Delete only matches for this category
      await DBHelper.executeDual("""
        DELETE ts FROM tbl_teamschedule ts
        JOIN tbl_team t ON ts.team_id = t.team_id
        WHERE t.category_id = :catId
      """, {"catId": categoryId});

      // Also delete orphaned matches and schedules
      await DBHelper.executeDual("""
        DELETE m FROM tbl_match m
        WHERE NOT EXISTS (
          SELECT 1 FROM tbl_teamschedule ts WHERE ts.match_id = m.match_id
        )
      """);

      await DBHelper.executeDual("""
        DELETE s FROM tbl_schedule s
        WHERE NOT EXISTS (
          SELECT 1 FROM tbl_match m WHERE m.schedule_id = s.schedule_id
        )
      """);

      // Refresh the view
      _loadData(initial: true);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('✅ Schedule cleared for category'),
          backgroundColor: Colors.orange,
        ),
      );
    } catch (e) {
      print("Error clearing category schedule: $e");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('❌ Error clearing schedule: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Widget _buildCategoryTitleBar(Map<String, dynamic> category, String title,
      List<Map<String, dynamic>> matches) {
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF2D0E7A), Color(0xFF1A0850)],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
      ),
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 28),
      child: Row(children: [
        const Text('MAKE X',
            style: TextStyle(
                color: Colors.white30,
                fontSize: 14,
                fontWeight: FontWeight.bold,
                letterSpacing: 2)),
        const Spacer(),
        Text(title,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 26,
                fontWeight: FontWeight.w900,
                letterSpacing: 3)),
        const Spacer(),
        IconButton(
            tooltip: 'Export PDF',
            icon: const Icon(Icons.picture_as_pdf,
                color: Color(0xFF00CFFF), size: 22),
            onPressed: () => _exportPdf(category, matches)),
        _buildLiveIndicator(),
        IconButton(
            tooltip: 'View Standings',
            icon: const Icon(Icons.emoji_events, color: Color(0xFFFFD700), size: 22),
            onPressed: widget.onStandings),
        IconButton(
            tooltip: 'Register',
            icon: const Icon(Icons.app_registration, color: Color(0xFF00CFFF), size: 22),
            onPressed: widget.onRegister),
      ]),
    );
  }

  // UPDATED: New schedule table using enhanced cards
  Widget _buildScheduleTable(Map<String, dynamic> category, int catId,
      List<Map<String, dynamic>> matches) {
    return matches.isEmpty
        ? const Center(
            child: Text('No matches scheduled.',
                style: TextStyle(color: Colors.white38, fontSize: 16)))
        : ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 4),
            itemCount: matches.length,
            itemBuilder: (context, index) {
              final match = matches[index];
              final matchNum = match['matchNumber'] as int;
              final schedule = match['schedule'] as String;
              final arena1Teams = match['arena1_teams'] as List? ?? [];
              final arena2Teams = match['arena2_teams'] as List? ?? [];
              final status = _getStatus(catId, matchNum);

              // Convert teams to the format expected by _EnhancedMatchCard
              final redTeam = arena1Teams.map((team) => {
                    'team_name': team['team_name'] as String,
                    'team_id': team['team_id'] as String,
                  }).toList();

              final blueTeam = arena2Teams.map((team) => {
                    'team_name': team['team_name'] as String,
                    'team_id': team['team_id'] as String,
                  }).toList();

              return _EnhancedMatchCard(
                match: match,
                matchNumber: matchNum,
                schedule: schedule,
                redTeam: redTeam,
                blueTeam: blueTeam,
                onStatusTap: () => _cycleStatus(catId, matchNum),
                status: status,
              );
            },
          );
  }

  Widget _buildHeader() {
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
            colors: [Color(0xFF2D0E7A), Color(0xFF1A0850), Color(0xFF2D0E7A)]),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            RichText(
                text: const TextSpan(children: [
              TextSpan(
                  text: 'Make',
                  style: TextStyle(
                      color: Colors.white, fontSize: 26, fontWeight: FontWeight.bold)),
              TextSpan(
                  text: 'bl',
                  style: TextStyle(
                      color: Color(0xFF00CFFF),
                      fontSize: 26,
                      fontWeight: FontWeight.bold)),
              TextSpan(
                  text: 'ock',
                  style: TextStyle(
                      color: Colors.white, fontSize: 26, fontWeight: FontWeight.bold)),
            ])),
            const Text('Construct Your Dreams',
                style: TextStyle(color: Colors.white38, fontSize: 13)),
          ]),
          Image.asset('assets/images/MakeX_logo.png',
              height: 100, fit: BoxFit.contain),
          const Text('CREOTEC',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 3)),
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
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        _PulsingDot(),
        const SizedBox(width: 5),
        Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('LIVE',
                  style: TextStyle(
                      color: Color(0xFF00FF88),
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.2)),
              Text(timeStr,
                  style: const TextStyle(color: Colors.white38, fontSize: 11)),
            ]),
      ]),
    );
  }

  Widget _headerCell(String text, {int flex = 1, bool center = false}) => Expanded(
        flex: flex,
        child: Text(text,
            textAlign: center ? TextAlign.center : TextAlign.left,
            style: const TextStyle(
                color: Colors.white70,
                fontWeight: FontWeight.bold,
                fontSize: 14,
                letterSpacing: 0.8)),
      );
}

// ── Bracket canvas ─────────────────────────────────────────────────────────
class _BracketCanvas extends StatelessWidget {
  final List<List<BracketMatch>> rounds;
  final void Function(BracketMatch) onMatchTap;
  final double matchW, matchH, gapW, gapH;

  const _BracketCanvas({
    required this.rounds,
    required this.onMatchTap,
    this.matchW = 220,
    this.matchH = 70,
    this.gapW = 48,
    this.gapH = 14,
  });

  @override
  Widget build(BuildContext context) {
    final totalH = rounds[0].length * (matchH + gapH) - gapH;
    final totalW = rounds.length * (matchW + gapW) - gapW;
    return SizedBox(
      width: totalW,
      height: totalH,
      child: Stack(children: [
        CustomPaint(
          size: Size(totalW, totalH),
          painter: _BracketLinePainter(
              rounds: rounds, matchW: matchW, matchH: matchH, gapH: gapH, gapW: gapW),
        ),
        for (int r = 0; r < rounds.length; r++)
          for (int m = 0; m < rounds[r].length; m++) _positionedCard(r, m, totalH),
      ]),
    );
  }

  Offset _offset(int round, int matchIdx, double totalH) {
    final slotH = totalH / rounds[round].length;
    return Offset(round * (matchW + gapW), (matchIdx + 0.5) * slotH - matchH / 2);
  }

  String _roundLabel(int roundIdx) {
    final totalRounds = rounds.length;
    if (roundIdx == totalRounds - 1) return 'FINAL';
    if (roundIdx == totalRounds - 2) return 'SEMI-FINAL';
    if (roundIdx == totalRounds - 3) return 'QUARTER-FINAL';
    return 'ROUND ${roundIdx + 1}';
  }

  Color _roundColor(int roundIdx) {
    final totalRounds = rounds.length;
    if (roundIdx == totalRounds - 1) return const Color(0xFFFFD700);
    if (roundIdx == totalRounds - 2) return const Color(0xFF00FF88);
    if (roundIdx == totalRounds - 3) return const Color(0xFF00CFFF);
    return const Color(0xFF7B6AAA);
  }

  Widget _positionedCard(int r, int m, double totalH) {
    final off = _offset(r, m, totalH);
    final match = rounds[r][m];
    final label = _roundLabel(r);
    final color = _roundColor(r);
    const double footerH = 22;

    return Positioned(
      left: off.dx,
      top: off.dy,
      width: matchW,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _MatchCard(match: match, onTap: () => onMatchTap(match), cardH: matchH),
          const SizedBox(height: 4),
          Container(
            height: footerH,
            width: matchW,
            decoration: BoxDecoration(
              color: color.withOpacity(0.08),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: color.withOpacity(0.3), width: 1),
            ),
            alignment: Alignment.center,
            child: Text(label,
                style: TextStyle(
                    color: color,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.4)),
          ),
        ],
      ),
    );
  }
}

// ── Line painter ──────────────────────────────────────────────────────────
class _BracketLinePainter extends CustomPainter {
  final List<List<BracketMatch>> rounds;
  final double matchW, matchH, gapH, gapW;

  const _BracketLinePainter({
    required this.rounds,
    required this.matchW,
    required this.matchH,
    required this.gapH,
    required this.gapW,
  });

  Offset _rightMid(int r, int m, double h) {
    final slotH = h / rounds[r].length;
    return Offset(r * (matchW + gapW) + matchW, (m + 0.5) * slotH);
  }

  Offset _leftMid(int r, int m, double h) {
    final slotH = h / rounds[r].length;
    return Offset(r * (matchW + gapW), (m + 0.5) * slotH);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final paintLine = Paint()
      ..color = const Color(0xFF2E1860)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    final paintWin = Paint()
      ..color = const Color(0xFF00FF88).withOpacity(0.35)
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke;

    for (int r = 0; r < rounds.length - 1; r++) {
      for (int m = 0; m < rounds[r].length; m += 2) {
        if (m + 1 >= rounds[r].length) continue;
        final top = _rightMid(r, m, size.height);
        final bot = _rightMid(r, m + 1, size.height);
        final midX = top.dx + gapW / 2;
        final midY = (top.dy + bot.dy) / 2;
        final nextM = m ~/ 2;
        if (nextM >= rounds[r + 1].length) continue;
        final nextIn = _leftMid(r + 1, nextM, size.height);

        final hasWinner1 =
            rounds[r][m].winner != null && !rounds[r][m].winner!.isBye;
        final hasWinner2 =
            rounds[r][m + 1].winner != null && !rounds[r][m + 1].winner!.isBye;

        final path = Path()
          ..moveTo(top.dx, top.dy)
          ..lineTo(midX, top.dy)
          ..lineTo(midX, bot.dy)
          ..lineTo(bot.dx, bot.dy);
        canvas.drawPath(path, paintLine);
        canvas.drawLine(Offset(midX, midY), Offset(nextIn.dx, midY),
            (hasWinner1 || hasWinner2) ? paintWin : paintLine);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => true;
}

// ── Match card ────────────────────────────────────────────────────────────
class _MatchCard extends StatelessWidget {
  final BracketMatch match;
  final VoidCallback onTap;
  final double cardH;

  const _MatchCard({required this.match, required this.onTap, this.cardH = 78.0});

  @override
  Widget build(BuildContext context) {
    final bool t1Real = !match.team1.isBye && match.team1.teamName != 'TBD';
    final bool t2Real = !match.team2.isBye && match.team2.teamName != 'TBD';
    final bool bothReal = t1Real && t2Real;
    final bool canPlay = match.winner == null && (t1Real || t2Real);
    final bool hasWinner = match.winner != null;
    final bool t1Wins = hasWinner && match.winner!.teamId == match.team1.teamId;
    final bool t2Wins = hasWinner && match.winner!.teamId == match.team2.teamId;

    Color borderCol;
    Color glowCol;
    double glowBlur;
    if (hasWinner) {
      borderCol = const Color(0xFF00FF88).withOpacity(0.5);
      glowCol = const Color(0xFF00FF88).withOpacity(0.15);
      glowBlur = 12;
    } else if (canPlay) {
      borderCol = const Color(0xFF5B2CC0);
      glowCol = const Color(0xFF5B2CC0).withOpacity(0.2);
      glowBlur = 8;
    } else {
      borderCol = const Color(0xFF1C1045);
      glowCol = Colors.transparent;
      glowBlur = 0;
    }

    const double kBorder = 1.5;
    final double inner = cardH - kBorder * 2;
    const double kVsW = 36.0;
    final double fs = (cardH * 0.18).clamp(10.0, 22.0);

    return GestureDetector(
      onTap: canPlay || hasWinner ? onTap : null,
      child: Container(
        height: cardH,
        decoration: BoxDecoration(
          color: hasWinner ? const Color(0xFF091910) : const Color(0xFF120A32),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: borderCol, width: kBorder),
          boxShadow: [
            BoxShadow(color: glowCol, blurRadius: glowBlur),
            BoxShadow(
                color: Colors.black.withOpacity(0.45),
                blurRadius: 5,
                offset: const Offset(0, 2)),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(9),
          child: SizedBox(
            height: inner,
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Expanded(
                  child: _teamCell(
                      name: match.team1.teamName,
                      isBye: match.team1.isBye,
                      isWinner: t1Wins,
                      isDim: hasWinner && !t1Wins,
                      align: CrossAxisAlignment.end,
                      fontSize: fs)),
              SizedBox(width: kVsW, child: _vsCell(bothReal, hasWinner, fs)),
              Expanded(
                  child: _teamCell(
                      name: match.team2.teamName,
                      isBye: match.team2.isBye,
                      isWinner: t2Wins,
                      isDim: hasWinner && !t2Wins,
                      align: CrossAxisAlignment.start,
                      fontSize: fs)),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _teamCell({
    required String name,
    required bool isBye,
    required bool isWinner,
    required bool isDim,
    required CrossAxisAlignment align,
    required double fontSize,
  }) {
    final bool isPlaceholder = name == 'TBD' || isBye;
    Color bg, textCol;
    if (isWinner) {
      bg = const Color(0xFF00FF88).withOpacity(0.09);
      textCol = const Color(0xFF00FF88);
    } else if (isDim) {
      bg = Colors.transparent;
      textCol = const Color(0xFF2A1C4A);
    } else if (isPlaceholder) {
      bg = Colors.transparent;
      textCol = const Color(0xFF22163A);
    } else {
      bg = Colors.transparent;
      textCol = Colors.white.withOpacity(0.9);
    }

    return Container(
      color: bg,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: align,
        children: [
          if (isWinner)
            Icon(Icons.emoji_events, color: const Color(0xFFFFD700),
                size: (fontSize * 0.9).clamp(10.0, 14.0)),
          Text(name,
              textAlign:
                  align == CrossAxisAlignment.end ? TextAlign.right : TextAlign.left,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  color: textCol,
                  fontSize: fontSize,
                  fontWeight: isWinner ? FontWeight.bold : FontWeight.w600,
                  height: 1.2)),
        ],
      ),
    );
  }

  Widget _vsCell(bool bothReal, bool hasWinner, double fs) {
    final bool glowing = bothReal && !hasWinner;
    return Container(
      color: const Color(0xFF0A0520),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Container(width: 1, height: 6, color: Colors.white.withOpacity(0.06)),
        const SizedBox(height: 3),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
          decoration: BoxDecoration(
            gradient: glowing
                ? const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF9B55F0), Color(0xFF5318B0)])
                : null,
            color: glowing ? null : const Color(0xFF0E0628),
            borderRadius: BorderRadius.circular(5),
            border: Border.all(
                color: glowing
                    ? const Color(0xFFBB88FF).withOpacity(0.45)
                    : Colors.white.withOpacity(0.05)),
            boxShadow: glowing
                ? [
                    BoxShadow(
                        color: const Color(0xFF8844EE).withOpacity(0.55),
                        blurRadius: 12,
                        spreadRadius: 1)
                  ]
                : [],
          ),
          child: Text('VS',
              style: TextStyle(
                  color: glowing ? Colors.white : Colors.white.withOpacity(0.08),
                  fontSize: (fs * 0.85).clamp(10.0, 14.0),
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.8,
                  fontStyle: FontStyle.italic)),
        ),
        const SizedBox(height: 3),
        Container(width: 1, height: 6, color: Colors.white.withOpacity(0.06)),
      ]),
    );
  }
}

// ── Pulsing dot ───────────────────────────────────────────────────────────
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
        vsync: this, duration: const Duration(milliseconds: 900))
      ..repeat(reverse: true);
    _anim = Tween(begin: 0.25, end: 1.0)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
        opacity: _anim,
        child: Container(
            width: 8,
            height: 8,
            decoration: const BoxDecoration(
                color: Color(0xFF00FF88), shape: BoxShape.circle)),
      );
}