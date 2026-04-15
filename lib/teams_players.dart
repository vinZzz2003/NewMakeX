import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'db_helper.dart';

// ── Accent palette per category index ────────────────────────────────────────
const _kCatColors = [
  Color(0xFF00CFFF), // blue
  Color(0xFF967BB6), // lavender
  Color(0xFFFFD700), // gold
  Color(0xFF00E5A0), // emerald
  Color(0xFFFF6B6B), // coral
  Color(0xFFFF8C42), // orange
];

Color _catColor(int index) => _kCatColors[index % _kCatColors.length];

// ─────────────────────────────────────────────────────────────────────────────
class TeamsPlayers extends StatefulWidget {
  final VoidCallback? onBack;
  const TeamsPlayers({super.key, this.onBack});

  @override
  State<TeamsPlayers> createState() => _TeamsPlayersState();
}

class _TeamsPlayersState extends State<TeamsPlayers>
    with TickerProviderStateMixin {
  TabController? _tabController;
  List<Map<String, dynamic>> _categories = [];

  // category_id → all teams
  Map<int, List<Map<String, dynamic>>> _teamsByCategory = {};
  // team_id → players
  Map<int, List<Map<String, dynamic>>> _playersByTeam = {};

  bool _isLoading = true;
  DateTime? _lastUpdated;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _loadData();
    _refreshTimer = Timer.periodic(
        const Duration(seconds: 15), (_) => _loadData(silent: true));
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _tabController?.dispose();
    super.dispose();
  }

  // ── Load all data ─────────────────────────────────────────────────────────
  Future<void> _loadData({bool silent = false}) async {
    if (!silent) setState(() => _isLoading = true);
    try {
      final categories = await DBHelper.getCategories();
      final conn = await DBHelper.getConnection();

      // Load all teams with mentor info
      final Map<int, List<Map<String, dynamic>>> teamsByCategory = {};
      for (final cat in categories) {
        final catId = int.tryParse(cat['category_id'].toString()) ?? 0;
        final teams = await DBHelper.getTeamsByCategory(catId);
        teamsByCategory[catId] = teams;
      }

      // Load all players grouped by team
      final playerResult = await conn.execute("""
        SELECT
          p.player_id,
          p.player_name,
          p.player_ispresent,
          p.team_id
        FROM tbl_player p
        ORDER BY p.team_id, p.player_name
      """);
      final Map<int, List<Map<String, dynamic>>> playersByTeam = {};
      for (final row in playerResult.rows) {
        final r = row.assoc();
        final teamId = int.tryParse(r['team_id']?.toString() ?? '0') ?? 0;
        playersByTeam.putIfAbsent(teamId, () => []).add(r);
      }

      final prevIndex = _tabController?.index ?? 0;
      _tabController?.dispose();
      _tabController = TabController(
        length: categories.length,
        vsync: this,
        initialIndex: prevIndex.clamp(0, (categories.length - 1).clamp(0, 999)),
      );

      setState(() {
        _categories = categories;
        _teamsByCategory = teamsByCategory;
        _playersByTeam = playersByTeam;
        _isLoading = false;
        _lastUpdated = DateTime.now();
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('❌ Failed to load: $e'),
          backgroundColor: Colors.red,
        ));
      }
    }
  }

  // ── Export to CSV ─────────────────────────────────────────────────────────
  Future<void> _exportTeamsToCSV() async {
    try {
      String csv = "Team Name,Mentor,Category,Present,Players\n";

      for (final category in _categories) {
        final catId = int.parse(category['category_id'].toString());
        final teams = _teamsByCategory[catId] ?? [];

        for (final team in teams) {
          final teamId = int.parse(team['team_id'].toString());
          final players = _playersByTeam[teamId] ?? [];
          final playerNames = players.map((p) => p['player_name']).join('; ');

          csv += '"${team['team_name']}",';
          csv += '"${team['mentor_name']}",';
          csv += '"${category['category_type']}",';
          csv += "${team['team_ispresent'] == '1' ? 'Yes' : 'No'},";
          csv += '"$playerNames"\n';
        }
      }

      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/teams_export_${DateTime.now().millisecondsSinceEpoch}.csv');
      await file.writeAsString(csv);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ Exported to ${file.path}'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      print('Export error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Export failed: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0720),
      body: Column(
        children: [
          _buildHeader(),
          if (_isLoading)
            const Expanded(
              child: Center(
                child: CircularProgressIndicator(color: Color(0xFF00CFFF)),
              ),
            )
          else if (_categories.isEmpty)
            const Expanded(
              child: Center(
                child: Text('No categories found.',
                    style: TextStyle(color: Colors.white38, fontSize: 16)),
              ),
            )
          else ...[
            _buildTabBar(),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: _categories.asMap().entries.map((e) {
                  final catId = int.tryParse(
                          e.value['category_id'].toString()) ??
                      0;
                  return _CategoryView(
                    category: e.value,
                    catIndex: e.key,
                    teams: _teamsByCategory[catId] ?? [],
                    playersByTeam: _playersByTeam,
                    lastUpdated: _lastUpdated,
                    onBack: widget.onBack,
                    onRefresh: () => _loadData(),
                    onExport: _exportTeamsToCSV,
                  );
                }).toList(),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ── Tab bar ───────────────────────────────────────────────────────────────
  Widget _buildTabBar() {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF130A30),
        border: Border(bottom: BorderSide(color: Color(0xFF2A1560), width: 1)),
      ),
      child: TabBar(
        controller: _tabController,
        isScrollable: true,
        indicatorWeight: 3,
        indicatorColor: const Color(0xFF00CFFF),
        labelColor: Colors.white,
        unselectedLabelColor: Colors.white38,
        labelStyle: const TextStyle(
            fontWeight: FontWeight.bold, fontSize: 12, letterSpacing: 1.2),
        tabs: _categories.asMap().entries.map((e) {
          final catId = int.tryParse(e.value['category_id'].toString()) ?? 0;
          final teams = _teamsByCategory[catId] ?? [];
          final present =
              teams.where((t) => t['team_ispresent'].toString() == '1').length;
          final accent = _catColor(e.key);
          return Tab(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 8),
                  Text((e.value['category_type'] ?? '').toString().toUpperCase()),
                  const SizedBox(width: 8),
                  // Present count badge
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.green.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.green.withOpacity(0.4), width: 1),
                    ),
                    child: Text('$present',
                        style: const TextStyle(
                            color: Colors.green,
                            fontSize: 10,
                            fontWeight: FontWeight.bold)),
                  ),
                  const SizedBox(width: 4),
                  // Absent count badge
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.red.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.red.withOpacity(0.35), width: 1),
                    ),
                    child: Text('${teams.length - present}',
                        style: const TextStyle(
                            color: Colors.redAccent,
                            fontSize: 10,
                            fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  // ── App header ────────────────────────────────────────────────────────────
  Widget _buildHeader() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF1A0550), Color(0xFF2D0E7A), Color(0xFF1A0A4A)],
        ),
        border: Border(bottom: BorderSide(color: Color(0xFF00CFFF), width: 1.5)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          RichText(
            text: const TextSpan(children: [
              TextSpan(
                  text: 'Make',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.bold)),
              TextSpan(
                  text: 'bl',
                  style: TextStyle(
                      color: Color(0xFF00CFFF),
                      fontSize: 22,
                      fontWeight: FontWeight.bold)),
              TextSpan(
                  text: 'ock',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.bold)),
            ]),
          ),
          Image.asset('assets/images/CenterLogo.png', height: 70, fit: BoxFit.contain),
          const Text('CREOTEC',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 3)),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Category view — split into PRESENT / ABSENT columns
