import 'package:flutter/widgets.dart';

import 'app/bus_app.dart';
import 'core/app_controller.dart';
import 'core/bus_repository.dart';
import 'core/database_factory.dart';
import 'core/storage_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  configureDatabaseFactory();

  final controller = AppController(
    repository: BusRepository(),
    storage: StorageService(),
  );
  await controller.initialize();

  runApp(BusApp(controller: controller));
}
