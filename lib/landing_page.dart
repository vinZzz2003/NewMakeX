// ignore_for_file: deprecated_member_use, unnecessary_underscores

import 'package:flutter/material.dart';
import 'dart:math' as math;
import 'main.dart';
import 'schedule_viewer.dart';
import 'standings.dart';
import 'teams_players.dart';

class LandingPage extends StatefulWidget {
  const LandingPage({super.key});

  @override
  State<LandingPage> createState() => _LandingPageState();
}

class _LandingPageState extends State<LandingPage>
    with TickerProviderStateMixin {
  late AnimationController _bgController;
  late AnimationController _logoController;
  late AnimationController _buttonsController;

  late Animation<double> _logoScale;
  late Animation<double> _logoOpacity;
  late Animation<double> _btn1Offset;
  late Animation<double> _btn2Offset;
  late Animation<double> _btn4Offset;
  late Animation<double> _btn1Opacity;
  late Animation<double> _btn2Opacity;
  late Animation<double> _btn4Opacity;

  @override
  void initState() {
    super.initState();

    // Background animation (now using progress for geometric patterns)
    _bgController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 30),
    )..repeat();

    // Logo entrance
    _logoController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _logoScale = Tween<double>(begin: 0.6, end: 1.0).animate(
      CurvedAnimation(parent: _logoController, curve: Curves.elasticOut),
    );
    _logoOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
          parent: _logoController,
          curve: const Interval(0.0, 0.5, curve: Curves.easeIn)),
    );

    // Buttons staggered entrance
    _buttonsController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _btn1Offset = Tween<double>(begin: 60.0, end: 0.0).animate(
      CurvedAnimation(
          parent: _buttonsController,
          curve: const Interval(0.0, 0.6, curve: Curves.easeOutCubic)),
    );
    _btn2Offset = Tween<double>(begin: 60.0, end: 0.0).animate(
      CurvedAnimation(
          parent: _buttonsController,
          curve: const Interval(0.2, 0.75, curve: Curves.easeOutCubic)),
    );
    _btn4Offset = Tween<double>(begin: 60.0, end: 0.0).animate(
      CurvedAnimation(
          parent: _buttonsController,
          curve: const Interval(0.5, 1.0, curve: Curves.easeOutCubic)),
    );
    _btn1Opacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
          parent: _buttonsController,
          curve: const Interval(0.0, 0.5, curve: Curves.easeIn)),
    );
    _btn2Opacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
          parent: _buttonsController,
          curve: const Interval(0.2, 0.65, curve: Curves.easeIn)),
    );
    _btn4Opacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
          parent: _buttonsController,
          curve: const Interval(0.5, 0.9, curve: Curves.easeIn)),
    );

    // Start animations
    Future.delayed(const Duration(milliseconds: 200), () {
      _logoController.forward();
    });
    Future.delayed(const Duration(milliseconds: 800), () {
      _buttonsController.forward();
    });
  }

  @override
  void dispose() {
    _bgController.dispose();
    _logoController.dispose();
    _buttonsController.dispose();
    super.dispose();
  }

  void _goToRegistration() {
    Navigator.of(context).push(
      _buildRoute(const RegistrationFlow()),
    );
  }

  void _goToSchedule() {
    Navigator.of(context).push(
      _buildRoute(ScheduleViewer(
        onRegister:  () => Navigator.of(context).pop(),
        onStandings: () {
          Navigator.of(context).pop();
          Navigator.of(context).push(
            _buildRoute(Standings(
              onBack: () => Navigator.of(context).pop(),
            )),
          );
        },
      )),
    );
  }

  void _goToStandings() {
    Navigator.of(context).push(
      _buildRoute(Standings(
        onBack: () => Navigator.of(context).pop(),
      )),
    );
  }

  void _goToTeams() {
    Navigator.of(context).push(
      _buildRoute(TeamsPlayers(
        onBack: () => Navigator.of(context).pop(),
      )),
    );
  }

  PageRoute _buildRoute(Widget page) {
    return PageRouteBuilder(
      pageBuilder: (_, __, ___) => page,
      transitionsBuilder: (_, anim, __, child) {
        return FadeTransition(
          opacity: anim,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0.05, 0),
              end: Offset.zero,
            ).animate(CurvedAnimation(parent: anim, curve: Curves.easeOut)),
            child: child,
          ),
        );
      },
      transitionDuration: const Duration(milliseconds: 350),
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    return Scaffold(
      body: Stack(
        children: [
          // ── Animated geometric background ─────────────────────────────
          _buildBackground(size),

          // ── Circuit line decorations ─────────────────────────────────
          _buildCircuitLines(size),

          // ── Main content ─────────────────────────────────────────────
          SafeArea(
            child: Column(
              children: [
                // ── Sponsor logos row ──
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Image.asset(
                        'assets/images/MakeblockLogo.png',
                        height: 44,
                        fit: BoxFit.contain,
                      ),
                      Image.asset(
                        'assets/images/CreotecLogo.png',
                        height: 44,
                        fit: BoxFit.contain,
                      ),
                    ],
                  ),
                ),

                Expanded(
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 540),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const SizedBox(height: 12),

                          // ── Main logo ──
                          AnimatedBuilder(
                            animation: _logoController,
                            builder: (_, __) => Opacity(
                              opacity: _logoOpacity.value,
                              child: Transform.scale(
                                scale: _logoScale.value,
                                child: _buildLogo(),
                              ),
                            ),
                          ),

                          const SizedBox(height: 28),

                          // Buttons
                          AnimatedBuilder(
                            animation: _buttonsController,
                            builder: (_, __) => Column(
                              children: [
                                // ── REGISTRATION ──
                                _animatedButton(
                                  offset: _btn1Offset.value,
                                  opacity: _btn1Opacity.value,
                                  child: _NavButton(
                                    label: 'REGISTRATION',
                                    subtitle: 'Register Now',
                                    icon: Icons.app_registration_rounded,
                                    color: const Color(0xFF00CFFF),
                                    isPrimary: true,
                                    onTap: _goToRegistration,
                                  ),
                                ),
                                const SizedBox(height: 12),

                                // ── SCHEDULE + STANDINGS ──
                                _animatedButton(
                                  offset: _btn2Offset.value,
                                  opacity: _btn2Opacity.value,
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: _NavButton(
                                          label: 'SCHEDULE',
                                          subtitle: 'View match schedule',
                                          icon: Icons.calendar_month_rounded,
                                          color: const Color(0xFF967BB6),
                                          isPrimary: false,
                                          onTap: _goToSchedule,
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: _NavButton(
                                          label: 'STANDINGS',
                                          subtitle: 'View leaderboard',
                                          icon: Icons.emoji_events_rounded,
                                          color: const Color(0xFFFFD700),
                                          isPrimary: false,
                                          onTap: _goToStandings,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 12),

                                // ── TEAMS & PLAYERS ──
                                _animatedButton(
                                  offset: _btn4Offset.value,
                                  opacity: _btn4Opacity.value,
                                  child: _NavButton(
                                    label: 'TEAMS & PLAYERS',
                                    subtitle: 'Browse registered teams',
                                    icon: Icons.groups_rounded,
                                    color: const Color(0xFF00E5A0),
                                    isPrimary: false,
                                    isTertiary: true,
                                    onTap: _goToTeams,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                // Footer
                _buildFooter(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Background ───────────────────────────────────────────────────────────
  Widget _buildBackground(Size size) {
    return Container(
      width: size.width,
      height: size.height,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color.fromARGB(255, 33, 3, 108),
            Color.fromARGB(255, 72, 55, 123),
            Color.fromARGB(255, 114, 27, 5),
          ],
          stops: [0.0, 0.5, 1.0],
        ),
      ),
      child: AnimatedBuilder(
        animation: _bgController,
        builder: (_, __) {
          return CustomPaint(
            painter: _GeometricPainter(_bgController.value),
          );
        },
      ),
    );
  }

  // ── Circuit line decorations ─────────────────────────────────────────────
  Widget _buildCircuitLines(Size size) {
    return Positioned.fill(
      child: CustomPaint(
        painter: _CircuitPainter(),
      ),
    );
  }

  // ── Logo ─────────────────────────────────────────────────────────────────
  Widget _buildLogo() {
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF7B2FFF).withOpacity(0.45),
            blurRadius: 80,
            spreadRadius: 25,
          ),
          BoxShadow(
            color: const Color(0xFF00CFFF).withOpacity(0.25),
            blurRadius: 50,
            spreadRadius: 10,
          ),
        ],
      ),
      child: Image.asset(
        'assets/images/MakeX_logo.png',
        width: 300,
        height: 300,
        fit: BoxFit.contain,
      ),
    );
  }

  // ── Footer ───────────────────────────────────────────────────────────────
  Widget _buildFooter() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Text(
        '© 2025 MakeX • Powered by Creotec',
        style: TextStyle(
          color: Colors.white.withOpacity(0.25),
          fontSize: 11,
          letterSpacing: 1,
        ),
      ),
    );
  }

  Widget _animatedButton({
    required double offset,
    required double opacity,
    required Widget child,
  }) {
    return Opacity(
      opacity: opacity,
      child: Transform.translate(
        offset: Offset(0, offset),
        child: child,
      ),
    );
  }
}

