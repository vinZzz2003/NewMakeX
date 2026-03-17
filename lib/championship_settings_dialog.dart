// championship_settings_dialog.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'championship_settings.dart';
import 'constants.dart';

class ChampionshipSettingsDialog extends StatefulWidget {
  final ChampionshipSettings settings;
  final Function(ChampionshipSettings) onSave;

  const ChampionshipSettingsDialog({
    super.key,
    required this.settings,
    required this.onSave,
  });

  @override
  State<ChampionshipSettingsDialog> createState() => _ChampionshipSettingsDialogState();
}

class _ChampionshipSettingsDialogState extends State<ChampionshipSettingsDialog> {
  late int _matchesPerAlliance;
  late TimeOfDay _startTime;
  late TimeOfDay _endTime;
  late int _durationMinutes;
  late int _intervalMinutes;
  late bool _lunchBreakEnabled;

  final _durationController = TextEditingController();
  final _intervalController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _matchesPerAlliance = widget.settings.matchesPerAlliance;
    _startTime = widget.settings.startTime;
    _endTime = widget.settings.endTime;
    _durationMinutes = widget.settings.durationMinutes;
    _intervalMinutes = widget.settings.intervalMinutes;
    _lunchBreakEnabled = widget.settings.lunchBreakEnabled;

    _durationController.text = _durationMinutes.toString();
    _intervalController.text = _intervalMinutes.toString();

