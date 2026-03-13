import 'dart:math';

// Single unified fairness class used throughout the app
class TeamFairnessData {
  final int teamId;
  final String teamName;
  final int totalRuns;
  
  int redCount = 0;
  int blueCount = 0;
  Set<int> playedRounds = {};
  Map<int, int> arenaHistory = {}; // round -> arena
  Map<int, List<int>> partners = {}; // round -> partner teamIds
  Map<int, List<int>> opponents = {}; // round -> opponent teamIds
  
  TeamFairnessData({
    required this.teamId,
    required this.teamName,
    required this.totalRuns,
  });

  // Helper for verification display
  Map<String, dynamic> toMap() {
    return {
      'teamId': teamId,
      'teamName': teamName,
      'red': redCount,
      'blue': blueCount,
      'rounds': playedRounds.toList(),
      'roundArena': arenaHistory,
    };
  }
}

class FairnessTracker {
  final int categoryId;
  final int totalRuns;
  final Map<int, TeamFairnessData> teamData = {};
  
  FairnessTracker(this.categoryId, this.totalRuns, List<Map<String, dynamic>> teams) {
    for (final team in teams) {
      final teamId = int.parse(team['team_id'].toString());
      teamData[teamId] = TeamFairnessData(
        teamId: teamId,
        teamName: team['team_name'].toString(),
        totalRuns: totalRuns,
      );
    }
  }
  
  // Check if a team can be placed in a specific arena for a round
  bool canPlaceInArena(int teamId, int arenaNumber, int round) {
    final data = teamData[teamId];
    if (data == null) return false;
    
    // Check if team already played this round
    if (data.playedRounds.contains(round)) return false;
    
    final targetRed = (totalRuns / 2).ceil();
    final targetBlue = (totalRuns / 2).floor();
    
    // MORE FLEXIBLE: Allow up to targetRed + 1 for RED if needed
    if (arenaNumber == 1) {
      if (data.redCount > targetRed) return false; // Allow equal to targetRed
    }
    else {
      if (data.blueCount > targetBlue) return false;
    }
    
    return true;
  }
  
  // Check if a match configuration is fair - MORE RELAXED
  bool isMatchFair(List<int> redTeamIds, List<int> blueTeamIds, int round) {
    // Check each team's arena constraints
    for (final teamId in redTeamIds) {
      if (!canPlaceInArena(teamId, 1, round)) return false;
    }
    for (final teamId in blueTeamIds) {
      if (!canPlaceInArena(teamId, 2, round)) return false;
    }
    
    return true; // Removed partner/opponent constraints for now
  }
  
  // Record a match
  void recordMatch(List<int> redTeamIds, List<int> blueTeamIds, int round) {
    // Record RED teams
    for (final teamId in redTeamIds) {
      final data = teamData[teamId];
      if (data != null) {
        data.playedRounds.add(round);
        data.redCount++;
        data.arenaHistory[round] = 1;
      }
    }
    
    // Record BLUE teams
    for (final teamId in blueTeamIds) {
      final data = teamData[teamId];
      if (data != null) {
        data.playedRounds.add(round);
        data.blueCount++;
        data.arenaHistory[round] = 2;
      }
    }
  }
  
  // Verify final fairness
  bool verifyFairness() {
    bool isFair = true;
    print("\n=== FAIRNESS VERIFICATION FOR CATEGORY $categoryId ===");
    
    final targetRed = (totalRuns / 2).ceil();
    final targetBlue = (totalRuns / 2).floor();
    
    for (final entry in teamData.entries) {
      final data = entry.value;
      
      print("${data.teamName}: RED=${data.redCount} (target: $targetRed), BLUE=${data.blueCount} (target: $targetBlue) | " +
            "Rounds played: ${data.playedRounds.join(', ')}");
      
      // Check red/blue balance (allow difference of 2)
      if ((data.redCount - targetRed).abs() > 1 || 
          (data.blueCount - targetBlue).abs() > 1) {
        print("  ⚠️  Red/Blue imbalance detected!");
        isFair = false;
      }
      
      // Check if any team missed a round - but don't fail verification
      for (int round = 1; round <= totalRuns; round++) {
        if (!data.playedRounds.contains(round)) {
          print("  ⚠️  Team ${data.teamName} did not play in round $round");
          isFair = false;
        }
      }
    }
    
    return isFair;
  }

  // Get fairness stats for verification
  Map<int, Map<String, dynamic>> getFairnessStats() {
    final stats = <int, Map<String, dynamic>>{};
    for (final entry in teamData.entries) {
      stats[entry.key] = entry.value.toMap();
    }
    return stats;
  }
}