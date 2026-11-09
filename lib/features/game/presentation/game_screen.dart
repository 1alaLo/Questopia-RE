import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../../core/media/qsp_html_view.dart';
import '../../../core/media/qsp_path_resolver.dart';
import '../../../core/native/qsp_models.dart';
import '../../../core/providers/settings_provider.dart';
import '../../../core/theme/game_colors.dart';
import '../../../core/theme/questopia_theme.dart';
import '../../../core/helpers/dialog_helper.dart';
import '../../../core/helpers/html_processor.dart';
import '../../../core/helpers/sheet_helper.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/widgets/questopia_scaffold.dart';
import '../../library/providers/play_session_tracker.dart';
import '../providers/game_engine_provider.dart';
import 'dialogs/game_dialogs_host.dart';
import 'sheets/game_options_sheet.dart';

class GameScreen extends ConsumerStatefulWidget {
  const GameScreen({required this.title, super.key});

  final String title;

  @override
  ConsumerState<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends ConsumerState<GameScreen>
    with WidgetsBindingObserver {
  int _activeTab =
      0; // 0: Story (Main Desc and Actions), 1: Status (Vars Desc), 2: Inventory (Objects)

  QspPathResolver? _resolver;
  String? _resolverKey;

  /// Parsed action/object labels and resolved icons are reused between
  /// rebuilds; heavy games rebuild the action list on every turn.
  final Map<String, ({String? imagePath, String text})> _visualCache = {};
  final Map<String, File?> _assetCache = {};

  QspPathResolver _getResolver() {
    // The engine already owns a resolver for the active game (it resolves
    // SHOWIMAGE/PLAYFILE paths). Reusing it means the file index and the
    // per-path cache are shared instead of built twice.
    final engine = ref.read(gameEngineProvider.notifier);
    final shared = engine.pathResolver;
    if (shared != null) {
      if (!identical(shared, _resolver)) {
        _resolver = shared;
        _resolverKey = null;
        _visualCache.clear();
        _assetCache.clear();
      }
      return shared;
    }

    final game = ref.read(gameEngineProvider).activeGame;
    final key = '${game?.gameFilePath}|${game?.folderPath}';
    if (_resolver == null || _resolverKey != key) {
      _resolverKey = key;
      _visualCache.clear();
      _assetCache.clear();
      final gameDir = game != null ? p.dirname(game.gameFilePath) : '';
      final rootFolder = game?.folderPath ?? '';
      _resolver = QspPathResolver([gameDir, rootFolder]);
    }
    return _resolver!;
  }

  bool _isHeaderVisible = true;
  Timer? _reappearTimer;

  /// Suppresses scroll handling while the header animation runs.
  ///
  /// Collapsing the header changes the body height, which changes the scroll
  /// extent, which fires another scroll notification. Without this guard the two
  /// feed each other and the bar flickers in and out.
  bool _suppressScrollEvents = false;
  Timer? _suppressTimer;

  /// Hides the header while reading downwards, restores it the moment the user
  /// scrolls back up, and never forces it back while the story sits at its end.
  void _onScrollNotification(ScrollNotification notification) {
    // Inner scrollables, such as the action list, must not drive the header.
    if (notification.depth != 0 || _suppressScrollEvents) return;
    if (notification is! ScrollUpdateNotification) return;

    final delta = notification.scrollDelta ?? 0;
    if (delta > 0.5) {
      _setHeaderVisible(false);
      _scheduleReappear(notification.metrics);
    } else if (delta < -0.5) {
      _reappearTimer?.cancel();
      _setHeaderVisible(true);
    }
  }

  void _setHeaderVisible(bool visible) {
    if (_isHeaderVisible == visible) return;
    _suppressScrollEvents = true;
    setState(() => _isHeaderVisible = visible);
    _suppressTimer?.cancel();
    _suppressTimer = Timer(const Duration(milliseconds: 320), () {
      _suppressScrollEvents = false;
    });
  }

  /// Brings the header back after the reader stops, but leaves it hidden at the
  /// very end of the story where the sudden pop used to look broken.
  void _scheduleReappear(ScrollMetrics metrics) {
    _reappearTimer?.cancel();
    if (metrics.extentAfter <= 1) return;
    _reappearTimer = Timer(const Duration(milliseconds: 1600), () {
      if (mounted) _setHeaderVisible(true);
    });
  }

  /// Drives auto-scroll for the story pane.
  final ScrollController _storyScrollController = ScrollController();

  /// Remembers the last auto-scrolled offset so each new passage advances once.
  double _lastAutoScrollOffset = 0;

  /// Play-time tracker captured once at init.
  ///
  /// The lifecycle callback cannot read the provider itself: the binding
  /// broadcasts a lifecycle change to every observer that was registered when
  /// the notification started, so a change arriving during teardown reaches a
  /// disposed element and `ref` throws. Holding the instance keeps the callback
  /// free of provider access, which is what the framework expects from an
  /// observer that may outlive its element by a frame.
  PlaySessionTracker? _playSessionTracker;

  @override
  void initState() {
    super.initState();
    final settings = ref.read(settingsProvider);
    SystemChrome.setEnabledSystemUIMode(
      settings.isImmersiveMode
          ? SystemUiMode.immersiveSticky
          : SystemUiMode.edgeToEdge,
    );
    _applyEngineSettings(settings);
    _playSessionTracker = ref.read(playSessionTrackerProvider);
    WidgetsBinding.instance.addObserver(this);
  }

  /// Starts or stops play-time accounting with the app lifecycle.
  ///
  /// Counting is tied to the foreground because a game left open in the
  /// background is not being played; pausing keeps the seconds already counted.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    // Reads the instance captured at init instead of the provider, because the
    // binding may deliver a lifecycle change to an observer whose element is
    // already disposed.
    final tracker = _playSessionTracker;
    if (tracker == null) return;
    if (state == AppLifecycleState.resumed) {
      tracker.resume();
    } else {
      tracker.pause();
      unawaited(tracker.flush());
    }
  }