// ── Nav Button ───────────────────────────────────────────────────────────────
class _NavButton extends StatefulWidget {
  final String label;
  final String subtitle;
  final IconData icon;
  final Color color;
  final bool isPrimary;
  final bool isTertiary;
  final VoidCallback onTap;

  const _NavButton({
    required this.label,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.isPrimary,
    required this.onTap,
    this.isTertiary = false,
  });

  @override
  State<_NavButton> createState() => _NavButtonState();
}

class _NavButtonState extends State<_NavButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _hoverController;
  late Animation<double> _scaleAnim;
  late Animation<double> _glowAnim;
  bool _hovered = false;

  @override
  void initState() {
    super.initState();
    _hoverController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 180),
    );
    _scaleAnim = Tween<double>(begin: 1.0, end: 1.03).animate(
      CurvedAnimation(parent: _hoverController, curve: Curves.easeOut),
    );
    _glowAnim = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _hoverController, curve: Curves.easeOut),
    );
  }

  @override
  void dispose() {
    _hoverController.dispose();
    super.dispose();
  }

  Color _getDarkerColor(Color color) {
    if (color == const Color(0xFF00CFFF)) return const Color(0xFF0099CC);
    if (color == const Color(0xFF967BB6)) return const Color(0xFF6B4F8F);
    if (color == const Color(0xFFFFD700)) return const Color(0xFFCCAC00);
    if (color == const Color(0xFF00E5A0)) return const Color(0xFF00B37A);
    return color.withOpacity(0.8);
  }

  @override
  Widget build(BuildContext context) {
    final double height = widget.isPrimary
        ? 76
        : widget.isTertiary
            ? 52
            : 64;

    return MouseRegion(
      onEnter: (_) {
        setState(() => _hovered = true);
        _hoverController.forward();
      },
      onExit: (_) {
        setState(() => _hovered = false);
        _hoverController.reverse();
      },
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedBuilder(
          animation: _hoverController,
          builder: (_, __) {
            return Transform.scale(
              scale: _scaleAnim.value,
              child: Container(
                width: double.infinity,
                height: height,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(widget.isPrimary ? 16 : 12),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      widget.color,
                      widget.color.withOpacity(0.75),
                      _getDarkerColor(widget.color),
                    ],
                  ),
                  border: null,
                  boxShadow: [
                    BoxShadow(
                      color: widget.color.withOpacity(_hovered ? 0.55 : 0.30),
                      blurRadius: _hovered ? (widget.isPrimary ? 32 : 24) : 20,
                      spreadRadius: _hovered ? (widget.isPrimary ? 4 : 2) : 2,
                    ),
                  ],
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: widget.isTertiary ? 32 : 40,
                      height: widget.isTertiary ? 32 : 40,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white.withOpacity(0.2),
                      ),
                      child: Icon(
                        widget.icon,
                        color: Colors.white,
                        size: widget.isTertiary ? 18 : 22,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.label,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: widget.isPrimary
                                ? 18
                                : widget.isTertiary
                                    ? 13
                                    : 15,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 2.5,
                          ),
                        ),
                        if (!widget.isTertiary)
                          Text(
                            widget.subtitle,
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.75),
                              fontSize: 11,
                              fontWeight: FontWeight.w400,
                              letterSpacing: 0.5,
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

// ── Geometric Tech Painter (simplified, no moving lines) ─────────────────
class _GeometricPainter extends CustomPainter {
  final double progress;
  _GeometricPainter(this.progress);

  @override
  void paint(Canvas canvas, Size size) {
    // Draw static geometric patterns only
    _drawHexagonGrid(canvas, size);
    _drawTechNodes(canvas, size);
    _drawGeometricShapes(canvas, size);
    _drawCentralGlow(canvas, size);
  }

  void _drawHexagonGrid(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;

    final hexSize = 70.0;
    final cols = (size.width / (hexSize * 1.5)).ceil() + 2;
    final rows = (size.height / (hexSize * 0.866)).ceil() + 2;
    
    // No movement - static grid
    for (int row = -1; row < rows; row++) {
      for (int col = -1; col < cols; col++) {
        final x = col * hexSize * 1.5;
        final y = row * hexSize * 0.866 + (col % 2) * hexSize * 0.433;
        
        // Calculate opacity based on distance from center
        final distanceToCenter = Offset(x - size.width/2, y - size.height/2).distance;
        final opacity = (0.25 * (1 - distanceToCenter / size.width)).clamp(0.1, 0.25);
        
        // Color shifts based on position
        final colorIndex = (row + col) % 3;
        Color color;
        switch(colorIndex) {
          case 0:
            color = const Color(0xFF7B2FFF); // Purple
            break;
          case 1:
            color = const Color(0xFF00CFFF); // Cyan
            break;
          default:
            color = const Color(0xFFFFD700); // Gold
        }
        
        paint.color = color.withOpacity(opacity);
        
        // Draw hexagon
        final path = Path();
        for (int i = 0; i < 6; i++) {
          final angle = i * 60 * math.pi / 180;
          final px = x + hexSize * math.cos(angle);
          final py = y + hexSize * math.sin(angle);
          if (i == 0) {
            path.moveTo(px, py);
          } else {
            path.lineTo(px, py);
          }
        }
        path.close();
        canvas.drawPath(path, paint);
      }
    }
  }

  void _drawTechNodes(Canvas canvas, Size size) {
    final nodeCount = 12;
    
    for (int i = 0; i < nodeCount; i++) {
      // Position nodes in a grid pattern - static
      final gridCol = i % 4;
      final gridRow = (i / 4).floor();
      
      final x = size.width * (0.15 + 0.7 * gridCol / 3);
      final y = size.height * (0.15 + 0.7 * gridRow / 3);
      
      // Static nodes (no pulsing)
      final nodeSize = 6.0;

      // Node glow
      canvas.drawCircle(
        Offset(x, y),
        nodeSize * 2,
        Paint()
          ..color = const Color(0xFF00CFFF).withOpacity(0.2)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10),
      );

      // Node core
      canvas.drawCircle(
        Offset(x, y),
        nodeSize,
        Paint()
          ..color = const Color(0xFF00CFFF).withOpacity(0.6)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
      );

      // Node center
      canvas.drawCircle(
        Offset(x, y),
        nodeSize * 0.4,
        Paint()..color = Colors.white.withOpacity(0.9),
      );

      // Draw connections between nearby nodes
      if (i < nodeCount - 1 && i % 4 != 3) {
        final nextCol = (i + 1) % 4;
        final nextRow = ((i + 1) / 4).floor();
        
        final nextX = size.width * (0.15 + 0.7 * nextCol / 3);
        final nextY = size.height * (0.15 + 0.7 * nextRow / 3);
        
        final paint = Paint()
          ..color = const Color(0xFF967BB6).withOpacity(0.2)
          ..strokeWidth = 1.0
          ..style = PaintingStyle.stroke;

        canvas.drawLine(
          Offset(x, y),
          Offset(nextX, nextY),
          paint,
        );
      }
    }
  }

  void _drawGeometricShapes(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    // Static squares (very slow rotation only)
    for (int i = 0; i < 3; i++) {
      final squareSize = 180.0 + i * 120;
      // Very slow rotation (barely noticeable)
      final rotation = progress * 0.2 * math.pi + i * math.pi / 6;
      
      paint.color = const Color(0xFF7B2FFF).withOpacity(0.12 - i * 0.02);
      
      canvas.save();
      canvas.translate(center.dx, center.dy);
      canvas.rotate(rotation);
      
      // Draw square
      canvas.drawRect(
        Rect.fromCenter(center: Offset.zero, width: squareSize, height: squareSize),
        paint,
      );
      
      canvas.restore();
    }

    // Static triangles
    for (int i = 0; i < 6; i++) {
      final angle = i * 60 * math.pi / 180;
      final distance = 220;
      
      final x = center.dx + distance * math.cos(angle);
      final y = center.dy + distance * math.sin(angle) * 0.6;
      
      paint.color = const Color(0xFFFFD700).withOpacity(0.15);
      
      final path = Path();
      for (int j = 0; j < 3; j++) {
        final triAngle = j * 120 * math.pi / 180;
        final px = x + 30 * math.cos(triAngle);
        final py = y + 30 * math.sin(triAngle);
        if (j == 0) {
          path.moveTo(px, py);
        } else {
          path.lineTo(px, py);
        }
      }
      path.close();
      canvas.drawPath(path, paint);
    }
  }

  void _drawCentralGlow(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    
    // Multiple layers of glow
    for (int i = 0; i < 3; i++) {
      final rectSize = 350.0 + i * 120;
      
      final gradient = RadialGradient(
        colors: [
          const Color(0xFF7B2FFF).withOpacity(0.2 - i * 0.04),
          Colors.transparent,
        ],
      );
      
      final rect = Rect.fromCenter(
        center: center,
        width: rectSize,
        height: rectSize * 0.8,
      );
      
      canvas.drawRect(
        rect,
        Paint()
          ..shader = gradient.createShader(
            Rect.fromCircle(center: center, radius: rectSize / 2)
          ),
      );
    }
    
    // Static center cross
    final linePaint = Paint()
      ..color = const Color(0xFF00CFFF).withOpacity(0.15)
      ..strokeWidth = 2.0
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10);
    
    canvas.drawLine(
      Offset(center.dx - 100, center.dy),
      Offset(center.dx + 100, center.dy),
      linePaint,
    );
    
    canvas.drawLine(
      Offset(center.dx, center.dy - 100),
      Offset(center.dx, center.dy + 100),
      linePaint,
    );
  }

  @override
  bool shouldRepaint(_GeometricPainter old) => old.progress != progress;
}

