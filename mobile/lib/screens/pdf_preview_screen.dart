import 'dart:io';
import 'package:flutter/cupertino.dart';
import 'package:provider/provider.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter_pdfview/flutter_pdfview.dart';
import '../services/vault_provider.dart';
import '../models/vault_file.dart';
import '../theme/app_theme.dart';

class PdfPreviewScreen extends StatefulWidget {
  final VaultFile file;
  const PdfPreviewScreen({super.key, required this.file});

  @override
  State<PdfPreviewScreen> createState() => _PdfPreviewScreenState();
}

class _PdfPreviewScreenState extends State<PdfPreviewScreen> {
  String? _localPath;
  bool _isLoading = true;
  String? _error;
  int _totalPages = 0;
  int _currentPage = 0;

  @override
  void initState() {
    super.initState();
    _loadPdf();
  }

  Future<void> _loadPdf() async {
    try {
      final vault = context.read<VaultProvider>();
      final bytes = await vault.decryptFileForView(widget.file);

      final dir = await getTemporaryDirectory();
      final path = '${dir.path}/preview_${widget.file.id}.pdf';
      await File(path).writeAsBytes(bytes);

      if (mounted) {
        setState(() {
          _localPath = path;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Failed to decrypt PDF: $e';
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      backgroundColor: AppTheme.bgPrimary,
      navigationBar: CupertinoNavigationBar(
        backgroundColor: AppTheme.bgPrimary.withOpacity(0.9),
        border: Border(
          bottom: BorderSide(color: AppTheme.separator.withOpacity(0.3)),
        ),
        middle: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              widget.file.originalName,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
              overflow: TextOverflow.ellipsis,
            ),
            if (_totalPages > 0)
              Text(
                'Page ${_currentPage + 1} of $_totalPages',
                style: const TextStyle(
                  fontSize: 11,
                  color: AppTheme.textTertiary,
                ),
              ),
          ],
        ),
        trailing: CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: () => Navigator.pop(context),
          child: const Text(
            'Done',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
      ),
      child: SafeArea(child: _buildBody()),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CupertinoActivityIndicator(radius: 14),
            SizedBox(height: 16),
            Text(
              'Decrypting PDF...',
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 15),
            ),
          ],
        ),
      );
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            _error!,
            style: const TextStyle(color: AppTheme.dangerRed, fontSize: 15),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    if (_localPath != null) {
      return PDFView(
        filePath: _localPath!,
        enableSwipe: true,
        swipeHorizontal: false,
        autoSpacing: true,
        pageFling: true,
        pageSnap: true,
        fitPolicy: FitPolicy.BOTH,
        nightMode: false,
        backgroundColor: const Color(0xFFFFFFFF),
        onRender: (pages) {
          if (mounted) setState(() => _totalPages = pages ?? 0);
        },
        onPageChanged: (page, total) {
          if (mounted) setState(() => _currentPage = page ?? 0);
        },
        onError: (error) {
          if (mounted) setState(() => _error = error.toString());
        },
      );
    }

    return const SizedBox.shrink();
  }
}
