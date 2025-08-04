import 'package:flutter/material.dart';
import 'dart:async';
import 'main.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    );

    _animation = CurvedAnimation(parent: _controller, curve: Curves.easeIn);
    _controller.forward();

    Timer(const Duration(seconds: 3), () {
      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const BreakerControlScreen()),
        );
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(
        0xFF2563eb,
      ), // BS14 blue theme matching Arduino
      body: Center(
        child: FadeTransition(
          opacity: _animation,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Yellow container matching Arduino switch container
              Container(
                margin: const EdgeInsets.all(40),
                padding: const EdgeInsets.symmetric(
                  vertical: 60,
                  horizontal: 50,
                ),
                decoration: BoxDecoration(
                  color: const Color(
                    0xFFFFFF00,
                  ), // Bright yellow matching Arduino
                  borderRadius: BorderRadius.circular(25),
                  border: Border.all(
                    color: Colors.black,
                    width: 5,
                  ), // Black border like Arduino
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.3),
                      blurRadius: 15,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    // Large BS14 title
                    const Text(
                      'BS14',
                      style: TextStyle(
                        fontSize: 100,
                        fontWeight: FontWeight.bold,
                        color: Colors.black, // Black text on yellow background
                        letterSpacing: 8,
                      ),
                    ),
                    const SizedBox(height: 20),
                    // Decorative line
                    Container(width: 200, height: 3, color: Colors.black),
                    const SizedBox(height: 20),
                    // Company branding
                    const Text(
                      'By Relport, Inc.',
                      style: TextStyle(
                        fontSize: 24,
                        color: Colors.black87,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 20),
                    // Subtitle
                    const Text(
                      'Recloser Breaker Simulator 14-pin',
                      style: TextStyle(
                        fontSize: 18,
                        color: Colors.black54,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
