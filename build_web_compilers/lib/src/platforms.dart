// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:build_modules/build_modules.dart';

const _libraries = [
  '_internal',
  'async',
  'collection',
  'convert',
  'core',
  'developer',
  'html',
  'html_common',
  'indexed_db',
  'js',
  'js_interop',
  'js_interop_unsafe',
  'js_util',
  'math',
  'svg',
  'typed_data',
  'web_audio',
  'web_gl',
  'web_sql',
];

final ddcPlatform = DartPlatform.register('ddc', _libraries);

final dart2jsPlatform = DartPlatform.register('dart2js', _libraries);
