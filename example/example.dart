import 'package:dart_subsystem/dart_subsystem.dart';

// 1. Define Category/Type descriptor
final networkTypeDesc = SubsystemTypeDesc(
  displayName: 'Network Services',
  description: 'Services managing communication and network I/O',
  serviceTypeId: 'core.network',
);

// 2. Define concrete Subsystem implementation descriptor
final apiClientClassDesc = SubsystemClassDesc(
  serviceType: networkTypeDesc,
  displayName: 'API Client Subsystem',
  description: 'Manages HTTP/REST calls and connection state',
  serviceClassId: 'network.api_client',
  defaultBuilder: (params) async => ApiClientSubsystem(classDesc: params.classDescription),
);

// 3. Subsystem implementation
class ApiClientSubsystem extends Subsystem {
  ApiClientSubsystem({required super.classDesc});

  bool _isConnected = false;
  bool get isConnected => _isConnected;

  @override
  void beginConstruct(BuildServiceParameters params) {
    // Synchronous setup right after instantiation
    print('[ApiClient] Constructing subsystem...');
  }

  @override
  Future<void> initialize(BuildServiceParameters params) async {
    // Asynchronous loading or handshake
    print('[ApiClient] Connecting to remote service...');
    await Future<void>.delayed(const Duration(milliseconds: 50));
    _isConnected = true;
    print('[ApiClient] Connected successfully!');
  }

  void fetchData(String endpoint) {
    // Protect against usage after disposal
    assertNotDisposed();
    print('[ApiClient] Fetching data from: $endpoint');
  }

  @override
  Future<void> dispose() async {
    // Release resources, disconnect connections
    print('[ApiClient] Disconnecting...');
    _isConnected = false;
  }

  @override
  Future<void> finalDispose() async {
    // Final cleanup guaranteed to execute even if dispose throws
    print('[ApiClient] Final cleanup complete.');
  }
}

Future<void> main() async {
  // Optional: hook into lifecycle errors during disposal
  SubsystemInstanceRegistry.onLifecycleError = (error, stackTrace) {
    print('[Lifecycle Error] $error');
  };

  // Build and register subsystems using the factory
  final factory = TSubsystemFactory();
  factory.addService(
    BuildServiceParameters(classDescription: apiClientClassDesc),
  );

  print('Registering subsystems...');
  await factory.registerSubsystems();

  // Retrieve subsystem instance synchronously
  final client = apiClientClassDesc.getInstance<ApiClientSubsystem>();
  client?.fetchData('/users');

  // Teardown
  print('Tearing down subsystems...');
  await SubsystemInstanceRegistry.clearAll();
  print('Done!');
}