  /// Begins timing the active game once the engine has a loaded world.
  ///
  /// The tracker keys off the same id the registry uses, so statistics land on
  /// the same entry the library menu reads back.
  void _syncPlaySession(GameEngineState engineState) {
    final game = engineState.activeGame;
    if (game == null || engineState.isLoading) return;
    final id = game.id.trim().isNotEmpty ? game.id.trim() : game.folderPath.trim();
    if (id.isEmpty) return;
    final tracker = ref.read(playSessionTrackerProvider);
    if (tracker.gameId == id) return;
    unawaited(tracker.start(id));
  }

  /// Pushes the audio and auto-save preferences into the running engine.
  void _applyEngineSettings(SettingsState settings) {
    ref.read(gameEngineProvider.notifier).applySettings(
          soundEnabled: settings.isSoundEnabled,
          autosaveEnabled: settings.isAutosaveEnabled,
          autosaveInterval: settings.autosaveInterval,
          imagesInDialogEnabled: settings.isImagesInDialogEnabled,
        );
  }

  /// Scrolls the story pane down after new text arrives when auto-scroll is on.
  void _maybeAutoScroll(SettingsState settings) {
    if (!settings.isUseAutoscroll) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_storyScrollController.hasClients) return;
      final position = _storyScrollController.position;
      if (position.maxScrollExtent <= _lastAutoScrollOffset) return;
      _lastAutoScrollOffset = position.maxScrollExtent;
      _storyScrollController.animateTo(
        position.maxScrollExtent,
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
      );
    });
  }

  @override
  void dispose() {
    _reappearTimer?.cancel();
    _suppressTimer?.cancel();
    _storyScrollController.dispose();
    ref.read(gameEngineProvider.notifier).stopAutosave();
    WidgetsBinding.instance.removeObserver(this);
    // Flush the final partial interval before the screen goes away, then drop
    // the session so the next game starts from a clean counter.
    final tracker = _playSessionTracker;
    _playSessionTracker = null;
    if (tracker != null) {
      unawaited(tracker.stop());
    }
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  String _stripTags(String html) {
    if (html.isEmpty) return html;
    return html
        .replaceAll(RegExp(r'<[^>]*>', caseSensitive: false, dotAll: true), '')
        .trim();
  }

  GameDialogType _lastDialogShown = GameDialogType.none;

  Future<T?> _openGameSheet<T>(WidgetBuilder builder) {
    return showQuestopiaSheet<T>(
      context: context,
      builder: builder,
    );
  }

  Future<void> _showOptionsMenu() async {
    debugPrint('[GameScreen] Opening options menu sheet...');
    await _openGameSheet<void>(
      (_) => const GameOptionsSheet(),
    );
  }



  /// Locates an asset file within the game directory using QspPathResolver.
  File? _findGameAssetFile(String relativePath) {
    if (relativePath.trim().isEmpty) return null;
    final key = relativePath.toLowerCase();
    if (_assetCache.containsKey(key)) return _assetCache[key];
    final resolved = _getResolver().resolve(relativePath);
    final file = resolved != null ? File(resolved) : null;
    _assetCache[key] = file;
    return file;
  }

  /// Extracts image paths (from image property or embedded <img> tag) and sanitized text.
  ({String? imagePath, String text}) _parseVisualItem(
    String rawName,
    String rawImage,
  ) {
    final key = '$rawName\u0000$rawImage';
    final cached = _visualCache[key];
    if (cached != null) return cached;
    // Labels can embed live values (money, time), so keep the cache bounded.
    if (_visualCache.length > 4096) _visualCache.clear();

    var imgPath = rawImage.trim();
    if (imgPath.isEmpty) {
      final match = RegExp(
        r'''<img[^>]+src=["']?([^"'>\s]+)["']?''',
        caseSensitive: false,
      ).firstMatch(rawName);
      if (match != null) {
        imgPath = match.group(1) ?? '';
      }
    }

    final cleanText = _stripTags(rawName).trim();
    final result = (
      imagePath: imgPath.isNotEmpty ? imgPath : null,
      text: cleanText,
    );
    _visualCache[key] = result;
    return result;
  }

  void _maybeShowEngineDialog(GameDialogType dialog) {
    if (dialog == GameDialogType.none || dialog == _lastDialogShown) return;
    debugPrint('[GameScreen] _maybeShowEngineDialog triggering: $dialog');
    _lastDialogShown = dialog;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      showQuestopiaDialog<void>(
        context: context,
        barrierDismissible: dialog != GameDialogType.error,
        builder: (_) => const GameDialogsHost(),
      ).then((_) {
        _lastDialogShown = GameDialogType.none;
        if (mounted) {
          ref.read(gameEngineProvider.notifier).closeDialog();
        }
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final engineState = ref.watch(gameEngineProvider);
    final engineNotifier = ref.read(gameEngineProvider.notifier);
    final settings = ref.watch(settingsProvider);

    final mainHtml = engineState.gameState.mainDesc.isNotEmpty
        ? engineState.gameState.mainDesc
        : '<p>Loading QSP Story...</p>';

    final varsHtml = engineState.gameState.varsDesc.isNotEmpty
        ? engineState.gameState.varsDesc
        : '<p>No status information available.</p>';

    // Audio and auto-save preferences must reach the engine as soon as they
    // change, without rebuilding the whole screen.
    ref.listen<SettingsState>(settingsProvider, (previous, next) {
      if (previous == null) return;
      if (previous.isSoundEnabled != next.isSoundEnabled ||
          previous.isAutosaveEnabled != next.isAutosaveEnabled ||
          previous.autosaveInterval != next.autosaveInterval) {
        _applyEngineSettings(next);
      }
    });

    _maybeShowEngineDialog(engineState.activeDialog);
    _maybeAutoScroll(settings);
    _syncPlaySession(engineState);

    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    final isDark = theme.brightness == Brightness.dark;
    final topBarBgColor =
        theme.appBarTheme.backgroundColor ?? theme.colorScheme.surface;
    final isTopBarDark =
        ThemeData.estimateBrightnessForColor(topBarBgColor) == Brightness.dark;

    final systemOverlay = SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness:
          isTopBarDark ? Brightness.light : Brightness.dark,
      statusBarBrightness: isTopBarDark ? Brightness.dark : Brightness.light,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarDividerColor: Colors.transparent,
      systemNavigationBarIconBrightness:
          isDark ? Brightness.light : Brightness.dark,
    );

    Future<bool> confirmExit() async {
      final l10n = AppLocalizations.of(context)!;
      final currentContext = context;
      final confirmed = await showQuestopiaDialog<bool>(
        context: currentContext,
        builder: (ctx) => QuestopiaConfirmationDialog(
          title: l10n.exitGameTitle,
          message: l10n.exitGameMessage,
          confirmLabel: l10n.close,
          cancelLabel: l10n.cancel,
          isDestructive: true,
          icon: Icons.exit_to_app_rounded,
        ),
      );
      if (!mounted) return false;
      return confirmed == true;
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final exit = await confirmExit();
        if (exit && context.mounted) {
          Navigator.of(context).pop(result);
        }
      },
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: systemOverlay,
        child: QuestopiaScaffold(
          isAppBarVisible: _isHeaderVisible,
          title: engineState.activeGame?.title ?? widget.title,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded),
            tooltip: MaterialLocalizations.of(context).backButtonTooltip,
            onPressed: () async {
              final exit = await confirmExit();
              if (exit && context.mounted) {
                Navigator.of(context).pop();
              }
            },
          ),
          titleWidget: Text(engineState.activeGame?.title ?? widget.title),
          actions: [
            IconButton(
              onPressed: _showOptionsMenu,
              icon: const Icon(Icons.more_vert_rounded),
              tooltip: AppLocalizations.of(context)!.gameOptionsTooltip,
            ),
          ],
          body: NotificationListener<ScrollNotification>(
            onNotification: (notification) {
              _onScrollNotification(notification);
              return false;
            },
            child: ExcludeSemantics(
              child: SafeArea(
                child: engineState.isLoading
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const CircularProgressIndicator(),
                            const SizedBox(height: 16),
                            Text(
                              AppLocalizations.of(context)!
                                  .loadingGameWorld,
                            ),
                          ],
                        ),
                      )
                    : IndexedStack(
                        index: _activeTab,
                        children: [
                          // Tab 0: Story (Main Desc + Actions + Input)
                          _buildStoryTab(
                            context,
                            mainHtml,
                            engineState,
                            engineNotifier,
                            settings,
                          ),
                          // Tab 1: Status / Vars
                          _buildVarsTab(
                            context,
                            varsHtml,
                            engineState,
                            settings,
                          ),
                          // Tab 2: Inventory / Objects
                          _buildObjectsTab(
                            context,
                            engineState,
                            engineNotifier,
                            settings,
                          ),
                        ],
                      ),
              ),
            ),
          ),
          extendBody: settings.isNavBarBlur,
          bottomNavigationBar: settings.isNavBarBlur
              ? ClipRect(
                  child: BackdropFilter(
                    filter: ImageFilter.blur(
                      sigmaX:
                          (settings.navBarBlurPercent.clamp(10.0, 100.0) / 100.0) *
                              24.0,
                      sigmaY:
                          (settings.navBarBlurPercent.clamp(10.0, 100.0) / 100.0) *
                              24.0,
                    ),
                    child: NavigationBar(
                      backgroundColor: Theme.of(context)
                          .colorScheme
                          .surface
                          .withValues(alpha: 0.70),
                      selectedIndex: _activeTab,
                      onDestinationSelected: (index) {
                        HapticFeedback.lightImpact();
                        debugPrint('[GameScreen] Switching tab to $index');
                        setState(() {
                          _activeTab = index;
                          _isHeaderVisible = true;
                        });
                      },
                      destinations: [
                        NavigationDestination(
                          icon: Badge(
                            isLabelVisible:
                                engineState.gameState.isMainDescChanged
                                    ? (_activeTab != 0)
                                    : false,
                            child: const Icon(Icons.article_outlined),
                          ),
                          selectedIcon: const Icon(Icons.article_rounded),
                          label: l10n.tabGame,
                        ),
                        NavigationDestination(
                          icon: Badge(
                            isLabelVisible:
                                engineState.gameState.isVarsDescChanged
                                    ? (_activeTab != 1)
                                    : false,
                            child: const Icon(Icons.tune_rounded),
                          ),
                          selectedIcon: const Icon(Icons.tune_rounded),
                          label: l10n.tabStatus,
                        ),
                        NavigationDestination(
                          icon: Badge(
                            isLabelVisible:
                                engineState.gameState.isObjectsChanged
                                    ? (_activeTab != 2)
                                    : false,
                            child: const Icon(Icons.backpack_outlined),
                          ),
                          selectedIcon: const Icon(Icons.backpack_rounded),
                          label: l10n.tabInventory,
                        ),
                      ],
                    ),
                  ),
                )
              : NavigationBar(
                  selectedIndex: _activeTab,
                  onDestinationSelected: (index) {
                    HapticFeedback.lightImpact();
                    debugPrint('[GameScreen] Switching tab to $index');
                    setState(() {
                      _activeTab = index;
                      _isHeaderVisible = true;
                    });
                  },
                  destinations: [
                    NavigationDestination(
                      icon: Badge(
                        isLabelVisible: engineState.gameState.isMainDescChanged
                            ? (_activeTab != 0)
                            : false,
                        child: const Icon(Icons.article_outlined),
                      ),
                      selectedIcon: const Icon(Icons.article_rounded),
                      label: l10n.tabGame,
                    ),
                    NavigationDestination(
                      icon: Badge(
                        isLabelVisible: engineState.gameState.isVarsDescChanged
                            ? (_activeTab != 1)
                            : false,
                        child: const Icon(Icons.tune_rounded),
                      ),
                      selectedIcon: const Icon(Icons.tune_rounded),
                      label: l10n.tabStatus,
                    ),
                    NavigationDestination(
                      icon: Badge(
                        isLabelVisible: engineState.gameState.isObjectsChanged
                            ? (_activeTab != 2)
                            : false,
                        child: const Icon(Icons.backpack_outlined),
                      ),
                      selectedIcon: const Icon(Icons.backpack_rounded),
                      label: l10n.tabInventory,
                    ),
                  ],
                ),
        ),
      ),
    );
  }

  /// Resolves the reading surface from the selected preset plus any overrides.
  ///
  /// An explicit custom colour always wins over the preset, so the two features
  /// stay independent.
  ({Color background, Color foreground, Color link}) _readingSurface(
    SettingsState settings,
    ThemeData theme,
  ) {
    final brightness = theme.brightness;
    // Only the opt-in "materialYou" preset is allowed to read the scheme, so the
    // default surface stays stable even when the accent follows the wallpaper.
    final scheme = theme.colorScheme;
    final background = settings.useGameBackgroundColor
        ? Color(settings.gameBackColor)
        : ReadingThemeColors.background(
            settings.readingTheme,
            brightness,
            scheme: scheme,
          );
    final foreground = settings.useGameTextColor
        ? Color(settings.gameTextColor)
        : ReadingThemeColors.foreground(
            settings.readingTheme,
            brightness,
            scheme: scheme,
          );
    final link = settings.useGameLinkColor
        ? Color(settings.gameLinkColor)
        : ReadingThemeColors.link(
            settings.readingTheme,
            brightness,
            scheme.primary,
            scheme: scheme,
          );
    return (background: background, foreground: foreground, link: link);
  }

  /// Text style shared by the story, status and inventory panes.
  TextStyle _gameTextStyle(SettingsState settings, Color color) => TextStyle(
        fontSize: settings.fontSize.clamp(
          QuestopiaTheme.minGameFontSize,
          QuestopiaTheme.maxGameFontSize,
        ),
        color: color,
        fontFamily: QuestopiaTheme.fontFamilyFor(settings.typefaceIndex),
        height: 1.5,
      );

  /// Widest comfortable measure for the reading panes.
  ///
  /// On a tablet the story pane is more than a thousand points wide; letting
  /// the text run the full width produces very long lines that are hard to
  /// read, so the column is capped and centred instead.
  static const double _maxReadingWidth = 820;

  /// Breakpoint above which the actions get their own column.
  static const double _wideLayoutBreakpoint = 900;

  /// Width of the action column in the tablet layout.
  static const double _actionColumnWidth = 360;

  Widget _buildStoryTab(
    BuildContext context,
    String mainHtml,
    GameEngineState engineState,
    GameEngineNotifier engineNotifier,
    SettingsState settings,
  ) {
    final size = MediaQuery.sizeOf(context);
    final screenHeight = size.height;
    final isWide = size.width >= _wideLayoutBreakpoint;
    double maxActionHeight;
    switch (settings.actionsHeightRatio) {
      case '1/5':
        maxActionHeight = screenHeight * 0.20;
        break;
      case '1/4':
        maxActionHeight = screenHeight * 0.25;
        break;
      case '1/3':
        maxActionHeight = screenHeight * 0.33;
        break;
      case '1/2':
        maxActionHeight = screenHeight * 0.50;
        break;
      case '2/3':
        maxActionHeight = screenHeight * 0.66;
        break;
      default:
        maxActionHeight = screenHeight * 0.33;
        break;
    }
    maxActionHeight = maxActionHeight.clamp(80.0, 450.0);

    final resolver = _getResolver();
    final theme = Theme.of(context);
    final surface = _readingSurface(settings, theme);

    final story = SingleChildScrollView(
      controller: _storyScrollController,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: _maxReadingWidth),
          child: QspHtmlView(
            html: mainHtml,
            resolver: resolver,
            backgroundColor: surface.background,
            textStyle: _gameTextStyle(settings, surface.foreground),
            linkColor: surface.link,
            disableImages: settings.isImageDisabled,
            muteVideos: settings.isVideoMute,
            imageWidthOverride:
                settings.isAutoWidth ? null : settings.customWidthImage,
            imageHeightOverride:
                settings.isAutoHeight ? null : settings.customHeightImage,
            onTapLink: (url) {
              final lower = url.toLowerCase();
              if (lower.startsWith('exec:') ||
                  lower.contains('/exec:') ||
                  lower.contains('exec%3a')) {
                final code = HtmlProcessor.decodeExecUrl(url);
                engineNotifier.execCode(code);
                return true;
              }
              return false;
            },
          ),
        ),
      ),
    );

    final hasActions = engineState.gameState.actions.isNotEmpty;
    final actions = hasActions
        ? Container(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            decoration: BoxDecoration(
              color: surface.background,
              // The separator line is opt-in, so the panel reads as part of
              // the story surface until the user asks for a divider.
              border: settings.isUseSeparator
                  ? Border(
                      top: BorderSide(
                        color: theme.colorScheme.outlineVariant
                            .withValues(alpha: 0.3),
                        width: 0.5,
                      ),
                    )
                  : null,
            ),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: isWide ? double.infinity : maxActionHeight,
              ),
              child: SingleChildScrollView(
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: engineState.gameState.actions.map((act) {
                    return _buildActionButton(
                      context,
                      act,
                      engineNotifier,
                      settings,
                    );
                  }).toList(),
                ),
              ),
            ),
          )
        : null;

    if (isWide) {
      // Tablet: story on the left, actions in a dedicated column. This mirrors
      // the classic QSP layout and keeps the buttons reachable instead of
      // pushing them off the bottom of a tall screen.
      return Container(
        color: surface.background,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: story),
            if (actions != null) ...[
              VerticalDivider(
                width: 1,
                thickness: 0.5,
                color: theme.colorScheme.outlineVariant.withValues(alpha: 0.3),
              ),
              SizedBox(
                width: _actionColumnWidth,
                child: actions,
              ),
            ],
          ],
        ),
      );
    }

    return Container(
      color: surface.background,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: story),
          if (actions != null) actions,
        ],
      ),
    );
  }

  Widget _buildActionButton(
    BuildContext context,
    QspAction act,
    GameEngineNotifier engineNotifier,
    SettingsState settings,
  ) {
    final colors = Theme.of(context).colorScheme;
    final visual = _parseVisualItem(act.name, act.image);
    // Action labels follow the same size as the story text so the whole game
    // surface scales together.
    final actionFontSize = settings.fontSize.clamp(
      QuestopiaTheme.minGameFontSize,
      QuestopiaTheme.maxGameFontSize,
    );
    final file =
        visual.imagePath != null ? _findGameAssetFile(visual.imagePath!) : null;

    Widget? imageWidget;
    if (file != null) {
      imageWidget = ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: Image.file(
          file,
          height: 28,
          fit: BoxFit.contain,
          gaplessPlayback: true,
          errorBuilder: (_, __, ___) => const SizedBox.shrink(),
        ),
      );
    }

    if (imageWidget != null && visual.text.isEmpty) {
      // Pure image button - custom sleek square/pill tile
      return Material(
        color: colors.secondaryContainer,
        borderRadius: BorderRadius.circular(12),
        elevation: 0.5,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () {
            debugPrint(
                '[GameScreen] Tapped action #${act.index}: "${act.name}"');
            engineNotifier.execAction(act.index);
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 32, maxHeight: 44),
              child: imageWidget,
            ),
          ),
        ),
      );
    }

    return FilledButton.tonal(
      onPressed: () {
        debugPrint('[GameScreen] Tapped action #${act.index}: "${act.name}"');
        engineNotifier.execAction(act.index);
      },
      style: FilledButton.styleFrom(
        padding: EdgeInsets.symmetric(
          horizontal: 14,
          vertical: imageWidget != null ? 8 : 10,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (imageWidget != null) ...[
            imageWidget,
            if (visual.text.isNotEmpty) const SizedBox(width: 8),
          ],
          if (visual.text.isNotEmpty)
            Flexible(
              child: Text(
                visual.text,
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: actionFontSize,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildVarsTab(
    BuildContext context,
    String varsHtml,
    GameEngineState engineState,
    SettingsState settings,
  ) {
    if (engineState.gameState.varsDesc.trim().isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.tune_rounded,
              size: 48,
              color: Theme.of(context).colorScheme.outline,
            ),
            const SizedBox(height: 12),
            Text(
              AppLocalizations.of(context)!.noStatusInformation,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: Theme.of(context).colorScheme.outline,
                  ),
            ),
          ],
        ),
      );
    }

    final resolver = _getResolver();
    final theme = Theme.of(context);
    final surface = _readingSurface(settings, theme);

    return Container(
      color: surface.background,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: _maxReadingWidth),
            child: QspHtmlView(
              html: varsHtml,
              resolver: resolver,
              backgroundColor: surface.background,
              textStyle: _gameTextStyle(settings, surface.foreground),
              linkColor: surface.link,
              disableImages: settings.isImageDisabled,
              muteVideos: settings.isVideoMute,
              imageWidthOverride:
                  settings.isAutoWidth ? null : settings.customWidthImage,
              imageHeightOverride:
                  settings.isAutoHeight ? null : settings.customHeightImage,
              onTapLink: (url) {
                final lower = url.toLowerCase();
                if (lower.startsWith('exec:') ||
                    lower.contains('/exec:') ||
                    lower.contains('exec%3a')) {
                  final code = HtmlProcessor.decodeExecUrl(url);
                  ref.read(gameEngineProvider.notifier).execCode(code);
                  return true;
                }
                return false;
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildObjectsTab(
    BuildContext context,
    GameEngineState engineState,
    GameEngineNotifier engineNotifier,
    SettingsState settings,
  ) {
    final objects = engineState.gameState.objects;
    final colors = Theme.of(context).colorScheme;
    // The inventory keeps the Material surface: its cards are Material widgets,
    // so a reading preset would fight the card colours. Only the font size is
    // shared with the reading panes.
    final objectFontSize = settings.fontSize.clamp(
      QuestopiaTheme.minGameFontSize,
      QuestopiaTheme.maxGameFontSize,
    );

    if (objects.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.backpack_outlined,
              size: 48,
              color: colors.outline,
            ),
            const SizedBox(height: 12),
            Text(
              AppLocalizations.of(context)!.inventoryIsEmpty,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: colors.outline,
                  ),
            ),
          ],
        ),
      );
    }

    final parsedObjects = objects.map((obj) {
      final visual = _parseVisualItem(obj.name, obj.image);
      final file = visual.imagePath != null
          ? _findGameAssetFile(visual.imagePath!)
          : null;
      return (obj: obj, visual: visual, file: file);
    }).toList();

    final allPureImages = parsedObjects.every(
      (p) => p.file != null && p.file!.existsSync() && p.visual.text.isEmpty,
    );

    if (allPureImages) {
      // Pure image inventory design: sleek, native square tiles grid
      return GridView.builder(
        padding: const EdgeInsets.all(16),
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 84,
          childAspectRatio: 1.0,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
        ),
        itemCount: parsedObjects.length,
        itemBuilder: (context, index) {
          final item = parsedObjects[index];
          return Card(
            elevation: 1,
            margin: EdgeInsets.zero,
            color: colors.surfaceContainerHigh,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: BorderSide(
                color: colors.outlineVariant.withValues(alpha: 0.6),
                width: 1,
              ),
            ),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () {
                debugPrint(
                    '[GameScreen] Selected object #${item.obj.index}: "${item.obj.name}"');
                engineNotifier.selectObject(item.obj.index);
              },
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Center(
                  child: Image.file(
                    item.file!,
                    fit: BoxFit.contain,
                    gaplessPlayback: true,
                    errorBuilder: (_, __, ___) => Icon(
                      Icons.inventory_2_outlined,
                      color: colors.outline,
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      );
    }

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: _maxReadingWidth),
        child: ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: parsedObjects.length,
          itemBuilder: (context, index) {
            final item = parsedObjects[index];
            final hasImage = item.file != null && item.file!.existsSync();

            return Card(
              margin: const EdgeInsets.only(bottom: 10),
              elevation: 0.5,
              color: colors.surfaceContainerLow,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: BorderSide(
                  color: colors.outlineVariant.withValues(alpha: 0.4),
                  width: 0.5,
                ),
              ),
              clipBehavior: Clip.antiAlias,
              child: ListTile(
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                leading: hasImage
                    ? Container(
                        width: 52,
                        height: 52,
                        decoration: BoxDecoration(
                          color: colors.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color:
                                colors.outlineVariant.withValues(alpha: 0.5),
                            width: 0.5,
                          ),
                        ),
                        padding: const EdgeInsets.all(4),
                        child: Image.file(
                          item.file!,
                          fit: BoxFit.contain,
                          gaplessPlayback: true,
                          errorBuilder: (_, __, ___) => Icon(
                            Icons.inventory_2_outlined,
                            color: colors.outline,
                          ),
                        ),
                      )
                    : CircleAvatar(
                        backgroundColor: colors.secondaryContainer,
                        child: Icon(
                          Icons.inventory_2_outlined,
                          color: colors.onSecondaryContainer,
                        ),
                      ),
                title: Text(
                  item.visual.text.isNotEmpty
                      ? item.visual.text
                      : 'Item #${item.obj.index + 1}',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: objectFontSize,
                    color: colors.onSurface,
                  ),
                ),
                onTap: () {
                  debugPrint(
                      '[GameScreen] Selected object #${item.obj.index}: "${item.obj.name}"');
                  engineNotifier.selectObject(item.obj.index);
                },
              ),
            );
          },
        ),
      ),
    );
  }
}
