import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/models.dart';
import 'pages/bind_page.dart';
import 'pages/login_page.dart';
import 'pages/moment_detail_page.dart';
import 'pages/preview_page.dart';
import 'pages/publish_page.dart';
import 'pages/settings_page.dart';
import 'pages/timeline_page.dart';
import 'providers.dart';
import 'theme.dart';

class TraceApp extends ConsumerWidget {
  const TraceApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokenStore = ref.watch(tokenStoreProvider);
    final scale = ref.watch(textScaleProvider);
    return MaterialApp(
      title: 'Trace · 同迹',
      debugShowCheckedModeBanner: false,
      theme: buildTraceTheme(level: scale),
      initialRoute: tokenStore.lastRead == null ? '/login' : '/timeline',
      routes: {
        '/login': (_) => const LoginPage(),
        '/bind': (_) => const BindPage(),
        '/timeline': (_) => const TimelinePage(),
        '/settings': (_) => const SettingsPage(),
      },
      onGenerateRoute: (settings) {
        final args = settings.arguments;
        if (settings.name == '/publish') {
          return MaterialPageRoute<Moment>(
            builder: (_) => PublishPage(
              editing: args is Moment ? args : null,
            ),
          );
        }
        if (settings.name == '/moment' && args is Moment) {
          return MaterialPageRoute<void>(
            builder: (_) => MomentDetailPage(moment: args),
          );
        }
        if (settings.name == '/preview' && args is Map<String, String>) {
          return MaterialPageRoute<void>(
            builder: (_) => PreviewPage(
              objectKey: args['objectKey'] ?? '',
              mediaType: args['mediaType'] ?? 'image',
            ),
          );
        }
        return null;
      },
    );
  }
}
