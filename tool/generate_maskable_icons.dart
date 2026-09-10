import 'dart:io';

import 'package:image/image.dart' as image;

void main() {
  final source = image.decodePng(
    File('assets/branding/app_icon.png').readAsBytesSync(),
  );
  if (source == null) {
    throw StateError('assets/branding/app_icon.png is not a valid PNG');
  }

  final opaqueIcon = image.Image(width: source.width, height: source.height);
  image.fill(opaqueIcon, color: image.ColorRgb8(6, 24, 47));
  image.compositeImage(opaqueIcon, source);

  for (final size in [192, 512]) {
    final icon = image.copyResize(
      opaqueIcon,
      width: size,
      height: size,
      interpolation: image.Interpolation.cubic,
    );
    File('web/icons/Icon-maskable-$size.png')
        .writeAsBytesSync(image.encodePng(icon));
  }
}