// ── Circuit painter (static decorative lines) ────────────────────────────────
class _CircuitPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF3D1A8C).withOpacity(0.25)
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;

    final dotPaint = Paint()
      ..color = const Color(0xFF00CFFF).withOpacity(0.3)
      ..style = PaintingStyle.fill;

    final leftPath = Path()
      ..moveTo(40, 80)
      ..lineTo(40, 200)
      ..lineTo(80, 200)
      ..lineTo(80, 280)
      ..lineTo(20, 280)
      ..moveTo(40, 340)
      ..lineTo(40, 420)
      ..lineTo(100, 420);

    final rightPath = Path()
      ..moveTo(size.width - 40, 120)
      ..lineTo(size.width - 40, 240)
      ..lineTo(size.width - 90, 240)
      ..lineTo(size.width - 90, 320)
      ..moveTo(size.width - 40, 380)
      ..lineTo(size.width - 40, 460)
      ..lineTo(size.width - 110, 460);

    canvas.drawPath(leftPath, paint);
    canvas.drawPath(rightPath, paint);

    for (final offset in [
      const Offset(40, 200),
      const Offset(80, 280),
      const Offset(40, 420),
    ]) {
      canvas.drawCircle(offset, 3, dotPaint);
    }
    for (final offset in [
      Offset(size.width - 40, 240),
      Offset(size.width - 90, 320),
      Offset(size.width - 40, 460),
    ]) {
      canvas.drawCircle(offset, 3, dotPaint);
    }
  }

  @override
  bool shouldRepaint(_CircuitPainter old) => false;
}