import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/token_store.dart';
import 'ui/app.dart';
import 'ui/providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final tokenStore = await createFileTokenStore();
  runApp(
    ProviderScope(
      overrides: [
        tokenStoreProvider.overrideWithValue(tokenStore),
      ],
      child: const TraceApp(),
    ),
  );
}
