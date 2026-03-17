// championship_schedule.dart
import 'package:flutter/material.dart';
import 'db_helper.dart';
import 'championship_settings.dart';
import 'championship_settings_dialog.dart';
import 'constants.dart';

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

  @override
  void initState() {
    super.initState();
    _loadSettingsAndMatches();
  }

  Future<void> _loadSettingsAndMatches() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      // Load settings
      final settings = await DBHelper.loadChampionshipSettings(widget.categoryId);
      
      // Load alliance count
      await _loadAllianceCount();
      
      setState(() {
        _settings = settings ?? ChampionshipSettings.defaults(widget.categoryId);
      });
      
      // Load matches
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
      final matches = await _getChampionshipMatches(widget.categoryId);
      
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

  Future<List<Map<String, dynamic>>> _getChampionshipMatches(int categoryId) async {
    try {
      final conn = await DBHelper.getConnection();
      
      // Check if table exists
      try {
        await conn.execute("SELECT 1 FROM tbl_championship_schedule LIMIT 1");
      } catch (e) {
        print("⚠️ tbl_championship_schedule doesn't exist yet");
        return [];
      }
      
      // Get matches with alliance details
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
      """, {"categoryId": categoryId});
      
      final rows = result.rows.map((r) {
        final data = r.assoc();
        
        // Format alliance names
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
        
        return data;
      }).toList();
      
      return rows;
      
    } catch (e, stackTrace) {
      print("❌ Error in _getChampionshipMatches: $e");
      print(stackTrace);
      return [];
    }
  }

  Future<void> _showSettingsDialog() async {
    if (_settings == null) return;
    
    final result = await showDialog<ChampionshipSettings>(
      context: context,
      builder: (context) => ChampionshipSettingsDialog(
        settings: _settings!,
        onSave: (updatedSettings) async {
          // Save settings to database
          await DBHelper.saveChampionshipSettings(updatedSettings);
          
          setState(() {
            _settings = updatedSettings;
          });
          
          // Show success message
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
    
    // Confirm with user
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

  String _getRoundName(int round, int totalMatches) {
    if (_allianceCount == 2) {
      // With only 2 alliances, it's a direct final series
      if (totalMatches > 1) {
        return 'FINAL SERIES'; // Multiple matches in the final
      } else {
        return 'FINAL';
      }
    } else {
      // Regular bracket naming
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
              'Click the gear icon to configure settings, then generate',
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
                  onPressed: _isGenerating ? null : _generateSchedule,
                  icon: _isGenerating
                      ? const SizedBox(
                          width: 16, height: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.auto_awesome),
                  label: Text(_isGenerating ? 'GENERATING...' : 'GENERATE SCHEDULE'),
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
                          color: const Color(0xFFFFD700).withOpacity(0.3)),
                    ),
                    child: const Icon(Icons.settings_rounded,
                        color: Color(0xFFFFD700), size: 20),
                  ),
                  onPressed: _showSettingsDialog,
                  tooltip: 'Championship Settings',
                ),
              ],
            ),
          ],
        ),
      );
    }

    // Group matches by round
    final Map<int, List<Map<String, dynamic>>> matchesByRound = {};
    for (var match in _matches) {
      final round = int.tryParse(match['match_round'].toString()) ?? 1;
      matchesByRound.putIfAbsent(round, () => []).add(match);
    }

    final sortedRounds = matchesByRound.keys.toList()..sort();

    return Column(
      children: [
        // Settings bar
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

        // Matches list
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              ...sortedRounds.map((round) {
                final roundMatches = matchesByRound[round]!;
                final roundName = _getRoundName(round, roundMatches.length);

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Round header
                    Container(
                      margin: const EdgeInsets.symmetric(vertical: 16),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            const Color(0xFFFFD700).withOpacity(0.15),
                            const Color(0xFFFFD700).withOpacity(0.05),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(30),
                        border: Border.all(
                          color: const Color(0xFFFFD700).withOpacity(0.3),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            round == sortedRounds.last ? Icons.star : Icons.emoji_events,
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
                              letterSpacing: 1,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              '${roundMatches.length} MATCH${roundMatches.length > 1 ? 'ES' : ''}',
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 10,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Matches
                    ...roundMatches.map((match) {
                      final isPlaceholder = 
                          match['alliance1_id'] == '0' || match['alliance1_id'] == null ||
                          match['alliance2_id'] == '0' || match['alliance2_id'] == null;

                      return Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              const Color(0xFF1A0A4A),
                              const Color(0xFF2D0E7A).withOpacity(0.5),
                            ],
                          ),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isPlaceholder
                                ? Colors.white.withOpacity(0.1)
                                : const Color(0xFFFFD700).withOpacity(0.3),
                            width: isPlaceholder ? 1 : 2,
                          ),
                        ),
                        child: Column(
                          children: [
                            // Alliances
                            Row(
                              children: [
                                // Alliance 1
                                Expanded(
                                  child: Container(
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: isPlaceholder
                                          ? Colors.white.withOpacity(0.02)
                                          : const Color(0xFF00CFFF).withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                        color: isPlaceholder
                                            ? Colors.white.withOpacity(0.1)
                                            : const Color(0xFF00CFFF).withOpacity(0.3),
                                      ),
                                    ),
                                    child: Column(
                                      children: [
                                        Row(
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          children: [
                                            Text(
                                              '#${match['alliance1_rank'] ?? '?'}',
                                              style: TextStyle(
                                                color: isPlaceholder
                                                    ? Colors.white24
                                                    : const Color(0xFF00CFFF),
                                                fontSize: 10,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                            const SizedBox(width: 4),
                                            const Text(
                                              'ALLIANCE',
                                              style: TextStyle(
                                                color: Color(0xFF00CFFF),
                                                fontSize: 9,
                                                fontWeight: FontWeight.bold,
                                                letterSpacing: 0.5,
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 6),
                                        Text(
                                          match['alliance1_name'] ?? 'TBD',
                                          style: TextStyle(
                                            color: isPlaceholder
                                                ? Colors.white38
                                                : Colors.white,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 13,
                                          ),
                                          textAlign: TextAlign.center,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),

                                // VS
                                Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 12),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 6,
                                    ),
                                    decoration: BoxDecoration(
                                      color: isPlaceholder
                                          ? Colors.white.withOpacity(0.05)
                                          : const Color(0xFFFFD700).withOpacity(0.15),
                                      borderRadius: BorderRadius.circular(20),
                                      border: Border.all(
                                        color: isPlaceholder
                                            ? Colors.white.withOpacity(0.1)
                                            : const Color(0xFFFFD700).withOpacity(0.3),
                                      ),
                                    ),
                                    child: Text(
                                      'VS',
                                      style: TextStyle(
                                        color: isPlaceholder
                                            ? Colors.white24
                                            : const Color(0xFFFFD700),
                                        fontWeight: FontWeight.bold,
                                        fontSize: 12,
                                        letterSpacing: 1,
                                      ),
                                    ),
                                  ),
                                ),

                                // Alliance 2
                                Expanded(
                                  child: Container(
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: isPlaceholder
                                          ? Colors.white.withOpacity(0.02)
                                          : const Color(0xFF00FF88).withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                        color: isPlaceholder
                                            ? Colors.white.withOpacity(0.1)
                                            : const Color(0xFF00FF88).withOpacity(0.3),
                                      ),
                                    ),
                                    child: Column(
                                      children: [
                                        Row(
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          children: [
                                            Text(
                                              '#${match['alliance2_rank'] ?? '?'}',
                                              style: TextStyle(
                                                color: isPlaceholder
                                                    ? Colors.white24
                                                    : const Color(0xFF00FF88),
                                                fontSize: 10,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                            const SizedBox(width: 4),
                                            const Text(
                                              'ALLIANCE',
                                              style: TextStyle(
                                                color: Color(0xFF00FF88),
                                                fontSize: 9,
                                                fontWeight: FontWeight.bold,
                                                letterSpacing: 0.5,
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 6),
                                        Text(
                                          match['alliance2_name'] ?? 'TBD',
                                          style: TextStyle(
                                            color: isPlaceholder
                                                ? Colors.white38
                                                : Colors.white,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 13,
                                          ),
                                          textAlign: TextAlign.center,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),

                            const SizedBox(height: 12),

                            // Match details
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                // Time
                                Row(
                                  children: [
                                    Icon(
                                      Icons.access_time,
                                      color: isPlaceholder
                                          ? Colors.white24
                                          : Colors.white38,
                                      size: 14,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      match['schedule_time'] ?? '--:--',
                                      style: TextStyle(
                                        color: isPlaceholder
                                            ? Colors.white24
                                            : Colors.white.withOpacity(0.5),
                                      ),
                                    ),
                                  ],
                                ),

                                // Status
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: (match['status']?.toString().toUpperCase() ?? 'PENDING') == 'PENDING'
                                        ? Colors.orange.withOpacity(0.15)
                                        : Colors.green.withOpacity(0.15),
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(
                                      color: (match['status']?.toString().toUpperCase() ?? 'PENDING') == 'PENDING'
                                          ? Colors.orange.withOpacity(0.3)
                                          : Colors.green.withOpacity(0.3),
                                    ),
                                  ),
                                  child: Text(
                                    (match['status']?.toString().toUpperCase() ?? 'PENDING'),
                                    style: TextStyle(
                                      color: (match['status']?.toString().toUpperCase() ?? 'PENDING') == 'PENDING'
                                          ? Colors.orange
                                          : Colors.green,
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),

                                // Round/Position info
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFFFD700).withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text(
                                    _allianceCount == 2 && roundMatches.length > 1
                                        ? 'MATCH ${match['match_position']}'
                                        : 'ROUND $round',
                                    style: const TextStyle(
                                      color: Color(0xFFFFD700),
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      );
                    }),
                  ],
                );
              }),
            ],
          ),
        ),
      ],
    );
  }
}