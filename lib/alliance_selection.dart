// alliance_selection.dart
import 'package:flutter/material.dart';
import 'dart:async';
import 'constants.dart';
import 'db_helper.dart';

enum SelectionStatus { pending, selecting, accepted, refused, timeout }

class AllianceTeam {
  final int teamId;
  final String teamName;
  final int rank;
  final int totalScore;
  final bool isTop50;
  final bool canRefuse;
  int refusalCount;
  
  AllianceTeam({
    required this.teamId,
    required this.teamName,
    required this.rank,
    required this.totalScore,
    required this.isTop50,
    required this.canRefuse,
    this.refusalCount = 0,
  });
}

class Alliance {
  final AllianceTeam captain;
  final AllianceTeam partner;
  final int round;
  
  Alliance({
    required this.captain,
    required this.partner,
    required this.round,
  });
}

class AllianceSelectionPage extends StatefulWidget {
  final int categoryId;
  final String categoryName;
  final List<Map<String, dynamic>> qualifiedTeams;
  final VoidCallback onComplete;
  final VoidCallback? onCancel;

  const AllianceSelectionPage({
    super.key,
    required this.categoryId,
    required this.categoryName,
    required this.qualifiedTeams,
    required this.onComplete,
    this.onCancel,
  });

  @override
  State<AllianceSelectionPage> createState() => _AllianceSelectionPageState();
}

