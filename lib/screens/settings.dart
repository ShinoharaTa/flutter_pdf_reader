import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../store/settings_store.dart';

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsStoreProvider);
    final settingsNotifier = ref.read(settingsStoreProvider.notifier);

    return Scaffold(
      appBar: AppBar(
        title: const Text("Settings"),
      ),
      body: ListView(
        children: [
          ListTile(
            title: const Text("Theme"),
            subtitle: Text(
              settings.themeMode == ThemeMode.dark ? "Dark" : "Light",
            ),
            trailing: Switch(
              value: settings.themeMode == ThemeMode.dark,
              onChanged: (value) => settingsNotifier.toggleThemeMode(),
            ),
          ),
          ListTile(
            title: const Text("Scroll Direction"),
            subtitle: Text(
              settings.scrollDirection == Axis.horizontal
                  ? "Horizontal"
                  : "Vertical",
            ),
            trailing: Switch(
              value: settings.scrollDirection == Axis.horizontal,
              onChanged: (value) => settingsNotifier.toggleScrollDirection(),
            ),
          ),
        ],
      ),
    );
  }
}
