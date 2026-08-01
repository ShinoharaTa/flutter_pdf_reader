import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../store/settings_store.dart';

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsStoreProvider);
    final notifier = ref.read(settingsStoreProvider.notifier);

    return Scaffold(
      appBar: AppBar(title: const Text("Settings")),
      body: ListView(
        children: [
          ListTile(
            title: const Text("テーマ"),
            subtitle: const Text("System はOSの設定に追従します"),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: SegmentedButton<ThemeMode>(
              segments: const [
                ButtonSegment(
                  value: ThemeMode.system,
                  label: Text('System'),
                  icon: Icon(Icons.brightness_auto),
                ),
                ButtonSegment(
                  value: ThemeMode.light,
                  label: Text('Light'),
                  icon: Icon(Icons.light_mode),
                ),
                ButtonSegment(
                  value: ThemeMode.dark,
                  label: Text('Dark'),
                  icon: Icon(Icons.dark_mode),
                ),
              ],
              selected: {settings.themeMode},
              onSelectionChanged: (selection) =>
                  notifier.setThemeMode(selection.first),
            ),
          ),
          const Divider(),
          const ListTile(title: Text("スクロール方向")),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: SegmentedButton<Axis>(
              segments: const [
                ButtonSegment(
                  value: Axis.horizontal,
                  label: Text('横'),
                  icon: Icon(Icons.swap_horiz_rounded),
                ),
                ButtonSegment(
                  value: Axis.vertical,
                  label: Text('縦'),
                  icon: Icon(Icons.swap_vert_rounded),
                ),
              ],
              selected: {settings.scrollDirection},
              onSelectionChanged: (selection) =>
                  notifier.setScrollDirection(selection.first),
            ),
          ),
        ],
      ),
    );
  }
}
