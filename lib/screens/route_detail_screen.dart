import 'dart:async';

import 'package:flutter/material.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../app/bus_app.dart';
import '../core/models.dart';
import '../widgets/eta_badge.dart';

class RouteDetailScreen extends StatefulWidget {
  const RouteDetailScreen({
    required this.routeKey,
    required this.provider,
    this.initialPathId,
    this.initialStopId,
    super.key,
  });

  final int routeKey;
  final BusProvider provider;
  final int? initialPathId;
  final int? initialStopId;

  @override
  State<RouteDetailScreen> createState() => _RouteDetailScreenState();
}

class _RouteDetailScreenState extends State<RouteDetailScreen>
    with TickerProviderStateMixin {
  bool _isLoading = true;
  String? _error;
  String? _statusMessage;
  RouteDetailData? _detail;
  Timer? _countdownTimer;
  TabController? _tabController;
  int _remainingSeconds = 0;
  bool _didScrollToInitialStop = false;
  bool _isScrollingToInitialStop = false;
  bool? _wakelockEnabled;
  int? _targetInitialPathId;
  final Map<int, GlobalKey> _stopKeys = <int, GlobalKey>{};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_refresh());
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncWakelock(
      AppControllerScope.of(context).settings.keepScreenAwakeOnRouteDetail,
    );
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _tabController?.dispose();
    if (_wakelockEnabled == true) {
      unawaited(_setWakelock(false));
    }
    super.dispose();
  }

  Future<void> _refresh() async {
    final controller = AppControllerScope.read(context);

    setState(() {
      _isLoading = true;
      _error = null;
      _statusMessage = '讀取中...';
    });

    try {
      final detail = await controller.getRouteDetail(
        widget.routeKey,
        provider: widget.provider,
      );
      if (!mounted) {
        return;
      }

      _syncTabController(detail);
      setState(() {
        _detail = detail;
        _isLoading = false;
        _statusMessage = null;
      });
      _startCountdown(controller.settings.busUpdateTime);
      _scrollToInitialStopIfNeeded();
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isLoading = false;
        _error = '$error';
        _statusMessage = '更新失敗，稍後重試';
      });
      _startCountdown(controller.settings.busErrorUpdateTime);
    }
  }

  void _syncTabController(RouteDetailData detail) {
    final pathIds = detail.paths.map((path) => path.pathId).toList();
    if (pathIds.isEmpty) {
      _tabController?.dispose();
      _tabController = null;
      _targetInitialPathId = null;
      return;
    }

    final initialIndex = _resolveInitialPathIndex(detail.paths);
    _targetInitialPathId = detail.paths[initialIndex].pathId;
    final selectedIndex = _tabController == null
        ? initialIndex
        : _tabController!.index.clamp(0, pathIds.length - 1);

    if (_tabController?.length == pathIds.length) {
      _tabController!.index = selectedIndex;
      return;
    }

    _tabController?.dispose();
    _tabController = TabController(
      length: pathIds.length,
      vsync: this,
      initialIndex: selectedIndex,
    );
    _tabController!.addListener(() {
      if (_tabController!.indexIsChanging) {
        return;
      }
      setState(() {});
      _scrollToInitialStopIfNeeded();
    });
  }

  int _resolveInitialPathIndex(List<PathInfo> paths) {
    if (widget.initialPathId == null || paths.isEmpty) {
      return 0;
    }

    final exactMatch = paths.indexWhere(
      (path) => path.pathId == widget.initialPathId,
    );
    if (exactMatch != -1) {
      return exactMatch;
    }

    final legacyIndex = widget.initialPathId!;
    if (legacyIndex >= 0 && legacyIndex < paths.length) {
      return legacyIndex;
    }
    return 0;
  }

  void _startCountdown(int seconds) {
    _countdownTimer?.cancel();
    _remainingSeconds = seconds;
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_remainingSeconds <= 0) {
        timer.cancel();
        unawaited(_refresh());
        return;
      }
      setState(() {
        _remainingSeconds -= 1;
      });
    });
  }

  void _scrollToInitialStopIfNeeded() {
    if (_didScrollToInitialStop ||
        _isScrollingToInitialStop ||
        widget.initialStopId == null ||
        _detail == null) {
      return;
    }

    final pathId = _currentPathId;
    if (pathId == null) {
      return;
    }
    if (_targetInitialPathId != null && _targetInitialPathId != pathId) {
      return;
    }

    unawaited(_attemptScrollToInitialStop(pathId, widget.initialStopId!));
  }

  Future<void> _attemptScrollToInitialStop(int pathId, int stopId) async {
    _isScrollingToInitialStop = true;
    try {
      for (var attempt = 0; attempt < 12; attempt++) {
        await WidgetsBinding.instance.endOfFrame;
        if (!mounted || _didScrollToInitialStop) {
          return;
        }
        if (_currentPathId != pathId) {
          return;
        }

        final key = _stopKeys[_keyForStop(pathId, stopId)];
        final targetContext = key?.currentContext;
        if (targetContext == null || !targetContext.mounted) {
          continue;
        }

        await Scrollable.ensureVisible(
          targetContext,
          duration: const Duration(milliseconds: 360),
          curve: Curves.easeOutCubic,
          alignment: 0.28,
        );
        _didScrollToInitialStop = true;
        return;
      }
    } finally {
      _isScrollingToInitialStop = false;
    }
  }

  int? get _currentPathId {
    final detail = _detail;
    final tabController = _tabController;
    if (detail == null || detail.paths.isEmpty || tabController == null) {
      return null;
    }

    return detail.paths[tabController.index].pathId;
  }

  int _keyForStop(int pathId, int stopId) {
    return Object.hash(pathId, stopId);
  }

  void _syncWakelock(bool enable) {
    if (_wakelockEnabled == enable) {
      return;
    }
    _wakelockEnabled = enable;
    unawaited(_setWakelock(enable));
  }

  Future<void> _setWakelock(bool enable) async {
    try {
      await WakelockPlus.toggle(enable: enable);
    } catch (_) {
      // Ignore unsupported platform or plugin errors and keep the page usable.
    }
  }

  bool _isInitialStop(StopInfo stop) {
    if (widget.initialStopId != stop.stopId) {
      return false;
    }
    return _targetInitialPathId == null || _targetInitialPathId == stop.pathId;
  }

  Future<void> _handleFavorite(StopInfo stop) async {
    final controller = AppControllerScope.read(context);
    String? groupName;

    if (controller.favoriteGroupNames.length > 1) {
      groupName = await _showGroupPicker(controller.favoriteGroupNames);
      if (!mounted) {
        return;
      }
      if (groupName == null) {
        return;
      }
      if (groupName == '__new__') {
        groupName = await _showAddGroupDialog();
        if (!mounted || groupName == null || groupName.trim().isEmpty) {
          return;
        }
        await controller.addFavoriteGroup(groupName);
      }
    } else if (controller.favoriteGroupNames.length == 1) {
      groupName = controller.favoriteGroupNames.first;
    }

    final selectedGroup = await controller.addFavoriteStop(
      FavoriteStop(
        provider: widget.provider,
        routeKey: widget.routeKey,
        pathId: stop.pathId,
        stopId: stop.stopId,
      ),
      groupName: groupName,
    );
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('已加入 $selectedGroup')));
  }

  Future<String?> _showGroupPicker(List<String> groups) {
    return showDialog<String>(
      context: context,
      builder: (context) {
        return SimpleDialog(
          title: const Text('選擇最愛群組'),
          children: [
            ...groups.map(
              (group) => SimpleDialogOption(
                onPressed: () => Navigator.of(context).pop(group),
                child: Text(group),
              ),
            ),
            const Divider(height: 1),
            SimpleDialogOption(
              onPressed: () => Navigator.of(context).pop('__new__'),
              child: const Text('新增群組'),
            ),
          ],
        );
      },
    );
  }

  Future<String?> _showAddGroupDialog() async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('新增最愛群組'),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(hintText: '輸入群組名稱'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.of(context).pop(controller.text.trim()),
              child: const Text('新增'),
            ),
          ],
        );
      },
    );
    controller.dispose();
    return result;
  }

  Widget _buildStopChip({required Widget label, Widget? avatar}) {
    return Chip(
      avatar: avatar,
      label: label,
      padding: EdgeInsets.zero,
      labelPadding: const EdgeInsets.symmetric(horizontal: 4),
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: VisualDensity.compact,
    );
  }

  Widget _buildStopTile(
    ThemeData theme,
    StopInfo stop, {
    required bool alwaysShowSeconds,
    required bool isHighlighted,
  }) {
    final message = (stop.msg ?? '').trim();
    final vehicle = stop.buses.isEmpty ? null : stop.buses.first;

    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(
          color: isHighlighted
              ? theme.colorScheme.secondary
              : theme.colorScheme.outlineVariant,
        ),
      ),
      color: isHighlighted ? theme.colorScheme.secondaryContainer : null,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 8, 6, 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            EtaBadge(
              stop: stop,
              alwaysShowSeconds: alwaysShowSeconds,
              size: 50,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      stop.stopName,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                        height: 1.15,
                      ),
                    ),
                    if (message.isNotEmpty || vehicle != null) ...[
                      const SizedBox(height: 4),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          if (message.isNotEmpty)
                            _buildStopChip(label: Text(message)),
                          if (vehicle != null)
                            _buildStopChip(
                              avatar: Icon(
                                vehicle.type == '1'
                                    ? Icons.accessible_rounded
                                    : Icons.directions_bus_rounded,
                                size: 16,
                              ),
                              label: Text(vehicle.id),
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
            PopupMenuButton<_StopAction>(
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints.tightFor(width: 36, height: 36),
              icon: const Icon(Icons.more_horiz_rounded, size: 20),
              onSelected: (value) {
                if (value == _StopAction.favorite) {
                  _handleFavorite(stop);
                }
              },
              itemBuilder: (context) => const [
                PopupMenuItem<_StopAction>(
                  value: _StopAction.favorite,
                  child: Text('加入最愛'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = AppControllerScope.of(context);
    final detail = _detail;
    final theme = Theme.of(context);
    final updateSeconds = _error == null
        ? controller.settings.busUpdateTime
        : controller.settings.busErrorUpdateTime;
    final progress = updateSeconds <= 0
        ? null
        : ((updateSeconds - _remainingSeconds) / updateSeconds).clamp(0.0, 1.0);

    return Scaffold(
      appBar: AppBar(
        title: Text(detail?.route.routeName ?? '公車資訊'),
        actions: [
          IconButton(
            onPressed: _refresh,
            icon: const Icon(Icons.refresh_rounded),
          ),
          IconButton(
            onPressed: detail == null
                ? null
                : () {
                    showDialog<void>(
                      context: context,
                      builder: (context) {
                        return AlertDialog(
                          title: Text(detail.route.routeName),
                          content: Text(
                            detail.route.description.isEmpty
                                ? 'routeKey: ${detail.route.routeKey}'
                                : detail.route.description,
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.of(context).pop(),
                              child: const Text('關閉'),
                            ),
                          ],
                        );
                      },
                    );
                  },
            icon: const Icon(Icons.info_outline_rounded),
          ),
        ],
      ),
      bottomNavigationBar: BottomAppBar(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              LinearProgressIndicator(value: progress),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  _statusMessage ??
                      (_remainingSeconds > 0
                          ? '$_remainingSeconds 秒後自動更新'
                          : '準備重新整理'),
                  style: theme.textTheme.bodySmall,
                ),
              ),
            ],
          ),
        ),
      ),
      body: _isLoading && detail == null
          ? const Center(child: CircularProgressIndicator())
          : detail == null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(_error ?? '目前無法載入公車資訊'),
              ),
            )
          : Column(
              children: [
                if (_tabController != null)
                  TabBar(
                    controller: _tabController,
                    isScrollable: true,
                    tabs: detail.paths
                        .map((path) => Tab(text: path.name))
                        .toList(),
                  ),
                Expanded(
                  child: _tabController == null
                      ? const Center(child: Text('目前沒有可顯示的方向'))
                      : TabBarView(
                          controller: _tabController,
                          children: detail.paths.map((path) {
                            final pathStops =
                                detail.stopsByPath[path.pathId] ?? const [];
                            return ListView.separated(
                              padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
                              itemCount: pathStops.length,
                              separatorBuilder: (_, _) =>
                                  const SizedBox(height: 6),
                              itemBuilder: (context, index) {
                                final stop = pathStops[index];
                                final key = _stopKeys.putIfAbsent(
                                  _keyForStop(path.pathId, stop.stopId),
                                  GlobalKey.new,
                                );
                                return Container(
                                  key: key,
                                  child: _buildStopTile(
                                    theme,
                                    stop,
                                    alwaysShowSeconds:
                                        controller.settings.alwaysShowSeconds,
                                    isHighlighted: _isInitialStop(stop),
                                  ),
                                );
                              },
                            );
                          }).toList(),
                        ),
                ),
              ],
            ),
    );
  }
}

enum _StopAction { favorite }
