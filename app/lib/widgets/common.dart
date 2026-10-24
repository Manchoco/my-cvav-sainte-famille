import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../models.dart';
import '../theme.dart';

void showMessage(BuildContext context, String message, {bool error = false}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text(message),
      backgroundColor: error ? AppColors.danger : AppColors.navy,
    ));
}

String errorText(Object e) => e is ApiException ? e.toString() : 'Une erreur est survenue. Réessayez.';

Future<bool> confirm(BuildContext context, {required String title, required String message, String confirmLabel = 'Confirmer', bool danger = false}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
        FilledButton(
          style: FilledButton.styleFrom(minimumSize: const Size(0, 44), backgroundColor: danger ? AppColors.danger : null),
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return ok ?? false;
}

class LoadingView extends StatelessWidget {
  const LoadingView({super.key});
  @override
  Widget build(BuildContext context) => const Center(child: CircularProgressIndicator());
}

class ErrorView extends StatelessWidget {
  const ErrorView({super.key, required this.error, required this.onRetry});
  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.cloud_off_rounded, size: 56, color: AppColors.muted),
          const SizedBox(height: 16),
          Text(errorText(error), textAlign: TextAlign.center, style: const TextStyle(fontSize: 15)),
          const SizedBox(height: 20),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(minimumSize: const Size(160, 46)),
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Réessayer'),
          ),
        ]),
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.title, this.message, this.action});
  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.1), shape: BoxShape.circle),
            child: Icon(icon, size: 40, color: AppColors.primary),
          ),
          const SizedBox(height: 16),
          Text(title, textAlign: TextAlign.center, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
          if (message != null) ...[
            const SizedBox(height: 8),
            Text(message!, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.muted)),
          ],
          if (action != null) ...[const SizedBox(height: 20), action!],
        ]),
      ),
    );
  }
}

/// Chargement asynchrone avec états chargement / erreur / données.
class AsyncBody<T> extends StatelessWidget {
  const AsyncBody({super.key, required this.future, required this.builder, required this.onRetry});
  final Future<T>? future;
  final Widget Function(T data) builder;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<T>(
      future: future,
      builder: (context, snap) {
        if (snap.hasError) return ErrorView(error: snap.error!, onRetry: onRetry);
        if (!snap.hasData) return const LoadingView();
        return builder(snap.data as T);
      },
    );
  }
}

class LegionBadge extends StatelessWidget {
  const LegionBadge(this.legion, {super.key, this.small = false});
  final Legion legion;
  final bool small;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: small ? 8 : 10, vertical: small ? 2 : 4),
      decoration: BoxDecoration(color: legion.color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
      child: Text(legion.label, style: TextStyle(color: legion.color, fontWeight: FontWeight.w700, fontSize: small ? 11 : 12)),
    );
  }
}

class ChildAvatar extends StatelessWidget {
  const ChildAvatar(this.child, {super.key, this.radius = 22});
  final Child child;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return CircleAvatar(
      radius: radius,
      backgroundColor: child.legion.color.withValues(alpha: 0.15),
      child: Text(child.initials, style: TextStyle(color: child.legion.color, fontWeight: FontWeight.w800, fontSize: radius * 0.7)),
    );
  }
}

class StatusPill extends StatelessWidget {
  const StatusPill({super.key, required this.label, required this.color, this.icon});
  final String label;
  final Color color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (icon != null) ...[Icon(icon, size: 14, color: color), const SizedBox(width: 4)],
        Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 12)),
      ]),
    );
  }
}

/// En-tête dégradé bleu avec logo, utilisé sur les écrans d'accueil.
class GradientHeader extends StatelessWidget {
  const GradientHeader({super.key, required this.title, this.subtitle, this.trailing, this.child});
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: AppColors.headerGradient,
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(28)),
      ),
      padding: EdgeInsets.fromLTRB(20, MediaQuery.paddingOf(context).top + 16, 20, 24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 46,
            height: 46,
            padding: const EdgeInsets.all(4),
            decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
            child: Image.asset('assets/images/logo_cvav.png'),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800)),
              if (subtitle != null)
                Text(subtitle!, style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 13)),
            ]),
          ),
          ?trailing,
        ]),
        if (child != null) ...[const SizedBox(height: 20), child!],
      ]),
    );
  }
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key, this.action});
  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 20, 4, 10),
      child: Row(children: [
        Expanded(child: Text(text, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800))),
        ?action,
      ]),
    );
  }
}

/// Onglets par légion (avec "Toutes" en option).
List<Legion?> legionTabs({bool withAll = true}) => [if (withAll) null, ...Legion.values];

Tab legionTab(Legion? l, {int? count}) {
  final label = l?.label ?? 'Toutes';
  return Tab(text: count == null ? label : '$label ($count)');
}
