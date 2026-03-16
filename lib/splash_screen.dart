import 'package:flutter/material.dart';
import 'config.dart';
import 'db_helper.dart';
import 'landing_page.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  bool _isInitialized = false;
  String _status = "Loading configuration...";
  String? _error;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    try {
      setState(() => _status = "Loading environment variables...");
      await Config.load();
      
      setState(() => _status = "Connecting to database...");
      await DBHelper.getConnection();
      
      setState(() => _status = "Running migrations...");
      await DBHelper.runMigrations();
      
      setState(() {
        _isInitialized = true;
        _status = "Ready!";
      });
      
    } catch (e) {
      setState(() {
        _error = e.toString();
        _status = "Initialization failed";
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Scaffold(
        backgroundColor: const Color(0xFF0E0630),
        body: Center(
          child: Container(
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              color: const Color(0xFF2D0E7A),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.red.withOpacity(0.5)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline, color: Colors.red, size: 64),
                const SizedBox(height: 16),
                const Text(
                  'Initialization Error',
                  style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  _error!,
                  style: const TextStyle(color: Colors.white70),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: () {
                    setState(() {
                      _error = null;
                      _status = "Retrying...";
                    });
                    _initialize();
                  },
                  child: const Text('RETRY'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (!_isInitialized) {
      return Scaffold(
        backgroundColor: const Color(0xFF0E0630),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Logo
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF7B2FFF).withOpacity(0.45),
                      blurRadius: 80,
                      spreadRadius: 25,
                    ),
                  ],
                ),
                child: Image.asset(
                  'assets/images/MakeX_logo.png',
                  width: 150,
                  height: 150,
                ),
              ),
              const SizedBox(height: 40),
              // Loading indicator
              const CircularProgressIndicator(
                color: Color(0xFF00CFFF),
              ),
              const SizedBox(height: 24),
              // Status text
              Text(
                _status,
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      );
    }

    // Go to the actual app
    return const LandingPage();
  }
}