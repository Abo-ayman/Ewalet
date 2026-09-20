import 'package:flutter/material.dart';

class ServicesScreen extends StatelessWidget {
  const ServicesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const SafeArea(
      child: Center(
        child: Text(
          "الخدمات",
          style: TextStyle(color: Colors.white, fontSize: 22),
        ),
      ),
    );
  }
}
