// championship_settings.dart
import 'package:flutter/material.dart';

class ChampionshipSettings {
  final int categoryId;
  int matchesPerAlliance;
  TimeOfDay startTime;
  TimeOfDay endTime;
  int durationMinutes;
  int intervalMinutes;
  bool lunchBreakEnabled;
  
  ChampionshipSettings({
    required this.categoryId,
    required this.matchesPerAlliance,
    required this.startTime,
    required this.endTime,
    required this.durationMinutes,
    required this.intervalMinutes,
    required this.lunchBreakEnabled,
  });
  
  // Factory constructor for default settings
  // Change the default matchesPerAlliance from 1 to 3
factory ChampionshipSettings.defaults(int categoryId) {
  return ChampionshipSettings(
    categoryId: categoryId,
    matchesPerAlliance: 3,  // Change from 1 to 3
    startTime: const TimeOfDay(hour: 13, minute: 0),
    endTime: const TimeOfDay(hour: 17, minute: 0),
    durationMinutes: 10,
    intervalMinutes: 5,
    lunchBreakEnabled: true,
  );
}
  
  // Convert to Map for database storage
  Map<String, dynamic> toMap() {
    return {
      'category_id': categoryId,
      'matches_per_alliance': matchesPerAlliance,
      'start_time': '${startTime.hour.toString().padLeft(2, '0')}:${startTime.minute.toString().padLeft(2, '0')}',
      'end_time': '${endTime.hour.toString().padLeft(2, '0')}:${endTime.minute.toString().padLeft(2, '0')}',
      'duration_minutes': durationMinutes,
      'interval_minutes': intervalMinutes,
      'lunch_break_enabled': lunchBreakEnabled ? 1 : 0,
    };
  }
  
  // Create from database row
  factory ChampionshipSettings.fromMap(Map<String, dynamic> map) {
    final startTimeStr = map['start_time']?.toString() ?? '13:00';
    final endTimeStr = map['end_time']?.toString() ?? '17:00';
    
    final startParts = startTimeStr.split(':');
    final endParts = endTimeStr.split(':');
    
    return ChampionshipSettings(
      categoryId: int.parse(map['category_id'].toString()),
      matchesPerAlliance: int.parse(map['matches_per_alliance']?.toString() ?? '1'),
      startTime: TimeOfDay(
        hour: int.parse(startParts[0]),
        minute: int.parse(startParts.length > 1 ? startParts[1] : '0'),
      ),
      endTime: TimeOfDay(
        hour: int.parse(endParts[0]),
        minute: int.parse(endParts.length > 1 ? endParts[1] : '0'),
      ),
      durationMinutes: int.parse(map['duration_minutes']?.toString() ?? '10'),
      intervalMinutes: int.parse(map['interval_minutes']?.toString() ?? '5'),
      lunchBreakEnabled: (map['lunch_break_enabled']?.toString() ?? '1') == '1',
    );
  }
  
  // Create a copy with updated values
  ChampionshipSettings copyWith({
    int? matchesPerAlliance,
    TimeOfDay? startTime,
    TimeOfDay? endTime,
    int? durationMinutes,
    int? intervalMinutes,
    bool? lunchBreakEnabled,
  }) {
    return ChampionshipSettings(
      categoryId: categoryId,
      matchesPerAlliance: matchesPerAlliance ?? this.matchesPerAlliance,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      durationMinutes: durationMinutes ?? this.durationMinutes,
      intervalMinutes: intervalMinutes ?? this.intervalMinutes,
      lunchBreakEnabled: lunchBreakEnabled ?? this.lunchBreakEnabled,
    );
  }
  
  // Format time for display
  String formatTime(TimeOfDay time) {
    final period = time.hour < 12 ? 'AM' : 'PM';
    final h12 = time.hourOfPeriod == 0 ? 12 : time.hourOfPeriod;
    return '${h12.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')} $period';
  }
  
  // Get start time as string for database
  String get startTimeString => 
      '${startTime.hour.toString().padLeft(2, '0')}:${startTime.minute.toString().padLeft(2, '0')}';
  
  // Get end time as string for database
  String get endTimeString => 
      '${endTime.hour.toString().padLeft(2, '0')}:${endTime.minute.toString().padLeft(2, '0')}';
  
  // Check if settings are valid
  bool get isValid {
    final startMinutes = startTime.hour * 60 + startTime.minute;
    final endMinutes = endTime.hour * 60 + endTime.minute;
    return endMinutes > startMinutes && durationMinutes > 0 && intervalMinutes >= 0;
  }
  
  // Get total minutes needed for one match (duration + interval)
  int get matchCycleMinutes => durationMinutes + intervalMinutes;
  
  // Estimate maximum matches possible within time window
  int get maxPossibleMatches {
    final startMinutes = startTime.hour * 60 + startTime.minute;
    final endMinutes = endTime.hour * 60 + endTime.minute;
    final totalAvailableMinutes = endMinutes - startMinutes;
    
    // Account for lunch break if enabled
    int lunchBreakMinutes = 0;
    if (lunchBreakEnabled) {
      // Lunch break is from 12:00 to 13:00 (60 minutes)
      // Check if the schedule overlaps with lunch
      if (startMinutes < 12 * 60 && endMinutes > 13 * 60) {
        lunchBreakMinutes = 60;
      } else if (startMinutes >= 12 * 60 && startMinutes < 13 * 60) {
        // Starts during lunch
        lunchBreakMinutes = (13 * 60 - startMinutes);
      } else if (endMinutes > 12 * 60 && endMinutes <= 13 * 60) {
        // Ends during lunch
        lunchBreakMinutes = (endMinutes - 12 * 60);
      }
    }
    
    final adjustedMinutes = totalAvailableMinutes - lunchBreakMinutes;
    if (adjustedMinutes <= 0) return 0;
    
    return (adjustedMinutes / matchCycleMinutes).floor();
  }
}