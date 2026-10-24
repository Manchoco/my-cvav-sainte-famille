import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';

import 'config.dart';
import 'screens/common/welcome_screen.dart';
import 'screens/parent/parent_shell.dart';
import 'screens/responsable/responsable_shell.dart';
import 'state/session.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('fr_FR');
  await AppConfig.load();
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(statusBarColor: Colors.transparent));
  final session = Session();
  runApp(ChangeNotifierProvider.value(value: session, child: const MyCvavApp()));
  await session.restore();
}

class MyCvavApp extends StatelessWidget {
  const MyCvavApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'My CVAV Sainte Famille',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      locale: const Locale('fr', 'FR'),
      supportedLocales: const [Locale('fr', 'FR')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: const RootGate(),
    );
  }
}

/// Aiguillage selon la session : accueil, espace responsable ou espace parent.
class RootGate extends StatelessWidget {
  const RootGate({super.key});

  @override
  Widget build(BuildContext context) {
    final session = context.watch<Session>();
    if (!session.ready) return const SplashScreen();
    final user = session.user;
    final Widget child = user == null
        ? const WelcomeScreen()
        : user.isResponsable
            ? const ResponsableShell()
            : const ParentShell();
    return AnimatedSwitcher(duration: const Duration(milliseconds: 300), child: KeyedSubtree(key: ValueKey(user?.role), child: child));
  }
}

class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: AppColors.headerGradient),
        child: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 120,
              height: 120,
              padding: const EdgeInsets.all(14),
              decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
              child: Image.asset('assets/images/logo_cvav.png'),
            ),
            const SizedBox(height: 20),
            const Text('My CVAV', style: TextStyle(color: Colors.white, fontSize: 30, fontWeight: FontWeight.w900)),
            const Text('Sainte Famille', style: TextStyle(color: Colors.white70, fontSize: 16)),
            const SizedBox(height: 32),
            const CircularProgressIndicator(color: Colors.white),
          ]),
        ),
      ),
    );
  }
}
