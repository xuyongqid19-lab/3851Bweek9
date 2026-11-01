import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class MobilePageShell extends StatelessWidget {
  const MobilePageShell({
    required this.child,
    super.key,
  });

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFE8F1FE), AppTheme.canvas, Color(0xFFEAF7F5)],
          ),
        ),
        child: Stack(
          children: [
            const Positioned(
              top: -60,
              left: -40,
              child: _DecorCircle(
                size: 220,
                colors: AppTheme.tealGradientColors,
                opacity: 0.16,
              ),
            ),
            const Positioned(
              top: 40,
              right: -70,
              child: _DecorCircle(
                size: 260,
                colors: AppTheme.blueGradientColors,
                opacity: 0.14,
              ),
            ),
            const Positioned(
              bottom: -80,
              right: -50,
              child: _DecorCircle(
                size: 240,
                colors: AppTheme.pinkGradientColors,
                opacity: 0.12,
              ),
            ),
            SafeArea(
              child: Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 430),
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.08),
                          blurRadius: 30,
                          offset: const Offset(0, 12),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(24),
                      child: SizedBox.expand(child: child),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DecorCircle extends StatelessWidget {
  const _DecorCircle({
    required this.size,
    required this.colors,
    this.opacity = 0.15,
  });

  final double size;
  final List<Color> colors;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: colors,
        ),
        shape: BoxShape.circle,
      ),
      foregroundDecoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 1 - opacity),
        shape: BoxShape.circle,
      ),
    );
  }
}

class GlobalVillageHeader extends StatelessWidget {
  const GlobalVillageHeader({
    this.showBackButton = false,
    this.onBack,
    super.key,
  });

  final bool showBackButton;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: 66,
          child: Stack(
            alignment: Alignment.center,
            children: [
              if (showBackButton)
                Positioned(
                  left: 8,
                  child: IconButton(
                    tooltip: 'Back',
                    onPressed: onBack ?? () => Navigator.maybePop(context),
                    icon: const Icon(Icons.arrow_back_ios_new, size: 20),
                  ),
                ),
              const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _BrandLogo(),
                  SizedBox(width: 10),
                  Text(
                    'Global Village',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.ink,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        Container(
          height: 2.5,
          margin: const EdgeInsets.symmetric(horizontal: 24),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: [
                Colors.transparent,
                AppTheme.brandTeal.withValues(alpha: 0.7),
                AppTheme.brand.withValues(alpha: 0.7),
                Colors.transparent,
              ],
            ),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      ],
    );
  }
}

class _BrandLogo extends StatelessWidget {
  const _BrandLogo();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 34,
      height: 34,
      decoration: BoxDecoration(
        gradient: AppTheme.brandGradient,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: AppTheme.brand.withValues(alpha: 0.35),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: const Icon(Icons.public, size: 20, color: Colors.white),
    );
  }
}

class AuthPageTitle extends StatelessWidget {
  const AuthPageTitle({
    required this.title,
    required this.subtitle,
    super.key,
  });

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            color: const Color(0xFFEAF2FE),
            borderRadius: BorderRadius.circular(18),
          ),
          child: const Icon(
            Icons.diversity_3,
            size: 28,
            color: AppTheme.brand,
          ),
        ),
        const SizedBox(height: 16),
        Text(
          title,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.headlineMedium,
        ),
        const SizedBox(height: 10),
        Text(
          subtitle,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: AppTheme.muted,
            fontSize: 14,
            height: 1.45,
          ),
        ),
      ],
    );
  }
}