// ─────────────────────────────────────────────────────────────────────────────
class _CategoryView extends StatefulWidget {
  final Map<String, dynamic> category;
  final int catIndex;
  final List<Map<String, dynamic>> teams;
  final Map<int, List<Map<String, dynamic>>> playersByTeam;
  final DateTime? lastUpdated;
  final VoidCallback? onBack;
  final VoidCallback onRefresh;
  final VoidCallback onExport;

  const _CategoryView({
    required this.category,
    required this.catIndex,
    required this.teams,
    required this.playersByTeam,
    required this.lastUpdated,
    required this.onRefresh,
    required this.onExport,
    this.onBack,
  });

  @override
  State<_CategoryView> createState() => _CategoryViewState();
}

class _CategoryViewState extends State<_CategoryView> {
  String _searchQuery = '';
  bool _showPresentOnly = false;

  List<Map<String, dynamic>> get _filteredTeams {
    var filtered = widget.teams;
    if (_searchQuery.isNotEmpty) {
      filtered = filtered.where((t) =>
          t['team_name'].toString().toLowerCase().contains(_searchQuery.toLowerCase()) ||
          t['mentor_name'].toString().toLowerCase().contains(_searchQuery.toLowerCase())).toList();
    }
    if (_showPresentOnly) {
      filtered = filtered.where((t) => t['team_ispresent'].toString() == '1').toList();
    }
    return filtered;
  }

  int get _totalTeams => widget.teams.length;
  int get _presentCount => widget.teams.where((t) => t['team_ispresent'].toString() == '1').length;
  int get _absentCount => _totalTeams - _presentCount;

