import 'package:flutter/material.dart';

import '../common/posts_screen.dart';
import 'attendance_screens.dart';
import 'children_screens.dart';
import 'dashboard_screen.dart';
import 'dues_screens.dart';

class ResponsableShell extends StatefulWidget {
  const ResponsableShell({super.key});

  @override
  State<ResponsableShell> createState() => _ResponsableShellState();
}

class _ResponsableShellState extends State<ResponsableShell> {
  int _index = 0;

  void _go(int i) => setState(() => _index = i);

  @override
  Widget build(BuildContext context) {
    final pages = [
      DashboardScreen(onNavigate: _go),
      const ChildrenScreen(),
      const AttendanceEventsScreen(),
      const DuesScreen(),
      const PostsScreen(canEdit: true),
    ];
    return Scaffold(
      body: IndexedStack(index: _index, children: pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: _go,
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home_rounded), label: 'Accueil'),
          NavigationDestination(icon: Icon(Icons.groups_outlined), selectedIcon: Icon(Icons.groups_rounded), label: 'Enfants'),
          NavigationDestination(icon: Icon(Icons.fact_check_outlined), selectedIcon: Icon(Icons.fact_check_rounded), label: 'Présences'),
          NavigationDestination(icon: Icon(Icons.payments_outlined), selectedIcon: Icon(Icons.payments_rounded), label: 'Cotisations'),
          NavigationDestination(icon: Icon(Icons.campaign_outlined), selectedIcon: Icon(Icons.campaign_rounded), label: 'Infos'),
        ],
      ),
    );
  }
}
