import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/helpers/dialog_helper.dart';
import '../../../../core/helpers/html_processor.dart';
import '../../../../core/l10n/app_localizations.dart';
import '../../../../core/media/qsp_path_resolver.dart';
import '../../providers/game_engine_provider.dart';
import 'game_media_viewer.dart';

/// Engine message modal dialog with image extraction and text decoding.
class GameMessageDialog extends ConsumerWidget {
  const GameMessageDialog({
    super.key,
    required this.text,
    required this.onClose,
    this.gameFolderPath,
  });

  final String text;
  final VoidCallback onClose;
  final String? gameFolderPath;

  static final RegExp _numericEntity = RegExp(r'&#(x?)([0-9a-fA-F]+);');

  static String _decodeEntities(String input) {
    return input.replaceAllMapped(_numericEntity, (match) {
      final hex = match.group(1) == 'x';
      final value = int.tryParse(match.group(2)!, radix: hex ? 16 : 10);
      if (value == null) return match.group(0)!;
      return String.fromCharCode(value);
    });
  }

  String _cleanText(String input) {
    if (input.isEmpty) return input;
    return _decodeEntities(input)
        .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'</?(?:p|div|li|tr)[^>]*>', caseSensitive: false),
            '\n')
        .replaceAll(RegExp(r'<[^>]*>', caseSensitive: false, dotAll: true), '')
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&quot;', '"')
        .replaceAll('&apos;', "'")
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&amp;', '&')
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .trim();
  }

  List<String> _extractImageSources(String input) {
    if (input.isEmpty) return const [];
    final processed = HtmlProcessor.processHtml(input);
    final results = <String>[];
    final regExp = RegExp(
      r'<img[^>]+src=["\x27]?([^"\x27\s>]+)["\x27]?[^>]*>',
      caseSensitive: false,
    );
    for (final match in regExp.allMatches(processed)) {
      final src = match.group(1);
      if (src != null && src.isNotEmpty) {
        results.add(src);
      }
    }
    return results;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    final images = _extractImageSources(text);
    final clean = _cleanText(text);

    // Reuse the engine resolver: it already knows the game directory and keeps
    // a cached index, so a message never triggers a recursive folder walk.
    final resolver = ref.read(gameEngineProvider.notifier).pathResolver ??
        (gameFolderPath != null && gameFolderPath!.isNotEmpty
            ? QspPathResolver([gameFolderPath!])
            : null);

    return QuestopiaDialog(
      title: Text(l10n.message),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final src in images)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: GameMediaViewer(
                mediaPath: resolver?.resolve(src) ?? src,
                maxHeight: 240,
              ),
            ),
          if (clean.isNotEmpty)
            Text(
              clean,
              style: TextStyle(
                color: colors.onSurface,
                fontSize: 15,
                height: 1.5,
              ),
            ),
        ],
      ),
      actions: [
        QuestopiaMorphButton.filled(
          onPressed: onClose,
          child: Text(l10n.ok),
        ),
      ],
    );
  }
}