  @override
  Widget build(BuildContext context) {
    final accent = _catColor(widget.catIndex);
    final categoryName = (widget.category['category_type'] ?? '').toString().toUpperCase();
    final present = widget.teams.where((t) => t['team_ispresent'].toString() == '1').toList();
    final absent = widget.teams.where((t) => t['team_ispresent'].toString() != '1').toList();

    final filteredPresent = present.where((t) => _filteredTeams.contains(t)).toList();
    final filteredAbsent = absent.where((t) => _filteredTeams.contains(t)).toList();

    return Column(
      children: [
        // ── Search Bar ─────────────────────────────────────────────────────
        _buildSearchBar(),

        // ── Stats Summary Cards ───────────────────────────────────────────
        _buildStatsSummary(),

        // ── Category title bar ─────────────────────────────────────────
        Container(
          decoration: BoxDecoration(
            color: const Color(0xFF130A30),
            border: Border(bottom: BorderSide(color: accent.withOpacity(0.3), width: 1)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
          child: Row(
            children: [
              // Category name + stats
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: [
                    accent.withOpacity(0.18),
                    accent.withOpacity(0.05),
                  ]),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: accent.withOpacity(0.35)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.category_rounded, color: accent, size: 16),
                    const SizedBox(width: 10),
                    Text(categoryName,
                        style: TextStyle(
                            color: accent,
                            fontWeight: FontWeight.w900,
                            fontSize: 15,
                            letterSpacing: 1.5)),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              // Stats row
              _statChip(Icons.groups_rounded, '${widget.teams.length}', 'TOTAL',
                  Colors.white54, Colors.white12),
              const SizedBox(width: 8),
              _statChip(Icons.check_circle_rounded, '${_presentCount}', 'PRESENT',
                  Colors.green, Colors.green.withOpacity(0.12)),
              const SizedBox(width: 8),
              _statChip(Icons.cancel_rounded, '${_absentCount}', 'ABSENT',
                  Colors.redAccent, Colors.red.withOpacity(0.10)),
              const Spacer(),
              // Live + refresh + export
              _LiveIndicator(lastUpdated: widget.lastUpdated),
              const SizedBox(width: 8),
              IconButton(
                tooltip: 'Refresh',
                icon: const Icon(Icons.refresh_rounded, color: Color(0xFF00CFFF), size: 20),
                onPressed: widget.onRefresh,
              ),
              IconButton(
                tooltip: 'Export CSV',
                icon: const Icon(Icons.download_rounded, color: Color(0xFF00E5A0), size: 20),
                onPressed: widget.onExport,
              ),
              if (widget.onBack != null)
                IconButton(
                  tooltip: 'Back',
                  icon: const Icon(Icons.arrow_back_ios_new, color: Color(0xFF00CFFF), size: 18),
                  onPressed: widget.onBack,
                ),
            ],
          ),
        ),

        // ── Column headers ─────────────────────────────────────────────
        Container(
          color: const Color(0xFF0F0828),
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 8),
          child: Row(
            children: [
              Expanded(
                child: _sectionHeader(
                    Icons.check_circle_outline_rounded,
                    'PRESENT',
                    '${filteredPresent.length} team${filteredPresent.length != 1 ? 's' : ''}',
                    Colors.green),
              ),
              Container(
                  width: 1, height: 36, color: Colors.white.withOpacity(0.08)),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(left: 20),
                  child: _sectionHeader(
                      Icons.cancel_outlined,
                      'ABSENT',
                      '${filteredAbsent.length} team${filteredAbsent.length != 1 ? 's' : ''}',
                      Colors.redAccent),
                ),
              ),
            ],
          ),
        ),

