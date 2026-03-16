import 'package:flutter/cupertino.dart';
import 'package:provider/provider.dart';
import '../services/vault_provider.dart';
import '../theme/app_theme.dart';

class UnlockScreen extends StatefulWidget {
  const UnlockScreen({super.key});

  @override
  State<UnlockScreen> createState() => _UnlockScreenState();
}

class _UnlockScreenState extends State<UnlockScreen> {
  final _controller = TextEditingController();
  bool _isLoading = false;
  String? _error;

  Future<void> _handleUnlock() async {
    final password = _controller.text.trim();
    if (password.isEmpty) return;

    setState(() {
      _isLoading = true;
      _error = null;
    });

    final vault = context.read<VaultProvider>();
    final success = await vault.unlock(password);

    if (!success && mounted) {
      setState(() {
        _isLoading = false;
        _error = 'Invalid master password.';
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      backgroundColor: AppTheme.bgPrimary,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 40),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Lock icon
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: AppTheme.fillTertiary,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Icon(
                  CupertinoIcons.lock_shield_fill,
                  size: 40,
                  color: AppTheme.accentBlue,
                ),
              ),
              const SizedBox(height: 28),

              // Title
              const Text(
                'Document Vault',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.5,
                  color: AppTheme.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Enter your master password to unlock',
                style: TextStyle(
                  fontSize: 15,
                  color: AppTheme.textSecondary,
                  letterSpacing: -0.2,
                ),
              ),
              const SizedBox(height: 32),

              // Password field
              CupertinoTextField(
                controller: _controller,
                obscureText: true,
                placeholder: 'Master Password',
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                decoration: BoxDecoration(
                  color: AppTheme.fillQuaternary,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppTheme.borderColor),
                ),
                style: const TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 17,
                ),
                placeholderStyle: const TextStyle(
                  color: AppTheme.textTertiary,
                  fontSize: 17,
                ),
                onSubmitted: (_) => _handleUnlock(),
              ),
              const SizedBox(height: 16),

              // Error
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Text(
                    _error!,
                    style: const TextStyle(
                      color: AppTheme.dangerRed,
                      fontSize: 13,
                    ),
                  ),
                ),

              // Unlock button
              SizedBox(
                width: double.infinity,
                child: CupertinoButton(
                  color: AppTheme.accentBlue,
                  borderRadius: BorderRadius.circular(10),
                  onPressed: _isLoading ? null : _handleUnlock,
                  child: _isLoading
                      ? const CupertinoActivityIndicator(
                          color: CupertinoColors.white,
                        )
                      : const Text(
                          'Unlock',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 17,
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 24),

              // Subtitle
              const Text(
                'Zero-knowledge encrypted. Your data never leaves your device unencrypted.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  color: AppTheme.textTertiary,
                  letterSpacing: -0.1,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
