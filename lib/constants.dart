import 'package:flutter/material.dart';

// Accent Colors
const Color kAccentBlue = Color(0xFF00CFFF);
const Color kAccentLavender = Color(0xFF967BB6);
const Color kAccentGold = Color(0xFFFFD700);
const Color kAccentEmerald = Color(0xFF00E5A0);
const Color kAccentCoral = Color(0xFFFF6B6B);
const Color kAccentOrange = Color(0xFFFF8C42);

// Status Colors
const Color kSuccessGreen = Color(0xFF00FF88);
const Color kErrorRed = Color(0xFFFF5252);
const Color kWarningOrange = Color(0xFFFFA726);

// Background Gradients
const LinearGradient kBackgroundGradient = LinearGradient(
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
  colors: [Color(0xFF1A0550), Color(0xFF2D0E7A), Color(0xFF1A0A4A)],
);

const LinearGradient kCardGradient = LinearGradient(
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
  colors: [Color(0xFF2D0E7A), Color(0xFF1E0A5A)],
);

// UI Constants
const double kCardBorderRadius = 24.0;
const double kButtonBorderRadius = 10.0;
const double kMaxCardWidth = 820.0;

// Animation Durations
const Duration kShortAnimation = Duration(milliseconds: 180);
const Duration kMediumAnimation = Duration(milliseconds: 350);
const Duration kLongAnimation = Duration(milliseconds: 600);

// Step labels for registration
const List<String> kStepLabels = ['School', 'Mentor', 'Team', 'Players'];
const List<Color> kStepColors = [
  kAccentBlue,
  kAccentLavender,
  kAccentGold,
  kAccentEmerald,
];

// Helper function to get category color by index
Color getCategoryColor(int index) {
  final colors = [
    kAccentBlue,
    kAccentLavender,
    kAccentGold,
    kAccentEmerald,
    kAccentCoral,
    kAccentOrange,
  ];
  return colors[index % colors.length];
}