import 'package:flutter/cupertino.dart';
import 'package:provider/provider.dart';
import 'services/vault_provider.dart';
import 'theme/app_theme.dart';
import 'screens/unlock_screen.dart';
import 'screens/home_screen.dart';

void main() {
  runApp(
    ChangeNotifierProvider(
      create: (_) => VaultProvider(),
      child: const DocumentVaultApp(),
    ),
  );
}

class DocumentVaultApp extends StatelessWidget {
  const DocumentVaultApp({super.key});

  @override
  Widget build(BuildContext context) {
    return CupertinoApp(
      title: 'Document Vault',
      theme: AppTheme.darkTheme,
      debugShowCheckedModeBanner: false,
      home: Consumer<VaultProvider>(
        builder: (context, vault, _) {
          if (!vault.isUnlocked) {
            return const UnlockScreen();
          }
          return const HomeScreen();
        },
      ),
    );
  }
}
