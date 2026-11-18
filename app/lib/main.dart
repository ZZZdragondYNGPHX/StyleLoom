import 'package:material_ui/material_ui.dart';

import 'bridge/core_client.dart';
import 'state/app_controller.dart';
import 'theme/app_theme.dart';
import 'ui/shell/workspace_shell.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final vaultDir = await StyleLoomClient.resolveDefaultVaultDir();
  final client = StyleLoomClient(vaultDir: vaultDir);
  final controller = AppController(client: client);
  controller.initialize();
  runApp(StyleLoomApp(controller: controller));
}

class StyleLoomApp extends StatelessWidget {
  const StyleLoomApp({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        return MaterialApp(
          title: 'StyleLoom',
          debugShowCheckedModeBanner: false,
          theme: StyleLoomTheme.light(),
          darkTheme: StyleLoomTheme.night(),
          themeMode: controller.isNightMode ? ThemeMode.dark : ThemeMode.light,
          home: WorkspaceShell(controller: controller),
        );
      },
    );
  }
}
