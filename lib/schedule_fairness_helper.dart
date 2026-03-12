import 'dart:math';
import 'db_helper.dart';

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
    
    // For arena 1 (RED)
    if (arenaNumber == 1) {
      // Can't exceed max red appearances
      if (data.redCount >= targetRed) return false;
    }
    // For arena 2 (BLUE)
    else {
      // Can't exceed max blue appearances
      if (data.blueCount >= targetBlue) return false;
    }
    
    return true;
  }
  
  // Check if a match configuration is fair
  bool isMatchFair(List<int> redTeamIds, List<int> blueTeamIds, int round) {
    // Check each team's arena constraints
    for (final teamId in redTeamIds) {
      if (!canPlaceInArena(teamId, 1, round)) return false;
    }
    for (final teamId in blueTeamIds) {
      if (!canPlaceInArena(teamId, 2, round)) return false;
    }
    
    // Relaxed partner/opponent constraints for now
    // You can gradually increase strictness
    
    return true;
  }
  
  // Check if teams have been partners too often (relaxed version)
  bool haveBeenPartnersTooOften(int teamId1, int teamId2) {
    final data1 = teamData[teamId1];
    final data2 = teamData[teamId2];
    if (data1 == null || data2 == null) return false;
    
    // Count how many times they've been partners
    int partnerCount = 0;
    for (final round in data1.partners.keys) {
      if (data1.partners[round]?.contains(teamId2) == true) {
        partnerCount++;
      }
    }
    
    // Allow up to 2 partner occurrences
    return partnerCount >= (totalRuns ~/ 2);
  }
  
  // Check if teams have been opponents too often (relaxed version)
  bool haveBeenOpponentsTooOften(int teamId1, int teamId2) {
    final data1 = teamData[teamId1];
    final data2 = teamData[teamId2];
    if (data1 == null || data2 == null) return false;
    
    // Count how many times they've been opponents
    int opponentCount = 0;
    for (final round in data1.opponents.keys) {
      if (data1.opponents[round]?.contains(teamId2) == true) {
        opponentCount++;
      }
    }
    
    // Allow up to 2 opponent occurrences
    return opponentCount >= (totalRuns ~/ 2);
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
        
        // Record partners
        data.partners[round] = <int>[];
        for (final partnerId in redTeamIds) {
          if (partnerId != teamId) {
            data.partners[round]!.add(partnerId);
          }
        }
        
        // Record opponents
        data.opponents[round] = List<int>.from(blueTeamIds);
      }
    }
    
    // Record BLUE teams
    for (final teamId in blueTeamIds) {
      final data = teamData[teamId];
      if (data != null) {
        data.playedRounds.add(round);
        data.blueCount++;
        data.arenaHistory[round] = 2;
        
        // Record partners
        data.partners[round] = <int>[];
        for (final partnerId in blueTeamIds) {
          if (partnerId != teamId) {
            data.partners[round]!.add(partnerId);
          }
        }
        
        // Record opponents
        data.opponents[round] = List<int>.from(redTeamIds);
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
      
      // Check red/blue balance (allow difference of 1)
      if ((data.redCount - targetRed).abs() > 1 || 
          (data.blueCount - targetBlue).abs() > 1) {
        print("  ⚠️  Red/Blue imbalance detected!");
        isFair = false;
      }
      
      // Check if any team missed a round
      for (int round = 1; round <= totalRuns; round++) {
        if (!data.playedRounds.contains(round)) {
          print("  ⚠️  Team ${data.teamName} did not play in round $round");
          isFair = false;
        }
      }
    }
    
    return isFair;
  }
}

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
}