import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'pages/bind_page.dart';
import 'pages/login_page.dart';
import 'pages/publish_page.dart';
import 'pages/settings_page.dart';
import 'pages/timeline_page.dart';
import 'providers.dart';

class TraceApp extends ConsumerWidget {
  const TraceApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokenStore = ref.watch(tokenStoreProvider);
    return MaterialApp(
      title: 'Trace · 同迹',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF7C6CF0)),
        useMaterial3: true,
      ),
      initialRoute: tokenStore.lastRead == null ? '/login' : '/timeline',
      routes: {
        '/login': (_) => const LoginPage(),
        '/bind': (_) => const BindPage(),
        '/timeline': (_) => const TimelinePage(),
        '/publish': (_) => const PublishPage(),
        '/settings': (_) => const SettingsPage(),
      },
    );
  }
}
