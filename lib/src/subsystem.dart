part of '../subsystem_base.dart';

/// Base class for all managed subsystems.
///
/// Subsystems are singletons managed within a [SubsystemTypeDesc] scope
/// by [SubsystemInstanceRegistry].
///
/// Lifecycle progression:
/// 1. Construction: [beginConstruct] -> [postConstruct] (synchronous)
/// 2. Initialization: [initialize] -> [postInitialize] (asynchronous)
/// 3. Teardown: [dispose] -> [finalDispose] (asynchronous, idempotent)
abstract class Subsystem {
  final SubsystemClassDesc classDesc;

  bool _isConstructed = false;
  bool _isInitialized = false;
  bool _isDisposed = false;

  /// Indicates whether construction hooks have completed.
  bool get isConstructed => _isConstructed;

  /// Indicates whether asynchronous initialization has completed successfully.
  bool get isInitialized => _isInitialized;

  /// Indicates whether the subsystem has been disposed.
  bool get isDisposed => _isDisposed;

  Subsystem({required this.classDesc}) {
    if (!classDesc.isValid()) {
      throw ArgumentError.value(
        classDesc,
        'classDesc',
        'Invalid SubsystemClassDesc provided to Subsystem',
      );
    }
  }

  // ⚠️ Lifecycle hooks: override in subclasses, do not invoke directly.

  /// Synchronous preparation immediately after instantiation.
  @protected
  void beginConstruct(BuildServiceParameters params) {}

  /// Synchronous post-instantiation hook.
  @protected
  void postConstruct(BuildServiceParameters params) {}

  /// Asynchronous initialization hook for loading resources, services, or data.
  @protected
  Future<void> initialize(BuildServiceParameters params) async {}

  /// Asynchronous post-initialization hook called after all batch subsystems are initialized.
  @protected
  Future<void> postInitialize(BuildServiceParameters params) async {}

  /// Primary teardown hook for releasing allocated resources and listeners.
  @protected
  Future<void> dispose() async {}

  /// Final teardown hook executed after [dispose], guaranteed even if [dispose] throws.
  @protected
  Future<void> finalDispose() async {}

  void _constructSubsystem(BuildServiceParameters params) {
    beginConstruct(params);
    postConstruct(params);
    _isConstructed = true;
  }

  Future<void> _initSubsystem(BuildServiceParameters params) async {
    await initialize(params);
    _isInitialized = true;
  }

  Future<void> _postInitSubsystem(BuildServiceParameters params) async {
    await postInitialize(params);
  }

  Future<void> _disposeSubsystem() async {
    if (_isDisposed) {
      return;
    }
    _isDisposed = true;
    try {
      await dispose();
    } finally {
      await finalDispose();
    }
  }
}
