import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/token_store.dart';
import 'db/app_database.dart';
import 'ui/app.dart';
import 'ui/providers.dart';
import 'ui/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final tokenStore = await createFileTokenStore();
  final db = AppDatabase();
  final overrides = [
    tokenStoreProvider.overrideWithValue(tokenStore),
    dbProvider.overrideWithValue(db),
  ];
  // 字号偏好读不出来时用默认档，不能因此开不了 App
  final saved = await db.pref('text_scale').catchError((_) => null);
  runApp(
    ProviderScope(
      overrides: [
        ...overrides,
        textScaleProvider.overrideWith((_) => _scaleOf(saved)),
      ],
      child: const TraceApp(),
    ),
  );
}

TextScaleLevel _scaleOf(String? raw) => switch (raw) {
      'small' => TextScaleLevel.small,
      'large' => TextScaleLevel.large,
      _ => TextScaleLevel.normal,
    };
