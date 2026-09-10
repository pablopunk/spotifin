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
  File('assets/branding/app_icon_ios.png')
      .writeAsBytesSync(image.encodePng(opaqueIcon));
}
