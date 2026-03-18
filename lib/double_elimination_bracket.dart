// double_elimination_bracket.dart
import 'package:flutter/material.dart';
import 'db_helper.dart';
import 'championship_settings.dart';
import 'championship_settings_dialog.dart';
import 'constants.dart';

class DoubleEliminationBracket extends StatefulWidget {
  final int categoryId;
  final String categoryName;

  const DoubleEliminationBracket({
    super.key,
    required this.categoryId,
    required this.categoryName,
  });

  @override
  State<DoubleEliminationBracket> createState() => _DoubleEliminationBracketState();
}

class _DoubleEliminationBracketState extends State<DoubleEliminationBracket> {
  List<Map<String, dynamic>> _alliances = [];
  List<Map<String, dynamic>> _matches = [];
  bool _isLoading = true;
  String? _error;
  ChampionshipSettings? _settings;
  bool _isGenerating = false;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      // Load settings
      final settings = await DBHelper.loadChampionshipSettings(widget.categoryId);
      
      setState(() {
        _settings = settings ?? ChampionshipSettings.defaults(widget.categoryId);
      });
      
      // Load alliances
      await _loadAlliances();
      
      // Load matches
      await _loadMatches();
      
    } catch (e, stackTrace) {
      print("❌ DoubleEliminationBracket error: $e");
      print(stackTrace);
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _loadAlliances() async {
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
      """, {"catId": widget.categoryId});
      
      setState(() {
        _alliances = result.rows.map((r) => r.assoc()).toList();
      });
      
      print("✅ Loaded ${_alliances.length} alliances");
    } catch (e) {
      print("Error loading alliances: $e");
    }
  }

  Future<void> _loadMatches() async {
    try {
      final conn = await DBHelper.getConnection();
      
      // Check if table exists
      try {
        await conn.execute("SELECT 1 FROM tbl_double_elimination LIMIT 1");
      } catch (e) {
        setState(() {
          _matches = [];
          _isLoading = false;
        });
        return;
      }
      
      final result = await conn.execute("""
        SELECT 
          match_id,
          round_name,
          match_position,
          alliance1_id,
          alliance2_id,
          winner_alliance_id,
          next_match_id_winner,
          next_match_id_loser,
          next_match_position_winner,
          next_match_position_loser,
          is_lower_bracket,
          status,
          schedule_time
        FROM tbl_double_elimination
        WHERE category_id = :catId
        ORDER BY 
          CASE 
            WHEN round_name LIKE 'Upper%' AND round_name NOT LIKE '%Final' THEN 1
            WHEN round_name = 'Upper Final' THEN 2
            WHEN round_name LIKE 'Lower%' THEN 3
            WHEN round_name = 'Lower Final' THEN 4
            WHEN round_name = 'Grand Final' THEN 5
            ELSE 6
          END,
          match_position
      """, {"catId": widget.categoryId});
      
      final matches = result.rows.map((r) {
        final data = r.assoc();
        
        // Add alliance names
        if (data['alliance1_id'] != null) {
          final alliance = _alliances.firstWhere(
            (a) => a['alliance_id'].toString() == data['alliance1_id'].toString(),
            orElse: () => {'captain_name': 'TBD', 'partner_name': ''}
          );
          data['alliance1_name'] = '${alliance['captain_name']} / ${alliance['partner_name']}';
        } else {
          data['alliance1_name'] = 'TBD';
        }
        
        if (data['alliance2_id'] != null) {
          final alliance = _alliances.firstWhere(
            (a) => a['alliance_id'].toString() == data['alliance2_id'].toString(),
            orElse: () => {'captain_name': 'TBD', 'partner_name': ''}
          );
          data['alliance2_name'] = '${alliance['captain_name']} / ${alliance['partner_name']}';
        } else {
          data['alliance2_name'] = 'TBD';
        }
        
        return data;
      }).toList();
      
      setState(() {
        _matches = matches;
        _isLoading = false;
      });
      
      print("✅ Loaded ${matches.length} double elimination matches");
    } catch (e) {
      print("Error loading matches: $e");
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _generateDoubleEliminationBracket() async {
    if (_settings == null) return;
    
    // Confirm with user
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF2D0E7A),
        title: Text('Generate Double Elimination Bracket?', 
            style: const TextStyle(color: Colors.white)),
        content: Text(
          'This will create a double elimination bracket for ${_alliances.length} alliances.\n\n'
          '• Upper bracket: Winners advance\n'
          '• Lower bracket: Losers drop down and play\n'
          '• Lower bracket winner faces Upper bracket final loser\n'
          '• Grand Final: Winner vs Winner\n\n'
          'Seeding: 1 vs ${_alliances.length}, 2 vs ${_alliances.length-1}, etc.',
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
      await _generateBracket();
      await _loadMatches();
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ Double elimination bracket generated'),
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

  Future<void> _generateBracket() async {
    final conn = await DBHelper.getConnection();
    
    // Delete existing matches
    await conn.execute(
      "DELETE FROM tbl_double_elimination WHERE category_id = :catId",
      {"catId": widget.categoryId}
    );
    
    final numAlliances = _alliances.length;
    
    // Calculate bracket size (next power of 2)
    int bracketSize = 2;
    while (bracketSize < numAlliances) {
      bracketSize *= 2;
    }
    
    // Create seeded list with byes
    final List<Map<String, dynamic>?> seededAlliances = List.filled(bracketSize, null);
    
    // Seed alliances: 1 vs last, 2 vs second last, etc.
    for (int i = 0; i < numAlliances; i++) {
      // Standard tournament seeding: top vs bottom
      if (i < numAlliances / 2) {
        // Place in first half
        int index = i * 2;
        if (index < bracketSize) {
          seededAlliances[index] = _alliances[i];
        }
      } else {
        // Place in second half, pairing with corresponding top seed
        int pairIndex = (numAlliances - 1 - i) * 2 + 1;
        if (pairIndex < bracketSize) {
          seededAlliances[pairIndex] = _alliances[i];
        }
      }
    }
    
    print("🎯 Generating ${bracketSize}-team bracket with ${numAlliances} alliances");
    
    await _generateFlexibleBracket(conn, seededAlliances, bracketSize, numAlliances);
  }

  Future<void> _generateFlexibleBracket(
    MySQLConnection conn, 
    List<Map<String, dynamic>?> seededAlliances,
    int bracketSize,
    int numAlliances
  ) async {
    int currentHour = _settings!.startTime.hour;
    int currentMinute = _settings!.startTime.minute;
    
    String formatTime(int hour, int minute) {
      return '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
    }
    
    // Calculate number of rounds
    int numRounds = 0;
    int temp = bracketSize;
    while (temp > 1) {
      temp ~/= 2;
      numRounds++;
    }
    
    // Maps to store match IDs
    final Map<String, int> upperMatchIds = {};
    final Map<String, int> lowerMatchIds = {};
    
    // --- GENERATE UPPER BRACKET (Winners Bracket) ---
    
    // First round matches (with possible byes)
    List<Map<String, dynamic>> firstRoundMatches = [];
    int matchPosition = 1;
    
    for (int i = 0; i < bracketSize; i += 2) {
      firstRoundMatches.add({
        'position': matchPosition,
        'alliance1': seededAlliances[i],
        'alliance2': seededAlliances[i + 1],
      });
      matchPosition++;
    }
    
    // Create first round matches
    int firstRoundMatchCount = 0;
    for (final match in firstRoundMatches) {
      // Check if it's a bye (one side null)
      final bool isBye = match['alliance1'] == null || match['alliance2'] == null;
      
      if (isBye) {
        // Bye - winner is the non-null alliance
        // We'll handle this in the next round
        continue;
      }
      
      // Regular match
      final time = formatTime(currentHour, currentMinute);
      final result = await conn.execute("""
        INSERT INTO tbl_double_elimination 
          (category_id, round_name, match_position, alliance1_id, alliance2_id, schedule_time, is_lower_bracket)
        VALUES
          (:catId, 'Upper Round 1', :pos, :a1, :a2, :time, FALSE)
      """, {
        "catId": widget.categoryId,
        "pos": match['position'],
        "a1": match['alliance1']!['alliance_id'],
        "a2": match['alliance2']!['alliance_id'],
        "time": time,
      });
      upperMatchIds['UR1_${match['position']}'] = result.lastInsertID.toInt();
      firstRoundMatchCount++;
      
      currentMinute += _settings!.durationMinutes + _settings!.intervalMinutes;
      while (currentMinute >= 60) { currentMinute -= 60; currentHour++; }
    }
    
    // Calculate matches in each round
    int matchesInCurrentRound = (firstRoundMatchCount + (bracketSize ~/ 2 - firstRoundMatchCount)) ~/ 2;
    
    // Generate subsequent upper bracket rounds
    for (int roundNum = 2; roundNum <= numRounds; roundNum++) {
      int matchesInThisRound = (bracketSize ~/ (1 << roundNum));
      
      for (int i = 0; i < matchesInThisRound; i++) {
        final time = formatTime(currentHour, currentMinute);
        final roundName = roundNum == numRounds ? 'Upper Final' : 'Upper Round $roundNum';
        
        final result = await conn.execute("""
          INSERT INTO tbl_double_elimination 
            (category_id, round_name, match_position, schedule_time, is_lower_bracket)
          VALUES
            (:catId, :roundName, :pos, :time, FALSE)
        """, {
          "catId": widget.categoryId,
          "roundName": roundName,
          "pos": i + 1,
          "time": time,
        });
        
        if (roundNum == numRounds) {
          upperMatchIds['UF'] = result.lastInsertID.toInt();
        } else {
          upperMatchIds['UR${roundNum}_${i + 1}'] = result.lastInsertID.toInt();
        }
        
        currentMinute += _settings!.durationMinutes + _settings!.intervalMinutes;
        while (currentMinute >= 60) { currentMinute -= 60; currentHour++; }
      }
    }
    
    // --- GENERATE LOWER BRACKET (Losers Bracket) ---
    // Number of lower bracket rounds = 2 * (numRounds - 1)
    int lowerRounds = 2 * (numRounds - 1);
    
    for (int round = 1; round <= lowerRounds; round++) {
      // Calculate matches in this lower round
      int matchesInLowerRound;
      if (round <= numRounds - 1) {
        matchesInLowerRound = (bracketSize ~/ 4) * round;
      } else {
        matchesInLowerRound = (bracketSize ~/ 4) * (lowerRounds - round + 1);
      }
      
      String roundName;
      if (round == lowerRounds) {
        roundName = 'Lower Final';
      } else {
        roundName = 'Lower Round $round';
      }
      
      for (int i = 0; i < matchesInLowerRound; i++) {
        final time = formatTime(currentHour, currentMinute);
        final result = await conn.execute("""
          INSERT INTO tbl_double_elimination 
            (category_id, round_name, match_position, schedule_time, is_lower_bracket)
          VALUES
            (:catId, :roundName, :pos, :time, TRUE)
        """, {
          "catId": widget.categoryId,
          "roundName": roundName,
          "pos": i + 1,
          "time": time,
        });
        
        if (round == lowerRounds) {
          lowerMatchIds['LF'] = result.lastInsertID.toInt();
        } else {
          lowerMatchIds['LR${round}_${i + 1}'] = result.lastInsertID.toInt();
        }
        
        currentMinute += _settings!.durationMinutes + _settings!.intervalMinutes;
        while (currentMinute >= 60) { currentMinute -= 60; currentHour++; }
      }
    }
    
    // --- GENERATE GRAND FINAL ---
    final timeGF = formatTime(currentHour, currentMinute);
    final resultGF = await conn.execute("""
      INSERT INTO tbl_double_elimination 
        (category_id, round_name, match_position, schedule_time, is_lower_bracket)
      VALUES
        (:catId, 'Grand Final', 1, :time, FALSE)
    """, {
      "catId": widget.categoryId,
      "time": timeGF,
    });
    final grandFinalId = resultGF.lastInsertID.toInt();
    
    // --- SETUP NEXT MATCH CONNECTIONS ---
    
    // Connect Upper Round 1 winners to Upper Round 2
    int upperRound2Index = 1;
    for (int i = 1; i <= firstRoundMatchCount; i += 2) {
      if (i + 1 <= firstRoundMatchCount) {
        final match1Key = 'UR1_$i';
        final match2Key = 'UR1_${i + 1}';
        final nextMatchKey = 'UR2_$upperRound2Index';
        
        if (upperMatchIds.containsKey(match1Key) && upperMatchIds.containsKey(nextMatchKey)) {
          await conn.execute("""
            UPDATE tbl_double_elimination 
            SET next_match_id_winner = :nextMatchId, next_match_position_winner = :pos
            WHERE match_id = :matchId
          """, {
            "nextMatchId": upperMatchIds[nextMatchKey]!,
            "pos": 1,
            "matchId": upperMatchIds[match1Key]!,
          });
        }
        
        if (upperMatchIds.containsKey(match2Key) && upperMatchIds.containsKey(nextMatchKey)) {
          await conn.execute("""
            UPDATE tbl_double_elimination 
            SET next_match_id_winner = :nextMatchId, next_match_position_winner = :pos
            WHERE match_id = :matchId
          """, {
            "nextMatchId": upperMatchIds[nextMatchKey]!,
            "pos": 2,
            "matchId": upperMatchIds[match2Key]!,
          });
        }
        
        upperRound2Index++;
      }
    }
    
    // Connect subsequent upper rounds
    for (int roundNum = 2; roundNum < numRounds; roundNum++) {
      int matchesInRound = bracketSize ~/ (1 << roundNum);
      int nextRoundIndex = 1;
      
      for (int i = 1; i <= matchesInRound; i += 2) {
        if (i + 1 <= matchesInRound) {
          final match1Key = 'UR${roundNum}_$i';
          final match2Key = 'UR${roundNum}_${i + 1}';
          final nextMatchKey = 'UR${roundNum + 1}_$nextRoundIndex';
          
          if (upperMatchIds.containsKey(match1Key) && upperMatchIds.containsKey(nextMatchKey)) {
            await conn.execute("""
              UPDATE tbl_double_elimination 
              SET next_match_id_winner = :nextMatchId, next_match_position_winner = :pos
              WHERE match_id = :matchId
            """, {
              "nextMatchId": upperMatchIds[nextMatchKey]!,
              "pos": 1,
              "matchId": upperMatchIds[match1Key]!,
            });
          }
          
          if (upperMatchIds.containsKey(match2Key) && upperMatchIds.containsKey(nextMatchKey)) {
            await conn.execute("""
              UPDATE tbl_double_elimination 
              SET next_match_id_winner = :nextMatchId, next_match_position_winner = :pos
              WHERE match_id = :matchId
            """, {
              "nextMatchId": upperMatchIds[nextMatchKey]!,
              "pos": 2,
              "matchId": upperMatchIds[match2Key]!,
            });
          }
          
          nextRoundIndex++;
        }
      }
    }
    
    // Connect Upper Final winner to Grand Final
    if (upperMatchIds.containsKey('UF')) {
      await conn.execute("""
        UPDATE tbl_double_elimination 
        SET next_match_id_winner = :nextMatchId, next_match_position_winner = :pos
        WHERE match_id = :matchId
      """, {
        "nextMatchId": grandFinalId,
        "pos": 1,
        "matchId": upperMatchIds['UF']!,
      });
    }
    
    // Connect Lower Final winner to Grand Final
    if (lowerMatchIds.containsKey('LF')) {
      await conn.execute("""
        UPDATE tbl_double_elimination 
        SET next_match_id_winner = :nextMatchId, next_match_position_winner = :pos
        WHERE match_id = :matchId
      """, {
        "nextMatchId": grandFinalId,
        "pos": 2,
        "matchId": lowerMatchIds['LF']!,
      });
    }
    
    print("✅ Generated flexible double elimination bracket for $bracketSize teams");
  }

  void _showMatchScoreDialog(Map<String, dynamic> match) {
    int? selectedWinnerId;
    
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          backgroundColor: const Color(0xFF2D0E7A),
          title: Text('Enter Match Result',
              style: const TextStyle(color: Colors.white)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Select Winner:', style: TextStyle(color: Colors.white70)),
              const SizedBox(height: 16),
              if (match['alliance1_id'] != null)
                ListTile(
                  title: Text(match['alliance1_name'] ?? 'Alliance 1',
                      style: const TextStyle(color: Colors.white)),
                  leading: Radio<int>(
                    value: int.parse(match['alliance1_id'].toString()),
                    groupValue: selectedWinnerId,
                    onChanged: (value) {
                      setState(() {
                        selectedWinnerId = value;
                      });
                    },
                  ),
                ),
              if (match['alliance2_id'] != null)
                ListTile(
                  title: Text(match['alliance2_name'] ?? 'Alliance 2',
                      style: const TextStyle(color: Colors.white)),
                  leading: Radio<int>(
                    value: int.parse(match['alliance2_id'].toString()),
                    groupValue: selectedWinnerId,
                    onChanged: (value) {
                      setState(() {
                        selectedWinnerId = value;
                      });
                    },
                  ),
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('CANCEL', style: TextStyle(color: Colors.white54)),
            ),
            ElevatedButton(
              onPressed: () async {
                if (selectedWinnerId != null) {
                  // Save result to database
                  final conn = await DBHelper.getConnection();
                  await conn.execute("""
                    UPDATE tbl_double_elimination 
                    SET winner_alliance_id = :winnerId, status = 'completed'
                    WHERE match_id = :matchId
                  """, {
                    "winnerId": selectedWinnerId,
                    "matchId": int.parse(match['match_id'].toString()),
                  });
                  
                  // Propagate winner to next match
                  if (match['next_match_id_winner'] != null) {
                    // Update the next match with this winner
                    int nextMatchId = int.parse(match['next_match_id_winner'].toString());
                    int position = int.parse(match['next_match_position_winner']?.toString() ?? '1');
                    
                    if (position == 1) {
                      await conn.execute("""
                        UPDATE tbl_double_elimination 
                        SET alliance1_id = :winnerId
                        WHERE match_id = :nextMatchId
                      """, {
                        "winnerId": selectedWinnerId,
                        "nextMatchId": nextMatchId,
                      });
                    } else {
                      await conn.execute("""
                        UPDATE tbl_double_elimination 
                        SET alliance2_id = :winnerId
                        WHERE match_id = :nextMatchId
                      """, {
                        "winnerId": selectedWinnerId,
                        "nextMatchId": nextMatchId,
                      });
                    }
                  }
                  
                  // Propagate loser to loser's bracket
                  if (match['next_match_id_loser'] != null && match['is_lower_bracket'] == 0) {
                    int loserId = selectedWinnerId == int.parse(match['alliance1_id'].toString())
                        ? int.parse(match['alliance2_id'].toString())
                        : int.parse(match['alliance1_id'].toString());
                    
                    int nextMatchId = int.parse(match['next_match_id_loser'].toString());
                    int position = int.parse(match['next_match_position_loser']?.toString() ?? '1');
                    
                    if (position == 1) {
                      await conn.execute("""
                        UPDATE tbl_double_elimination 
                        SET alliance1_id = :loserId
                        WHERE match_id = :nextMatchId
                      """, {
                        "loserId": loserId,
                        "nextMatchId": nextMatchId,
                      });
                    } else {
                      await conn.execute("""
                        UPDATE tbl_double_elimination 
                        SET alliance2_id = :loserId
                        WHERE match_id = :nextMatchId
                      """, {
                        "loserId": loserId,
                        "nextMatchId": nextMatchId,
                      });
                    }
                  }
                  
                  Navigator.pop(ctx);
                  await _loadMatches();
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFFD700),
              ),
              child: const Text('SAVE', style: TextStyle(color: Colors.black)),
            ),
          ],
        ),
      ),
    );
  }

  String _getRoundColor(String roundName) {
    if (roundName.contains('Upper')) return const Color(0xFF00CFFF);
    if (roundName.contains('Lower')) return const Color(0xFFFF6B6B);
    if (roundName.contains('Grand')) return const Color(0xFFFFD700);
    return Colors.white;
  }

  String _getRoundIcon(String roundName) {
    if (roundName.contains('Upper')) return '↑';
    if (roundName.contains('Lower')) return '↓';
    if (roundName.contains('Grand')) return '🏆';
    return '•';
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
            Text('Loading bracket...',
                style: TextStyle(color: Colors.white54)),
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
            Text('Error loading bracket',
                style: TextStyle(color: Colors.redAccent)),
            const SizedBox(height: 8),
            Text(_error!,
                style: TextStyle(color: Colors.white38, fontSize: 12),
                textAlign: TextAlign.center),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loadData,
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
                Icons.account_tree,
                size: 64,
                color: Color(0xFFFFD700),
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'No Bracket Generated Yet',
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w800,
                letterSpacing: 1,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '${_alliances.length} alliances detected',
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
                  onPressed: _isGenerating ? null : _generateDoubleEliminationBracket,
                  icon: _isGenerating
                      ? const SizedBox(
                          width: 16, height: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.auto_awesome),
                  label: Text(_isGenerating ? 'GENERATING...' : 'GENERATE BRACKET'),
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
                  onPressed: () => _showSettingsDialog(),
                  tooltip: 'Championship Settings',
                ),
              ],
            ),
          ],
        ),
      );
    }

    // Group matches by round
    final Map<String, List<Map<String, dynamic>>> matchesByRound = {};
    for (final match in _matches) {
      final round = match['round_name'] as String;
      matchesByRound.putIfAbsent(round, () => []).add(match);
    }

    // Define round order
    final List<String> roundOrder = [];
    
    // Add upper bracket rounds
    for (int i = 1; i <= 10; i++) {
      if (matchesByRound.containsKey('Upper Round $i')) {
        roundOrder.add('Upper Round $i');
      }
    }
    if (matchesByRound.containsKey('Upper Final')) {
      roundOrder.add('Upper Final');
    }
    
    // Add lower bracket rounds
    for (int i = 1; i <= 20; i++) {
      if (matchesByRound.containsKey('Lower Round $i')) {
        roundOrder.add('Lower Round $i');
      }
    }
    if (matchesByRound.containsKey('Lower Final')) {
      roundOrder.add('Lower Final');
    }
    
    // Add grand final
    if (matchesByRound.containsKey('Grand Final')) {
      roundOrder.add('Grand Final');
    }

    return Column(
      children: [
        // Header with info
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
                  color: const Color(0xFF00CFFF).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFF00CFFF).withOpacity(0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.emoji_events, color: Color(0xFF00CFFF), size: 14),
                    const SizedBox(width: 6),
                    Text(
                      '${_alliances.length} Alliances',
                      style: const TextStyle(color: Color(0xFF00CFFF), fontSize: 12),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFFFF6B6B).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFFFF6B6B).withOpacity(0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.restart_alt, color: Color(0xFFFF6B6B), size: 14),
                    const SizedBox(width: 6),
                    const Text(
                      'Double Elimination',
                      style: TextStyle(color: Color(0xFFFF6B6B), fontSize: 12),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              IconButton(
                icon: _isGenerating
                    ? const SizedBox(
                        width: 18, height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Color(0xFFFFD700)))
                    : const Icon(Icons.refresh, color: Color(0xFFFFD700), size: 18),
                onPressed: _isGenerating ? null : _loadData,
                tooltip: 'Refresh',
              ),
            ],
          ),
        ),

        // Bracket visualization
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: roundOrder
                  .where((round) => matchesByRound.containsKey(round))
                  .map((round) {
                final roundMatches = matchesByRound[round]!;
                final color = _getRoundColor(round);
                final icon = _getRoundIcon(round);
                
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Round header
                    Container(
                      margin: const EdgeInsets.symmetric(vertical: 12),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: color.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(30),
                        border: Border.all(color: color.withOpacity(0.3)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            icon,
                            style: TextStyle(color: color, fontSize: 16),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            round.toUpperCase(),
                            style: TextStyle(
                              color: color,
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
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

                    // Matches in this round
                    ...roundMatches.map((match) {
                      final hasBothTeams = match['alliance1_id'] != null && match['alliance2_id'] != null;
                      final isPlayed = match['winner_alliance_id'] != null;
                      final matchColor = round.contains('Upper') 
                          ? const Color(0xFF00CFFF)
                          : round.contains('Lower')
                              ? const Color(0xFFFF6B6B)
                              : const Color(0xFFFFD700);

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
                            color: isPlayed
                                ? Colors.green.withOpacity(0.5)
                                : matchColor.withOpacity(0.3),
                            width: isPlayed ? 2 : 1,
                          ),
                        ),
                        child: Column(
                          children: [
                            // Alliances
                            Row(
                              children: [
                                // Alliance 1
                                Expanded(
                                  child: GestureDetector(
                                    onTap: hasBothTeams && !isPlayed ? () => _showMatchScoreDialog(match) : null,
                                    child: Container(
                                      padding: const EdgeInsets.all(12),
                                      decoration: BoxDecoration(
                                        color: match['winner_alliance_id'] != null && 
                                               match['winner_alliance_id'].toString() == match['alliance1_id']?.toString()
                                            ? Colors.green.withOpacity(0.15)
                                            : matchColor.withOpacity(0.1),
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(
                                          color: match['winner_alliance_id'] != null && 
                                                 match['winner_alliance_id'].toString() == match['alliance1_id']?.toString()
                                              ? Colors.green
                                              : matchColor.withOpacity(0.3),
                                        ),
                                      ),
                                      child: Column(
                                        children: [
                                          Text(
                                            '#${match['alliance1_id'] != null ? _getAllianceRank(match['alliance1_id']) : '?'}',
                                            style: TextStyle(
                                              color: matchColor,
                                              fontSize: 10,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            match['alliance1_name'] ?? 'TBD',
                                            textAlign: TextAlign.center,
                                            style: TextStyle(
                                              color: match['alliance1_id'] != null 
                                                  ? Colors.white 
                                                  : Colors.white38,
                                              fontSize: 11,
                                              fontWeight: FontWeight.bold,
                                            ),
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),

                                // VS / Result
                                Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 8),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: isPlayed
                                          ? Colors.green.withOpacity(0.15)
                                          : matchColor.withOpacity(0.15),
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                        color: isPlayed
                                            ? Colors.green.withOpacity(0.3)
                                            : matchColor.withOpacity(0.3),
                                      ),
                                    ),
                                    child: Text(
                                      isPlayed ? 'WINNER' : 'VS',
                                      style: TextStyle(
                                        color: isPlayed ? Colors.green : matchColor,
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ),

                                // Alliance 2
                                Expanded(
                                  child: GestureDetector(
                                    onTap: hasBothTeams && !isPlayed ? () => _showMatchScoreDialog(match) : null,
                                    child: Container(
                                      padding: const EdgeInsets.all(12),
                                      decoration: BoxDecoration(
                                        color: match['winner_alliance_id'] != null && 
                                               match['winner_alliance_id'].toString() == match['alliance2_id']?.toString()
                                            ? Colors.green.withOpacity(0.15)
                                            : matchColor.withOpacity(0.1),
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(
                                          color: match['winner_alliance_id'] != null && 
                                                 match['winner_alliance_id'].toString() == match['alliance2_id']?.toString()
                                              ? Colors.green
                                              : matchColor.withOpacity(0.3),
                                        ),
                                      ),
                                      child: Column(
                                        children: [
                                          Text(
                                            '#${match['alliance2_id'] != null ? _getAllianceRank(match['alliance2_id']) : '?'}',
                                            style: TextStyle(
                                              color: matchColor,
                                              fontSize: 10,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            match['alliance2_name'] ?? 'TBD',
                                            textAlign: TextAlign.center,
                                            style: TextStyle(
                                              color: match['alliance2_id'] != null 
                                                  ? Colors.white 
                                                  : Colors.white38,
                                              fontSize: 11,
                                              fontWeight: FontWeight.bold,
                                            ),
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ],
                                      ),
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
                                      color: Colors.white38,
                                      size: 12,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      match['schedule_time'] ?? '--:--',
                                      style: TextStyle(
                                        color: Colors.white.withOpacity(0.5),
                                        fontSize: 10,
                                      ),
                                    ),
                                  ],
                                ),

                                // Status
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: isPlayed
                                        ? Colors.green.withOpacity(0.15)
                                        : hasBothTeams
                                            ? Colors.orange.withOpacity(0.15)
                                            : Colors.grey.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: isPlayed
                                          ? Colors.green.withOpacity(0.3)
                                          : hasBothTeams
                                              ? Colors.orange.withOpacity(0.3)
                                              : Colors.grey.withOpacity(0.2),
                                    ),
                                  ),
                                  child: Text(
                                    isPlayed ? 'COMPLETED' : 
                                    hasBothTeams ? 'READY' : 'PENDING',
                                    style: TextStyle(
                                      color: isPlayed ? Colors.green : 
                                             hasBothTeams ? Colors.orange : Colors.grey,
                                      fontSize: 8,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),

                                // Next match info
                                if (match['next_match_id_winner'] != null && isPlayed)
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: matchColor.withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Row(
                                      children: [
                                        Icon(
                                          Icons.arrow_forward,
                                          color: matchColor,
                                          size: 10,
                                        ),
                                        const SizedBox(width: 2),
                                        Text(
                                          'Advances',
                                          style: TextStyle(
                                            color: matchColor,
                                            fontSize: 8,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ],
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
              }).toList(),
            ),
          ),
        ),
      ],
    );
  }

  String _getAllianceRank(dynamic allianceId) {
    if (allianceId == null) return '?';
    final alliance = _alliances.firstWhere(
      (a) => a['alliance_id'].toString() == allianceId.toString(),
      orElse: () => {'alliance_rank': '?'}
    );
    return alliance['alliance_rank']?.toString() ?? '?';
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
}