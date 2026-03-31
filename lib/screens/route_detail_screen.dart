import 'dart:async';

import 'package:flutter/material.dart';

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
  final Map<int, GlobalKey> _stopKeys = <int, GlobalKey>{};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_refresh());
    });
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _tabController?.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    final controller = AppControllerScope.read(context);

    setState(() {
      _isLoading = true;
      _error = null;
      _statusMessage = '更新中...';
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
      return;
    }

    final initialIndex = widget.initialPathId == null
        ? 0
        : pathIds.indexOf(widget.initialPathId!).clamp(0, pathIds.length - 1);
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
        widget.initialStopId == null ||
        _detail == null) {
      return;
    }

    final pathId = _currentPathId;
    if (widget.initialPathId != null && widget.initialPathId != pathId) {
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final pathId = _currentPathId;
      if (pathId == null) {
        return;
      }
      final key = _stopKeys[_keyForStop(pathId, widget.initialStopId!)];
      final context = key?.currentContext;
      if (context == null) {
        return;
      }
      Scrollable.ensureVisible(
        context,
        duration: const Duration(milliseconds: 320),
        alignment: 0.3,
      );
      _didScrollToInitialStop = true;
    });
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
            decoration: const InputDecoration(hintText: '例如：通勤'),
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
        title: Text(detail?.route.routeName ?? '載入中...'),
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
                          ? '$_remainingSeconds 秒後重新整理'
                          : '等待下一次更新'),
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
                child: Text(_error ?? '沒有可顯示的資料。'),
              ),
            )
          : Column(
              children: [
                // Padding(
                //   padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                //   child: Card(
                //     child: Padding(
                //       padding: const EdgeInsets.all(16),
                //       child: Column(
                //         crossAxisAlignment: CrossAxisAlignment.start,
                //         children: [
                //           Wrap(
                //             spacing: 8,
                //             runSpacing: 8,
                //             children: [
                //               Chip(label: Text(widget.provider.label)),
                //               Chip(
                //                 label: Text(
                //                   'routeKey ${detail.route.routeKey}',
                //                 ),
                //               ),
                //             ],
                //           ),
                //           if (detail.route.description.isNotEmpty) ...[
                //             const SizedBox(height: 10),
                //             Text(detail.route.description),
                //           ],
                //         ],
                //       ),
                //     ),
                //   ),
                // ),
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
                      ? const Center(child: Text('沒有方向資料。'))
                      : TabBarView(
                          controller: _tabController,
                          children: detail.paths.map((path) {
                            final pathStops =
                                detail.stopsByPath[path.pathId] ?? const [];
                            return ListView.separated(
                              padding: const EdgeInsets.fromLTRB(
                                16,
                                12,
                                16,
                                24,
                              ),
                              itemCount: pathStops.length,
                              separatorBuilder: (_, _) =>
                                  const SizedBox(height: 10),
                              itemBuilder: (context, index) {
                                final stop = pathStops[index];
                                final key = _stopKeys.putIfAbsent(
                                  _keyForStop(path.pathId, stop.stopId),
                                  GlobalKey.new,
                                );
                                return Card(
                                  key: key,
                                  color: widget.initialStopId == stop.stopId
                                      ? theme.colorScheme.secondaryContainer
                                      : null,
                                  child: ListTile(
                                    contentPadding: const EdgeInsets.all(14),
                                    leading: EtaBadge(
                                      stop: stop,
                                      alwaysShowSeconds:
                                          controller.settings.alwaysShowSeconds,
                                    ),
                                    title: Text(stop.stopName),
                                    subtitle: Padding(
                                      padding: const EdgeInsets.only(top: 8),
                                      child: Wrap(
                                        spacing: 8,
                                        runSpacing: 8,
                                        children: [
                                          if ((stop.msg ?? '')
                                              .trim()
                                              .isNotEmpty)
                                            Chip(label: Text(stop.msg!.trim())),
                                          if (stop.buses.isNotEmpty)
                                            Chip(
                                              avatar: Icon(
                                                stop.buses.first.type == '1'
                                                    ? Icons.accessible_rounded
                                                    : Icons
                                                          .directions_bus_rounded,
                                                size: 18,
                                              ),
                                              label: Text(stop.buses.first.id),
                                            ),
                                        ],
                                      ),
                                    ),
                                    trailing: PopupMenuButton<_StopAction>(
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
