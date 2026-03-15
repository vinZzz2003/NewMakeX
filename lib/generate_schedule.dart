import 'package:flutter/material.dart';
import 'dart:math';
import 'db_helper.dart';
import 'registration_shared.dart';
import 'schedule_fairness_helper.dart';
import 'config.dart';

class GenerateSchedule extends StatefulWidget {
  final VoidCallback? onBack;
  final VoidCallback? onGenerated;

  const GenerateSchedule({
    super.key,
    this.onBack,
    this.onGenerated,
  });

  @override
  State<GenerateSchedule> createState() => _GenerateScheduleState();
}

class _GenerateScheduleState extends State<GenerateSchedule> {
  static const _accent = Color(0xFF00CFFF);

  final Map<int, int> _runsPerCategory      = {}; // matches per team
  final Map<int, int> _arenasPerCategory    = {};
  final Map<int, int> _teamCountPerCategory = {};

  List<Map<String, dynamic>> _categories = [];
  bool _isLoadingData = true;

  TimeOfDay _startTime = const TimeOfDay(hour: 9,  minute: 0);
  TimeOfDay _endTime   = const TimeOfDay(hour: 17, minute: 0);
  final _durationController = TextEditingController(text: '2'); // Default 2 minutes
  final _intervalController = TextEditingController(text: '1'); // Default 1 minute

  bool _lunchBreakEnabled = true;
  bool _isGenerating      = false;

  static int get _maxTeamsPerArena => Config.maxTeamsPerArena;

  @override
  void initState() {
    super.initState();
    _loadCategories();
    _durationController.addListener(() => setState(() {}));
    _intervalController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _durationController.dispose();
    _intervalController.dispose();
    super.dispose();
  }