class _AllianceSelectionPageState extends State<AllianceSelectionPage>
    with TickerProviderStateMixin {
  // Initialize immediately to prevent LateError
  late List<AllianceTeam> _availableTeams = [];
  late List<Alliance> _formedAlliances = [];
  late List<AllianceTeam> _selectionOrder = [];
  
  int _currentSelectorIndex = 0;
  AllianceTeam? _currentSelector;
  SelectionStatus _currentStatus = SelectionStatus.selecting;
  AllianceTeam? _pendingInvitee;
  
  Timer? _selectionTimer;
  int _secondsRemaining = 30;
  late AnimationController _timerController;
  late Animation<double> _timerAnimation;
  
  bool _isComplete = false;
  bool _isInitialized = false;  // Track initialization status
  bool _showTeamSelector = true; // Show team count selector first
  int _teamsToKeep = 0; // Number of teams to keep for alliance selection
  
  String? _statusMessage;
  String? _errorMessage;
  
  final Map<int, int> _refusalCounts = {};
  
  // Current match time display
  String _currentTime = '';

  @override
  void initState() {
    super.initState();
    _updateCurrentTime();
    
    _timerController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 30),
    );
    
    _timerAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _timerController, curve: Curves.linear),
    );
    
    _timerController.addListener(() {
      if (_timerController.isAnimating) {
        setState(() {
          _secondsRemaining = 30 - (_timerController.value * 30).floor();
        });
      }
    });

    // Initialize data after controller is set up
    _initializeAllianceData();

    // Update time every second
    Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        _updateCurrentTime();
      }
    });
  }

  void _updateCurrentTime() {
    final now = DateTime.now();
    setState(() {
      _currentTime = '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}';
    });
  }

  void _initializeAllianceData() {
    try {
      // Sort teams by rank (score)
      final sortedTeams = List<Map<String, dynamic>>.from(widget.qualifiedTeams)
        ..sort((a, b) => (b['totalScore'] as int).compareTo(a['totalScore'] as int));
      
      print("🎯 Alliance Selection - Qualified Teams:");
      for (var team in sortedTeams) {
        print("   ${team['team_name']}: ${team['totalScore']} pts");
      }
      
      // Set default teams to keep (half of total, but must be even)
      _teamsToKeep = (sortedTeams.length / 2).ceil();
      if (_teamsToKeep % 2 != 0) _teamsToKeep++;
      
      // Don't initialize teams yet - wait for user to confirm count
      _availableTeams = [];
      _formedAlliances = [];
      _selectionOrder = [];
      _isInitialized = true;
      
    } catch (e) {
      print("Error initializing alliance data: $e");
      // Ensure lists are at least empty
      _availableTeams = [];
      _formedAlliances = [];
      _selectionOrder = [];
      _isInitialized = false;
      
      setState(() {
        _errorMessage = 'Failed to initialize: $e';
      });
    }
  }

  void _startAllianceSelection() {
    if (_teamsToKeep < 2 || _teamsToKeep > widget.qualifiedTeams.length) {
      setState(() {
        _errorMessage = 'Please select a valid number of teams';
      });
      return;
    }
    
    // Sort teams by rank
    final sortedTeams = List<Map<String, dynamic>>.from(widget.qualifiedTeams)
      ..sort((a, b) => (b['totalScore'] as int).compareTo(a['totalScore'] as int));
    
    // Take only the top N teams
    final topTeams = sortedTeams.take(_teamsToKeep).toList();
    
    print("✅ Keeping top $_teamsToKeep teams for alliance selection");
    print("❌ Eliminating ${sortedTeams.length - _teamsToKeep} teams");
    
    // Convert to AllianceTeam objects
    setState(() {
      _availableTeams = [];
      for (int i = 0; i < topTeams.length; i++) {
        final team = topTeams[i];
        
        // Only the top half of remaining teams can refuse
        final canRefuse = i < (topTeams.length / 2).ceil();
        
        _availableTeams.add(AllianceTeam(
          teamId: team['team_id'] as int,
          teamName: team['team_name'] as String,
          rank: i + 1,
          totalScore: team['totalScore'] as int,
          isTop50: true,
          canRefuse: canRefuse,
        ));
      }
      
      _formedAlliances = [];
      _selectionOrder = List.from(_availableTeams);
      _currentSelectorIndex = 0;
      _currentSelector = _selectionOrder.isNotEmpty ? _selectionOrder.first : null;
      _showTeamSelector = false;
      
      if (_currentSelector != null) {
        _startSelectionTimer();
        _setStatusMessage('${_currentSelector!.teamName} is selecting an alliance partner');
      }
    });
  }

  void _setStatusMessage(String message) {
    _statusMessage = message;
    // Auto-clear after 3 seconds
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted && _statusMessage == message) {
        setState(() {
          _statusMessage = null;
        });
      }
    });
  }

  void _startSelectionTimer() {
    _secondsRemaining = 30;
    _timerController.reset();
    _timerController.forward();
    _currentStatus = SelectionStatus.selecting;
    
    _selectionTimer?.cancel();
    _selectionTimer = Timer(const Duration(seconds: 30), () {
      if (_currentStatus == SelectionStatus.selecting && mounted) {
        _handleTimeout();
      }
    });
  }

  void _handleTimeout() {
    if (!mounted) return;
    setState(() {
      _currentStatus = SelectionStatus.timeout;
      _errorMessage = '${_currentSelector?.teamName} ran out of time';
    });
    
    // Skip this selector - they lose their turn
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) {
        _moveToNextSelector();
      }
    });
  }

  void _moveToNextSelector() {
    if (!mounted) return;
    setState(() {
      _currentSelectorIndex++;
      _errorMessage = null;
      _statusMessage = null;
      
      if (_currentSelectorIndex < _selectionOrder.length) {
        _currentSelector = _selectionOrder[_currentSelectorIndex];
        // Only if this team hasn't been selected yet
        if (_isTeamInAlliance(_currentSelector!.teamId)) {
          // Skip if already in alliance
          _moveToNextSelector();
          return;
        }
        _currentStatus = SelectionStatus.selecting;
        _startSelectionTimer();
        _setStatusMessage('${_currentSelector!.teamName} is selecting an alliance partner');
      } else {
        _checkSelectionComplete();
      }
    });
  }

  void _selectTeam(AllianceTeam selectedTeam) {
    if (_currentStatus != SelectionStatus.selecting) return;
    if (_currentSelector == null) return;
    
    // Can't select own team
    if (_currentSelector!.teamId == selectedTeam.teamId) {
      setState(() {
        _errorMessage = 'Cannot select your own team';
      });
      return;
    }
    
    // Check if selected team is already in an alliance
    if (_isTeamInAlliance(selectedTeam.teamId)) {
      setState(() {
        _errorMessage = '${selectedTeam.teamName} is already in an alliance';
      });
      return;
    }
    
    setState(() {
      _pendingInvitee = selectedTeam;
      _currentStatus = SelectionStatus.pending;
      _setStatusMessage('${_currentSelector!.teamName} invited ${selectedTeam.teamName}');
    });
    
    _selectionTimer?.cancel();
    _timerController.stop();
  }

  void _handleInvitationResponse(bool accepted) {
    if (_pendingInvitee == null || _currentSelector == null) return;
    
    if (accepted) {
      // Alliance formed
      final alliance = Alliance(
        captain: _currentSelector!,
        partner: _pendingInvitee!,
        round: _formedAlliances.length + 1,
      );
      
      setState(() {
        _formedAlliances.add(alliance);
        _currentStatus = SelectionStatus.accepted;
        _setStatusMessage('Alliance formed: ${_currentSelector!.teamName} + ${_pendingInvitee!.teamName}');
        _errorMessage = null;
      });
      
      // Check if all possible alliances are formed
      final int expectedAlliances = _availableTeams.length ~/ 2;
      
      if (_formedAlliances.length >= expectedAlliances) {
        print("🎯 All alliances formed! Saving to database...");
        
        // Save to database - call the method but don't wait for it
        _saveAlliancesToDatabase();
        
        // Show success message briefly
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ All alliances formed successfully!'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 1),
          ),
        );
        
        // Return to previous screen with success result after a short delay
        Future.delayed(const Duration(milliseconds: 500), () {
          if (mounted) {
            Navigator.pop(context, true);
          }
        });
        
        return; // Don't proceed to next selector
      }
      
      // Move to next selector after delay
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) {
          _moveToNextSelector();
        }
      });
      
    } else {
      // Team refused
      if (_pendingInvitee!.canRefuse) {
        if (_pendingInvitee!.refusalCount < 1) {
          setState(() {
            _pendingInvitee!.refusalCount++;
            _currentStatus = SelectionStatus.refused;
            _setStatusMessage('${_pendingInvitee!.teamName} refused the invitation');
            _errorMessage = null;
          });
          
          // Continue selection for current selector
          Future.delayed(const Duration(seconds: 2), () {
            if (mounted) {
              setState(() {
                _currentStatus = SelectionStatus.selecting;
              });
              _startSelectionTimer();
            }
          });
        } else {
          // Already refused once, cannot refuse again
          setState(() {
            _errorMessage = '${_pendingInvitee!.teamName} cannot refuse again';
          });
          
          // Auto-accept
          Future.delayed(const Duration(seconds: 1), () {
            _handleInvitationResponse(true);
          });
        }
      } else {
        // Bottom half cannot refuse - auto-accept
        setState(() {
          _errorMessage = '${_pendingInvitee!.teamName} cannot refuse';
        });
        
        // Auto-accept
        Future.delayed(const Duration(seconds: 1), () {
          _handleInvitationResponse(true);
        });
      }
    }
    
    _pendingInvitee = null;
  }

  bool _isTeamInAlliance(int teamId) {
    for (final alliance in _formedAlliances) {
      if (alliance.captain.teamId == teamId || alliance.partner.teamId == teamId) {
        return true;
      }
    }
    return false;
  }

  void _checkSelectionComplete() {
    print("🔍 Checking if selection is complete");
    print("📊 Available teams: ${_availableTeams.length}");
    print("📊 Formed alliances: ${_formedAlliances.length}");
    
    final int expectedAlliances = _availableTeams.length ~/ 2;
    
    if (_formedAlliances.length >= expectedAlliances) {
      print("🎯 All alliances formed! Saving to database...");
      
      // Save to database
      _saveAlliancesToDatabase();
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ All alliances formed successfully!'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 1),
          ),
        );
        
        Future.delayed(const Duration(milliseconds: 500), () {
          if (mounted) {
            Navigator.pop(context, true);
          }
        });
      }
    } else {
      // If not all alliances formed, this method shouldn't be called
      print("⚠️ _checkSelectionComplete called but not all alliances formed");
    }
  }

  Future<void> _saveAlliancesToDatabase() async {
    // Safety check
    if (!_isInitialized) {
      print("⚠️ Cannot save - not initialized");
      return;
    }
    
    if (_formedAlliances.isEmpty) {
      print("⚠️ No alliances to save");
      return;
    }
    
    try {
      print("💾 Attempting to save ${_formedAlliances.length} alliances to database...");
      
      final conn = await DBHelper.getConnection();
      
      // First, check if the table exists
      try {
        await conn.execute("SELECT 1 FROM tbl_alliance_selections LIMIT 1");
        print("✅ tbl_alliance_selections table exists");
      } catch (e) {
        print("❌ tbl_alliance_selections table does not exist: $e");
        // Try to create the table
        await DBHelper.executeDual("""
          CREATE TABLE IF NOT EXISTS tbl_alliance_selections (
            alliance_id INT AUTO_INCREMENT PRIMARY KEY,
            category_id INT NOT NULL,
            captain_team_id INT NOT NULL,
            partner_team_id INT NOT NULL,
            selection_round INT NOT NULL,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
          )
        """);
        print("✅ Created tbl_alliance_selections table");
      }
      
      // Clear existing alliances for this category
      print("🗑️ Clearing existing alliances for category ${widget.categoryId}");
      await DBHelper.executeDual(
        "DELETE FROM tbl_alliance_selections WHERE category_id = :catId",
        {"catId": widget.categoryId},
      );
      
      // Save new alliances
      for (int i = 0; i < _formedAlliances.length; i++) {
        final alliance = _formedAlliances[i];
        print("📝 Saving alliance ${i + 1}: Captain ${alliance.captain.teamId} (${alliance.captain.teamName}) + Partner ${alliance.partner.teamId} (${alliance.partner.teamName})");
        
        await DBHelper.executeDual("""
          INSERT INTO tbl_alliance_selections 
            (category_id, captain_team_id, partner_team_id, selection_round)
          VALUES
            (:catId, :captainId, :partnerId, :round)
        """, {
          "catId": widget.categoryId,
          "captainId": alliance.captain.teamId,
          "partnerId": alliance.partner.teamId,
          "round": i + 1,
        });
      }
      
      print("✅ Successfully saved ${_formedAlliances.length} alliances to database");
      
      // Verify the save worked
      final verifyResult = await conn.execute(
        "SELECT COUNT(*) as count FROM tbl_alliance_selections WHERE category_id = :catId",
        {"catId": widget.categoryId},
      );
      final count = verifyResult.rows.first.assoc()['count'];
      print("🔍 Verification: Found $count alliances in database for category ${widget.categoryId}");
      
    } catch (e, stackTrace) {
      print("❌ Error saving alliances: $e");
      print(stackTrace);
    }
  }

  void _completeAllianceFormation() {
    print("🎯 _completeAllianceFormation called");
    print("📊 Formed alliances count: ${_formedAlliances.length}");
    
    // Safety check
    if (!_isInitialized) {
      print("⚠️ Cannot complete - not initialized");
      setState(() {
        _errorMessage = "Initialization failed. Please try again.";
      });
      return;
    }
    
    setState(() {
      _isComplete = true;
      _selectionTimer?.cancel();
      _timerController.stop();
    });
    
    // Save alliances to database
    _saveAlliancesToDatabase().then((_) {
      print("✅ Alliance save completed");
      
      // IMPORTANT: Do NOT call widget.onComplete() here
      // Just update UI to show completion screen
      if (mounted) {
        setState(() {
          // UI already updated to show completion screen
        });
      }
    }).catchError((error) {
      print("❌ Alliance save failed: $error");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error saving alliances: $error'),
            backgroundColor: Colors.red,
          ),
        );
      }
    });
  }

  String _formatTeamId(int teamId) {
    return 'C${teamId.toString().padLeft(3, '0')}R';
  }

  Widget _buildTeamSelector() {
    final totalTeams = widget.qualifiedTeams.length;
    final maxTeams = totalTeams - (totalTeams % 2); // Must be even
    
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xFF130840),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFFFD700).withOpacity(0.2)),
      ),
      child: Column(
        children: [
          const Text(
            'SELECT NUMBER OF QUALIFYING TEAMS',
            style: TextStyle(
              color: Color(0xFFFFD700),
              fontSize: 18,
              fontWeight: FontWeight.bold,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Total teams: $totalTeams',
            style: const TextStyle(color: Colors.white70, fontSize: 14),
          ),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                onPressed: _teamsToKeep > 2
                    ? () => setState(() => _teamsToKeep -= 2)
                    : null,
                icon: const Icon(Icons.remove_circle, color: Color(0xFFFFD700), size: 32),
              ),
              Container(
                width: 100,
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E0A5A),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFFFD700).withOpacity(0.3)),
                ),
                child: Text(
                  '$_teamsToKeep',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Color(0xFFFFD700),
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              IconButton(
                onPressed: _teamsToKeep < maxTeams
                    ? () => setState(() => _teamsToKeep += 2)
                    : null,
                icon: const Icon(Icons.add_circle, color: Color(0xFFFFD700), size: 32),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Must be an even number (2, 4, 6, etc.)',
            style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 12),
          ),
          const SizedBox(height: 24),
          Text(
            'This will create ${_teamsToKeep ~/ 2} alliances',
            style: const TextStyle(color: Colors.white, fontSize: 16),
          ),
          const SizedBox(height: 32),
          ElevatedButton(
            onPressed: _startAllianceSelection,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFFD700),
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text(
              'START ALLIANCE CEREMONY',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _selectionTimer?.cancel();
    _timerController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Show loading state while initializing
    if (!_isInitialized) {
      return Scaffold(
        backgroundColor: const Color(0xFF0E0630),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const CircularProgressIndicator(color: Color(0xFFFFD700)),
              const SizedBox(height: 16),
              Text(
                'Initializing alliance selection...',
                style: TextStyle(color: Colors.white.withOpacity(0.7)),
              ),
              if (_errorMessage != null) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.red.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.red.withOpacity(0.3)),
                  ),
                  child: Text(
                    _errorMessage!,
                    style: const TextStyle(color: Colors.red),
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () {
                    setState(() {
                      _errorMessage = null;
                      _initializeAllianceData();
                    });
                  },
                  child: const Text('RETRY'),
                ),
              ],
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFF0E0630),
      body: Column(
        children: [
          _buildHeader(),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Center(
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 1400),
                  child: Column(
                    children: [
                      _buildTitleSection(),
                      const SizedBox(height: 24),
                      if (!_isComplete)
                        _showTeamSelector
                            ? _buildTeamSelector()
                            : _buildSelectionInterface(),
                      if (_isComplete) _buildCompletionInterface(),
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

  Widget _buildHeader() {
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF1A0550), Color(0xFF2D0E7A), Color(0xFF1A0A4A)],
        ),
        border: Border(bottom: BorderSide(color: Color(0xFFFFD700), width: 1.5)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          RichText(
            text: const TextSpan(children: [
              TextSpan(
                text: 'Make',
                style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
              ),
              TextSpan(
                text: 'bl',
                style: TextStyle(color: Color(0xFF00CFFF), fontSize: 22, fontWeight: FontWeight.bold),
              ),
              TextSpan(
                text: 'ock',
                style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
              ),
            ]),
          ),
          Image.asset('assets/images/CenterLogo.png', height: 70, fit: BoxFit.contain),
          const Text(
            'CREOTEC',
            style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold, letterSpacing: 3),
          ),
        ],
      ),
    );
  }

  Widget _buildTitleSection() {
    final totalTeams = widget.qualifiedTeams.length;
    
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF2D0E7A), Color(0xFF1A0A4A)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFFFD700).withOpacity(0.4), width: 2),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFFFFD700).withOpacity(0.15),
              border: Border.all(color: const Color(0xFFFFD700).withOpacity(0.4)),
            ),
            child: const Icon(Icons.people_alt_rounded, color: Color(0xFFFFD700), size: 32),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'ALLIANCE CEREMONY',
                  style: const TextStyle(
                    color: Color(0xFFFFD700),
                    fontSize: 28,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 3,
                  ),
                ),
                Text(
                  widget.categoryName.toUpperCase(),
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.6),
                    fontSize: 14,
                    letterSpacing: 2,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFF00CFFF).withOpacity(0.15),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFF00CFFF).withOpacity(0.3)),
            ),
            child: Row(
              children: [
                const Icon(Icons.emoji_events, color: Color(0xFF00CFFF), size: 16),
                const SizedBox(width: 8),
                Text(
                  '$totalTeams ELIGIBLE TEAMS',
                  style: const TextStyle(color: Color(0xFF00CFFF), fontSize: 12, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSelectionInterface() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Left Column - Alliance Formation
        Expanded(
          flex: 7,
          child: Column(
            children: [
              _buildCurrentSelectorPanel(),
              const SizedBox(height: 16),
              _buildAvailableTeamsPanel(),
            ],
          ),
        ),
        const SizedBox(width: 24),
        // Right Column - Alliance Cards
        Expanded(
          flex: 5,
          child: _buildAllianceCardsPanel(),
        ),
      ],
    );
  }

  Widget _buildCurrentSelectorPanel() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF130840),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFFFD700).withOpacity(0.2)),
      ),
      child: Column(
        children: [
          // Status Message
          if (_statusMessage != null)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFFFD700).withOpacity(0.1),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
              ),
              child: Row(
                children: [
                  Icon(Icons.info, color: const Color(0xFFFFD700), size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _statusMessage!,
                      style: const TextStyle(color: Color(0xFFFFD700), fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),

          // Error Message
          if (_errorMessage != null)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.1),
              ),
              child: Row(
                children: [
                  Icon(Icons.error, color: Colors.red, size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _errorMessage!,
                      style: const TextStyle(color: Colors.red, fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),

          // Current Selector and Timer
          Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                // Selector Info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'CURRENT SELECTOR',
                        style: TextStyle(
                          color: Color(0xFFFFD700),
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.5,
                        ),
                      ),
                      const SizedBox(height: 16),
                      if (_currentSelector != null)
                        Row(
                          children: [
                            Container(
                              width: 60,
                              height: 60,
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [getCategoryColor(_currentSelector!.rank), getCategoryColor(_currentSelector!.rank).withOpacity(0.7)],
                                ),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Center(
                                child: Text(
                                  '#${_currentSelector!.rank}',
                                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 20),
                                ),
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _currentSelector!.teamName,
                                    style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
                                  ),
                                  const SizedBox(height: 4),
                                  Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFF00CFFF).withOpacity(0.15),
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: Text(
                                          _formatTeamId(_currentSelector!.teamId),
                                          style: const TextStyle(color: Color(0xFF00CFFF), fontSize: 11),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        '${_currentSelector!.totalScore} pts',
                                        style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 14),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
                // Timer
                Container(
                  width: 120,
                  height: 120,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFFFFD700).withOpacity(0.3)),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text(
                        'TIME',
                        style: TextStyle(color: Color(0xFFFFD700), fontSize: 12, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      AnimatedBuilder(
                        animation: _timerAnimation,
                        builder: (context, child) {
                          return Stack(
                            alignment: Alignment.center,
                            children: [
                              SizedBox(
                                width: 60,
                                height: 60,
                                child: CircularProgressIndicator(
                                  value: _timerAnimation.value,
                                  strokeWidth: 4,
                                  backgroundColor: Colors.white10,
                                  valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFFFFD700)),
                                ),
                              ),
                              Text(
                                '$_secondsRemaining',
                                style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                              ),
                            ],
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Pending Invitation
          if (_pendingInvitee != null)
            Container(
              margin: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: const Color(0xFF1E0A5A),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFFFD700).withOpacity(0.3)),
              ),
              child: Column(
                children: [
                  const Text(
                    'INVITATION PENDING',
                    style: TextStyle(color: Color(0xFFFFD700), fontSize: 14, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Column(
                        children: [
                          Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              color: getCategoryColor(_currentSelector!.rank).withOpacity(0.2),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Center(
                              child: Text(
                                '#${_currentSelector!.rank}',
                                style: TextStyle(color: getCategoryColor(_currentSelector!.rank), fontWeight: FontWeight.bold),
                              ),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _currentSelector!.teamName,
                            style: const TextStyle(color: Colors.white, fontSize: 12),
                          ),
                        ],
                      ),
                      Container(
                        margin: const EdgeInsets.symmetric(horizontal: 20),
                        child: const Icon(Icons.arrow_forward, color: Color(0xFFFFD700), size: 24),
                      ),
                      Column(
                        children: [
                          Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              color: getCategoryColor(_pendingInvitee!.rank).withOpacity(0.2),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Center(
                              child: Text(
                                '#${_pendingInvitee!.rank}',
                                style: TextStyle(color: getCategoryColor(_pendingInvitee!.rank), fontWeight: FontWeight.bold),
                              ),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _pendingInvitee!.teamName,
                            style: const TextStyle(color: Colors.white, fontSize: 12),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      ElevatedButton(
                        onPressed: () => _handleInvitationResponse(true),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
                        ),
                        child: const Text('ACCEPT', style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                      const SizedBox(width: 16),
                      OutlinedButton(
                        onPressed: () => _handleInvitationResponse(false),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.red,
                          side: const BorderSide(color: Colors.red),
                          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
                        ),
                        child: const Text('REFUSE', style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                  if (_pendingInvitee!.canRefuse)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        '${_pendingInvitee!.teamName} can refuse once (${_pendingInvitee!.refusalCount}/1)',
                        style: TextStyle(color: Colors.orange.withOpacity(0.7), fontSize: 11),
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildAvailableTeamsPanel() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF130840),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFFFD700).withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFFFD700).withOpacity(0.1),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
              border: Border(bottom: BorderSide(color: const Color(0xFFFFD700).withOpacity(0.2))),
            ),
            child: Row(
              children: [
                const Icon(Icons.people, color: Color(0xFFFFD700), size: 20),
                const SizedBox(width: 8),
                Text(
                  'AVAILABLE TEAMS (${_availableTeams.where((t) => !_isTeamInAlliance(t.teamId)).length})',
                  style: TextStyle(
                    color: const Color(0xFFFFD700).withOpacity(0.9),
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    letterSpacing: 1.5,
                  ),
                ),
              ],
            ),
          ),

          // Team List
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: _availableTeams.where((team) => !_isTeamInAlliance(team.teamId)).map((team) {
                final isCurrentSelector = team.teamId == _currentSelector?.teamId;
                final canBeSelected = _currentStatus == SelectionStatus.selecting && 
                                      !isCurrentSelector && 
                                      _pendingInvitee == null;
                
                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: canBeSelected
                          ? getCategoryColor(team.rank).withOpacity(0.3)
                          : Colors.transparent,
                    ),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: ListTile(
                    leading: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: getCategoryColor(team.rank).withOpacity(0.2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Center(
                        child: Text(
                          '#${team.rank}',
                          style: TextStyle(color: getCategoryColor(team.rank), fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                    title: Row(
                      children: [
                        Expanded(
                          child: Text(
                            team.teamName,
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFF00CFFF).withOpacity(0.15),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            _formatTeamId(team.teamId),
                            style: const TextStyle(color: Color(0xFF00CFFF), fontSize: 10),
                          ),
                        ),
                      ],
                    ),
                    subtitle: Row(
                      children: [
                        Text(
                          '${team.totalScore} pts',
                          style: TextStyle(
                            color: team.isTop50 ? const Color(0xFFFFD700) : Colors.white54,
                            fontSize: 12,
                            fontWeight: team.isTop50 ? FontWeight.bold : FontWeight.normal,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: team.isTop50
                                ? const Color(0xFFFFD700).withOpacity(0.15)
                                : Colors.white.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            team.canRefuse ? 'CAN REFUSE' : 'CANNOT REFUSE',
                            style: TextStyle(
                              color: team.canRefuse ? const Color(0xFFFFD700) : Colors.white38,
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                    trailing: canBeSelected
                        ? ElevatedButton(
                            onPressed: () => _selectTeam(team),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: getCategoryColor(team.rank),
                              foregroundColor: Colors.black,
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(20),
                              ),
                            ),
                            child: const Text('SELECT', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                          )
                        : null,
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAllianceCardsPanel() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF130840),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFFFD700).withOpacity(0.2)),
      ),
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFFFD700).withOpacity(0.1),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
              border: Border(bottom: BorderSide(color: const Color(0xFFFFD700).withOpacity(0.2))),
            ),
            child: Row(
              children: [
                const Icon(Icons.emoji_events, color: Color(0xFFFFD700), size: 20),
                const SizedBox(width: 8),
                Text(
                  'ALLIANCE CARDS',
                  style: TextStyle(
                    color: const Color(0xFFFFD700).withOpacity(0.9),
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    letterSpacing: 1.5,
                  ),
                ),
                const Spacer(),
                Text(
                  '1ST TEAM • 2ND TEAM • 3RD TEAM • 4TH TEAM',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.3),
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
          ),

          // Alliance Cards
          Padding(
            padding: const EdgeInsets.all(16),
            child: _formedAlliances.isEmpty
                ? Center(
                    child: Column(
                      children: [
                        const SizedBox(height: 40),
                        Icon(Icons.group_off_rounded, color: Colors.white.withOpacity(0.1), size: 64),
                        const SizedBox(height: 16),
                        Text(
                          'No alliances formed yet',
                          style: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 16),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Alliances will appear here as they are formed',
                          style: TextStyle(color: Colors.white.withOpacity(0.2), fontSize: 12),
                        ),
                        const SizedBox(height: 40),
                      ],
                    ),
                  )
                : Column(
                    children: List.generate(_formedAlliances.length, (index) {
                      final alliance = _formedAlliances[index];
                      final color = getCategoryColor(index + 1);
                      
                      return Container(
                        margin: const EdgeInsets.only(bottom: 16),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              color.withOpacity(0.15),
                              color.withOpacity(0.05),
                            ],
                          ),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: color.withOpacity(0.3)),
                        ),
                        child: Column(
                          children: [
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: color,
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Text(
                                    'ALLIANCE ${index + 1}',
                                    style: const TextStyle(color: Colors.black, fontSize: 11, fontWeight: FontWeight.bold),
                                  ),
                                ),
                                const Spacer(),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: color.withOpacity(0.2),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    'ROUND ${index + 1}',
                                    style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            Row(
                              children: [
                                // Captain
                                Expanded(
                                  child: Container(
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: Colors.black.withOpacity(0.3),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(color: color.withOpacity(0.3)),
                                    ),
                                    child: Column(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.all(8),
                                          decoration: BoxDecoration(
                                            color: color.withOpacity(0.2),
                                            shape: BoxShape.circle,
                                          ),
                                          child: const Icon(Icons.person, color: Colors.white70, size: 20),
                                        ),
                                        const SizedBox(height: 8),
                                        Text(
                                          alliance.captain.teamName,
                                          style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                                          textAlign: TextAlign.center,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        const SizedBox(height: 4),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: color.withOpacity(0.2),
                                            borderRadius: BorderRadius.circular(4),
                                          ),
                                          child: Text(
                                            '(C) #${alliance.captain.rank}',
                                            style: TextStyle(color: color, fontSize: 9, fontWeight: FontWeight.bold),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                Container(
                                  margin: const EdgeInsets.symmetric(horizontal: 8),
                                  child: const Icon(Icons.add_circle_outline, color: Colors.white38, size: 20),
                                ),
                                // Partner
                                Expanded(
                                  child: Container(
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: Colors.black.withOpacity(0.3),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(color: color.withOpacity(0.3)),
                                    ),
                                    child: Column(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.all(8),
                                          decoration: BoxDecoration(
                                            color: color.withOpacity(0.2),
                                            shape: BoxShape.circle,
                                          ),
                                          child: const Icon(Icons.group, color: Colors.white70, size: 20),
                                        ),
                                        const SizedBox(height: 8),
                                        Text(
                                          alliance.partner.teamName,
                                          style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                                          textAlign: TextAlign.center,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        const SizedBox(height: 4),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: color.withOpacity(0.2),
                                            borderRadius: BorderRadius.circular(4),
                                          ),
                                          child: Text(
                                            '(F) #${alliance.partner.rank}',
                                            style: TextStyle(color: color, fontSize: 9, fontWeight: FontWeight.bold),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      );
                    }),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildCompletionInterface() {
    return Column(
      children: [
        // Completion Banner
        Container(
          padding: const EdgeInsets.all(32),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF1E5A0A), Color(0xFF0A3A1E)],
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFF00E5A0).withOpacity(0.5), width: 2),
          ),
          child: Column(
            children: [
              // ... existing content ...
              
              const SizedBox(height: 32),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ElevatedButton(
                    onPressed: () {
                      // When user clicks PROCEED TO CHAMPIONSHIP ROUND
                      // Now we call widget.onComplete() ONLY when button is clicked
                      widget.onComplete();
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF00E5A0),
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    child: const Text(
                      'PROCEED TO CHAMPIONSHIP ROUND',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, letterSpacing: 1.5),
                    ),
                  ),
                  const SizedBox(width: 16),
                  if (widget.onCancel != null)
                    OutlinedButton(
                      onPressed: widget.onCancel,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: BorderSide(color: Colors.white.withOpacity(0.3)),
                        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                      ),
                      child: const Text('CANCEL', style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                ],
              ),
            ],
          ),
        ),

        const SizedBox(height: 24),

        // Final Standings Preview
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: const Color(0xFF130840),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFFFD700).withOpacity(0.2)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'FINAL QUALIFICATION STANDINGS',
                style: TextStyle(color: Color(0xFFFFD700), fontSize: 14, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  headingRowColor: WidgetStateProperty.all(const Color(0xFF2D0E7A)),
                  dataRowColor: WidgetStateProperty.all(Colors.transparent),
                  columns: const [
                    DataColumn(label: Text('RANK', style: TextStyle(color: Colors.white))),
                    DataColumn(label: Text('TEAM', style: TextStyle(color: Colors.white))),
                    DataColumn(label: Text('SCORE', style: TextStyle(color: Colors.white))),
                    DataColumn(label: Text('STATUS', style: TextStyle(color: Colors.white))),
                  ],
                  rows: _availableTeams.map((team) {
                    final inAlliance = _isTeamInAlliance(team.teamId);
                    return DataRow(
                      cells: [
                        DataCell(Text('#${team.rank}', style: TextStyle(color: getCategoryColor(team.rank)))),
                        DataCell(Text(team.teamName, style: const TextStyle(color: Colors.white))),
                        DataCell(Text('${team.totalScore}', style: const TextStyle(color: Color(0xFFFFD700)))),
                        DataCell(
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: inAlliance ? Colors.green.withOpacity(0.2) : Colors.orange.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              inAlliance ? 'IN ALLIANCE' : 'WAITING',
                              style: TextStyle(
                                color: inAlliance ? Colors.green : Colors.orange,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      ],
                    );
                  }).toList(),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}