    _durationController.addListener(() => setState(() {}));
    _intervalController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _durationController.dispose();
    _intervalController.dispose();
    super.dispose();
  }

  bool get _timeError {
    return (_endTime.hour * 60 + _endTime.minute) <=
        (_startTime.hour * 60 + _startTime.minute);
  }

  Future<void> _pickTime(bool isStart) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: isStart ? _startTime : _endTime,
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.dark(
            primary: kAccentGold,
            onPrimary: Colors.black,
            surface: Color(0xFF2D0E7A),
            onSurface: Colors.white,
          ),
          timePickerTheme: TimePickerThemeData(
            dialHandColor: kAccentGold,
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
        if (isStart) {
          _startTime = picked;
        } else {
          _endTime = picked;
        }
      });
    }
  }

  String _formatTime(TimeOfDay t) {
    final period = t.hour < 12 ? 'AM' : 'PM';
    final h12 = t.hourOfPeriod == 0 ? 12 : t.hourOfPeriod;
    return '${h12.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')} $period';
  }

  Widget _buildTimeTile({
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
          border: Border.all(color: kAccentGold.withOpacity(0.25)),
        ),
        child: Row(children: [
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: kAccentGold.withOpacity(0.1),
            ),
            child: const Icon(Icons.access_time_rounded,
                size: 14, color: kAccentGold),
          ),
          const SizedBox(width: 10),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label,
                style: TextStyle(fontSize: 9,
                    color: Colors.white.withOpacity(0.4),
                    fontWeight: FontWeight.bold, letterSpacing: 0.5)),
            Text(_formatTime(time),
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
    required Color color,
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
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
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
              borderSide: BorderSide(color: color, width: 2),
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
    final duration = int.tryParse(_durationController.text.trim()) ?? 10;
    final breakMins = int.tryParse(_intervalController.text.trim()) ?? 5;
    if (duration <= 0) return const SizedBox.shrink();

    int h = _startTime.hour, m = _startTime.minute;

    String fmt(int hour, int min) {
      final total = hour * 60 + min;
      final th = total ~/ 60;
      final tm = total % 60;
      final period = th < 12 ? 'AM' : 'PM';
      final h12 = th % 12 == 0 ? 12 : th % 12;
      return '${h12.toString().padLeft(2, '0')}:${tm.toString().padLeft(2, '0')} $period';
    }

    final m1Start = fmt(h, m);
    final m1End = fmt(h, m + duration);
    final m2Start = fmt(h, m + duration + breakMins);
    final m2End = fmt(h, m + duration + breakMins + duration);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: kAccentGold.withOpacity(0.06),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: kAccentGold.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.schedule_rounded, size: 11, color: kAccentGold),
            const SizedBox(width: 5),
            const Text('EXAMPLE TIMING',
                style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold,
                    color: kAccentGold, letterSpacing: 1)),
          ]),
          const SizedBox(height: 8),
          _previewRow('Match 1', m1Start, m1End, kAccentGold),
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
          _previewRow('Match 2', m2Start, m2End, kAccentEmerald),
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

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        width: 500,
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF2D0E7A), Color(0xFF1E0A5A)],
          ),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: kAccentGold.withOpacity(0.4), width: 1.5),
          boxShadow: [
            BoxShadow(
              color: kAccentGold.withOpacity(0.15),
              blurRadius: 40,
              spreadRadius: 4,
            ),
          ],
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
                    shape: BoxShape.circle,
                    color: kAccentGold.withOpacity(0.15),
                    border: Border.all(color: kAccentGold.withOpacity(0.3)),
                  ),
                  child: const Icon(Icons.settings_rounded, 
                      color: kAccentGold, size: 22),
                ),
                const SizedBox(width: 14),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('CHAMPIONSHIP SETTINGS',
                          style: TextStyle(color: Colors.white,
                              fontSize: 16, fontWeight: FontWeight.w800,
                              letterSpacing: 1.5)),
                      Text('Configure championship match schedule',
                          style: TextStyle(color: Colors.white54,
                              fontSize: 11)),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white38),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 20),
            
            Container(height: 1, color: kAccentGold.withOpacity(0.2)),
            const SizedBox(height: 20),

            // Matches per alliance
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('MATCHES PER ALLIANCE',
                          style: TextStyle(color: Colors.white,
                              fontWeight: FontWeight.w700, fontSize: 11,
                              letterSpacing: 1)),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8),
                              height: 48,
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.05),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: kAccentGold.withOpacity(0.3)),
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Center(
                                      child: Text(
                                        '$_matchesPerAlliance',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 20,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ),
                                  Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      InkWell(
                                        onTap: () => setState(() {
                                          if (_matchesPerAlliance < 5) {
                                            _matchesPerAlliance++;
                                          }
                                        }),
                                        child: const Icon(Icons.keyboard_arrow_up,
                                            color: kAccentGold, size: 20),
                                      ),
                                      InkWell(
                                        onTap: () => setState(() {
                                          if (_matchesPerAlliance > 1) {
                                            _matchesPerAlliance--;
                                          }
                                        }),
                                        child: const Icon(Icons.keyboard_arrow_down,
                                            color: kAccentGold, size: 20),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Time settings
            _buildTimeTile(
              label: 'START TIME',
              time: _startTime,
              isStart: true,
            ),
            const SizedBox(height: 10),
            _buildTimeTile(
              label: 'END TIME',
              time: _endTime,
              isStart: false,
            ),
            
            if (_timeError) ...[
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
            
            // Duration and interval
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _buildNumberField(
                    label: 'DURATION',
                    subtitle: 'minutes per match',
                    controller: _durationController,
                    color: kAccentGold,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildNumberField(
                    label: 'INTERVAL',
                    subtitle: 'minutes between',
                    controller: _intervalController,
                    color: kAccentEmerald,
                  ),
                ),
              ],
            ),
            
            const SizedBox(height: 16),
            
            // Timing preview
            _buildTimingPreview(),
            
            const SizedBox(height: 16),
            
            // Lunch break toggle
            GestureDetector(
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
                    activeThumbColor: const Color(0xFFFFD700),
                    inactiveThumbColor: Colors.white24,
                    inactiveTrackColor: Colors.white12,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ]),
              ),
            ),
            
            const SizedBox(height: 24),
            
            // Action buttons
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
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
                    onPressed: () {
                      final duration = int.tryParse(_durationController.text.trim()) ?? 10;
                      final interval = int.tryParse(_intervalController.text.trim()) ?? 5;
                      
                      if (duration <= 0) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Duration must be greater than 0'),
                            backgroundColor: Colors.red,
                          ),
                        );
                        return;
                      }
                      
                      if (_timeError) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('End time must be after start time'),
                            backgroundColor: Colors.red,
                          ),
                        );
                        return;
                      }
                      
                      final updatedSettings = ChampionshipSettings(
                        categoryId: widget.settings.categoryId,
                        matchesPerAlliance: _matchesPerAlliance,
                        startTime: _startTime,
                        endTime: _endTime,
                        durationMinutes: duration,
                        intervalMinutes: interval,
                        lunchBreakEnabled: _lunchBreakEnabled,
                      );
                      
                      widget.onSave(updatedSettings);
                      Navigator.pop(context);
                    },
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
                            colors: [Color(0xFFFFD700), Color(0xFFCCAC00)]),
                        borderRadius: BorderRadius.circular(10),
                        boxShadow: [
                          BoxShadow(
                              color: kAccentGold.withOpacity(0.4),
                              blurRadius: 16,
                              spreadRadius: 1),
                        ],
                      ),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        alignment: Alignment.center,
                        child: const Text('SAVE SETTINGS',
                            style: TextStyle(color: Colors.black,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 1)),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}