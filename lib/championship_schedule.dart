// championship_schedule.dart
import 'package:flutter/material.dart';
import 'db_helper.dart';

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

  @override
  void initState() {
    super.initState();
    _loadMatches();
  }

  Future<void> _loadMatches() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

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
      
      // First, check if the table exists
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
        WHERE a1.category_id = :catId OR a2.category_id = :catId OR cs.alliance1_id = 0 OR cs.alliance2_id = 0
        ORDER BY cs.match_round, cs.match_position
      """, {"catId": categoryId});
      
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

  Future<void> _generateSchedule() async {
    try {
      setState(() => _isLoading = true);
      
      print("🏆 Generating championship schedule for category ${widget.categoryId}");
      
      final conn = await DBHelper.getConnection();
      
      // Get alliances
      final alliancesResult = await conn.execute("""
        SELECT alliance_id, captain_team_id, partner_team_id, selection_round
        FROM tbl_alliance_selections 
        WHERE category_id = :catId
        ORDER BY selection_round
      """, {"catId": widget.categoryId});
      
      final alliances = alliancesResult.rows.map((r) => r.assoc()).toList();
      
      if (alliances.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No alliances found. Complete alliance selection first.'),
            backgroundColor: Colors.orange,
          ),
        );
        setState(() => _isLoading = false);
        return;
      }
      
      // Create table if not exists
      await conn.execute("""
        CREATE TABLE IF NOT EXISTS tbl_championship_schedule (
          match_id INT AUTO_INCREMENT PRIMARY KEY,
          alliance1_id INT NOT NULL,
          alliance2_id INT NOT NULL,
          match_round INT NOT NULL,
          match_position INT NOT NULL,
          schedule_time VARCHAR(20),
          arena_number INT DEFAULT 1,
          status VARCHAR(20) DEFAULT 'pending',
          INDEX idx_category (alliance1_id, alliance2_id)
        )
      """);
      
      // Clear existing
      await conn.execute("""
        DELETE FROM tbl_championship_schedule 
        WHERE alliance1_id IN (SELECT alliance_id FROM tbl_alliance_selections WHERE category_id = :catId)
        OR alliance2_id IN (SELECT alliance_id FROM tbl_alliance_selections WHERE category_id = :catId)
      """, {"catId": widget.categoryId});
      
      final numAlliances = alliances.length;
      int matchesInserted = 0;
      
      if (numAlliances == 4) {
        // Semifinals
        await conn.execute("""
          INSERT INTO tbl_championship_schedule 
            (alliance1_id, alliance2_id, match_round, match_position, schedule_time)
          VALUES
            (:a1, :a4, 1, 1, '13:00'),
            (:a2, :a3, 1, 2, '13:10')
        """, {
          "a1": alliances[0]['alliance_id'],
          "a2": alliances[1]['alliance_id'],
          "a3": alliances[2]['alliance_id'],
          "a4": alliances[3]['alliance_id'],
        });
        matchesInserted += 2;
        
        // Final placeholder
        await conn.execute("""
          INSERT INTO tbl_championship_schedule 
            (alliance1_id, alliance2_id, match_round, match_position, schedule_time, status)
          VALUES
            (0, 0, 2, 1, '13:30', 'pending')
        """);
        matchesInserted += 1;
        
      } else if (numAlliances == 8) {
        // Quarterfinals
        for (int i = 0; i < 4; i++) {
          await conn.execute("""
            INSERT INTO tbl_championship_schedule 
              (alliance1_id, alliance2_id, match_round, match_position, schedule_time)
            VALUES
              (:a1, :a2, 1, :pos, :time)
          """, {
            "a1": alliances[i * 2]['alliance_id'],
            "a2": alliances[i * 2 + 1]['alliance_id'],
            "pos": i + 1,
            "time": '${13 + i * 10}:00',
          });
        }
        matchesInserted += 4;
        
        // Semifinals placeholders
        for (int i = 0; i < 2; i++) {
          await conn.execute("""
            INSERT INTO tbl_championship_schedule 
              (alliance1_id, alliance2_id, match_round, match_position, schedule_time, status)
            VALUES
              (0, 0, 2, :pos, :time, 'pending')
          """, {
            "pos": i + 1,
            "time": '${14 + i * 10}:00',
          });
        }
        matchesInserted += 2;
        
        // Final placeholder
        await conn.execute("""
          INSERT INTO tbl_championship_schedule 
            (alliance1_id, alliance2_id, match_round, match_position, schedule_time, status)
          VALUES
            (0, 0, 3, 1, '15:00', 'pending')
        """);
        matchesInserted += 1;
        
      } else if (numAlliances == 2) {
        // Direct final
        await conn.execute("""
          INSERT INTO tbl_championship_schedule 
            (alliance1_id, alliance2_id, match_round, match_position, schedule_time)
          VALUES
            (:a1, :a2, 1, 1, '13:00')
        """, {
          "a1": alliances[0]['alliance_id'],
          "a2": alliances[1]['alliance_id'],
        });
        matchesInserted += 1;
      }
      
      print("✅ Inserted $matchesInserted championship matches");
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('✅ Generated $matchesInserted championship matches!'),
          backgroundColor: Colors.green,
        ),
      );
      
      // Reload matches
      await _loadMatches();
      
    } catch (e, stackTrace) {
      print("❌ Error generating championship schedule: $e");
      print(stackTrace);
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: $e'),
          backgroundColor: Colors.red,
        ),
      );
      setState(() => _isLoading = false);
    }
  }

  String _getRoundName(int round, int totalMatches) {
    if (totalMatches == 1) return 'FINAL';
    if (round == 1) {
      if (totalMatches > 2) return 'QUARTER-FINAL';
      return 'SEMI-FINAL';
    }
    if (round == 2) return 'SEMI-FINAL';
    return 'FINAL';
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
              onPressed: _loadMatches,
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
              'Complete alliance selection first',
              style: TextStyle(
                color: Colors.white.withOpacity(0.5),
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _generateSchedule,
              icon: const Icon(Icons.auto_awesome),
              label: const Text('GENERATE CHAMPIONSHIP SCHEDULE'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFFD700),
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
              ),
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

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Header
        Container(
          margin: const EdgeInsets.only(bottom: 24),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFFFFD700), Color(0xFFCCAC00)],
            ),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFFFD700).withOpacity(0.3),
                blurRadius: 20,
                spreadRadius: 2,
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.2),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.emoji_events,
                  color: Colors.black,
                  size: 28,
                ),
              ),
              const SizedBox(width: 16),
              Text(
                '${widget.categoryName} CHAMPIONSHIP',
                style: const TextStyle(
                  color: Colors.black,
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 2,
                ),
              ),
            ],
          ),
        ),

        // Matches by round
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

                          // Round
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
                              'ROUND $round',
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
              }).toList(),
            ],
          );
        }).toList(),

        // Regenerate button at bottom
        const SizedBox(height: 20),
        Center(
          child: OutlinedButton.icon(
            onPressed: _generateSchedule,
            icon: const Icon(Icons.refresh, size: 16),
            label: const Text('REGENERATE SCHEDULE'),
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFFFFD700),
              side: const BorderSide(color: Color(0xFFFFD700)),
              padding: const EdgeInsets.symmetric(
                horizontal: 24,
                vertical: 12,
              ),
            ),
          ),
        ),
        const SizedBox(height: 20),
      ],
    );
  }
}