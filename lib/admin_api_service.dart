import 'package:http/http.dart' as http;
import 'dart:convert';

class AdminApiService {
  static const String baseUrl = 'http://175.20.0.41/roboventure_api';
  
  static Future<List<Map<String, dynamic>>> getQualifiedTeams(int categoryId) async {
    final url = Uri.parse('$baseUrl/admin_alliance_selection.php?action=get_qualified_teams&category_id=$categoryId');
    
    try {
      final response = await http.get(url);
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true) {
          return List<Map<String, dynamic>>.from(data['teams']);
        }
      }
      return [];
    } catch (e) {
      print('Error getting qualified teams: $e');
      return [];
    }
  }
  
  static Future<int> saveAlliance({
    required int categoryId,
    required int captainTeamId,
    required int partnerTeamId,
    required int selectionRound,
  }) async {
    final url = Uri.parse('$baseUrl/admin_alliance_selection.php?action=save_alliance');
    
    final response = await http.post(
      url,
      headers: {'Content-Type': 'application/json'},
      body: json.encode({
        'category_id': categoryId,
        'captain_team_id': captainTeamId,
        'partner_team_id': partnerTeamId,
        'selection_round': selectionRound,
      }),
    );
    
    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      if (data['success'] == true) {
        return data['alliance_id'];
      }
    }
    throw Exception('Failed to save alliance');
  }
  
  static Future<List<Map<String, dynamic>>> getAlliances(int categoryId) async {
    final url = Uri.parse('$baseUrl/admin_alliance_selection.php?action=get_alliances&category_id=$categoryId');
    
    try {
      final response = await http.get(url);
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true) {
          return List<Map<String, dynamic>>.from(data['alliances']);
        }
      }
      return [];
    } catch (e) {
      print('Error getting alliances: $e');
      return [];
    }
  }
}