        // ── Two-column team list ───────────────────────────────────────
Expanded(
  child: _filteredTeams.isEmpty
      ? Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.search_off_rounded, color: Colors.white24, size: 48),
              const SizedBox(height: 12),
              Text('No teams match your search',
                  style: TextStyle(color: Colors.white24, fontSize: 14)),
            ],
          ),
        )
      : Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // PRESENT column
            Expanded(
              child: _TeamColumn(
                teams: filteredPresent,
                playersByTeam: widget.playersByTeam,
                accent: Colors.green,
                isEmpty: filteredPresent.isEmpty,
                emptyLabel: 'No teams present',
                catIndex: widget.catIndex,
                isPresent: true,
                onTeamUpdated: widget.onRefresh,  // Add this
              ),
            ),
            // Divider
            Container(
              width: 1,
              color: Colors.white.withOpacity(0.06),
            ),
            // ABSENT column
            Expanded(
              child: _TeamColumn(
                teams: filteredAbsent,
                playersByTeam: widget.playersByTeam,
                accent: Colors.redAccent,
                isEmpty: filteredAbsent.isEmpty,
                emptyLabel: 'All teams present!',
                catIndex: widget.catIndex,
                isPresent: false,
                onTeamUpdated: widget.onRefresh,  // Add this
              ),
            ),
          ],
        ),
),
      ],
    );
  }

  Widget _buildSearchBar() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF0F0828),
        border: Border(bottom: BorderSide(color: Colors.white.withOpacity(0.05))),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Search team or mentor...',
                hintStyle: TextStyle(color: Colors.white.withOpacity(0.3)),
                prefixIcon: const Icon(Icons.search, color: Color(0xFF00CFFF), size: 20),
                filled: true,
                fillColor: Colors.white.withOpacity(0.05),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 18, color: Colors.white54),
                        onPressed: () => setState(() => _searchQuery = ''),
                      )
                    : null,
              ),
              onChanged: (value) => setState(() => _searchQuery = value),
            ),
          ),
          const SizedBox(width: 12),
          FilterChip(
            label: const Text('Present Only'),
            labelStyle: TextStyle(
              color: _showPresentOnly ? Colors.black : Colors.white70,
              fontSize: 12,
            ),
            selected: _showPresentOnly,
            onSelected: (v) => setState(() => _showPresentOnly = v),
            backgroundColor: Colors.white.withOpacity(0.05),
            selectedColor: const Color(0xFF00E5A0),
            checkmarkColor: Colors.black,
          ),
        ],
      ),
    );
  }

  Widget _buildStatsSummary() {
    return Container(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          _statCard('TOTAL', _totalTeams, const Color(0xFF00CFFF)),
          const SizedBox(width: 12),
          _statCard('PRESENT', _presentCount, const Color(0xFF00E5A0)),
          const SizedBox(width: 12),
          _statCard('ABSENT', _absentCount, const Color(0xFFFF5252)),
        ],
      ),
    );
  }

  Widget _statCard(String label, int count, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [color.withOpacity(0.15), color.withOpacity(0.05)],
          ),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Column(
          children: [
            Text(
              count.toString(),
              style: TextStyle(
                color: color,
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              label,
              style: TextStyle(
                color: color.withOpacity(0.7),
                fontSize: 10,
                fontWeight: FontWeight.w600,
                letterSpacing: 1,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _statChip(IconData icon, String value, String label, Color color, Color bg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withOpacity(0.3))),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 14),
          const SizedBox(width: 6),
          Text(value,
              style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 13)),
          const SizedBox(width: 4),
          Text(label,
              style: TextStyle(color: color.withOpacity(0.7), fontSize: 9, letterSpacing: 1)),
        ],
      ),
    );
  }

  Widget _sectionHeader(IconData icon, String title, String sub, Color color) {
    return Row(
      children: [
        Icon(icon, color: color, size: 16),
        const SizedBox(width: 8),
        Text(title,
            style: TextStyle(
                color: color,
                fontWeight: FontWeight.w900,
                fontSize: 12,
                letterSpacing: 1.5)),
        const SizedBox(width: 8),
        Text(sub, style: TextStyle(color: color.withOpacity(0.5), fontSize: 10)),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Scrollable column of team cards
// ─────────────────────────────────────────────────────────────────────────────
class _TeamColumn extends StatelessWidget {
  final List<Map<String, dynamic>> teams;
  final Map<int, List<Map<String, dynamic>>> playersByTeam;
  final Color accent;
  final bool isEmpty;
  final String emptyLabel;
  final int catIndex;
  final bool isPresent;
  final VoidCallback onTeamUpdated;  // Add this

  const _TeamColumn({
    required this.teams,
    required this.playersByTeam,
    required this.accent,
    required this.isEmpty,
    required this.emptyLabel,
    required this.catIndex,
    required this.isPresent,
    required this.onTeamUpdated,  // Add this
  });

  @override
  Widget build(BuildContext context) {
    if (isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              isPresent ? Icons.group_off_rounded : Icons.celebration_rounded,
              color: accent.withOpacity(0.2),
              size: 48,
            ),
            const SizedBox(height: 12),
            Text(emptyLabel,
                style: TextStyle(color: accent.withOpacity(0.4), fontSize: 13)),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: teams.length,
      itemBuilder: (context, index) {
        final team = teams[index];
        final teamId = int.tryParse(team['team_id']?.toString() ?? '0') ?? 0;
        final players = playersByTeam[teamId] ?? [];
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: _TeamCard(
            team: team,
            players: players,
            accent: accent,
            catIndex: catIndex,
            cardIndex: index,
            isPresent: isPresent,
            onTeamUpdated: onTeamUpdated,  // Pass it down
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Expandable team card with player list and edit/delete functionality
// ─────────────────────────────────────────────────────────────────────────────
class _TeamCard extends StatefulWidget {
  final Map<String, dynamic> team;
  final List<Map<String, dynamic>> players;
  final Color accent;
  final int catIndex;
  final int cardIndex;
  final bool isPresent;
  final VoidCallback onTeamUpdated;

  const _TeamCard({
    required this.team,
    required this.players,
    required this.accent,
    required this.catIndex,
    required this.cardIndex,
    required this.isPresent,
    required this.onTeamUpdated,
  });

  @override
  State<_TeamCard> createState() => _TeamCardState();
}

class _TeamCardState extends State<_TeamCard> with SingleTickerProviderStateMixin {
  bool _expanded = false;
  late AnimationController _ctrl;
  late Animation<double> _expandAnim;
  bool _hovered = false;
  bool _isUpdating = false;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 220));
    _expandAnim = CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _toggle() {
    setState(() => _expanded = !_expanded);
    _expanded ? _ctrl.forward() : _ctrl.reverse();
  }

  String _formatDate(String? dateStr) {
    if (dateStr == null || dateStr.isEmpty) return '';
    try {
      final date = DateTime.parse(dateStr);
      return '${date.month}/${date.day}/${date.year}';
    } catch (e) {
      return dateStr;
    }
  }

  // Get team presence status
  bool get isTeamPresent => widget.team['team_ispresent'].toString() == '1';
  String get teamStatusText => isTeamPresent ? 'PRESENT' : 'ABSENT';
  Color get teamStatusColor => isTeamPresent ? Colors.green : Colors.redAccent;
  IconData get teamStatusIcon => isTeamPresent ? Icons.check_circle : Icons.cancel;

  // ── Toggle Team Presence ───────────────────────────────────────────────
  Future<void> _toggleTeamPresence() async {
    final newPresent = !isTeamPresent;
    final oldPresent = isTeamPresent;
    
    // Update UI locally immediately
    setState(() {
      widget.team['team_ispresent'] = newPresent ? '1' : '0';
    });
    
    try {
      final teamId = int.parse(widget.team['team_id'].toString());
      await DBHelper.executeDual(
        "UPDATE tbl_team SET team_ispresent = :present WHERE team_id = :teamId",
        {"present": newPresent ? 1 : 0, "teamId": teamId},
      );
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(newPresent ? '✅ Team marked present' : '⚠️ Team marked absent'),
            backgroundColor: newPresent ? Colors.green : Colors.orange,
            duration: const Duration(seconds: 1),
          ),
        );
      }
    } catch (e) {
      // Revert on error
      setState(() {
        widget.team['team_ispresent'] = oldPresent ? '1' : '0';
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('❌ Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _showEditTeamDialog() {
  final teamNameController = TextEditingController(text: widget.team['team_name']?.toString() ?? '');
  final mentorNameController = TextEditingController(text: widget.team['mentor_name']?.toString() ?? '');
  bool present = isTeamPresent;
  
  // Store old values for rollback
  final oldTeamName = widget.team['team_name']?.toString() ?? '';
  final oldMentorName = widget.team['mentor_name']?.toString() ?? '—';
  final oldPresent = isTeamPresent;

  showDialog(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setDialogState) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          width: 400,
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF2D0E7A), Color(0xFF1E0A5A)],
            ),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: widget.accent.withOpacity(0.4), width: 1.5),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: widget.accent.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(Icons.edit, color: widget.accent, size: 20),
                  ),
                  const SizedBox(width: 12),
                  const Text('EDIT TEAM',
                      style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white54),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              // Team Name
              _buildDialogField(
                label: 'TEAM NAME',
                controller: teamNameController,
                icon: Icons.group,
                accent: widget.accent,
              ),
              const SizedBox(height: 16),
              // Mentor Name
              _buildDialogField(
                label: 'MENTOR NAME',
                controller: mentorNameController,
                icon: Icons.person,
                accent: widget.accent,
              ),
              const SizedBox(height: 16),
              // Present Toggle
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    Icon(teamStatusIcon, color: teamStatusColor, size: 20),
                    const SizedBox(width: 12),
                    const Text('TEAM STATUS',
                        style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold)),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      decoration: BoxDecoration(
                        color: teamStatusColor.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: teamStatusColor.withOpacity(0.3)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(teamStatusIcon, color: teamStatusColor, size: 14),
                          const SizedBox(width: 4),
                          Text(teamStatusText,
                              style: TextStyle(color: teamStatusColor, fontSize: 11, fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  const Text('CHANGE STATUS?',
                      style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold)),
                  const Spacer(),
                  Switch(
                    value: present,
                    onChanged: (v) => setDialogState(() => present = v),
                    activeColor: widget.accent,
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(ctx),
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: Colors.white.withOpacity(0.2)),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      child: const Text('CANCEL', style: TextStyle(color: Colors.white54)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => _updateTeam(
                        teamName: teamNameController.text.trim(),
                        mentorName: mentorNameController.text.trim(),
                        isPresent: present,
                        oldTeamName: oldTeamName,
                        oldMentorName: oldMentorName,
                        oldPresent: oldPresent,
                        dialogContext: ctx,  // Fixed: use dialogContext instead of context
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: widget.accent,
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      child: _isUpdating
                          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Text('SAVE CHANGES', style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

  Widget _buildDialogField({
    required String label,
    required TextEditingController controller,
    required IconData icon,
    required Color accent,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(color: accent, fontSize: 11, fontWeight: FontWeight.bold)),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            prefixIcon: Icon(icon, color: accent, size: 20),
            filled: true,
            fillColor: Colors.white.withOpacity(0.05),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide.none,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: Colors.white.withOpacity(0.15)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: accent, width: 2),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _updateTeam({
  required String teamName,
  required String mentorName,
  required bool isPresent,
  required String oldTeamName,
  required String oldMentorName,
  required bool oldPresent,
  required BuildContext dialogContext,  // Changed from 'context' to 'dialogContext'
}) async {
  // Update UI locally immediately
  setState(() {
    widget.team['team_name'] = teamName;
    widget.team['mentor_name'] = mentorName;
    widget.team['team_ispresent'] = isPresent ? '1' : '0';
  });
  
  setState(() => _isUpdating = true);
  
  try {
    final conn = await DBHelper.getConnection();
    final teamId = int.parse(widget.team['team_id'].toString());
    final mentorId = widget.team['mentor_id'] != null 
        ? int.parse(widget.team['mentor_id'].toString()) 
        : null;

    // Update team
    await DBHelper.executeDual(
      "UPDATE tbl_team SET team_name = :name, team_ispresent = :present WHERE team_id = :teamId",
      {"name": teamName, "present": isPresent ? 1 : 0, "teamId": teamId},
    );

    // Update mentor name if changed
    if (mentorId != null && mentorName.isNotEmpty) {
      await DBHelper.executeDual(
        "UPDATE tbl_mentor SET mentor_name = :name WHERE mentor_id = :mentorId",
        {"name": mentorName, "mentorId": mentorId},
      );
    }

    if (mounted) {
      ScaffoldMessenger.of(dialogContext).showSnackBar(
        const SnackBar(content: Text('✅ Team updated successfully'), backgroundColor: Colors.green),
      );
      Navigator.pop(dialogContext);
    }
  } catch (e) {
    // Revert on error
    setState(() {
      widget.team['team_name'] = oldTeamName;
      widget.team['mentor_name'] = oldMentorName;
      widget.team['team_ispresent'] = oldPresent ? '1' : '0';
    });
    if (mounted) {
      ScaffoldMessenger.of(dialogContext).showSnackBar(
        SnackBar(content: Text('❌ Error: $e'), backgroundColor: Colors.red),
      );
    }
  } finally {
    if (mounted) setState(() => _isUpdating = false);
  }
}

  // ── Delete Team Dialog ───────────────────────────────────────────────
  void _showDeleteTeamDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF2D0E7A),
        title: const Text('Delete Team?', style: TextStyle(color: Colors.white)),
        content: Text(
          'Are you sure you want to delete "${widget.team['team_name']}"?\n\nThis will also delete all players in this team. This action cannot be undone.',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('CANCEL', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            onPressed: () => _deleteTeam(ctx),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            child: const Text('DELETE', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteTeam(BuildContext ctx) async {
    try {
      final conn = await DBHelper.getConnection();
      final teamId = int.parse(widget.team['team_id'].toString());

      await DBHelper.executeDual("DELETE FROM tbl_player WHERE team_id = :teamId", {"teamId": teamId});
      await DBHelper.executeDual("DELETE FROM tbl_team WHERE team_id = :teamId", {"teamId": teamId});

      if (mounted) {
        Navigator.pop(ctx);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('🗑️ Team deleted successfully'), backgroundColor: Colors.orange),
        );
        widget.onTeamUpdated();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('❌ Error deleting team: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  // ── Toggle Player Presence (Local Update - No Flicker) ───────────────────
  Future<void> _togglePlayerPresence(int playerId, bool currentPresent) async {
    final newPresent = !currentPresent;
    
    setState(() {
      final playerIndex = widget.players.indexWhere((p) => 
          int.parse(p['player_id'].toString()) == playerId);
      if (playerIndex != -1) {
        widget.players[playerIndex]['player_ispresent'] = newPresent ? '1' : '0';
      }
    });
    
    try {
      await DBHelper.executeDual(
        "UPDATE tbl_player SET player_ispresent = :present WHERE player_id = :playerId",
        {"present": newPresent ? 1 : 0, "playerId": playerId},
      );
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(newPresent ? '✅ Player marked present' : '⚠️ Player marked absent'),
            backgroundColor: newPresent ? Colors.green : Colors.orange,
            duration: const Duration(seconds: 1),
          ),
        );
      }
    } catch (e) {
      setState(() {
        final playerIndex = widget.players.indexWhere((p) => 
            int.parse(p['player_id'].toString()) == playerId);
        if (playerIndex != -1) {
          widget.players[playerIndex]['player_ispresent'] = currentPresent ? '1' : '0';
        }
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('❌ Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  // ── Edit Player Dialog ───────────────────────────────────────────────
  void _showEditPlayerDialog(Map<String, dynamic> player) {
    final playerNameController = TextEditingController(text: player['player_name']?.toString() ?? '');
    final playerId = int.parse(player['player_id'].toString());
    bool isPresent = player['player_ispresent'].toString() == '1';
    
    final oldName = player['player_name']?.toString() ?? '';
    final oldPresent = player['player_ispresent'].toString() == '1';

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => Dialog(
          backgroundColor: Colors.transparent,
          child: Container(
            width: 350,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF2D0E7A), Color(0xFF1E0A5A)],
              ),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: widget.accent.withOpacity(0.4), width: 1.5),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: widget.accent.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(Icons.edit, color: widget.accent, size: 18),
                    ),
                    const SizedBox(width: 12),
                    const Text('EDIT PLAYER',
                        style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white54),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: playerNameController,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    labelText: 'PLAYER NAME',
                    labelStyle: TextStyle(color: widget.accent),
                    prefixIcon: Icon(Icons.person, color: widget.accent),
                    filled: true,
                    fillColor: Colors.white.withOpacity(0.05),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    const Text('PRESENT?', style: TextStyle(color: Colors.white70)),
                    const Spacer(),
                    Switch(
                      value: isPresent,
                      onChanged: (v) => setDialogState(() => isPresent = v),
                      activeColor: widget.accent,
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: const Text('CANCEL', style: TextStyle(color: Colors.white54)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () async {
                          final newName = playerNameController.text.trim();
                          final newPresent = isPresent;
                          
                          setState(() {
                            final playerIndex = widget.players.indexWhere((p) => 
                                int.parse(p['player_id'].toString()) == playerId);
                            if (playerIndex != -1) {
                              widget.players[playerIndex]['player_name'] = newName;
                              widget.players[playerIndex]['player_ispresent'] = newPresent ? '1' : '0';
                            }
                          });
                          
                          try {
                            await DBHelper.executeDual(
                              "UPDATE tbl_player SET player_name = :name, player_ispresent = :present WHERE player_id = :playerId",
                              {
                                "name": newName,
                                "present": newPresent ? 1 : 0,
                                "playerId": playerId,
                              },
                            );
                            if (mounted) {
                              Navigator.pop(ctx);
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('✅ Player updated'), backgroundColor: Colors.green),
                              );
                            }
                          } catch (e) {
                            setState(() {
                              final playerIndex = widget.players.indexWhere((p) => 
                                  int.parse(p['player_id'].toString()) == playerId);
                              if (playerIndex != -1) {
                                widget.players[playerIndex]['player_name'] = oldName;
                                widget.players[playerIndex]['player_ispresent'] = oldPresent ? '1' : '0';
                              }
                            });
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('❌ Error: $e'), backgroundColor: Colors.red),
                              );
                            }
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: widget.accent,
                          foregroundColor: Colors.black,
                        ),
                        child: const Text('SAVE'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Delete Player Dialog ───────────────────────────────────────────────
  void _showDeletePlayerDialog(int playerId, String playerName) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF2D0E7A),
        title: const Text('Remove Player?', style: TextStyle(color: Colors.white)),
        content: Text(
          'Remove "$playerName" from this team?',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('CANCEL', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            onPressed: () async {
              try {
                await DBHelper.executeDual(
                  "DELETE FROM tbl_player WHERE player_id = :playerId",
                  {"playerId": playerId},
                );
                if (mounted) {
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('🗑️ Player removed'), backgroundColor: Colors.orange),
                  );
                  widget.onTeamUpdated();
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('❌ Error: $e'), backgroundColor: Colors.red),
                  );
                }
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            child: const Text('REMOVE', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final team = widget.team;
    final teamName = (team['team_name'] ?? '').toString();
    final teamId = team['team_id']?.toString() ?? '';
    final mentorName = team['mentor_name']?.toString() ?? '—';
    final accent = widget.accent;

    final presentPlayers =
        widget.players.where((p) => p['player_ispresent'].toString() == '1').length;
    final totalPlayers = widget.players.length;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: _hovered ? accent.withOpacity(0.6) : accent.withOpacity(0.2),
            width: 1.5,
          ),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              accent.withOpacity(_hovered ? 0.10 : 0.05),
              const Color(0xFF0D0720),
            ],
          ),
          boxShadow: _hovered
              ? [BoxShadow(color: accent.withOpacity(0.15), blurRadius: 16, spreadRadius: 1)]
              : [],
        ),
        child: Column(
          children: [
            // ── Card header ──────────────────────────────────────────
            InkWell(
              onTap: widget.players.isNotEmpty ? _toggle : null,
              borderRadius: BorderRadius.circular(14),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
                child: Row(
                  children: [
                    // Team ID badge with status indicator
                    GestureDetector(
                      onTap: _showEditTeamDialog,
                      child: Stack(
                        children: [
                          Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: accent.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: accent.withOpacity(0.3), width: 1),
                            ),
                            child: Center(
                              child: Text(
                                '#$teamId',
                                style: TextStyle(
                                    color: accent, fontWeight: FontWeight.w900, fontSize: 11),
                              ),
                            ),
                          ),
                          // Status indicator dot on badge
                          Positioned(
                            right: 0,
                            bottom: 0,
                            child: Container(
                              width: 12,
                              height: 12,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: teamStatusColor,
                                border: Border.all(color: Colors.white, width: 1.5),
                                boxShadow: [
                                  BoxShadow(
                                    color: teamStatusColor.withOpacity(0.5),
                                    blurRadius: 4,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),

                    // Team name + mentor + status
                    Expanded(
                      child: GestureDetector(
                        onTap: _showEditTeamDialog,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    teamName,
                                    style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w800,
                                        fontSize: 14,
                                        letterSpacing: 0.3),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                // Team status badge
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: teamStatusColor.withOpacity(0.15),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(color: teamStatusColor.withOpacity(0.3)),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(teamStatusIcon, color: teamStatusColor, size: 10),
                                      const SizedBox(width: 3),
                                      Text(
                                        teamStatusText,
                                        style: TextStyle(
                                          color: teamStatusColor,
                                          fontSize: 8,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 3),
                            Row(
                              children: [
                                Icon(Icons.person_outline_rounded, color: Colors.white38, size: 12),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Text(
                                    mentorName,
                                    style: const TextStyle(color: Colors.white38, fontSize: 11),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),

                    // Player count pill
                    if (totalPlayers > 0)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.06),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: Colors.white.withOpacity(0.12)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.people_alt_rounded, color: Colors.white38, size: 12),
                            const SizedBox(width: 5),
                            Text(
                              '$presentPlayers/$totalPlayers',
                              style: const TextStyle(
                                  color: Colors.white54, fontSize: 11, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      ),

                    const SizedBox(width: 8),

                    // Edit and Delete buttons
                    IconButton(
                      icon: Icon(Icons.edit_outlined, color: accent.withOpacity(0.7), size: 18),
                      onPressed: _showEditTeamDialog,
                      tooltip: 'Edit Team',
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                    IconButton(
                      icon: Icon(Icons.delete_outline, color: Colors.redAccent.withOpacity(0.7), size: 18),
                      onPressed: _showDeleteTeamDialog,
                      tooltip: 'Delete Team',
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),

                    const SizedBox(width: 4),

                    // Expand chevron
                    if (widget.players.isNotEmpty)
                      AnimatedRotation(
                        turns: _expanded ? 0.5 : 0.0,
                        duration: const Duration(milliseconds: 220),
                        child: Icon(Icons.keyboard_arrow_down_rounded,
                            color: accent.withOpacity(0.7), size: 20),
                      ),
                  ],
                ),
              ),
            ),

            // ── Expandable player list ───────────────────────────────
            SizeTransition(
              sizeFactor: _expandAnim,
              child: Column(
                children: [
                  Container(
                    height: 1,
                    margin: const EdgeInsets.symmetric(horizontal: 16),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(colors: [
                        Colors.transparent,
                        accent.withOpacity(0.3),
                        Colors.transparent,
                      ]),
                    ),
                  ),
                  // Player grid header
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
                    child: Row(
                      children: [
                        const Expanded(
                          flex: 3,
                          child: Text('PLAYER',
                              style: TextStyle(
                                  color: Colors.white24,
                                  fontSize: 9,
                                  letterSpacing: 1.5,
                                  fontWeight: FontWeight.bold)),
                        ),
                        const Expanded(
                          flex: 2,
                          child: Text('STATUS',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  color: Colors.white24,
                                  fontSize: 9,
                                  letterSpacing: 1.5,
                                  fontWeight: FontWeight.bold)),
                        ),
                        const SizedBox(width: 60),
                      ],
                    ),
                  ),
                  // Player rows
                  ...widget.players.asMap().entries.map((e) {
                    final p = e.value;
                    final playerPresent = p['player_ispresent'].toString() == '1';
                    final fullName = p['player_name']?.toString() ?? '';
                    final playerId = int.parse(p['player_id'].toString());
                    final isEven = e.key % 2 == 0;

                    return Container(
                      color: isEven ? Colors.white.withOpacity(0.02) : Colors.transparent,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: Row(
                        children: [
                          // Player avatar + name
                          Expanded(
                            flex: 3,
                            child: GestureDetector(
                              onTap: () => _showEditPlayerDialog(p),
                              child: Row(
                                children: [
                                  Container(
                                    width: 28,
                                    height: 28,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: playerPresent
                                          ? Colors.green.withOpacity(0.15)
                                          : Colors.red.withOpacity(0.12),
                                      border: Border.all(
                                        color: playerPresent
                                            ? Colors.green.withOpacity(0.4)
                                            : Colors.red.withOpacity(0.3),
                                      ),
                                    ),
                                    child: Center(
                                      child: Text(
                                        fullName.isNotEmpty ? fullName[0].toUpperCase() : '?',
                                        style: TextStyle(
                                          color: playerPresent ? Colors.green : Colors.redAccent,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      fullName,
                                      style: const TextStyle(color: Colors.white70, fontSize: 12),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          // Status badge (clickable to toggle)
                          Expanded(
                            flex: 2,
                            child: Center(
                              child: GestureDetector(
                                onTap: () => _togglePlayerPresence(playerId, playerPresent),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: playerPresent
                                        ? Colors.green.withOpacity(0.12)
                                        : Colors.red.withOpacity(0.10),
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(
                                      color: playerPresent
                                          ? Colors.green.withOpacity(0.4)
                                          : Colors.red.withOpacity(0.35),
                                      width: 1,
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Container(
                                        width: 6,
                                        height: 6,
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          color: playerPresent ? Colors.green : Colors.redAccent,
                                          boxShadow: [
                                            BoxShadow(
                                              color: playerPresent
                                                  ? Colors.green.withOpacity(0.5)
                                                  : Colors.red.withOpacity(0.4),
                                              blurRadius: 4,
                                            )
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 5),
                                      Text(
                                        playerPresent ? 'Present' : 'Absent',
                                        style: TextStyle(
                                          color: playerPresent ? Colors.green : Colors.redAccent,
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                          // Edit/Delete player buttons
                          SizedBox(
                            width: 60,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                IconButton(
                                  icon: Icon(Icons.edit_outlined, size: 14, color: Colors.white38),
                                  onPressed: () => _showEditPlayerDialog(p),
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(),
                                ),
                                IconButton(
                                  icon: Icon(Icons.delete_outline, size: 14, color: Colors.redAccent.withOpacity(0.5)),
                                  onPressed: () => _showDeletePlayerDialog(playerId, fullName),
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                  const SizedBox(height: 10),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Live indicator widget
// ─────────────────────────────────────────────────────────────────────────────
class _LiveIndicator extends StatefulWidget {
  final DateTime? lastUpdated;
  const _LiveIndicator({this.lastUpdated});

  @override
  State<_LiveIndicator> createState() => _LiveIndicatorState();
}

class _LiveIndicatorState extends State<_LiveIndicator>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))
      ..repeat(reverse: true);
    _anim = Tween<double>(begin: 0.3, end: 1.0)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.lastUpdated;
    final timeStr = t == null
        ? '--:--:--'
        : '${t.hour.toString().padLeft(2, '0')}:'
            '${t.minute.toString().padLeft(2, '0')}:'
            '${t.second.toString().padLeft(2, '0')}';

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        FadeTransition(
          opacity: _anim,
          child: Container(
            width: 7,
            height: 7,
            decoration: const BoxDecoration(color: Color(0xFF00FF88), shape: BoxShape.circle),
          ),
        ),
        const SizedBox(width: 6),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('LIVE',
                style: TextStyle(
                    color: Color(0xFF00FF88),
                    fontSize: 8,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.2)),
            Text(timeStr, style: const TextStyle(color: Colors.white38, fontSize: 8)),
          ],
        ),
      ],
    );
  }
}