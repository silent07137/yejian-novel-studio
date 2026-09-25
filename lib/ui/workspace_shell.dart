import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:flutter/services.dart';

import '../models/library_data.dart';
import '../platform/document_saver.dart';
import '../state/app_controller.dart';
import '../theme/app_theme.dart';
import 'book_management.dart';
import 'book_pages.dart';

class WorkspaceShell extends StatelessWidget {
  const WorkspaceShell({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        return LayoutBuilder(
          builder: (context, constraints) {
            final desktop = constraints.maxWidth >= 880;
            final dark = Theme.of(context).brightness == Brightness.dark;
            final keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;
            final hasMobileBookNavigation =
                !desktop && !keyboardOpen && controller.isBookWorkspace;
            final hasMobileAppNavigation =
                !desktop && !keyboardOpen && controller.isAppNavigationContext;
            final hasMobileNavigation =
                hasMobileBookNavigation || hasMobileAppNavigation;
            final systemStyle = SystemUiOverlayStyle(
              statusBarColor: Colors.transparent,
              statusBarIconBrightness: dark
                  ? Brightness.light
                  : Brightness.dark,
              statusBarBrightness: dark ? Brightness.dark : Brightness.light,
              systemNavigationBarColor: Colors.transparent,
              systemNavigationBarIconBrightness: dark
                  ? Brightness.light
                  : Brightness.dark,
              systemNavigationBarDividerColor: Colors.transparent,
              systemNavigationBarContrastEnforced: false,
            );
            return AnnotatedRegion<SystemUiOverlayStyle>(
              value: systemStyle,
              child: PopScope(
                canPop: !controller.canGoBack,
                onPopInvokedWithResult: (didPop, _) {
                  if (!didPop && controller.canGoBack) controller.goBack();
                },
                child: Scaffold(
                  resizeToAvoidBottomInset: true,
                  body: SafeArea(
                    bottom: !hasMobileNavigation,
                    child: desktop
                        ? Row(
                            children: [
                              _DesktopSidebar(controller: controller),
                              Expanded(
                                child: _WorkspaceBody(controller: controller),
                              ),
                            ],
                          )
                        : _FloatingNavigationHost(
                            controller: controller,
                            page: controller.page,
                            bookNavigation: hasMobileBookNavigation,
                            hasNavigation: hasMobileNavigation,
                            child: _WorkspaceBody(controller: controller),
                          ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _DesktopSidebar extends StatelessWidget {
  const _DesktopSidebar({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final palette = paletteById(controller.data.settings.palette);
    final sidebarColor = Theme.of(context).brightness == Brightness.dark
        ? Theme.of(context).colorScheme.surfaceContainerLowest
        : palette.sidebar;
    final book = controller.activeBook;
    return Container(
      width: 224,
      decoration: BoxDecoration(
        color: sidebarColor,
        border: Border(
          right: BorderSide(color: Theme.of(context).dividerColor),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(16, 22, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary,
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(
                  Icons.auto_stories_rounded,
                  color: Theme.of(context).colorScheme.onPrimary,
                  size: 20,
                ),
              ),
              const SizedBox(width: 11),
              const Text(
                '页间',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
              ),
            ],
          ),
          if (book != null && controller.isBookContext) ...[
            const SizedBox(height: 24),
            _ActiveBookTile(book: book, controller: controller),
          ],
          const Spacer(),
          _NavigationTile(
            icon: Icons.grid_view_rounded,
            label: '书架',
            selected: controller.page == WorkspacePage.home,
            onTap: () => controller.navigate(WorkspacePage.home),
          ),
          if (book != null && controller.isBookContext) ...[
            const SizedBox(height: 6),
            Divider(color: Theme.of(context).dividerColor),
            _NavigationTile(
              icon: Icons.edit_note_rounded,
              label: '本书 · 写作',
              selected: controller.page == WorkspacePage.writing,
              onTap: () => controller.navigateBook(WorkspacePage.writing),
            ),
            _NavigationTile(
              icon: Icons.collections_bookmark_outlined,
              label: '本书 · 设定',
              selected: controller.page == WorkspacePage.characters,
              onTap: () => controller.navigateBook(WorkspacePage.characters),
            ),
            _NavigationTile(
              icon: Icons.account_tree_outlined,
              label: '本书 · 情节',
              selected: controller.page == WorkspacePage.timeline,
              onTap: () => controller.navigateBook(WorkspacePage.timeline),
            ),
            _NavigationTile(
              icon: Icons.ios_share_rounded,
              label: '本书 · 导出',
              selected: controller.page == WorkspacePage.export,
              onTap: () => controller.navigateBook(WorkspacePage.export),
            ),
          ],
          const SizedBox(height: 6),
          Divider(color: Theme.of(context).dividerColor),
          _NavigationTile(
            icon: Icons.settings_outlined,
            label: '设置',
            selected:
                controller.page == WorkspacePage.settings ||
                controller.page == WorkspacePage.appSettings ||
                controller.page == WorkspacePage.about ||
                controller.page == WorkspacePage.profile,
            onTap: () => controller.navigate(WorkspacePage.settings),
          ),
        ],
      ),
    );
  }
}

class _ActiveBookTile extends StatelessWidget {
  const _ActiveBookTile({required this.book, required this.controller});

  final Book book;
  final AppController controller;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => controller.navigate(WorkspacePage.bookOverview),
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Row(
          children: [
            _Cover(book: book, width: 36, height: 48, radius: 7),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    book.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${book.wordCount} 字',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NavigationTile extends StatelessWidget {
  const _NavigationTile({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          height: 42,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: selected ? scheme.primaryContainer : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              Icon(
                icon,
                size: 19,
                color: selected ? scheme.onPrimaryContainer : null,
              ),
              const SizedBox(width: 11),
              Text(
                label,
                style: TextStyle(fontWeight: selected ? FontWeight.w600 : null),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MobileBookNavigation extends StatelessWidget {
  const _MobileBookNavigation({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    const pages = [
      WorkspacePage.writing,
      WorkspacePage.characters,
      WorkspacePage.timeline,
      WorkspacePage.export,
    ];
    final selected = pages.indexOf(controller.page).clamp(0, 3);
    final scheme = Theme.of(context).colorScheme;
    final bottomInset = MediaQuery.viewPaddingOf(context).bottom;
    final capsuleWidth = (MediaQuery.sizeOf(context).width - 32).clamp(
      220.0,
      280.0,
    );
    final itemWidth = (capsuleWidth - 8) / pages.length;
    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset + 8),
      child: Center(
        heightFactor: 1,
        child: SizedBox(
          key: const ValueKey('book-nav-capsule'),
          width: capsuleWidth,
          height: 60,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: scheme.surfaceContainer.withValues(alpha: .97),
              borderRadius: BorderRadius.circular(31),
              border: Border.all(color: scheme.outlineVariant),
              boxShadow: [
                BoxShadow(
                  color: scheme.shadow.withValues(alpha: .14),
                  blurRadius: 18,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  AnimatedPositioned(
                    key: const ValueKey('book-nav-indicator'),
                    left: selected * itemWidth,
                    top: 0,
                    bottom: 0,
                    width: itemWidth,
                    duration: const Duration(milliseconds: 260),
                    curve: Curves.easeOutCubic,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: scheme.primaryContainer,
                        borderRadius: BorderRadius.circular(27),
                      ),
                    ),
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: _AppNavigationItem(
                          key: const ValueKey('book-nav-writing'),
                          icon: Icons.edit_note_outlined,
                          selectedIcon: Icons.edit_note_rounded,
                          label: '写作',
                          selected: selected == 0,
                          onTap: () => controller.navigateBook(pages[0]),
                        ),
                      ),
                      Expanded(
                        child: _AppNavigationItem(
                          key: const ValueKey('book-nav-settings'),
                          icon: Icons.collections_bookmark_outlined,
                          selectedIcon: Icons.collections_bookmark_rounded,
                          label: '设定',
                          selected: selected == 1,
                          onTap: () => controller.navigateBook(pages[1]),
                        ),
                      ),
                      Expanded(
                        child: _AppNavigationItem(
                          key: const ValueKey('book-nav-story'),
                          icon: Icons.account_tree_outlined,
                          selectedIcon: Icons.account_tree_rounded,
                          label: '情节',
                          selected: selected == 2,
                          onTap: () => controller.navigateBook(pages[2]),
                        ),
                      ),
                      Expanded(
                        child: _AppNavigationItem(
                          key: const ValueKey('book-nav-export'),
                          icon: Icons.ios_share_outlined,
                          selectedIcon: Icons.ios_share_rounded,
                          label: '导出',
                          selected: selected == 3,
                          onTap: () => controller.navigateBook(pages[3]),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MobileAppNavigation extends StatelessWidget {
  const _MobileAppNavigation({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final selected = controller.page == WorkspacePage.home ? 0 : 1;
    final scheme = Theme.of(context).colorScheme;
    final bottomInset = MediaQuery.viewPaddingOf(context).bottom;
    final capsuleWidth = MediaQuery.sizeOf(context).width < 278 ? 184.0 : 196.0;
    final itemWidth = (capsuleWidth - 8) / 2;
    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset + 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            key: const ValueKey('app-nav-capsule'),
            width: capsuleWidth,
            height: 60,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: scheme.surfaceContainer.withValues(alpha: .97),
                borderRadius: BorderRadius.circular(31),
                border: Border.all(color: scheme.outlineVariant),
                boxShadow: [
                  BoxShadow(
                    color: scheme.shadow.withValues(alpha: .14),
                    blurRadius: 18,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    AnimatedAlign(
                      key: const ValueKey('app-nav-indicator'),
                      alignment: selected == 0
                          ? Alignment.centerLeft
                          : Alignment.centerRight,
                      duration: const Duration(milliseconds: 260),
                      curve: Curves.easeOutCubic,
                      child: Container(
                        width: itemWidth,
                        decoration: BoxDecoration(
                          color: scheme.primaryContainer,
                          borderRadius: BorderRadius.circular(27),
                        ),
                      ),
                    ),
                    Row(
                      children: [
                        Expanded(
                          child: _AppNavigationItem(
                            key: const ValueKey('app-nav-bookshelf'),
                            icon: Icons.auto_stories_outlined,
                            selectedIcon: Icons.auto_stories_rounded,
                            label: '书架',
                            selected: selected == 0,
                            onTap: () =>
                                controller.navigate(WorkspacePage.home),
                          ),
                        ),
                        Expanded(
                          child: _AppNavigationItem(
                            key: const ValueKey('app-nav-settings'),
                            icon: Icons.settings_outlined,
                            selectedIcon: Icons.settings_rounded,
                            label: '设置',
                            selected: selected == 1,
                            onTap: () =>
                                controller.navigate(WorkspacePage.settings),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FloatingNavigationHost extends StatefulWidget {
  const _FloatingNavigationHost({
    required this.controller,
    required this.page,
    required this.bookNavigation,
    required this.hasNavigation,
    required this.child,
  });

  final AppController controller;
  final WorkspacePage page;
  final bool bookNavigation;
  final bool hasNavigation;
  final Widget child;

  @override
  State<_FloatingNavigationHost> createState() =>
      _FloatingNavigationHostState();
}

class _FloatingNavigationHostState extends State<_FloatingNavigationHost> {
  bool _navigationVisible = true;

  @override
  void didUpdateWidget(covariant _FloatingNavigationHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.page != widget.page ||
        oldWidget.bookNavigation != widget.bookNavigation) {
      _navigationVisible = true;
    }
  }

  bool _handleUserScroll(UserScrollNotification notification) {
    if (notification.metrics.axis != Axis.vertical) return false;
    final shouldShow = switch (notification.direction) {
      ScrollDirection.reverse => false,
      ScrollDirection.forward => true,
      ScrollDirection.idle => _navigationVisible,
    };
    if (shouldShow != _navigationVisible) {
      setState(() => _navigationVisible = shouldShow);
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      clipBehavior: Clip.hardEdge,
      children: [
        NotificationListener<UserScrollNotification>(
          onNotification: _handleUserScroll,
          child: widget.child,
        ),
        if (widget.hasNavigation)
          Positioned(
            key: ValueKey(
              widget.bookNavigation
                  ? 'floating-book-navigation'
                  : 'floating-app-navigation',
            ),
            left: 0,
            right: 0,
            bottom: 0,
            child: IgnorePointer(
              ignoring: !_navigationVisible,
              child: ExcludeSemantics(
                excluding: !_navigationVisible,
                child: AnimatedSlide(
                  key: ValueKey(
                    widget.bookNavigation
                        ? 'floating-book-navigation-motion'
                        : 'floating-app-navigation-motion',
                  ),
                  offset: _navigationVisible
                      ? Offset.zero
                      : const Offset(0, 1.45),
                  duration: const Duration(milliseconds: 240),
                  curve: Curves.easeOutCubic,
                  child: widget.bookNavigation
                      ? _MobileBookNavigation(controller: widget.controller)
                      : _MobileAppNavigation(controller: widget.controller),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _AppNavigationItem extends StatelessWidget {
  const _AppNavigationItem({
    super.key,
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(31),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AnimatedScale(
                scale: selected ? 1.08 : 1,
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutBack,
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 180),
                  child: Icon(
                    selected ? selectedIcon : icon,
                    key: ValueKey(selected),
                    size: 20,
                    color: selected
                        ? scheme.onPrimaryContainer
                        : scheme.onSurfaceVariant,
                  ),
                ),
              ),
              const SizedBox(height: 2),
              AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 180),
                style: TextStyle(
                  fontSize: 10.5,
                  height: 1,
                  color: selected
                      ? scheme.onPrimaryContainer
                      : scheme.onSurfaceVariant,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                ),
                child: Text(label),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WorkspaceBody extends StatelessWidget {
  const _WorkspaceBody({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final content = switch (controller.page) {
      WorkspacePage.home => HomePage(controller: controller),
      WorkspacePage.bookOverview => BookOverviewPage(controller: controller),
      WorkspacePage.writing => WritingPage(controller: controller),
      WorkspacePage.characters => BookSettingsPage(controller: controller),
      WorkspacePage.timeline => StoryPlanningPage(controller: controller),
      WorkspacePage.export => ExportPage(controller: controller),
      WorkspacePage.settings => SettingsPage(controller: controller),
      WorkspacePage.appSettings => ApplicationSettingsPage(
        controller: controller,
      ),
      WorkspacePage.about => const AboutPage(),
      WorkspacePage.profile => ProfilePage(controller: controller),
    };
    return Column(
      children: [
        _TopBar(controller: controller),
        Expanded(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            reverseDuration: const Duration(milliseconds: 180),
            layoutBuilder: (currentChild, previousChildren) => Stack(
              alignment: Alignment.topCenter,
              fit: StackFit.expand,
              children: [...previousChildren, ?currentChild],
            ),
            transitionBuilder: (child, animation) => FadeTransition(
              opacity: animation,
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0.025, 0),
                  end: Offset.zero,
                ).animate(animation),
                child: SizedBox.expand(child: child),
              ),
            ),
            child: KeyedSubtree(key: ValueKey(controller.page), child: content),
          ),
        ),
      ],
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final canGoBack = controller.canGoBack;
    final compact = MediaQuery.sizeOf(context).width < 600;
    return Container(
      height: 56,
      padding: EdgeInsets.symmetric(horizontal: compact ? 10 : 20),
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        border: Border(
          bottom: BorderSide(color: Theme.of(context).dividerColor),
        ),
      ),
      child: compact
          ? Stack(
              alignment: Alignment.center,
              children: [
                if (canGoBack)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: IconButton(
                      tooltip: '返回',
                      onPressed: controller.goBack,
                      icon: const Icon(Icons.arrow_back_rounded),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 102),
                  child: _buildTitle(context, TextAlign.center),
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: _buildActions(context),
                ),
              ],
            )
          : Row(
              children: [
                if (canGoBack) ...[
                  IconButton(
                    tooltip: '返回',
                    onPressed: controller.goBack,
                    icon: const Icon(Icons.arrow_back_rounded),
                  ),
                  const SizedBox(width: 6),
                ],
                Expanded(child: _buildTitle(context, TextAlign.start)),
                _SaveIndicator(state: controller.saveState),
                const SizedBox(width: 6),
                _buildActions(context),
              ],
            ),
    );
  }

  Widget _buildTitle(BuildContext context, TextAlign textAlign) =>
      AnimatedSwitcher(
        duration: const Duration(milliseconds: 180),
        child: SizedBox(
          width: double.infinity,
          child: Text(
            controller.pageTitle,
            key: ValueKey(controller.pageTitle),
            maxLines: 1,
            textAlign: textAlign,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleLarge,
          ),
        ),
      );

  Widget _buildActions(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: controller.isBookContext
        ? [
            IconButton(
              tooltip: '在本书中搜索',
              onPressed: () => showSearch<void>(
                context: context,
                delegate: _WorkspaceSearchDelegate(controller),
              ),
              icon: const Icon(Icons.search_rounded),
            ),
            PopupMenuButton<WorkspacePage>(
              tooltip: '更多',
              icon: const Icon(Icons.more_horiz_rounded),
              onSelected: (page) =>
                  page == WorkspacePage.home ||
                      page == WorkspacePage.bookOverview
                  ? controller.navigate(page)
                  : controller.openSubpage(page),
              itemBuilder: (context) => const [
                PopupMenuItem(
                  value: WorkspacePage.bookOverview,
                  child: Text('作品首页'),
                ),
                PopupMenuItem(value: WorkspacePage.home, child: Text('回到书架')),
                PopupMenuItem(value: WorkspacePage.settings, child: Text('设置')),
              ],
            ),
          ]
        : const [],
  );
}

class _WorkspaceSearchDelegate extends SearchDelegate<void> {
  _WorkspaceSearchDelegate(this.controller);

  final AppController controller;

  @override
  String? get searchFieldLabel => '搜索章节、角色、设定与事件';

  List<_WorkspaceSearchEntry> get _entries {
    final book = controller.activeBook;
    if (book == null) return const [];
    return [
      ...book.chapters.map(
        (item) => _WorkspaceSearchEntry(
          title: item.title,
          subtitle: '章节 · ${item.summary}',
          page: WorkspacePage.writing,
          chapterId: item.id,
        ),
      ),
      ...book.roles.map(
        (item) => _WorkspaceSearchEntry(
          title: item.name,
          subtitle: '角色 · ${item.identity}',
          page: WorkspacePage.characters,
        ),
      ),
      ...book.worlds.map(
        (item) => _WorkspaceSearchEntry(
          title: item.title,
          subtitle: '世界观 · ${item.type}',
          page: WorkspacePage.characters,
        ),
      ),
      ...book.events.map(
        (item) => _WorkspaceSearchEntry(
          title: item.title,
          subtitle: '事件 · ${item.storyDate}',
          page: WorkspacePage.timeline,
        ),
      ),
    ];
  }

  @override
  List<Widget>? buildActions(BuildContext context) => [
    if (query.isNotEmpty)
      IconButton(
        tooltip: '清空',
        onPressed: () => query = '',
        icon: const Icon(Icons.close_rounded),
      ),
  ];

  @override
  Widget? buildLeading(BuildContext context) => IconButton(
    tooltip: '返回',
    onPressed: () => close(context, null),
    icon: const Icon(Icons.arrow_back_ios_new_rounded),
  );

  @override
  Widget buildResults(BuildContext context) => _buildList(context);

  @override
  Widget buildSuggestions(BuildContext context) => _buildList(context);

  Widget _buildList(BuildContext context) {
    final needle = query.trim().toLowerCase();
    final entries = _entries
        .where(
          (item) =>
              needle.isEmpty ||
              item.title.toLowerCase().contains(needle) ||
              item.subtitle.toLowerCase().contains(needle),
        )
        .toList();
    if (entries.isEmpty) return const Center(child: Text('没有找到匹配内容'));
    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: entries.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final item = entries[index];
        return ListTile(
          title: Text(item.title),
          subtitle: Text(item.subtitle),
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: () {
            close(context, null);
            if (item.chapterId != null) {
              controller.selectChapter(item.chapterId!);
            }
            const bookPages = {
              WorkspacePage.writing,
              WorkspacePage.characters,
              WorkspacePage.timeline,
              WorkspacePage.export,
            };
            if (bookPages.contains(item.page)) {
              controller.navigateBook(item.page);
            } else {
              controller.navigate(item.page);
            }
          },
        );
      },
    );
  }
}

class _WorkspaceSearchEntry {
  const _WorkspaceSearchEntry({
    required this.title,
    required this.subtitle,
    required this.page,
    this.chapterId,
  });

  final String title;
  final String subtitle;
  final WorkspacePage page;
  final String? chapterId;
}

class _SaveIndicator extends StatelessWidget {
  const _SaveIndicator({required this.state});

  final SaveState state;

  @override
  Widget build(BuildContext context) {
    final (icon, label) = switch (state) {
      SaveState.saved => (Icons.check_circle_outline_rounded, '已保存到本机'),
      SaveState.saving => (Icons.sync_rounded, '保存中'),
      SaveState.failed => (Icons.error_outline_rounded, '保存失败'),
    };
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          icon,
          size: 16,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
        const SizedBox(width: 6),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}

class HomePage extends StatelessWidget {
  const HomePage({super.key, required this.controller});

  final AppController controller;

  Future<void> _newBook(BuildContext context) async {
    final field = TextEditingController();
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('新建作品'),
        content: TextField(
          controller: field,
          autofocus: true,
          decoration: const InputDecoration(labelText: '书名'),
          onSubmitted: (value) => Navigator.pop(context, value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, field.text),
            child: const Text('创建'),
          ),
        ],
      ),
    );
    field.dispose();
    if (value != null) controller.createBook(value);
  }

  @override
  Widget build(BuildContext context) {
    final data = controller.data;
    final compact = MediaQuery.sizeOf(context).width < 600;
    return SingleChildScrollView(
      padding: EdgeInsets.all(compact ? 16 : 28),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1180),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '我的书架',
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                  ),
                  FilledButton.icon(
                    onPressed: () => _newBook(context),
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('新建作品'),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              if (data.books.isEmpty)
                _EmptyCard(onPressed: () => _newBook(context))
              else
                LayoutBuilder(
                  builder: (context, constraints) {
                    final count = constraints.maxWidth >= 1000
                        ? 3
                        : constraints.maxWidth >= 640
                        ? 2
                        : 1;
                    final width =
                        (constraints.maxWidth - (count - 1) * 16) / count;
                    return Wrap(
                      spacing: 16,
                      runSpacing: 16,
                      children: data.books
                          .map(
                            (book) => SizedBox(
                              width: width,
                              child: _BookCard(
                                book: book,
                                controller: controller,
                              ),
                            ),
                          )
                          .toList(),
                    );
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BookCard extends StatelessWidget {
  const _BookCard({required this.book, required this.controller});

  final Book book;
  final AppController controller;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => controller.openBook(book.id),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Stack(
                children: [
                  _Cover(book: book, width: 82, height: 112, radius: 10),
                  Positioned(
                    right: 4,
                    bottom: 4,
                    child: IconButton.filledTonal(
                      tooltip: '更换封面',
                      constraints: const BoxConstraints.tightFor(
                        width: 30,
                        height: 30,
                      ),
                      padding: EdgeInsets.zero,
                      onPressed: () => controller.chooseCover(book),
                      icon: const Icon(Icons.image_outlined, size: 16),
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      book.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      book.description.isEmpty ? '尚未填写简介' : book.description,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      '${book.chapters.length} 章  ·  ${book.wordCount} 字',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                tooltip: '作品操作',
                onSelected: (value) {
                  if (value == 'edit') {
                    editBookDetails(context, controller, book);
                  } else if (value == 'delete') {
                    confirmBookDeletion(context, controller, book);
                  }
                },
                itemBuilder: (context) => const [
                  PopupMenuItem(value: 'edit', child: Text('编辑作品')),
                  PopupMenuItem(value: 'delete', child: Text('删除作品')),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyCard extends StatelessWidget {
  const _EmptyCard({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Row(
          children: [
            const Icon(Icons.library_add_outlined, size: 32),
            const SizedBox(width: 18),
            const Expanded(child: Text('还没有作品，从一个书名开始。')),
            OutlinedButton(onPressed: onPressed, child: const Text('创建')),
          ],
        ),
      ),
    );
  }
}

class BookOverviewPage extends StatelessWidget {
  const BookOverviewPage({super.key, required this.controller});

  final AppController controller;

  Future<void> _editBookInfo(BuildContext context, Book book) async {
    final title = TextEditingController(text: book.title);
    final description = TextEditingController(text: book.description);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('编辑作品资料'),
        content: SizedBox(
          width: 480,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: title,
                  autofocus: true,
                  maxLength: 120,
                  decoration: const InputDecoration(labelText: '书名 *'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: description,
                  minLines: 4,
                  maxLines: 7,
                  decoration: const InputDecoration(labelText: '作品简介'),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      controller.updateActiveBookInfo(
        title: title.text,
        description: description.text,
      );
    }
    title.dispose();
    description.dispose();
  }

  void _continueWriting(Book book) {
    if (book.chapters.isEmpty) controller.createChapter();
    controller.continueWriting();
  }

  void _createChapter({String? volumeId}) {
    controller.createChapter(volumeId: volumeId);
    controller.continueWriting();
  }

  Future<void> _createVolume(BuildContext context) async {
    final title = TextEditingController();
    final created = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('新建分卷'),
        content: TextField(
          controller: title,
          autofocus: true,
          maxLength: 80,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => Navigator.pop(context, true),
          decoration: const InputDecoration(
            labelText: '分卷名称',
            hintText: '例如：第一卷 雾灯来信',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('创建'),
          ),
        ],
      ),
    );
    final volumeTitle = title.text;
    await Future<void>.delayed(const Duration(milliseconds: 250));
    title.dispose();
    if (created == true) controller.createVolume(volumeTitle);
  }

  @override
  Widget build(BuildContext context) {
    final book = controller.activeBook;
    if (book == null) return const Center(child: Text('请先从书架选择作品。'));
    final compact = MediaQuery.sizeOf(context).width < 620;
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        compact ? 16 : 28,
        20,
        compact ? 16 : 28,
        40,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 920),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Card(
                child: Padding(
                  padding: EdgeInsets.all(compact ? 18 : 24),
                  child: compact
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _BookOverviewHeader(
                              book: book,
                              controller: controller,
                              compact: true,
                            ),
                            const SizedBox(height: 20),
                            _BookOverviewSummary(
                              book: book,
                              controller: controller,
                            ),
                            const SizedBox(height: 20),
                            _BookOverviewActions(
                              book: book,
                              onContinue: () => _continueWriting(book),
                              onEdit: () => _editBookInfo(context, book),
                            ),
                          ],
                        )
                      : Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _BookOverviewHeader(
                              book: book,
                              controller: controller,
                              compact: false,
                            ),
                            const SizedBox(width: 24),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _BookOverviewSummary(
                                    book: book,
                                    controller: controller,
                                  ),
                                  const SizedBox(height: 20),
                                  _BookOverviewActions(
                                    book: book,
                                    onContinue: () => _continueWriting(book),
                                    onEdit: () => _editBookInfo(context, book),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                ),
              ),
              const SizedBox(height: 18),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  _BookQuickAction(
                    icon: Icons.edit_note_rounded,
                    label: '写作',
                    onPressed: () => _continueWriting(book),
                  ),
                  _BookQuickAction(
                    icon: Icons.collections_bookmark_outlined,
                    label: '设定',
                    onPressed: () =>
                        controller.openSubpage(WorkspacePage.characters),
                  ),
                  _BookQuickAction(
                    icon: Icons.account_tree_outlined,
                    label: '情节',
                    onPressed: () =>
                        controller.openSubpage(WorkspacePage.timeline),
                  ),
                  _BookQuickAction(
                    icon: Icons.ios_share_rounded,
                    label: '导出',
                    onPressed: () =>
                        controller.openSubpage(WorkspacePage.export),
                  ),
                ],
              ),
              const SizedBox(height: 28),
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 10,
                runSpacing: 10,
                children: [
                  SizedBox(
                    width: compact ? double.infinity : 360,
                    child: Text(
                      '章节目录',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                  ),
                  Wrap(
                    spacing: 8,
                    children: [
                      OutlinedButton.icon(
                        onPressed: () => _createVolume(context),
                        icon: const Icon(Icons.create_new_folder_outlined),
                        label: const Text('新建分卷'),
                      ),
                      FilledButton.icon(
                        onPressed: _createChapter,
                        icon: const Icon(Icons.add_rounded),
                        label: const Text('新建章节'),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 14),
              BookDirectory(
                controller: controller,
                book: book,
                onOpenChapter: controller.openChapter,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BookOverviewHeader extends StatelessWidget {
  const _BookOverviewHeader({
    required this.book,
    required this.controller,
    required this.compact,
  });

  final Book book;
  final AppController controller;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        _Cover(
          book: book,
          width: compact ? 108 : 132,
          height: compact ? 148 : 180,
          radius: 12,
        ),
        Positioned(
          right: 6,
          bottom: 6,
          child: IconButton.filledTonal(
            tooltip: '更换封面',
            onPressed: () => controller.chooseCover(book),
            icon: const Icon(Icons.image_outlined, size: 18),
          ),
        ),
      ],
    );
  }
}

class _BookOverviewSummary extends StatelessWidget {
  const _BookOverviewSummary({required this.book, required this.controller});

  final Book book;
  final AppController controller;

  String _date(DateTime value) =>
      '${value.year}.${value.month.toString().padLeft(2, '0')}.${value.day.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(book.title, style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 6),
        Text(
          controller.data.profile.authorName,
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 16),
        Text(
          book.description.isEmpty ? '尚未填写作品简介。' : book.description,
          style: TextStyle(
            height: 1.55,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 18),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _BookMetaChip(text: '${book.wordCount} 字'),
            _BookMetaChip(text: '${book.chapters.length} 章'),
            _BookMetaChip(text: '${book.volumes.length} 卷'),
            _BookMetaChip(text: '更新 ${_date(book.updatedAt)}'),
          ],
        ),
      ],
    );
  }
}

class _BookOverviewActions extends StatelessWidget {
  const _BookOverviewActions({
    required this.book,
    required this.onContinue,
    required this.onEdit,
  });

  final Book book;
  final VoidCallback onContinue;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        FilledButton.icon(
          onPressed: onContinue,
          icon: const Icon(Icons.edit_note_rounded),
          label: Text(book.chapters.isEmpty ? '写第一章' : '继续写作'),
        ),
        OutlinedButton.icon(
          onPressed: onEdit,
          icon: const Icon(Icons.edit_outlined),
          label: const Text('编辑资料'),
        ),
      ],
    );
  }
}

class _BookMetaChip extends StatelessWidget {
  const _BookMetaChip({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).dividerColor),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(text, style: Theme.of(context).textTheme.bodySmall),
    );
  }
}

class _BookQuickAction extends StatelessWidget {
  const _BookQuickAction({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 19),
      label: Text(label),
    );
  }
}

class WritingPage extends StatelessWidget {
  const WritingPage({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final book = controller.activeBook;
    final chapter = controller.activeChapter;
    if (book == null) {
      return const Center(child: Text('请先在作品库中创建一本书。'));
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final showNotes = constraints.maxWidth >= 1120;
        final showChapterList = constraints.maxWidth >= 720;
        return Row(
          children: [
            if (showChapterList)
              _ChapterList(book: book, controller: controller),
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
                transitionBuilder: (child, animation) => FadeTransition(
                  opacity: animation,
                  child: SlideTransition(
                    position: Tween<Offset>(
                      begin: const Offset(.025, 0),
                      end: Offset.zero,
                    ).animate(animation),
                    child: child,
                  ),
                ),
                child: chapter == null
                    ? Center(
                        key: const ValueKey('empty-chapter'),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text('还没有章节'),
                            const SizedBox(height: 16),
                            FilledButton.icon(
                              onPressed: () => controller.createChapter(),
                              icon: const Icon(Icons.add_rounded),
                              label: const Text('写第一章'),
                            ),
                          ],
                        ),
                      )
                    : _EditorPane(
                        key: ValueKey(chapter.id),
                        chapter: chapter,
                        controller: controller,
                      ),
              ),
            ),
            if (showNotes) _WritingNotes(book: book, chapter: chapter),
          ],
        );
      },
    );
  }
}

class _ChapterList extends StatelessWidget {
  const _ChapterList({required this.book, required this.controller});

  final Book book;
  final AppController controller;

  Future<void> _createVolume(BuildContext context) async {
    final field = TextEditingController();
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('新建分卷'),
        content: TextField(
          controller: field,
          autofocus: true,
          decoration: const InputDecoration(labelText: '分卷名称'),
          onSubmitted: (value) => Navigator.pop(context, value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, field.text),
            child: const Text('创建'),
          ),
        ],
      ),
    );
    field.dispose();
    if (value != null) controller.createVolume(value);
  }

  Future<void> _renameChapter(BuildContext context, Chapter chapter) async {
    final field = TextEditingController(text: chapter.title);
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('重命名章节'),
        content: TextField(
          controller: field,
          autofocus: true,
          maxLength: 120,
          onSubmitted: (value) => Navigator.pop(context, value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, field.text),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    field.dispose();
    if (value != null) controller.renameChapter(chapter.id, value);
  }

  Future<void> _deleteChapter(BuildContext context, Chapter chapter) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除章节？'),
        content: Text('“${chapter.title}”会从目录移除，请先导出需要保留的内容。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed == true) controller.deleteChapter(chapter.id);
  }

  Widget _chapterTile(BuildContext context, Chapter chapter) {
    final selected = chapter.id == controller.selectedChapterId;
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: ListTile(
        selected: selected,
        selectedTileColor: Theme.of(context).colorScheme.primaryContainer,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        contentPadding: const EdgeInsets.only(left: 12, right: 2),
        title: Text(
          chapter.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          '${chapter.status} · ${chapter.wordCount} 字'
          '${chapter.exportEnabled ? '' : ' · 不导出'}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 11),
        ),
        trailing: PopupMenuButton<String>(
          tooltip: '章节操作',
          onSelected: (value) {
            if (value == 'rename') _renameChapter(context, chapter);
            if (value == 'duplicate') controller.duplicateChapter(chapter.id);
            if (value == 'up') controller.moveChapter(chapter.id, -1);
            if (value == 'down') controller.moveChapter(chapter.id, 1);
            if (value == 'export') controller.toggleChapterExport(chapter.id);
            if (value.startsWith('status:')) {
              controller.setChapterStatus(chapter.id, value.substring(7));
            }
            if (value == 'volume:none') {
              controller.moveChapterToVolume(chapter.id, null);
            }
            if (value.startsWith('volume:') && value != 'volume:none') {
              controller.moveChapterToVolume(chapter.id, value.substring(7));
            }
            if (value == 'delete') _deleteChapter(context, chapter);
          },
          itemBuilder: (context) => [
            const PopupMenuItem(value: 'rename', child: Text('重命名')),
            const PopupMenuItem(value: 'duplicate', child: Text('复制章节')),
            const PopupMenuItem(value: 'up', child: Text('上移')),
            const PopupMenuItem(value: 'down', child: Text('下移')),
            PopupMenuItem(
              value: 'export',
              child: Text(chapter.exportEnabled ? '排除导出' : '加入导出'),
            ),
            const PopupMenuDivider(),
            ...['草稿', '修订中', '定稿'].map(
              (status) => PopupMenuItem(
                value: 'status:$status',
                child: Text('状态 · $status'),
              ),
            ),
            const PopupMenuDivider(),
            const PopupMenuItem(value: 'volume:none', child: Text('移动到 · 未分卷')),
            ...book.volumes.map(
              (volume) => PopupMenuItem(
                value: 'volume:${volume.id}',
                child: Text('移动到 · ${volume.title}'),
              ),
            ),
            const PopupMenuDivider(),
            const PopupMenuItem(value: 'delete', child: Text('删除')),
          ],
        ),
        onTap: () => controller.selectChapter(chapter.id),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 250,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(
          right: BorderSide(color: Theme.of(context).dividerColor),
        ),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 10, 10),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    '章节',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                IconButton(
                  tooltip: '新建章节',
                  onPressed: () => controller.createChapter(),
                  icon: const Icon(Icons.add_rounded),
                ),
                IconButton(
                  tooltip: '新建分卷',
                  onPressed: () => _createVolume(context),
                  icon: const Icon(Icons.create_new_folder_outlined),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              children: [
                if (book.chapters
                    .where((item) => item.volumeId == null)
                    .isNotEmpty) ...[
                  const Padding(
                    padding: EdgeInsets.fromLTRB(8, 8, 8, 6),
                    child: Text(
                      '未分卷',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                  ...book.chapters
                      .where((item) => item.volumeId == null)
                      .map((chapter) => _chapterTile(context, chapter)),
                ],
                ...book.volumes.map((volume) {
                  final chapters = book.chapters
                      .where((item) => item.volumeId == volume.id)
                      .toList();
                  return ExpansionTile(
                    initiallyExpanded: true,
                    tilePadding: const EdgeInsets.only(left: 8, right: 2),
                    childrenPadding: EdgeInsets.zero,
                    title: Text(
                      volume.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    trailing: IconButton(
                      tooltip: '在此卷新建章节',
                      onPressed: () =>
                          controller.createChapter(volumeId: volume.id),
                      icon: const Icon(Icons.add_rounded, size: 20),
                    ),
                    children: chapters
                        .map((chapter) => _chapterTile(context, chapter))
                        .toList(),
                  );
                }),
                if (book.chapters.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: Text('还没有章节'),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MarkedBodyController extends TextEditingController {
  _MarkedBodyController(this.chapter) : super(text: chapter.body);

  final Chapter chapter;

  void refreshMarkers() => notifyListeners();

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    if (chapter.markers.isEmpty) {
      return super.buildTextSpan(
        context: context,
        style: style,
        withComposing: withComposing,
      );
    }
    if (withComposing &&
        value.composing.isValid &&
        !value.composing.isCollapsed) {
      return super.buildTextSpan(
        context: context,
        style: style,
        withComposing: withComposing,
      );
    }
    final points = <int>{0, text.length};
    for (final marker in chapter.markers) {
      points.add(marker.start.clamp(0, text.length));
      points.add(marker.end.clamp(0, text.length));
    }
    final offsets = points.toList()..sort();
    final color = Theme.of(context).colorScheme.primary;
    return TextSpan(
      style: style,
      children: [
        for (var index = 0; index < offsets.length - 1; index++)
          TextSpan(
            text: text.substring(offsets[index], offsets[index + 1]),
            style:
                chapter.markers.any(
                  (marker) =>
                      marker.start < offsets[index + 1] &&
                      marker.end > offsets[index],
                )
                ? TextStyle(
                    backgroundColor: color.withValues(alpha: .12),
                    decoration: TextDecoration.underline,
                    decorationColor: color,
                    decorationThickness: 1.5,
                  )
                : null,
          ),
      ],
    );
  }
}

typedef _MarkerDraft = ({
  String kind,
  String note,
  String? referenceId,
  String newReference,
});

class _EditorPane extends StatefulWidget {
  const _EditorPane({
    super.key,
    required this.chapter,
    required this.controller,
  });

  final Chapter chapter;
  final AppController controller;

  @override
  State<_EditorPane> createState() => _EditorPaneState();
}

class _EditorPaneState extends State<_EditorPane> {
  late final TextEditingController _titleController;
  late final _MarkedBodyController _bodyController;
  late final FocusNode _bodyFocusNode;
  late final UndoHistoryController _undoController;
  late final ScrollController _bodyScrollController;
  bool _showParagraphNumbers = false;
  bool _markerPreviewOpen = false;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.chapter.title);
    _bodyController = _MarkedBodyController(widget.chapter);
    _bodyFocusNode = FocusNode();
    _undoController = UndoHistoryController();
    _bodyScrollController = ScrollController()..addListener(_onBodyScroll);
    _titleController.addListener(_commitTitleWhenCompositionEnds);
    _bodyController.addListener(_commitBodyWhenCompositionEnds);
  }

  void _commitTitleWhenCompositionEnds() {
    final composing = _titleController.value.composing;
    if (composing.isValid && !composing.isCollapsed) return;
    widget.controller.updateChapterTitle(_titleController.text);
  }

  void _commitBodyWhenCompositionEnds() {
    final composing = _bodyController.value.composing;
    if (composing.isValid && !composing.isCollapsed) return;
    widget.controller.updateChapterBody(_bodyController.text);
  }

  void _onBodyScroll() {
    if (_showParagraphNumbers && mounted) setState(() {});
  }

  void _toggleIndent() {
    final value = _bodyController.value;
    final selection = value.selection;
    final offset = selection.isValid ? selection.start : value.text.length;
    final searchStart = offset <= 0 ? -1 : offset - 1;
    final lineStart = searchStart < 0
        ? -1
        : value.text.lastIndexOf('\n', searchStart);
    final start = lineStart < 0 ? 0 : lineStart + 1;
    final nextBreak = value.text.indexOf('\n', offset);
    final end = nextBreak < 0 ? value.text.length : nextBreak;
    const indent = '　　';
    final hasIndent = value.text.startsWith(indent, start);
    final paragraph = value.text.substring(start, end);
    final nextParagraph = hasIndent
        ? paragraph.substring(indent.length)
        : '$indent$paragraph';
    final nextText = value.text.replaceRange(start, end, nextParagraph);
    final nextOffset = (offset + (hasIndent ? -indent.length : indent.length))
        .clamp(0, nextText.length);
    _bodyController.value = value.copyWith(
      text: nextText,
      selection: TextSelection.collapsed(offset: nextOffset),
      composing: TextRange.empty,
    );
  }

  Future<void> _showIndentSelector() async {
    final lines = _bodyController.text.split('\n');
    const indent = '　　';
    final selected = <int>{
      for (var i = 0; i < lines.length; i++)
        if (lines[i].startsWith(indent)) i,
    };
    final result = await showDialog<Set<int>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('选择缩进段落'),
          content: SizedBox(
            width: 420,
            height: MediaQuery.sizeOf(context).height * .55,
            child: ListView.builder(
              itemCount: lines.length,
              itemBuilder: (context, index) => CheckboxListTile(
                value: selected.contains(index),
                title: Text('第 ${index + 1} 段'),
                subtitle: Text(
                  lines[index].trim().isEmpty ? '空段落' : lines[index].trim(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                onChanged: (value) => setDialogState(() {
                  value == true ? selected.add(index) : selected.remove(index);
                }),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, selected.toSet()),
              child: const Text('应用'),
            ),
          ],
        ),
      ),
    );
    if (result == null || !mounted) return;
    final revised = [
      for (var i = 0; i < lines.length; i++)
        result.contains(i)
            ? (lines[i].startsWith(indent) ? lines[i] : '$indent${lines[i]}')
            : (lines[i].startsWith(indent)
                  ? lines[i].substring(indent.length)
                  : lines[i]),
    ].join('\n');
    final offset = _bodyController.selection.baseOffset;
    _bodyController.value = _bodyController.value.copyWith(
      text: revised,
      selection: TextSelection.collapsed(
        offset: offset.clamp(0, revised.length),
      ),
      composing: TextRange.empty,
    );
  }

  Future<void> _showLineSpacing() async {
    final current = widget.controller.data.settings.lineHeight;
    final selected = await showModalBottomSheet<double>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ListTile(title: Text('行距')),
            for (final value in const [1.4, 1.6, 1.8])
              ListTile(
                title: Text('${value.toStringAsFixed(1)} 倍'),
                trailing: current == value
                    ? const Icon(Icons.check_rounded)
                    : null,
                onTap: () => Navigator.pop(context, value),
              ),
          ],
        ),
      ),
    );
    if (selected != null) widget.controller.updateLineHeight(selected);
  }

  Future<void> _showChapterDirectory() async {
    final book = widget.controller.activeBook;
    if (book == null) return;

    List<Widget> chapterTiles(Iterable<Chapter> chapters) => chapters
        .map(
          (chapter) => ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(
              chapter.id == widget.controller.selectedChapterId
                  ? Icons.radio_button_checked_rounded
                  : Icons.radio_button_unchecked_rounded,
            ),
            title: Text(
              chapter.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text('${chapter.status} · ${chapter.wordCount} 字'),
            onTap: () => Navigator.pop(context, chapter.id),
          ),
        )
        .toList();

    final value = await showModalBottomSheet<String>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => FractionallySizedBox(
        heightFactor: .72,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 12, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '章节目录',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  FilledButton.tonalIcon(
                    onPressed: () => Navigator.pop(context, '__new__'),
                    icon: const Icon(Icons.add_rounded, size: 18),
                    label: const Text('新建'),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 24),
                children: [
                  if (book.chapters
                      .where((chapter) => chapter.volumeId == null)
                      .isNotEmpty) ...[
                    const Padding(
                      padding: EdgeInsets.only(top: 8, bottom: 4),
                      child: Text(
                        '未分卷',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                    ...chapterTiles(
                      book.chapters.where(
                        (chapter) => chapter.volumeId == null,
                      ),
                    ),
                  ],
                  ...book.volumes.expand((volume) {
                    final chapters = book.chapters.where(
                      (chapter) => chapter.volumeId == volume.id,
                    );
                    if (chapters.isEmpty) return <Widget>[];
                    return <Widget>[
                      Padding(
                        padding: const EdgeInsets.only(top: 16, bottom: 4),
                        child: Text(
                          volume.title,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                      ...chapterTiles(chapters),
                    ];
                  }),
                  if (book.chapters.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 40),
                      child: Center(child: Text('还没有章节')),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
    if (!mounted || value == null) return;
    if (value == '__new__') {
      widget.controller.createChapter();
    } else {
      widget.controller.selectChapter(value);
    }
  }

  Future<void> _showResearch() async {
    final previousSelection = _bodyController.selection;
    final book = widget.controller.activeBook;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => SafeArea(
        top: false,
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * .55,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
            children: [
              Text('查设定', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 16),
              if (book == null || (book.roles.isEmpty && book.worlds.isEmpty))
                const Text('当前作品还没有角色或世界观资料。'),
              ...?book?.roles.map(
                (role) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.person_outline_rounded),
                  title: Text(role.name),
                  subtitle: Text(
                    role.description.isEmpty ? '角色卡' : role.description,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              ...?book?.worlds.map(
                (world) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.public_rounded),
                  title: Text(world.title),
                  subtitle: Text(
                    world.description.isEmpty ? world.type : world.description,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (!mounted) return;
    _bodyFocusNode.requestFocus();
    if (previousSelection.isValid) {
      _bodyController.selection = previousSelection;
    }
  }

  Future<void> _captureIdea() async {
    final previousSelection = _bodyController.selection;
    final field = TextEditingController();
    final value = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          0,
          20,
          MediaQuery.viewInsetsOf(context).bottom + 20,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('记灵感', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 14),
            TextField(
              controller: field,
              autofocus: true,
              minLines: 2,
              maxLines: 5,
              decoration: const InputDecoration(hintText: '一句话也可以'),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () => Navigator.pop(context, field.text),
              child: const Text('保存灵感'),
            ),
          ],
        ),
      ),
    );
    field.dispose();
    if (value?.trim().isNotEmpty == true) widget.controller.createNote(value!);
    if (!mounted) return;
    _bodyFocusNode.requestFocus();
    if (previousSelection.isValid) {
      _bodyController.selection = previousSelection;
    }
  }

  Future<void> _addMarker() async {
    final selection = _bodyController.selection;
    if (!selection.isValid || selection.isCollapsed) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('请先选中要标注的正文')));
      return;
    }
    final book = widget.controller.activeBook;
    if (book == null) return;
    var kind = 'revision';
    String? referenceId = '__new__';
    var newReferenceText = selection.textInside(_bodyController.text);
    var noteText = '';
    final draft = await showDialog<_MarkerDraft>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('添加正文标注'),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    '“${selection.textInside(_bodyController.text)}”',
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: kind,
                    decoration: const InputDecoration(labelText: '类型'),
                    items: const [
                      DropdownMenuItem(value: 'revision', child: Text('待修改')),
                      DropdownMenuItem(value: 'clue', child: Text('伏笔')),
                      DropdownMenuItem(value: 'idea', child: Text('灵感')),
                    ],
                    onChanged: (value) => setDialogState(() {
                      kind = value ?? 'revision';
                      referenceId = '__new__';
                    }),
                  ),
                  if (kind != 'revision') ...[
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      key: ValueKey('marker-reference-$kind'),
                      initialValue: referenceId,
                      decoration: InputDecoration(
                        labelText: kind == 'clue' ? '关联伏笔' : '关联灵感',
                      ),
                      items: [
                        DropdownMenuItem(
                          value: '__new__',
                          child: Text(kind == 'clue' ? '新建伏笔' : '新建灵感'),
                        ),
                        if (kind == 'clue')
                          ...book.clues.map(
                            (clue) => DropdownMenuItem(
                              value: clue.id,
                              child: Text(
                                clue.title,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          )
                        else
                          ...book.notes.map(
                            (idea) => DropdownMenuItem(
                              value: idea.id,
                              child: Text(
                                idea.body,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                      ],
                      onChanged: (value) =>
                          setDialogState(() => referenceId = value),
                    ),
                    if (referenceId == '__new__') ...[
                      const SizedBox(height: 12),
                      TextFormField(
                        initialValue: newReferenceText,
                        onChanged: (value) => newReferenceText = value,
                        maxLines: 2,
                        decoration: InputDecoration(
                          labelText: kind == 'clue' ? '伏笔名称' : '灵感内容',
                        ),
                      ),
                    ],
                  ],
                  const SizedBox(height: 12),
                  TextFormField(
                    onChanged: (value) => noteText = value,
                    maxLines: 3,
                    decoration: const InputDecoration(labelText: '备注（可随时修改）'),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, (
                kind: kind,
                note: noteText,
                referenceId: referenceId,
                newReference: newReferenceText,
              )),
              child: const Text('保存标注'),
            ),
          ],
        ),
      ),
    );
    if (draft == null || !mounted) return;
    String? linkedId = draft.referenceId;
    if (draft.kind != 'revision' && linkedId == '__new__') {
      if (draft.newReference.trim().isEmpty) return;
      linkedId = draft.kind == 'clue'
          ? widget.controller.createClue(
              draft.newReference,
              draft.note,
              originChapterId: widget.chapter.id,
            )
          : widget.controller.createNote(draft.newReference);
    }
    final marker = widget.controller.addChapterMarker(
      start: selection.start,
      end: selection.end,
      kind: draft.kind,
      note: draft.note,
      referenceId: draft.kind == 'revision' ? null : linkedId,
    );
    if (marker != null) _bodyController.refreshMarkers();
    _bodyFocusNode.requestFocus();
    _bodyController.selection = selection;
  }

  Future<void> _showMarkerAtCursor() async {
    if (_markerPreviewOpen || !mounted) return;
    final selection = _bodyController.selection;
    if (!selection.isValid || !selection.isCollapsed) return;
    final offset = selection.baseOffset;
    final marker = widget.chapter.markers
        .where((item) => item.start <= offset && offset < item.end)
        .firstOrNull;
    if (marker == null) return;
    _markerPreviewOpen = true;
    final kind = switch (marker.kind) {
      'clue' => '伏笔',
      'idea' => '灵感',
      _ => '待修改',
    };
    try {
      await showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        builder: (context) => SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '正文标注 · $kind',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 10),
                Text('“${marker.quote}”'),
                if (marker.note.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(marker.note),
                ],
              ],
            ),
          ),
        ),
      );
    } finally {
      _markerPreviewOpen = false;
    }
  }

  List<Widget> _paragraphNumberLabels(
    BuildContext context,
    BoxConstraints constraints,
    TextStyle style,
  ) {
    final content = _bodyController.text;
    final offsets = <int>[0];
    for (var index = 0; index < content.length; index++) {
      if (content.codeUnitAt(index) == 10) offsets.add(index + 1);
    }
    final painter = TextPainter(
      text: TextSpan(text: content, style: style),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
    )..layout(maxWidth: (constraints.maxWidth - 34).clamp(1, double.infinity));
    final scrollOffset = _bodyScrollController.hasClients
        ? _bodyScrollController.offset
        : 0.0;
    final positions = [
      for (final offset in offsets)
        painter.getOffsetForCaret(TextPosition(offset: offset), Rect.zero).dy -
            scrollOffset,
    ];
    painter.dispose();
    return [
      for (var index = 0; index < positions.length; index++)
        if (positions[index] >= -style.fontSize! &&
            positions[index] <= constraints.maxHeight)
          Positioned(
            left: 0,
            top: positions[index],
            width: 30,
            child: IgnorePointer(
              child: Text(
                '${index + 1}',
                key: ValueKey('paragraph-number-${index + 1}'),
                textAlign: TextAlign.right,
                style: TextStyle(
                  fontSize: 11,
                  color: Theme.of(context).colorScheme.onSurfaceVariant
                      .withValues(alpha: .5),
                ),
              ),
            ),
          ),
    ];
  }

  Future<void> _showMarkers() async {
    final book = widget.controller.activeBook;
    final selectedId = await showModalBottomSheet<String>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) {
          final markers = widget.chapter.markers.toList()
            ..sort((a, b) => a.start.compareTo(b.start));
          return SizedBox(
            height: MediaQuery.sizeOf(sheetContext).height * .62,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 12, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          '正文标注',
                          style: Theme.of(sheetContext).textTheme.titleLarge,
                        ),
                      ),
                      Text('${markers.length} 处'),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: markers.isEmpty
                      ? const Center(child: Text('还没有标注。选中正文后点“添加标注”。'))
                      : ListView.builder(
                          itemCount: markers.length,
                          itemBuilder: (context, index) {
                            final marker = markers[index];
                            final kindLabel = switch (marker.kind) {
                              'clue' => '伏笔',
                              'idea' => '灵感',
                              _ => '待修改',
                            };
                            final linkedLabel = switch (marker.kind) {
                              'clue' =>
                                book?.clues
                                    .where(
                                      (item) => item.id == marker.referenceId,
                                    )
                                    .map((item) => item.title)
                                    .firstOrNull,
                              'idea' =>
                                book?.notes
                                    .where(
                                      (item) => item.id == marker.referenceId,
                                    )
                                    .map((item) => item.body)
                                    .firstOrNull,
                              _ => null,
                            };
                            final details = [
                              if (linkedLabel?.isNotEmpty == true) linkedLabel!,
                              if (marker.note.isNotEmpty) marker.note,
                            ].join(' · ');
                            return ListTile(
                              key: ValueKey('chapter-marker-${marker.id}'),
                              leading: const Icon(
                                Icons.bookmark_outline_rounded,
                              ),
                              title: Text(
                                '$kindLabel · ${marker.quote}',
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              subtitle: details.isEmpty
                                  ? null
                                  : Text(
                                      details,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                              onTap: () =>
                                  Navigator.pop(sheetContext, marker.id),
                              trailing: PopupMenuButton<String>(
                                tooltip: '标注操作',
                                onSelected: (action) async {
                                  if (action == 'edit') {
                                    var revisedText = marker.note;
                                    final revised = await showDialog<String>(
                                      context: sheetContext,
                                      builder: (context) => AlertDialog(
                                        title: const Text('编辑标注'),
                                        content: TextFormField(
                                          initialValue: revisedText,
                                          onChanged: (value) =>
                                              revisedText = value,
                                          autofocus: true,
                                          maxLines: 3,
                                          decoration: const InputDecoration(
                                            labelText: '备注',
                                          ),
                                        ),
                                        actions: [
                                          TextButton(
                                            onPressed: () =>
                                                Navigator.pop(context),
                                            child: const Text('取消'),
                                          ),
                                          FilledButton(
                                            onPressed: () => Navigator.pop(
                                              context,
                                              revisedText,
                                            ),
                                            child: const Text('保存'),
                                          ),
                                        ],
                                      ),
                                    );
                                    if (revised != null) {
                                      widget.controller.updateChapterMarker(
                                        marker.id,
                                        revised,
                                      );
                                    }
                                  } else {
                                    final confirmed = await showDialog<bool>(
                                      context: sheetContext,
                                      builder: (context) => AlertDialog(
                                        title: const Text('删除标注？'),
                                        content: const Text(
                                          '只删除正文中的标注，不删除关联的伏笔或灵感。',
                                        ),
                                        actions: [
                                          TextButton(
                                            onPressed: () =>
                                                Navigator.pop(context, false),
                                            child: const Text('取消'),
                                          ),
                                          FilledButton(
                                            onPressed: () =>
                                                Navigator.pop(context, true),
                                            child: const Text('删除'),
                                          ),
                                        ],
                                      ),
                                    );
                                    if (confirmed == true) {
                                      widget.controller.deleteChapterMarker(
                                        marker.id,
                                      );
                                    }
                                  }
                                  if (sheetContext.mounted) {
                                    setSheetState(() {});
                                  }
                                  _bodyController.refreshMarkers();
                                },
                                itemBuilder: (context) => const [
                                  PopupMenuItem(
                                    value: 'edit',
                                    child: Text('编辑备注'),
                                  ),
                                  PopupMenuItem(
                                    value: 'delete',
                                    child: Text('删除标注'),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          );
        },
      ),
    );
    if (!mounted || selectedId == null) return;
    final marker = widget.chapter.markers
        .where((item) => item.id == selectedId)
        .firstOrNull;
    if (marker == null) return;
    _bodyFocusNode.requestFocus();
    _bodyController.selection = TextSelection(
      baseOffset: marker.start.clamp(0, _bodyController.text.length),
      extentOffset: marker.end.clamp(0, _bodyController.text.length),
    );
  }

  @override
  void dispose() {
    _titleController.removeListener(_commitTitleWhenCompositionEnds);
    _bodyController.removeListener(_commitBodyWhenCompositionEnds);
    _bodyFocusNode.dispose();
    _undoController.dispose();
    _bodyScrollController.dispose();
    _titleController.dispose();
    _bodyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = widget.controller.data.settings;
    final compact = MediaQuery.sizeOf(context).width < 620;
    final keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;
    return ColoredBox(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: Column(
        children: [
          Container(
            height: 50,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: Theme.of(context).dividerColor),
              ),
            ),
            child: Row(
              children: [
                if (compact)
                  TextButton.icon(
                    key: const ValueKey('open-chapter-directory'),
                    onPressed: _showChapterDirectory,
                    icon: const Icon(Icons.menu_book_outlined, size: 20),
                    label: const Text('目录'),
                  ),
                if (!compact) ...[
                  IconButton(
                    tooltip: '减小字号',
                    onPressed: () => widget.controller.updateFontSize(
                      (settings.fontSize - 1).clamp(14, 32),
                    ),
                    icon: const Icon(Icons.text_decrease_rounded, size: 19),
                  ),
                  Text('${settings.fontSize.round()}'),
                  IconButton(
                    tooltip: '增大字号',
                    onPressed: () => widget.controller.updateFontSize(
                      (settings.fontSize + 1).clamp(14, 32),
                    ),
                    icon: const Icon(Icons.text_increase_rounded, size: 19),
                  ),
                  const SizedBox(width: 8),
                  Chip(
                    avatar: const Icon(
                      Icons.format_line_spacing_rounded,
                      size: 16,
                    ),
                    label: Text('${settings.lineHeight.toStringAsFixed(1)}×'),
                    visualDensity: VisualDensity.compact,
                  ),
                ],
                const Spacer(),
                Text(
                  '${widget.chapter.wordCount} 字',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                IconButton(
                  key: const ValueKey('add-chapter-marker'),
                  tooltip: '添加标注',
                  onPressed: _addMarker,
                  icon: const Icon(Icons.bookmark_add_outlined),
                ),
                IconButton(
                  key: const ValueKey('open-chapter-markers'),
                  tooltip: '正文标注',
                  onPressed: _showMarkers,
                  icon: const Icon(Icons.bookmarks_outlined),
                ),
                PopupMenuButton<String>(
                  tooltip: '段落设置',
                  icon: const Icon(Icons.format_align_left_rounded),
                  onSelected: (value) {
                    if (value == 'indent') {
                      _toggleIndent();
                    } else if (value == 'line') {
                      _showLineSpacing();
                    } else if (value == 'numbers') {
                      setState(
                        () => _showParagraphNumbers = !_showParagraphNumbers,
                      );
                    }
                  },
                  itemBuilder: (menuContext) => [
                    PopupMenuItem(
                      value: 'indent',
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onLongPress: () {
                          Navigator.pop(menuContext);
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            if (mounted) _showIndentSelector();
                          });
                        },
                        child: const SizedBox(
                          width: double.infinity,
                          child: Text('切换首行缩进 · 长按选择段落'),
                        ),
                      ),
                    ),
                    const PopupMenuDivider(),
                    PopupMenuItem(
                      value: 'numbers',
                      child: Text(_showParagraphNumbers ? '隐藏段落标记' : '显示段落标记'),
                    ),
                    PopupMenuItem(
                      value: 'line',
                      child: Text(
                        '行距 · ${settings.lineHeight.toStringAsFixed(1)} 倍',
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 820),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 34, 24, 24),
                  child: Column(
                    children: [
                      TextField(
                        controller: _titleController,
                        style: Theme.of(context).textTheme.headlineMedium,
                        decoration: const InputDecoration(
                          hintText: '章节标题',
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          filled: false,
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                      const SizedBox(height: 18),
                      Expanded(
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            final bodyStyle = TextStyle(
                              fontSize: settings.fontSize,
                              height: settings.lineHeight,
                              letterSpacing: .15,
                            );
                            return Stack(
                              clipBehavior: Clip.hardEdge,
                              children: [
                                Positioned.fill(
                                  left: _showParagraphNumbers ? 34 : 0,
                                  child: TextField(
                                    controller: _bodyController,
                                    scrollController: _bodyScrollController,
                                    focusNode: _bodyFocusNode,
                                    undoController: _undoController,
                                    expands: true,
                                    maxLines: null,
                                    minLines: null,
                                    textAlignVertical: TextAlignVertical.top,
                                    keyboardType: TextInputType.multiline,
                                    style: bodyStyle,
                                    onTap: () => WidgetsBinding.instance
                                        .addPostFrameCallback((_) {
                                          if (mounted) _showMarkerAtCursor();
                                        }),
                                    contextMenuBuilder: (context, editable) {
                                      final items = editable
                                          .contextMenuButtonItems
                                          .toList();
                                      if (!_bodyController
                                          .selection
                                          .isCollapsed) {
                                        items.add(
                                          ContextMenuButtonItem(
                                            label: '添加标注',
                                            onPressed: () {
                                              editable.hideToolbar();
                                              _addMarker();
                                            },
                                          ),
                                        );
                                      }
                                      return AdaptiveTextSelectionToolbar.buttonItems(
                                        anchors: editable.contextMenuAnchors,
                                        buttonItems: items,
                                      );
                                    },
                                    decoration: const InputDecoration(
                                      hintText: '从这里开始写……',
                                      border: InputBorder.none,
                                      enabledBorder: InputBorder.none,
                                      focusedBorder: InputBorder.none,
                                      filled: false,
                                      contentPadding: EdgeInsets.zero,
                                    ),
                                  ),
                                ),
                                if (_showParagraphNumbers)
                                  ..._paragraphNumberLabels(
                                    context,
                                    constraints,
                                    bodyStyle,
                                  ),
                              ],
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (keyboardOpen)
            _EditorKeyboardToolbar(
              undoController: _undoController,
              onIndent: _toggleIndent,
              onResearch: _showResearch,
              onIdea: _captureIdea,
              onMarker: _addMarker,
            ),
        ],
      ),
    );
  }
}

class _EditorKeyboardToolbar extends StatelessWidget {
  const _EditorKeyboardToolbar({
    required this.undoController,
    required this.onIndent,
    required this.onResearch,
    required this.onIdea,
    required this.onMarker,
  });

  final UndoHistoryController undoController;
  final VoidCallback onIndent;
  final VoidCallback onResearch;
  final VoidCallback onIdea;
  final VoidCallback onMarker;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surface,
      child: SafeArea(
        top: false,
        bottom: false,
        child: SizedBox(
          height: 48,
          child: ValueListenableBuilder<UndoHistoryValue>(
            valueListenable: undoController,
            builder: (context, value, _) => Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                IconButton(
                  tooltip: '撤销',
                  onPressed: value.canUndo ? undoController.undo : null,
                  icon: const Icon(Icons.undo_rounded),
                ),
                IconButton(
                  tooltip: '重做',
                  onPressed: value.canRedo ? undoController.redo : null,
                  icon: const Icon(Icons.redo_rounded),
                ),
                IconButton(
                  tooltip: '切换段首缩进',
                  onPressed: onIndent,
                  icon: const Icon(Icons.format_indent_increase_rounded),
                ),
                IconButton(
                  tooltip: '查设定',
                  onPressed: onResearch,
                  icon: const Icon(Icons.manage_search_rounded),
                ),
                IconButton(
                  tooltip: '记灵感',
                  onPressed: onIdea,
                  icon: const Icon(Icons.lightbulb_outline_rounded),
                ),
                IconButton(
                  tooltip: '添加标注',
                  onPressed: onMarker,
                  icon: const Icon(Icons.bookmark_add_outlined),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _WritingNotes extends StatelessWidget {
  const _WritingNotes({required this.book, required this.chapter});

  final Book book;
  final Chapter? chapter;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 260,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(left: BorderSide(color: Theme.of(context).dividerColor)),
      ),
      child: ListView(
        children: [
          const Text('本章笔记', style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 14),
          Text(
            chapter?.summary.isNotEmpty == true
                ? chapter!.summary
                : '还没有填写章节目标。',
          ),
          const SizedBox(height: 28),
          const Text('出场角色', style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          ...book.roles
              .take(4)
              .map(
                (role) => ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(
                    radius: 14,
                    child: Text(role.name.characters.first),
                  ),
                  title: Text(role.name),
                  subtitle: Text(role.identity),
                ),
              ),
        ],
      ),
    );
  }
}

class CharactersPage extends StatelessWidget {
  const CharactersPage({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final roles = controller.activeBook?.roles ?? [];
    return _ContentPage(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('角色卡', style: Theme.of(context).textTheme.headlineMedium),
              const Spacer(),
              FilledButton.icon(
                onPressed: () => _showRoleDialog(context, controller),
                icon: const Icon(Icons.person_add_alt_1_rounded),
                label: const Text('新建角色'),
              ),
            ],
          ),
          const SizedBox(height: 20),
          if (roles.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(26),
                child: Text('还没有角色卡。'),
              ),
            )
          else
            LayoutBuilder(
              builder: (context, constraints) {
                final count = constraints.maxWidth >= 900
                    ? 3
                    : constraints.maxWidth >= 560
                    ? 2
                    : 1;
                final width = (constraints.maxWidth - (count - 1) * 14) / count;
                return Wrap(
                  spacing: 14,
                  runSpacing: 14,
                  children: roles
                      .map(
                        (role) => SizedBox(
                          width: width,
                          child: _RoleCardView(role: role),
                        ),
                      )
                      .toList(),
                );
              },
            ),
        ],
      ),
    );
  }

  Future<void> _showRoleDialog(
    BuildContext context,
    AppController controller,
  ) async {
    final field = TextEditingController();
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('新建角色'),
        content: TextField(
          controller: field,
          autofocus: true,
          decoration: const InputDecoration(labelText: '姓名'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, field.text),
            child: const Text('创建'),
          ),
        ],
      ),
    );
    field.dispose();
    if (value != null && value.trim().isNotEmpty) {
      controller.createRole(value.trim());
    }
  }
}

class _RoleCardView extends StatelessWidget {
  const _RoleCardView({required this.role});

  final RoleCard role;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 22,
                  child: Text(role.name.characters.first),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        role.name,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      if (role.identity.isNotEmpty)
                        Text(
                          role.identity,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              role.description.isEmpty ? '尚未填写角色描述。' : role.description,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
            if (role.goal.isNotEmpty) ...[
              const SizedBox(height: 14),
              Text(
                '目标  ${role.goal}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class TimelinePage extends StatelessWidget {
  const TimelinePage({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final book = controller.activeBook;
    final events = book?.events ?? [];
    return _ContentPage(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('故事时间', style: Theme.of(context).textTheme.headlineMedium),
              const Spacer(),
              FilledButton.icon(
                onPressed: book == null
                    ? null
                    : () => _showEventDialog(context, controller),
                icon: const Icon(Icons.add_rounded),
                label: const Text('记录事件'),
              ),
            ],
          ),
          const SizedBox(height: 22),
          if (events.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(26),
                child: Text('时间线还是空的。'),
              ),
            )
          else
            ...events.indexed.map((entry) {
              final (index, event) = entry;
              final chapter = book?.chapters
                  .where((item) => item.id == event.chapterId)
                  .firstOrNull;
              return IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(
                      width: 34,
                      child: Column(
                        children: [
                          Container(
                            width: 12,
                            height: 12,
                            decoration: BoxDecoration(
                              color: Theme.of(context).colorScheme.primary,
                              shape: BoxShape.circle,
                            ),
                          ),
                          if (index < events.length - 1)
                            Expanded(
                              child: Container(
                                width: 1,
                                color: Theme.of(context).dividerColor,
                              ),
                            ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 14),
                        child: Card(
                          child: Padding(
                            padding: const EdgeInsets.all(18),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  event.storyDate,
                                  style: TextStyle(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .primary,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 7),
                                Text(
                                  event.title,
                                  style: Theme.of(context).textTheme.titleLarge,
                                ),
                                if (event.description.isNotEmpty) ...[
                                  const SizedBox(height: 7),
                                  Text(event.description),
                                ],
                                if (chapter != null) ...[
                                  const SizedBox(height: 10),
                                  Text(
                                    '关联章节 · ${chapter.title}',
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodySmall,
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }

  Future<void> _showEventDialog(
    BuildContext context,
    AppController controller,
  ) async {
    final title = TextEditingController();
    final date = TextEditingController();
    final created = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('记录事件'),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: title,
                autofocus: true,
                decoration: const InputDecoration(labelText: '事件名称'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: date,
                decoration: const InputDecoration(labelText: '故事时间'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (created == true && title.text.trim().isNotEmpty) {
      controller.createEvent(title.text.trim(), storyDate: date.text.trim());
    }
    title.dispose();
    date.dispose();
  }
}

class ExportPage extends StatefulWidget {
  const ExportPage({super.key, required this.controller});

  final AppController controller;

  @override
  State<ExportPage> createState() => _ExportPageState();
}

class _ExportPageState extends State<ExportPage> {
  String? _linkedDirectoryUri;

  @override
  void initState() {
    super.initState();
    _loadLinkedDirectory();
  }

  Future<void> _loadLinkedDirectory() async {
    final uri = await AndroidExportDirectory.linkedUri();
    if (mounted) setState(() => _linkedDirectoryUri = uri);
  }

  Future<void> _linkDirectory() async {
    final result = await AndroidExportDirectory.link();
    if (!mounted) return;
    final message = switch (result.status) {
      DirectoryLinkStatus.linked => '导出目录已关联',
      DirectoryLinkStatus.cancelled => '已取消关联目录',
      DirectoryLinkStatus.failed => result.message ?? '无法关联导出目录',
      DirectoryLinkStatus.unsupported => '当前平台无需关联目录',
    };
    if (result.status == DirectoryLinkStatus.linked) {
      setState(() => _linkedDirectoryUri = result.uri);
    }
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _clearDirectory() async {
    await AndroidExportDirectory.clear();
    if (!mounted) return;
    setState(() => _linkedDirectoryUri = null);
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('已取消目录关联')));
  }

  Future<void> _export(
    BuildContext context,
    Future<DocumentSaveResult> Function() action,
  ) async {
    final result = await action();
    if (!context.mounted) return;
    final message = switch (result.status) {
      DocumentSaveStatus.saved =>
        result.location == null ? '文件已保存' : '文件已保存：${result.location}',
      DocumentSaveStatus.cancelled => '已取消保存',
      DocumentSaveStatus.failed => result.message ?? '文件保存失败',
    };
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return _ContentPage(
      reserveBookNavigation: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (Platform.isAndroid) ...[
            Card(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Row(
                  children: [
                    const Icon(Icons.folder_outlined),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _linkedDirectoryUri == null ? '关联导出目录' : '已关联导出目录',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 3),
                          Text(
                            _linkedDirectoryUri == null
                                ? '请选择 内部存储/Download/yejie'
                                : '后续文件将直接写入该目录',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                    if (_linkedDirectoryUri == null)
                      FilledButton.tonal(
                        onPressed: _linkDirectory,
                        child: const Text('选择目录'),
                      )
                    else
                      TextButton(
                        onPressed: _clearDirectory,
                        child: const Text('取消关联'),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
          ],
          Text('阅读与交稿', style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 20),
          _ExportCard(
            icon: Icons.description_outlined,
            title: '纯文本 TXT',
            text: '按目录顺序导出参与导出的章节。',
            button: '保存 TXT',
            onPressed:
                widget.controller.activeBook?.chapters.any(
                      (chapter) => chapter.exportEnabled,
                    ) ==
                    true
                ? () => _export(context, widget.controller.exportPlainText)
                : null,
          ),
          const SizedBox(height: 14),
          _ExportCard(
            icon: Icons.code_rounded,
            title: 'Markdown',
            text: '使用卷、章标题层级保存正文。',
            button: '保存 Markdown',
            onPressed:
                widget.controller.activeBook?.chapters.any(
                      (chapter) => chapter.exportEnabled,
                    ) ==
                    true
                ? () => _export(context, widget.controller.exportMarkdown)
                : null,
          ),
          const SizedBox(height: 30),
          Text('工程备份', style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 20),
          const _ExportCard(
            icon: Icons.inventory_2_outlined,
            title: '.yejian.zip',
            text: '可校验的完整工程备份正在重建。',
            button: '开发中',
            onPressed: null,
          ),
          const SizedBox(height: 14),
          Text(
            'EPUB、DOCX、PDF 与完整工程备份尚未开放。',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _ExportCard extends StatelessWidget {
  const _ExportCard({
    required this.icon,
    required this.title,
    required this.text,
    required this.button,
    required this.onPressed,
  });

  final IconData icon;
  final String title;
  final String text;
  final String button;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 560;
          final details = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 5),
              Text(text),
            ],
          );
          return Padding(
            padding: const EdgeInsets.all(22),
            child: compact
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Icon(
                          icon,
                          size: 30,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                      const SizedBox(height: 14),
                      details,
                      const SizedBox(height: 18),
                      OutlinedButton(onPressed: onPressed, child: Text(button)),
                    ],
                  )
                : Row(
                    children: [
                      Icon(
                        icon,
                        size: 32,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(width: 18),
                      Expanded(child: details),
                      const SizedBox(width: 16),
                      OutlinedButton(onPressed: onPressed, child: Text(button)),
                    ],
                  ),
          );
        },
      ),
    );
  }
}

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final data = controller.data;
    final profile = data.profile;
    return _ContentPage(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('个人信息', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 10),
          Card(
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              key: const ValueKey('settings-author-card'),
              onTap: () => controller.openSubpage(WorkspacePage.profile),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 16,
                ),
                child: Row(
                  children: [
                    _Avatar(profile: profile, size: 60),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Text(
                        profile.authorName.trim().isEmpty
                            ? '未命名'
                            : profile.authorName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Icon(Icons.chevron_right_rounded),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),
          Text('设置', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 10),
          Card(
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                ListTile(
                  key: const ValueKey('open-app-settings'),
                  leading: const Icon(Icons.tune_rounded),
                  title: const Text('应用设置'),
                  subtitle: const Text('显示模式、配色、字号与字体'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () =>
                      controller.openSubpage(WorkspacePage.appSettings),
                ),
                const Divider(height: 1),
                ListTile(
                  key: const ValueKey('open-about-app'),
                  leading: const Icon(Icons.info_outline_rounded),
                  title: const Text('关于应用'),
                  subtitle: const Text('版本、许可与数据说明'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => controller.openSubpage(WorkspacePage.about),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class ApplicationSettingsPage extends StatelessWidget {
  const ApplicationSettingsPage({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final settings = controller.data.settings;
    final fontName = settings.customFontPath == null
        ? '系统无衬线体'
        : settings.customFontPath!.split(Platform.pathSeparator).last;
    return _ContentPage(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('外观', style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 18),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '显示模式',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: SegmentedButton<String>(
                      showSelectedIcon: false,
                      segments: const [
                        ButtonSegment(
                          value: 'light',
                          icon: Icon(Icons.light_mode_rounded, size: 18),
                          label: Text('白天'),
                        ),
                        ButtonSegment(
                          value: 'dark',
                          icon: Icon(Icons.dark_mode_rounded, size: 18),
                          label: Text('夜间'),
                        ),
                        ButtonSegment(
                          value: 'system',
                          icon: Icon(Icons.brightness_auto_rounded, size: 18),
                          label: Text('同步'),
                        ),
                      ],
                      selected: {settings.appearanceMode},
                      onSelectionChanged: (value) =>
                          controller.updateAppearanceMode(value.single),
                    ),
                  ),
                  const Divider(height: 30),
                  const Text(
                    '配色',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: palettes.map((palette) {
                      final selected = palette.id == settings.palette;
                      return InkWell(
                        onTap: () => controller.updatePalette(palette.id),
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          width: 112,
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: selected
                                  ? Theme.of(context).colorScheme.primary
                                  : Theme.of(context).dividerColor,
                              width: selected ? 2 : 1,
                            ),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 22,
                                height: 22,
                                decoration: BoxDecoration(
                                  color: palette.seed,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 9),
                              Text(palette.name),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 26),
          Text('正文', style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 18),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  _SettingSlider(
                    label: '字号',
                    valueLabel: '${settings.fontSize.round()} px',
                    value: settings.fontSize,
                    min: 14,
                    max: 32,
                    divisions: 18,
                    onChanged: controller.updateFontSize,
                  ),
                  const Divider(height: 30),
                  _SettingSlider(
                    label: '行间距',
                    valueLabel: '${settings.lineHeight.toStringAsFixed(1)} 倍',
                    value: settings.lineHeight,
                    min: 1.2,
                    max: 2,
                    divisions: 8,
                    onChanged: controller.updateLineHeight,
                  ),
                  const Divider(height: 30),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final compact = constraints.maxWidth < 560;
                      final actions = Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          if (settings.customFontPath != null)
                            TextButton(
                              onPressed: controller.clearCustomFont,
                              child: const Text('恢复默认'),
                            ),
                          OutlinedButton(
                            onPressed: controller.chooseCustomFont,
                            child: const Text('选择字体'),
                          ),
                        ],
                      );
                      if (compact) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('自定义字体'),
                            const SizedBox(height: 6),
                            Text(
                              fontName,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                            const SizedBox(height: 12),
                            actions,
                          ],
                        );
                      }
                      return Row(
                        children: [
                          const Expanded(child: Text('自定义字体')),
                          Flexible(
                            child: Text(
                              fontName,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ),
                          const SizedBox(width: 12),
                          actions,
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class AboutPage extends StatelessWidget {
  const AboutPage({super.key, this.openLink = SystemLinkLauncher.open});

  final Future<bool> Function(Uri) openLink;

  static const _version = '0.4.0-dev.16 (18)';
  static const _applicationId = 'com.silent07137.yejian_native';
  static final Uri _projectUri = Uri.parse(
    'https://github.com/silent07137/yejian-novel-studio',
  );
  static final Uri _issuesUri = Uri.parse(
    'https://github.com/silent07137/yejian-novel-studio/issues',
  );
  static final Uri _formsUri = Uri.parse(
    'https://forms.cloud.microsoft/r/JJdHgxPRdS',
  );

  Future<void> _openExternal(BuildContext context, Uri uri) async {
    final opened = await openLink(uri);
    if (!opened && context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('无法打开链接，请检查浏览器设置')));
    }
  }

  Future<void> _showVersionHistory(BuildContext context) {
    return showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('版本历史'),
        content: const SingleChildScrollView(
          child: Text(
            '0.4.0-dev.16\n'
            '· 时间线按数字层级与同时间顺序排列，保留故事时间\n'
            '· 正文选字菜单可直接添加标注，点击标注可查看备注\n'
            '· 段落设置新增段号显示和批量缩进，行距统一入口\n'
            '· 书内底栏改为覆盖式悬浮，同步显示模式文案优化\n\n'
            '0.4.0-dev.15\n'
            '· 作品打开与返回恢复页面切换动画\n'
            '· 伏笔和灵感支持删除\n'
            '· 正文标注可定位、编辑，并关联伏笔或灵感\n\n'
            '0.4.0-dev.14\n'
            '· 关于应用新增 GitHub Issues 与 Microsoft Forms 反馈入口\n'
            '· 单本书内菜单改为悬浮胶囊，支持滚动显隐\n\n'
            '0.4.0-dev.11\n'
            '· 精简设置页作者卡片\n'
            '· 增加项目仓库入口\n\n'
            '0.4.0-dev.10\n'
            '· 悬浮底栏上滑收起、下滑显示\n'
            '· 开源许可统一为 GPL-2.0-only\n\n'
            '0.4.0-dev.9\n'
            '· 书架 / 设置改为不占底栏槽位的悬浮胶囊\n'
            '· 缩小胶囊宽高，保留手势安全间距\n\n'
            '0.4.0-dev.8\n'
            '· 全局底栏改为紧凑胶囊并增加切换动画\n'
            '· 章节目录统一为底部抽屉交互\n'
            '· 流程图补全合流、分支与关系标签\n\n'
            '0.4.0-dev.7\n'
            '· 重整移动端思维导图\n'
            '· 增加书架 / 设置全局导航\n'
            '· 增加设置首页与关于应用\n\n'
            '0.4.0-dev.6\n'
            '· 完善目录管理、模板字段、时间线与明暗模式',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  Future<void> _showPrivacy(BuildContext context) {
    return showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('数据与隐私'),
        content: const Text(
          '页间采用本地优先设计。作品、章节、角色、世界观与情节数据保存在设备本地；只有在你主动导出或分享文件时，数据才会离开应用。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('知道了'),
          ),
        ],
      ),
    );
  }

  Future<void> _showAppLicense(BuildContext context) {
    return showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('开源许可证'),
        content: const SingleChildScrollView(
          child: Text(
            '页间仅以 GNU General Public License version 2（GPL-2.0-only）发布，不包含“或任何后续版本”条款。完整许可证正文随源代码仓库提供。',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return _ContentPage(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 8),
          Center(
            child: Column(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(24),
                  child: Image.asset(
                    'assets/branding/launcher_icon_1024.png',
                    width: 104,
                    height: 104,
                    fit: BoxFit.cover,
                  ),
                ),
                const SizedBox(height: 16),
                Text('页间', style: Theme.of(context).textTheme.headlineMedium),
                const SizedBox(height: 5),
                Text(
                  _applicationId,
                  style: Theme.of(context).textTheme.bodySmall
                      ?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          const SizedBox(height: 28),
          Card(
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                const ListTile(title: Text('版本'), trailing: Text(_version)),
                const Divider(height: 1),
                ListTile(
                  title: const Text('版本历史'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => _showVersionHistory(context),
                ),
                const Divider(height: 1),
                ListTile(
                  title: const Text('开源许可证'),
                  subtitle: const Text('GPL-2.0-only'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => _showAppLicense(context),
                ),
              ],
            ),
          ),
          const SizedBox(height: 22),
          Text(
            '项目',
            style: Theme.of(context).textTheme.titleMedium
                ?.copyWith(color: scheme.primary),
          ),
          const SizedBox(height: 10),
          Card(
            clipBehavior: Clip.antiAlias,
            child: ListTile(
              key: const ValueKey('open-project-repository'),
              minVerticalPadding: 14,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 18,
                vertical: 4,
              ),
              leading: Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: scheme.primaryContainer,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.code_rounded,
                  color: scheme.onPrimaryContainer,
                ),
              ),
              title: const Text('GitHub'),
              subtitle: Text(
                _projectUri.toString(),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => _openExternal(context, _projectUri),
            ),
          ),
          const SizedBox(height: 22),
          Text(
            '问题反馈',
            style: Theme.of(context).textTheme.titleMedium
                ?.copyWith(color: scheme.primary),
          ),
          const SizedBox(height: 10),
          Card(
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                ListTile(
                  key: const ValueKey('open-github-issues'),
                  title: const Text('GitHub Issues'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => _openExternal(context, _issuesUri),
                ),
                const Divider(height: 1),
                ListTile(
                  key: const ValueKey('open-microsoft-forms'),
                  title: const Text('Microsoft Forms'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => _openExternal(context, _formsUri),
                ),
              ],
            ),
          ),
          const SizedBox(height: 22),
          Text(
            '说明与许可',
            style: Theme.of(context).textTheme.titleMedium
                ?.copyWith(color: scheme.primary),
          ),
          const SizedBox(height: 10),
          Card(
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                ListTile(
                  title: const Text('数据与隐私'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => _showPrivacy(context),
                ),
                const Divider(height: 1),
                ListTile(
                  title: const Text('第三方开源许可'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => showLicensePage(
                    context: context,
                    applicationName: '页间',
                    applicationVersion: _version,
                    applicationIcon: Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(18),
                        child: Image.asset(
                          'assets/branding/launcher_icon_1024.png',
                          width: 72,
                          height: 72,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Text(
            '本地优先的长篇小说写作工具',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _SettingSlider extends StatelessWidget {
  const _SettingSlider({
    required this.label,
    required this.valueLabel,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.onChanged,
  });

  final String label;
  final String valueLabel;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(width: 88, child: Text(label)),
        Expanded(
          child: Slider(
            value: value,
            min: min,
            max: max,
            divisions: divisions,
            onChanged: onChanged,
          ),
        ),
        SizedBox(width: 68, child: Text(valueLabel, textAlign: TextAlign.end)),
      ],
    );
  }
}

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key, required this.controller});

  final AppController controller;

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  late final TextEditingController _name;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(
      text: widget.controller.data.profile.authorName,
    );
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.controller.data;
    return _ContentPage(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('个人中心', style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 20),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Stack(
                    children: [
                      _Avatar(profile: data.profile, size: 86),
                      Positioned(
                        right: 0,
                        bottom: 0,
                        child: IconButton.filledTonal(
                          tooltip: '更换头像',
                          constraints: const BoxConstraints.tightFor(
                            width: 32,
                            height: 32,
                          ),
                          padding: EdgeInsets.zero,
                          onPressed: widget.controller.chooseAvatar,
                          icon: const Icon(
                            Icons.photo_camera_outlined,
                            size: 17,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(width: 24),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        TextField(
                          controller: _name,
                          onChanged: widget.controller.updateAuthorName,
                          decoration: const InputDecoration(labelText: '作者名'),
                        ),
                        const SizedBox(height: 20),
                        Wrap(
                          spacing: 28,
                          runSpacing: 14,
                          children: [
                            _ProfileStat(
                              value: '${data.totalWords}',
                              label: '累计字数',
                            ),
                            _ProfileStat(
                              value: '${data.profile.writingDays}',
                              label: '写作天数',
                            ),
                            _ProfileStat(
                              value: '${data.books.length}',
                              label: '作品',
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfileStat extends StatelessWidget {
  const _ProfileStat({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
        ),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}

class _ContentPage extends StatelessWidget {
  const _ContentPage({required this.child, this.reserveBookNavigation = false});

  final Widget child;
  final bool reserveBookNavigation;

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 600;
    final inset = MediaQuery.viewPaddingOf(context).bottom;
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        compact ? 16 : 28,
        compact ? 16 : 28,
        compact ? 16 : 28,
        reserveBookNavigation && compact ? 92 + inset : (compact ? 16 : 28),
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1040),
          child: child,
        ),
      ),
    );
  }
}

class _Cover extends StatelessWidget {
  const _Cover({
    required this.book,
    required this.width,
    required this.height,
    required this.radius,
  });

  final Book book;
  final double width;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final path = book.coverPath;
    final imageExists = path != null && File(path).existsSync();
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: SizedBox(
        width: width,
        height: height,
        child: imageExists
            ? Image.file(File(path), fit: BoxFit.cover)
            : DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Theme.of(context).colorScheme.primaryContainer,
                      Theme.of(context).colorScheme.secondaryContainer,
                    ],
                  ),
                ),
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Text(
                      book.title.characters.take(3).join(),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onPrimaryContainer,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ),
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.profile, required this.size});

  final WriterProfile profile;
  final double size;

  @override
  Widget build(BuildContext context) {
    final path = profile.avatarPath;
    final imageExists = path != null && File(path).existsSync();
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Theme.of(context).colorScheme.primaryContainer,
        image: imageExists
            ? DecorationImage(image: FileImage(File(path)), fit: BoxFit.cover)
            : null,
      ),
      alignment: Alignment.center,
      child: imageExists
          ? null
          : Text(
              profile.authorName.trim().isEmpty
                  ? '页'
                  : profile.authorName == '未命名'
                  ? '页'
                  : profile.authorName.characters.first,
              style: TextStyle(
                fontSize: size * .36,
                fontWeight: FontWeight.w700,
                color: Theme.of(context).colorScheme.onPrimaryContainer,
              ),
            ),
    );
  }
}
