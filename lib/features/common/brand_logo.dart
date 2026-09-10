import 'package:flutter/material.dart';

import '../../app/theme.dart';

class SpotifinLogo extends StatelessWidget {
  const SpotifinLogo({required this.size, super.key});

  final double size;

  @override
  Widget build(BuildContext context) => Image.asset(
    'assets/branding/app_icon.png',
    width: size,
    height: size,
    fit: BoxFit.contain,
    filterQuality: FilterQuality.high,
    semanticLabel: 'Spotifin',
  );
}

class SpotifinWordmark extends StatelessWidget {
  const SpotifinWordmark({super.key});

  @override
  Widget build(BuildContext context) => ShaderMask(
    blendMode: BlendMode.srcIn,
    shaderCallback: SpotifinGradients.brand.createShader,
    child: Text(
      'Spotifin',
      overflow: TextOverflow.ellipsis,
      style: Theme.of(context).textTheme.titleLarge
          ?.copyWith(color: Colors.white, fontWeight: FontWeight.w800),
    ),
  );
}