  Future<void> _loadCategories() async {
    try {
      // FIX: Change getCategories() to getCategories() (with an 's')
      final cats = await DBHelper.getCategories();
      final seen = <int>{};
      final unique = cats.where((c) {
        final id = int.tryParse(c['category_id'].toString()) ?? 0;
        return id > 0 && seen.add(id);
      }).toList();

      final Map<int, int> teamCounts = {};
      for (final c in unique) {
        final id    = int.tryParse(c['category_id'].toString()) ?? 0;
        final teams = await DBHelper.getTeamsByCategory(id);
        teamCounts[id] = teams.length;
      }

      setState(() {
        _categories = unique;
        for (final c in unique) {
          final id    = int.tryParse(c['category_id'].toString()) ?? 0;
          final count = teamCounts[id] ?? 0;
          // Default to 4 matches per team
          _runsPerCategory[id]      = 4;
          _arenasPerCategory[id]    = count == 0 ? 1 : (count / _maxTeamsPerArena).ceil();
          _teamCountPerCategory[id] = count;
        }
        _isLoadingData = false;
      });
    } catch (e) {
      setState(() => _isLoadingData = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('❌ Failed to load categories: $e'),
              backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _generateSchedule() async {
    final duration = int.tryParse(_durationController.text.trim()) ?? 2;
    final interval = int.tryParse(_intervalController.text.trim()) ?? 1;

    if (duration <= 0) { 
      _snack('❌ Duration must be greater than 0.', Colors.red); 
      return; 
    }

    final startMin = _startTime.hour * 60 + _startTime.minute;
    final endMin   = _endTime.hour   * 60 + _endTime.minute;
    if (endMin <= startMin) { 
      _snack('❌ End time must be after start time.', Colors.red); 
      return; 
    }
    if (_hasArenaError) { 
      _snack('❌ Some categories exceed arena capacity.', Colors.red); 
      return; 
    }

    final confirmed = await _showConfirmDialog();
    if (confirmed != true) return;

    setState(() => _isGenerating = true);
    try {
      final st = '${_startTime.hour.toString().padLeft(2, '0')}:${_startTime.minute.toString().padLeft(2, '0')}';
      final et = '${_endTime.hour.toString().padLeft(2, '0')}:${_endTime.minute.toString().padLeft(2, '0')}';

      await _generateFairSchedule(
        startTime: st,
        endTime: et,
        durationMinutes: duration,
        intervalMinutes: interval,
        lunchBreak: _lunchBreakEnabled,
      );
      
      if (mounted) {
        _snack('✅ Schedule generated successfully!', Colors.green);
        widget.onGenerated?.call();
      }
    } catch (e) {
      if (mounted) _snack('❌ Error: $e', Colors.red);
    } finally {
      if (mounted) setState(() => _isGenerating = false);
    }
  }

  Future<void> _generateFairSchedule({
    required String startTime,
    required String endTime,
    required int durationMinutes,
    required int intervalMinutes,
    bool lunchBreak = true,
  }) async {
    final conn = await DBHelper.getConnection();

    // Clear old schedule
    await DBHelper.clearSchedule();

    // ── Store the matches per team setting in a new table ──
    // First, create a table to store category settings if it doesn't exist
    try {
      await conn.execute("""
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
    for (final entry in _runsPerCategory.entries) {
      final categoryId = entry.key;
      final matchesPerTeam = entry.value;
      
      await conn.execute("""
        INSERT INTO tbl_category_settings (category_id, matches_per_team)
        VALUES (:catId, :matches)
        ON DUPLICATE KEY UPDATE matches_per_team = :matches
      """, {
        "catId": categoryId,
        "matches": matchesPerTeam,
      });
      print("📊 Stored matches per team for category $categoryId: $matchesPerTeam");
    }

    // Get first available referee
    final refResult = await conn.execute(
      "SELECT referee_id FROM tbl_referee ORDER BY referee_id LIMIT 1"
    );
    if (refResult.rows.isEmpty) {
      throw Exception('No referees found. Please add at least one referee.');
    }
    final defaultRefereeId = int.parse(
      refResult.rows.first.assoc()['referee_id'] ?? '0',
    );

    // Parse times
    final startParts = startTime.split(':');
    int currentHour = int.parse(startParts[0]);
    int currentMinute = int.parse(startParts[1]);

    final endParts = endTime.split(':');
    final endLimitMinutes = int.parse(endParts[0]) * 60 + int.parse(endParts[1]);

    bool hasTimeRemaining() {
      final currentMinutes = currentHour * 60 + currentMinute;
      return currentMinutes + durationMinutes <= endLimitMinutes;
    }

    void advanceTime(int minutes) {
      currentMinute += minutes;
      while (currentMinute >= 60) {
        currentMinute -= 60;
        currentHour++;
      }
      if (lunchBreak && currentHour == 12 && currentMinute >= 0) {
        currentHour = 13;
        currentMinute = 0;
      }
    }

    // Process each category
    for (final entry in _runsPerCategory.entries) {
      final categoryId = entry.key;
      final matchesPerTeam = entry.value;
      
      final teams = await DBHelper.getTeamsByCategory(categoryId);
      if (teams.isEmpty) continue;

      final teamCount = teams.length;
      
      // Calculate total matches needed
      final totalMatches = (teamCount * matchesPerTeam) ~/ 4;
      
      print("\n=== SCHEDULING CATEGORY $categoryId ===");
      print("Teams: $teamCount, Matches per team: $matchesPerTeam");
      print("Total matches needed: $totalMatches");
      print("This means $matchesPerTeam rounds (each team plays once per round)");

      // Create team map for lookup
      final Map<int, Map<String, dynamic>> teamMap = {};
      for (final team in teams) {
        final teamId = int.parse(team['team_id'].toString());
        teamMap[teamId] = team;
      }

      // Initialize fairness tracker
      final tracker = FairnessTracker(categoryId, matchesPerTeam, teams);
      
      // Generate matches using round-robin style with fairness constraints
      final matches = _generateFairMatchesRoundRobin(
        teamIds: teamMap.keys.toList(),
        matchesPerTeam: matchesPerTeam,
        tracker: tracker,
      );

      print("Generated ${matches.length} fair matches (should be $totalMatches)");

      // Group matches by round
      final Map<int, List<Map<String, dynamic>>> matchesByRound = {};
      
      // Calculate matches per round
      final matchesPerRound = teamCount ~/ 4; // How many simultaneous matches per round
      
      for (int i = 0; i < matches.length; i++) {
        // Calculate which round this match belongs to
        // Each round has matchesPerRound matches
        final round = (i ~/ matchesPerRound) + 1;
        
        if (!matchesByRound.containsKey(round)) {
          matchesByRound[round] = [];
        }
        matchesByRound[round]!.add(matches[i]);
      }
      
      print("Grouped into ${matchesByRound.length} rounds");

      // Schedule each round
      for (int round = 1; round <= matchesPerTeam; round++) {
        final roundMatches = matchesByRound[round] ?? [];
        
        if (roundMatches.isEmpty) {
          print("⚠️ No matches for round $round");
          continue;
        }
        
        print("\n--- Scheduling Round $round with ${roundMatches.length} matches ---");
        
        for (final match in roundMatches) {
          if (!hasTimeRemaining()) {
            print("⚠️ End time reached - stopping scheduling");
            break;
          }

          final redTeamIds = match['red'] as List<int>;
          final blueTeamIds = match['blue'] as List<int>;

          // Format times
          final startHH = currentHour.toString().padLeft(2, '0');
          final startMM = currentMinute.toString().padLeft(2, '0');
          final startStr = '$startHH:$startMM:00';

          int endHour = currentHour;
          int endMinute = currentMinute + durationMinutes;
          while (endMinute >= 60) {
            endMinute -= 60;
            endHour++;
          }
          final endStr = '${endHour.toString().padLeft(2, '0')}:${endMinute.toString().padLeft(2, '0')}:00';

          // Insert schedule and match
          final scheduleId = await DBHelper.insertSchedule(
            startTime: startStr, 
            endTime: endStr
          );
          final matchId = await DBHelper.insertMatch(scheduleId);

          // Insert RED teams
          for (final teamId in redTeamIds) {
            await DBHelper.insertTeamSchedule(
              matchId: matchId,
              roundId: round, // Use the correct round number
              teamId: teamId,
              refereeId: defaultRefereeId,
              arenaNumber: 1,
            );
          }

          // Insert BLUE teams
          for (final teamId in blueTeamIds) {
            await DBHelper.insertTeamSchedule(
              matchId: matchId,
              roundId: round, // Use the correct round number
              teamId: teamId,
              refereeId: defaultRefereeId,
              arenaNumber: 2,
            );
          }

          // Print match info
          final redNames = redTeamIds.map((id) => teamMap[id]!['team_name']).join(', ');
          final blueNames = blueTeamIds.map((id) => teamMap[id]!['team_name']).join(', ');
          print("Match: RED: [$redNames] vs BLUE: [$blueNames] at $startStr (Round $round)");

          advanceTime(durationMinutes + intervalMinutes);
        }
      }

      tracker.verifyFairness();
    }

    await DBHelper.verifyScheduleFairness();
  }

  List<Map<String, dynamic>> _generateFairMatchesRoundRobin({
  required List<int> teamIds,
  required int matchesPerTeam,
  required FairnessTracker tracker,
}) {
  final random = Random();
  final matches = <Map<String, dynamic>>[];
  final teamCount = teamIds.length;
  
  // Calculate total matches needed
  final totalMatches = (teamCount * matchesPerTeam) ~/ 4;
  
  // Track appearances per team
  final appearances = <int, int>{};
  for (final teamId in teamIds) {
    appearances[teamId] = 0;
  }
  
  print("\n=== GENERATING FAIR MATCHES ===");
  print("Teams: $teamCount, Matches per team: $matchesPerTeam");
  print("Total matches needed: $totalMatches");
  
  // Simple approach: Create matches round by round
  for (int round = 1; round <= matchesPerTeam; round++) {
    print("\n--- Round $round ---");
    
    // Get teams that haven't played this round yet
    List<int> availableTeams = [];
    for (final teamId in teamIds) {
      // Check if team has already played this round by looking at matches
      bool playedThisRound = false;
      for (final match in matches) {
        if ((match['red'] as List<int>).contains(teamId) || 
            (match['blue'] as List<int>).contains(teamId)) {
          if (matches.indexOf(match) ~/ (teamCount ~/ 4) + 1 == round) {
            playedThisRound = true;
            break;
          }
        }
      }
      if (!playedThisRound && appearances[teamId]! < matchesPerTeam) {
        availableTeams.add(teamId);
      }
    }
    
    availableTeams.shuffle(random);
    print("Available teams for round $round: $availableTeams");
    
    // Create as many matches as possible in this round
    int matchesInThisRound = 0;
    while (availableTeams.length >= 4 && matchesInThisRound < (teamCount ~/ 4)) {
      // Take first 4 teams
      final matchTeams = availableTeams.sublist(0, 4);
      availableTeams.removeRange(0, 4);
      
      // Simple split: first 2 are RED, last 2 are BLUE
      final redIds = [matchTeams[0], matchTeams[1]];
      final blueIds = [matchTeams[2], matchTeams[3]];
      
      // Record the match
      matches.add({
        'red': List<int>.from(redIds),
        'blue': List<int>.from(blueIds),
      });
      
      // Update appearances
      for (final teamId in redIds) {
        appearances[teamId] = appearances[teamId]! + 1;
      }
      for (final teamId in blueIds) {
        appearances[teamId] = appearances[teamId]! + 1;
      }
      
      matchesInThisRound++;
      print("Match ${matches.length}: RED ${redIds.join(',')} vs BLUE ${blueIds.join(',')}");
    }
    
    print("Created $matchesInThisRound matches in round $round");
  }
  
  print("\n=== MATCH GENERATION COMPLETE ===");
  print("Generated ${matches.length}/$totalMatches matches");
  
  return matches;
}

  // Helper method to add remaining matches if needed
  void _addRemainingMatches(
    List<Map<String, dynamic>> matches,
    List<int> teamIds,
    int matchesPerTeam,
    int totalMatches,
    FairnessTracker tracker,
    Map<int, Set<int>> teamsNeedingRound,
  ) {
    print("\n=== ADDING REMAINING MATCHES (with relaxed constraints) ===");
    final random = Random();
    
    // Track appearances per team
    final appearances = <int, int>{};
    for (final teamId in teamIds) {
      appearances[teamId] = 0;
    }
    
    // Count current appearances
    for (final match in matches) {
      for (final teamId in match['red'] as List<int>) {
        appearances[teamId] = (appearances[teamId] ?? 0) + 1;
      }
      for (final teamId in match['blue'] as List<int>) {
        appearances[teamId] = (appearances[teamId] ?? 0) + 1;
      }
    }
    
    int round = matchesPerTeam;
    while (matches.length < totalMatches) {
      // Find teams that need more appearances
      final neededTeams = <int>[];
      for (final teamId in teamIds) {
        if ((appearances[teamId] ?? 0) < matchesPerTeam) {
          neededTeams.add(teamId);
        }
      }
      
      if (neededTeams.length < 4) break;
      
      neededTeams.shuffle(random);
      final matchTeams = neededTeams.take(4).toList();
      
      // Try to split fairly
      final redIds = <int>[matchTeams[0], matchTeams[1]];
      final blueIds = <int>[matchTeams[2], matchTeams[3]];
      
      // Record the match
      matches.add({
        'red': redIds,
        'blue': blueIds,
      });
      
      // Update appearances
      for (final teamId in redIds) {
        appearances[teamId] = (appearances[teamId] ?? 0) + 1;
      }
      for (final teamId in blueIds) {
        appearances[teamId] = (appearances[teamId] ?? 0) + 1;
      }
      
      print("Added match ${matches.length}: RED ${redIds.join(',')} vs BLUE ${blueIds.join(',')}");
    }
  }

  String? _arenaWarning(int categoryId) {
    final teams    = _teamCountPerCategory[categoryId] ?? 0;
    final arenas   = _arenasPerCategory[categoryId]    ?? 1;
    if (teams == 0) return null;
    if (teams > arenas * _maxTeamsPerArena) {
      return '$teams teams — needs ≥${(teams / _maxTeamsPerArena).ceil()} arenas';
    }
    return null;
  }

  bool get _hasArenaError {
    for (final cat in _categories) {
      final id = int.tryParse(cat['category_id'].toString()) ?? 0;
      if (_arenaWarning(id) != null) return true;
    }
    return false;
  }

  Future<bool?> _showConfirmDialog() {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          width: 400,
          padding: const EdgeInsets.all(28),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft, end: Alignment.bottomRight,
              colors: [Color(0xFF2D0E7A), Color(0xFF1E0A5A)],
            ),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
                color: Colors.orange.withOpacity(0.4), width: 1.5),
            boxShadow: [
              BoxShadow(color: Colors.orange.withOpacity(0.1),
                  blurRadius: 30, spreadRadius: 4),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 56, height: 56,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.orange.withOpacity(0.15),
                  border: Border.all(color: Colors.orange.withOpacity(0.4)),
                ),
                child: const Icon(Icons.warning_amber_rounded,
                    color: Colors.orange, size: 30),
              ),
              const SizedBox(height: 16),
              const Text('Generate Schedule?',
                  style: TextStyle(color: Colors.white, fontSize: 18,
                      fontWeight: FontWeight.w800)),
              const SizedBox(height: 10),
              Text(
                'This will DELETE the existing schedule\nand generate a new one with fair match allocation.',
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: Colors.white.withOpacity(0.6), fontSize: 13, height: 1.5),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(ctx).pop(false),
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: Colors.white.withOpacity(0.2)),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                      ),
                      child: Text('CANCEL',
                          style: TextStyle(
                              color: Colors.white.withOpacity(0.5),
                              fontWeight: FontWeight.bold)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => Navigator.of(ctx).pop(true),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.transparent,
                        shadowColor: Colors.transparent,
                        padding: EdgeInsets.zero,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                      ),
                      child: Ink(
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                              colors: [Color(0xFF00CFFF), Color(0xFF0099CC)]),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Padding(
                          padding: EdgeInsets.symmetric(vertical: 14),
                          child: Center(
                            child: Text('GENERATE',
                                style: TextStyle(color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 1)),
                          ),
                        ),
                      ),
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

  void _snack(String msg, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: color));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1A0A4A),
      body: Column(
        children: [
          const RegistrationHeader(),
          Expanded(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Container(
                  width: 820,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft, end: Alignment.bottomRight,
                      colors: [Color(0xFF2D0E7A), Color(0xFF1E0A5A)],
                    ),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                        color: _accent.withOpacity(0.3), width: 1.5),
                    boxShadow: [
                      BoxShadow(color: _accent.withOpacity(0.08),
                          blurRadius: 40, spreadRadius: 4),
                      BoxShadow(color: Colors.black.withOpacity(0.4),
                          blurRadius: 30, offset: const Offset(0, 10)),
                    ],
                  ),
                  child: Stack(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(40, 36, 40, 36),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // Title
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: _accent.withOpacity(0.1),
                                    border: Border.all(
                                        color: _accent.withOpacity(0.3)),
                                  ),
                                  child: const Icon(Icons.calendar_month_rounded,
                                      color: _accent, size: 22),
                                ),
                                const SizedBox(width: 14),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text('GENERATE SCHEDULE',
                                        style: TextStyle(color: Colors.white,
                                            fontSize: 20,
                                            fontWeight: FontWeight.w800,
                                            letterSpacing: 2)),
                                    Text('Fair match allocation with balanced alliances',
                                        style: TextStyle(
                                            color: Colors.white.withOpacity(0.4),
                                            fontSize: 12)),
                                  ],
                                ),
                              ],
                            ),
                            const SizedBox(height: 28),
                            buildDivider(_accent),
                            const SizedBox(height: 28),

                            // Two columns
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(child: _buildCategoryColumn()),
                                const SizedBox(width: 28),
                                SizedBox(width: 240,
                                    child: _buildScheduleColumn()),
                              ],
                            ),
                            const SizedBox(height: 32),
                            buildDivider(_accent),
                            const SizedBox(height: 28),

                            // Fairness preview
                            _buildFairnessPreview(),
                            const SizedBox(height: 20),

                            // Generate button
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton(
                                onPressed: _isGenerating ? null : _generateSchedule,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.transparent,
                                  shadowColor: Colors.transparent,
                                  padding: EdgeInsets.zero,
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12)),
                                ),
                                child: Ink(
                                  decoration: BoxDecoration(
                                    gradient: const LinearGradient(
                                        colors: [Color(0xFF00CFFF), Color(0xFF0099CC)]),
                                    borderRadius: BorderRadius.circular(12),
                                    boxShadow: [
                                      BoxShadow(
                                          color: _accent.withOpacity(0.4),
                                          blurRadius: 20, spreadRadius: 2),
                                    ],
                                  ),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(vertical: 18),
                                    alignment: Alignment.center,
                                    child: _isGenerating
                                        ? const SizedBox(width: 22, height: 22,
                                            child: CircularProgressIndicator(
                                                strokeWidth: 2, color: Colors.white))
                                        : const Row(
                                            mainAxisAlignment: MainAxisAlignment.center,
                                            children: [
                                              Icon(Icons.auto_awesome_rounded,
                                                  color: Colors.white, size: 20),
                                              SizedBox(width: 10),
                                              Text('GENERATE FAIR SCHEDULE',
                                                  style: TextStyle(
                                                    color: Colors.white,
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: 15,
                                                    letterSpacing: 2,
                                                  )),
                                            ],
                                          ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                      // Back button
                      Positioned(top: 12, left: 12,
                        child: IconButton(
                          icon: const Icon(Icons.arrow_back_ios_new,
                              color: _accent, size: 18),
                          onPressed: widget.onBack),
                      ),

                      // Close button
                      Positioned(top: 12, right: 12,
                        child: IconButton(
                          icon: Icon(Icons.close,
                              color: Colors.white.withOpacity(0.35), size: 20),
                          onPressed: () => Navigator.of(context).maybePop()),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFairnessPreview() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF00E5A0).withOpacity(0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF00E5A0).withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.balance_rounded, 
                  color: Color(0xFF00E5A0), size: 18),
              const SizedBox(width: 8),
              const Text('FAIRNESS CONSTRAINTS',
                  style: TextStyle(color: Color(0xFF00E5A0),
                      fontWeight: FontWeight.bold, fontSize: 12,
                      letterSpacing: 1)),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _constraintChip(
                  '✓ Balanced Alliances',
                  'Every team gets equal RED/BLUE matches',
                  Icons.sports_mma,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _constraintChip(
                  '✓ Unique Teams',
                  '4 unique teams per match',
                  Icons.groups,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _constraintChip(
                  '✓ Fair Partners',
                  'Minimize repeated teammates',
                  Icons.people,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _constraintChip(
                  '✓ Fair Opponents',
                  'Minimize repeated opponents',
                  Icons.sports_kabaddi,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _constraintChip(String title, String subtitle, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFF00E5A0).withOpacity(0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF00E5A0).withOpacity(0.15)),
      ),
      child: Row(
        children: [
          Icon(icon, color: const Color(0xFF00E5A0), size: 14),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 11)),
                Text(subtitle,
                    style: TextStyle(
                        color: Colors.white.withOpacity(0.5),
                        fontSize: 9)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryColumn() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          const Expanded(
            child: Text('CATEGORY',
                style: TextStyle(color: _accent, fontWeight: FontWeight.w800,
                    fontSize: 11, letterSpacing: 1.5)),
          ),
          SizedBox(width: 90,
            child: Center(child: Text('MATCHES',
                style: TextStyle(color: _accent.withOpacity(0.8),
                    fontWeight: FontWeight.w800, fontSize: 11, letterSpacing: 1.5))),
          ),
          const SizedBox(width: 10),
          SizedBox(width: 90,
            child: Column(children: [
              Center(child: Text('ARENAS',
                  style: TextStyle(color: _accent.withOpacity(0.8),
                      fontWeight: FontWeight.w800, fontSize: 11, letterSpacing: 1.5))),
              Center(child: Text('max $_maxTeamsPerArena teams',
                  style: TextStyle(fontSize: 9,
                      color: Colors.white.withOpacity(0.3),
                      fontStyle: FontStyle.italic))),
            ])),
        ]),
        const SizedBox(height: 4),
        Container(height: 1, color: _accent.withOpacity(0.15)),
        const SizedBox(height: 14),

        _isLoadingData
            ? const Center(child: CircularProgressIndicator(
                strokeWidth: 2, color: _accent))
            : Column(
                children: _categories.map((c) {
                  final id      = int.tryParse(c['category_id'].toString()) ?? 0;
                  final name    = (c['category_type'] ?? '').toString();
                  final count   = _teamCountPerCategory[id] ?? 0;
                  final warning = _arenaWarning(id);

                  return Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.04),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: warning != null
                            ? Colors.orange.withOpacity(0.4)
                            : _accent.withOpacity(0.15),
                      ),
                    ),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(name.toUpperCase(),
                                      style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 13)),
                                  const SizedBox(height: 3),
                                  Row(children: [
                                    Icon(
                                      count == 0
                                          ? Icons.warning_amber_rounded
                                          : Icons.groups_rounded,
                                      size: 12,
                                      color: count == 0
                                          ? Colors.orange
                                          : Colors.white38,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      '$count team${count != 1 ? 's' : ''} registered',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: count == 0
                                            ? Colors.orange
                                            : Colors.white38,
                                      ),
                                    ),
                                  ]),
                                ],
                              ),
                            ),
                            // Matches spinner
                            SizedBox(
                              width: 90,
                              child: Center(
                                child: _buildSpinner(id, isRuns: true),
                              ),
                            ),
                            const SizedBox(width: 10),
                            SizedBox(width: 90,
                                child: Center(
                                    child: _buildSpinner(id, isRuns: false))),
                          ],
                        ),

                        if (warning != null) ...[
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: Colors.orange.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                  color: Colors.orange.withOpacity(0.3)),
                            ),
                            child: Row(children: [
                              const Icon(Icons.warning_amber_rounded,
                                  size: 12, color: Colors.orange),
                              const SizedBox(width: 6),
                              Text(warning,
                                  style: const TextStyle(
                                      fontSize: 10, color: Colors.orange)),
                            ]),
                          ),
                        ] else if (count > 0) ...[
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: const Color(0xFF00E5A0).withOpacity(0.08),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                  color: const Color(0xFF00E5A0)
                                      .withOpacity(0.25)),
                            ),
                            child: Row(children: [
                              const Icon(Icons.check_circle_outline_rounded,
                                  size: 12, color: Color(0xFF00E5A0)),
                              const SizedBox(width: 6),
                              Text(
                                'Capacity: ${(_arenasPerCategory[id] ?? 1) * _maxTeamsPerArena} teams',
                                style: const TextStyle(
                                    fontSize: 10, color: Color(0xFF00E5A0)),
                              ),
                            ]),
                          ),
                        ],
                      ],
                    ),
                  );
                }).toList(),
              ),
      ],
    );
  }

  Widget _buildScheduleColumn() {
    final timeError = (_endTime.hour * 60 + _endTime.minute) <=
        (_startTime.hour * 60 + _startTime.minute);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('SCHEDULE SETTINGS',
            style: TextStyle(color: _accent.withOpacity(0.9),
                fontWeight: FontWeight.w800, fontSize: 11, letterSpacing: 1.5)),
        const SizedBox(height: 4),
        Container(height: 1, color: _accent.withOpacity(0.15)),
        const SizedBox(height: 16),

        _timeTile(label: 'START TIME', time: _startTime, isStart: true),
        const SizedBox(height: 10),
        _timeTile(label: 'END TIME', time: _endTime, isStart: false),

        if (timeError) ...[
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.red.withOpacity(0.1),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: Colors.red.withOpacity(0.3)),
            ),
            child: const Row(children: [
              Icon(Icons.error_outline_rounded, size: 12, color: Colors.red),
              SizedBox(width: 6),
              Text('End must be after start',
                  style: TextStyle(fontSize: 10, color: Colors.red)),
            ]),
          ),
        ],

        const SizedBox(height: 16),

        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: _buildNumberField(
              label: 'DURATION',
              subtitle: 'min / match',
              controller: _durationController,
            )),
            const SizedBox(width: 12),
            Expanded(child: _buildNumberField(
              label: 'BREAK',
              subtitle: 'min between',
              controller: _intervalController,
            )),
          ],
        ),
        const SizedBox(height: 12),

        _buildTimingPreview(),
        const SizedBox(height: 16),

        Container(height: 1, color: Colors.white.withOpacity(0.08)),
        const SizedBox(height: 14),

        _buildLunchToggle(),
      ],
    );
  }

  Widget _timeTile({
    required String label,
    required TimeOfDay time,
    required bool isStart,
  }) {
    return GestureDetector(
      onTap: () => _pickTime(isStart),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.05),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: _accent.withOpacity(0.25)),
        ),
        child: Row(children: [
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _accent.withOpacity(0.1),
            ),
            child: const Icon(Icons.access_time_rounded,
                size: 14, color: _accent),
          ),
          const SizedBox(width: 10),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label,
                style: TextStyle(fontSize: 9,
                    color: Colors.white.withOpacity(0.4),
                    fontWeight: FontWeight.bold, letterSpacing: 0.5)),
            Text(_fmtTime(time),
                style: const TextStyle(fontSize: 16,
                    fontWeight: FontWeight.bold, color: Colors.white)),
          ]),
          const Spacer(),
          Icon(Icons.edit_rounded, size: 14, color: Colors.white.withOpacity(0.3)),
        ]),
      ),
    );
  }

  Widget _buildNumberField({
    required String label,
    required String subtitle,
    required TextEditingController controller,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(color: Colors.white,
                fontWeight: FontWeight.w700, fontSize: 11, letterSpacing: 1)),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white,
              fontSize: 18, fontWeight: FontWeight.bold),
          decoration: InputDecoration(
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
            filled: true,
            fillColor: Colors.white.withOpacity(0.05),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: Colors.white.withOpacity(0.15)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: _accent, width: 2),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(subtitle,
            style: TextStyle(
                fontSize: 9, color: Colors.white.withOpacity(0.35))),
      ],
    );
  }

  Widget _buildTimingPreview() {
    final duration  = int.tryParse(_durationController.text.trim()) ?? 2;
    final breakMins = int.tryParse(_intervalController.text.trim())  ?? 1;
    if (duration <= 0) return const SizedBox.shrink();

    int h = _startTime.hour, m = _startTime.minute;

    String fmt(int hour, int min) {
      final total = hour * 60 + min;
      final th    = total ~/ 60;
      final tm    = total % 60;
      final period = th < 12 ? 'AM' : 'PM';
      final h12 = th % 12 == 0 ? 12 : th % 12;
      return '${h12.toString().padLeft(2, '0')}:${tm.toString().padLeft(2, '0')} $period';
    }

    final m1Start = fmt(h, m);
    final m1End   = fmt(h, m + duration);
    final m2Start = fmt(h, m + duration + breakMins);
    final m2End   = fmt(h, m + duration + breakMins + duration);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _accent.withOpacity(0.06),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _accent.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.schedule_rounded, size: 11, color: _accent),
            const SizedBox(width: 5),
            const Text('EXAMPLE TIMING',
                style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold,
                    color: _accent, letterSpacing: 1)),
          ]),
          const SizedBox(height: 8),
          _previewRow('Match 1', m1Start, m1End, _accent),
          if (breakMins > 0) ...[
            const SizedBox(height: 4),
            Row(children: [
              const SizedBox(width: 6),
              Icon(Icons.coffee_rounded, size: 10, color: Colors.orange.shade400),
              const SizedBox(width: 4),
              Text('$breakMins min break',
                  style: TextStyle(fontSize: 9, color: Colors.orange.shade400,
                      fontStyle: FontStyle.italic)),
            ]),
            const SizedBox(height: 4),
          ] else const SizedBox(height: 4),
          _previewRow('Match 2', m2Start, m2End, const Color(0xFF00E5A0)),
        ],
      ),
    );
  }

  Widget _previewRow(String label, String start, String end, Color color) {
    return Row(children: [
      Container(width: 3, height: 16,
          decoration: BoxDecoration(
              color: color, borderRadius: BorderRadius.circular(2))),
      const SizedBox(width: 8),
      Text('$label  ',
          style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold,
              color: color)),
      Text('$start – $end',
          style: TextStyle(fontSize: 10,
              color: Colors.white.withOpacity(0.5))),
    ]);
  }

  Widget _buildLunchToggle() {
    return GestureDetector(
      onTap: () => setState(() => _lunchBreakEnabled = !_lunchBreakEnabled),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: _lunchBreakEnabled
              ? const Color(0xFFFFD700).withOpacity(0.07)
              : Colors.white.withOpacity(0.03),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: _lunchBreakEnabled
                ? const Color(0xFFFFD700).withOpacity(0.35)
                : Colors.white.withOpacity(0.1),
          ),
        ),
        child: Row(children: [
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _lunchBreakEnabled
                  ? const Color(0xFFFFD700).withOpacity(0.15)
                  : Colors.white.withOpacity(0.05),
            ),
            child: Icon(Icons.restaurant_rounded, size: 14,
                color: _lunchBreakEnabled
                    ? const Color(0xFFFFD700)
                    : Colors.white38),
          ),
          const SizedBox(width: 10),
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('LUNCH BREAK',
                  style: TextStyle(
                    fontWeight: FontWeight.bold, fontSize: 11, letterSpacing: 0.5,
                    color: _lunchBreakEnabled
                        ? const Color(0xFFFFD700)
                        : Colors.white38,
                  )),
              Text('12:00 PM – 1:00 PM  •  No matches',
                  style: TextStyle(fontSize: 9, height: 1.4,
                      color: _lunchBreakEnabled
                          ? Colors.white38
                          : Colors.white24)),
            ],
          )),
          Switch(
            value: _lunchBreakEnabled,
            onChanged: (v) => setState(() => _lunchBreakEnabled = v),
            activeColor: const Color(0xFFFFD700),
            inactiveThumbColor: Colors.white24,
            inactiveTrackColor: Colors.white12,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ]),
      ),
    );
  }

  Widget _buildSpinner(int categoryId, {required bool isRuns}) {
    final value  = isRuns ? (_runsPerCategory[categoryId] ?? 4) // Default to 4 matches
                          : (_arenasPerCategory[categoryId] ?? 1);
    final maxVal = isRuns ? 99 : 3;
    final color  = isRuns ? _accent : const Color(0xFF967BB6);

    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 38, height: 38,
            child: Center(
              child: Text('$value',
                  style: TextStyle(fontWeight: FontWeight.bold,
                      fontSize: 16, color: color)),
            ),
          ),
          Container(width: 1, height: 38,
              color: color.withOpacity(0.2)),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 26, height: 19,
                child: InkWell(
                  borderRadius: const BorderRadius.only(
                      topRight: Radius.circular(8)),
                  onTap: () => setState(() {
                    if (value < maxVal) {
                      if (isRuns) _runsPerCategory[categoryId] = value + 1;
                      else _arenasPerCategory[categoryId] = value + 1;
                    }
                  }),
                  child: Icon(Icons.keyboard_arrow_up,
                      size: 16, color: color.withOpacity(0.8)),
                ),
              ),
              Container(height: 1, width: 26, color: color.withOpacity(0.2)),
              SizedBox(
                width: 26, height: 19,
                child: InkWell(
                  borderRadius: const BorderRadius.only(
                      bottomRight: Radius.circular(8)),
                  onTap: () => setState(() {
                    if (value > 1) {
                      if (isRuns) _runsPerCategory[categoryId] = value - 1;
                      else _arenasPerCategory[categoryId] = value - 1;
                    }
                  }),
                  child: Icon(Icons.keyboard_arrow_down,
                      size: 16, color: color.withOpacity(0.8)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _pickTime(bool isStart) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: isStart ? _startTime : _endTime,
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.dark(
            primary: _accent,
            onPrimary: Colors.black,
            surface: Color(0xFF2D0E7A),
            onSurface: Colors.white,
          ),
          timePickerTheme: TimePickerThemeData(
            dialHandColor: _accent,
            dialBackgroundColor: const Color(0xFF1E0A5A),
            hourMinuteColor: Colors.white.withOpacity(0.1),
            hourMinuteTextColor: Colors.white,
          ),
        ),
        child: child!,
      ),
    );
    if (picked != null) {
      setState(() {
        if (isStart) _startTime = picked;
        else         _endTime   = picked;
      });
    }
  }

  String _fmtTime(TimeOfDay t) {
    final period = t.hour < 12 ? 'AM' : 'PM';
    final h12    = t.hourOfPeriod == 0 ? 12 : t.hourOfPeriod;
    return '${h12.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')} $period';
  }
}