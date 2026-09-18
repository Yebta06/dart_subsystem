# dart_subsystem

A robust, lifecycle-aware framework for managing singleton services (subsystems) in Dart and Flutter applications.

Inspired by advanced modular architectures (such as Unreal Engine Subsystems), this package provides a highly structured, scalable, and fail-safe way to define, initialize, access, and dispose of global or scoped services.

## Features

- **Explicit Lifecycle Hooks**: Predictable states (`isConstructed`, `isInitialized`, `isDisposed`) with guaranteed sequential execution.
- **Dependency & Async Awareness**: Supports both synchronous foundational services and asynchronous parallel services during startup.
- **Fail-Safe Initialization**: If a subsystem fails to initialize, it is safely rolled back and disposed, preventing "zombie" singletons from polluting your app state.
- **Idempotent Teardown**: Ensures resources are cleaned up cleanly. A `finalDispose()` hook runs reliably even if primary disposal throws an exception.
- **Type-Safe Organization**: Group implementations under category types (`SubsystemTypeDesc`) and concrete definitions (`SubsystemClassDesc`) for clean abstraction and lookup.

## Installation

Add the following to your `pubspec.yaml`:

```yaml
dependencies:
  dart_subsystem: ^0.1.0
```

## Quick Start

### 1. Define Subsystem Descriptors
Subsystems are organized by types and specific class implementations.

```dart
import 'package:dart_subsystem/dart_subsystem.dart';

// 1. Define the Category/Type
final networkTypeDesc = SubsystemTypeDesc(
  displayName: 'Network Services',
  description: 'Handles all external communications',
  serviceTypeId: 'core.network',
);

// 2. Define the Concrete Implementation Descriptor
final apiClassDesc = SubsystemClassDesc(
  serviceType: networkTypeDesc,
  displayName: 'REST API Subsystem',
  description: 'Manages REST API calls',
  serviceClassId: 'network.api',
  defaultBuilder: (params) async => ApiSubsystem(classDesc: params.classDescription),
);
```

### 2. Implement your Subsystem
Extend the `Subsystem` class and override the lifecycle hooks you need.

```dart
class ApiSubsystem extends Subsystem {
  ApiSubsystem({required super.classDesc});

  @override
  void beginConstruct(BuildServiceParameters params) {
    // Synchronous setup: runs immediately after instantiation
    print('Constructing API Subsystem...');
  }

  @override
  Future<void> initialize(BuildServiceParameters params) async {
    // Asynchronous setup: connect to databases, fetch tokens, etc.
    print('Initializing API connections...');
    await Future.delayed(Duration(seconds: 1)); 
  }

  @override
  Future<void> dispose() async {
    // Clean up resources when the app shuts down or service is removed
    print('Closing API connections...');
  }
}
```

### 3. Register and Build
Use the `TSubsystemFactory` to queue up your services and build them safely.

```dart
void main() async {
  final factory = TSubsystemFactory();

  // Add the service. You can pass 'isSynchronous: true' if other services depend on it immediately.
  factory.addService(BuildServiceParameters(classDescription: apiClassDesc));

  try {
    // Builds and initializes all registered subsystems
    await factory.registerSubsystems();
    print('All subsystems are ready!');
  } on SubsystemInitializationException catch (e) {
    print('Startup failed: ${e.message}');
  }
}
```

### 4. Access your Subsystem
Once initialized, you can retrieve your subsystem anywhere in your app synchronously or asynchronously.

```dart
// Synchronous retrieval
final api = SubsystemInstanceRegistry.findSubsystemByIdsChecked<ApiSubsystem>(
  'core.network', 
  'network.api',
);

// Or via the descriptor
final api = apiClassDesc.getInstanceSync<ApiSubsystem>();
```

## Lifecycle Phases

1. **Construction**: `beginConstruct` -> `postConstruct` (Synchronous)
2. **Initialization**: `initialize` -> `postInitialize` (Asynchronous)
3. **Teardown**: `dispose` -> `finalDispose` (Asynchronous, guaranteed execution)

## Error Handling

If a subsystem throws an exception during `initialize()` or `postInitialize()`, `dart_subsystem` handles it gracefully:
1. The failing subsystem is immediately removed from the registry.
2. Its `dispose()` and `finalDispose()` methods are called to clean up any partial state.
3. The original exception is bundled into a `SubsystemInitializationException` and rethrown.
4. You can inspect failures via `SubsystemInstanceRegistry.lastFailedRegistrations`.

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
