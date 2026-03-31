import 'package:flutter/material.dart';

import '../app/bus_app.dart';
import '../core/models.dart';
import 'favorite_groups_screen.dart';
import 'route_detail_screen.dart';

class FavoritesScreen extends StatelessWidget {
  const FavoritesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = AppControllerScope.of(context);
    final groups = controller.favoriteGroupNames;

    return DefaultTabController(
      length: groups.isEmpty ? 1 : groups.length,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('我的最愛'),
          actions: [
            IconButton(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const FavoriteGroupsScreen(),
                  ),
                );
              },
              icon: const Icon(Icons.folder_outlined),
            ),
          ],
          bottom: groups.isEmpty
              ? null
              : TabBar(
                  isScrollable: true,
                  tabs: groups.map((group) => Tab(text: group)).toList(),
                ),
        ),
        body: groups.isEmpty
            ? const _EmptyFavoritesState()
            : TabBarView(
                children: groups.map((group) {
                  return _FavoriteGroupList(groupName: group);
                }).toList(),
              ),
      ),
    );
  }
}

class _FavoriteGroupList extends StatelessWidget {
  const _FavoriteGroupList({required this.groupName});

  final String groupName;

  @override
  Widget build(BuildContext context) {
    final controller = AppControllerScope.of(context);

    return FutureBuilder<List<FavoriteResolvedItem>>(
      future: controller.resolveFavoriteGroup(groupName),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text('載入最愛失敗：${snapshot.error}'),
            ),
          );
        }

        final items = snapshot.data ?? const [];
        if (items.isEmpty) {
          return const _EmptyFavoritesState(message: '這個群組還沒有站牌。');
        }

        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          itemCount: items.length,
          separatorBuilder: (_, _) => const SizedBox(height: 10),
          itemBuilder: (context, index) {
            final item = items[index];
            return Dismissible(
              key: ValueKey(
                '$groupName-${item.reference.provider.name}-${item.reference.routeKey}-${item.reference.pathId}-${item.reference.stopId}',
              ),
              direction: DismissDirection.endToStart,
              background: Container(
                alignment: Alignment.centerRight,
                padding: const EdgeInsets.only(right: 20),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.errorContainer,
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Icon(
                  Icons.delete_outline_rounded,
                  color: Theme.of(context).colorScheme.onErrorContainer,
                ),
              ),
              onDismissed: (_) async {
                await controller.removeFavoriteStop(groupName, item.reference);
                if (!context.mounted) {
                  return;
                }
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('已從 $groupName 移除 ${item.stop.stopName}'),
                  ),
                );
              },
              child: Card(
                child: ListTile(
                  contentPadding: const EdgeInsets.all(14),
                  leading: Container(
                    width: 56,
                    height: 56,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Text(
                      item.route.routeName,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelMedium,
                    ),
                  ),
                  title: Text(item.stop.stopName),
                  subtitle: Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      '${item.reference.provider.label} · '
                      '${item.route.description.isEmpty ? "routeKey ${item.route.routeKey}" : item.route.description}',
                    ),
                  ),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => RouteDetailScreen(
                          routeKey: item.reference.routeKey,
                          provider: item.reference.provider,
                          initialPathId: item.reference.pathId,
                          initialStopId: item.reference.stopId,
                        ),
                      ),
                    );
                  },
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _EmptyFavoritesState extends StatelessWidget {
  const _EmptyFavoritesState({this.message = '還沒有任何最愛站牌。'});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(message, textAlign: TextAlign.center),
      ),
    );
  }
}
