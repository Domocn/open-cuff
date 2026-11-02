import 'package:flutter/material.dart';

const teal = Color(0xFF147C92);
const tealDark = Color(0xFF0F5C6B);

ThemeData buildTheme(Brightness b) {
  final dark = b == Brightness.dark;
  final scheme = ColorScheme.fromSeed(seedColor: teal, brightness: b).copyWith(
    primary: dark ? const Color(0xFF4FB8CC) : teal,
    surface: dark ? const Color(0xFF10171C) : const Color(0xFFF7F9FA),
    surfaceContainer: dark ? const Color(0xFF172129) : Colors.white,
    surfaceContainerHigh: dark ? const Color(0xFF1E2A33) : const Color(0xFFEDF2F4),
  );
  return ThemeData(
    colorScheme: scheme,
    useMaterial3: true,
    scaffoldBackgroundColor: scheme.surface,
    cardTheme: CardThemeData(
      color: scheme.surfaceContainer,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: scheme.surfaceContainer,
      indicatorColor: scheme.primary.withValues(alpha: .16),
    ),
    textTheme: const TextTheme(
      headlineSmall: TextStyle(fontWeight: FontWeight.w700, letterSpacing: -.3),
      titleMedium: TextStyle(fontWeight: FontWeight.w700),
    ),
  );
}

/// A rounded white card with a little padding, used everywhere.
class Box extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  const Box({super.key, required this.child, this.padding = const EdgeInsets.all(14), this.onTap});

  @override
  Widget build(BuildContext context) => Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(onTap: onTap, child: Padding(padding: padding, child: child)),
      );
}

class Pill extends StatelessWidget {
  final String text;
  final Color color;
  const Pill(this.text, this.color, {super.key});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(color: color.withValues(alpha: .15), borderRadius: BorderRadius.circular(99)),
        child: Text(text, style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 12.5)),
      );
}

TextStyle muted(BuildContext c) => TextStyle(color: Theme.of(c).colorScheme.onSurfaceVariant, fontSize: 13);
