part of '../subsystem_base.dart';

/// Descriptor for a subsystem type category (e.g. settings, navigation, telemetry).
///
/// Bridges subsystem classes with the registry that manages them and facilitates
/// type-scoped lookups.
class SubsystemTypeDesc {
  SubsystemTypeDesc({
    required this.displayName,
    required this.description,
    required this.serviceTypeId,
    this.supportsMultipleClasses = false,
  });

  final String displayName;
  final String description;

  /// Unique identifier of this service type category (e.g., 'core.settings').
  final String serviceTypeId;

  /// Whether multiple distinct subsystem classes can be registered under this type.
  final bool supportsMultipleClasses;

  bool _isTypeContextInitialized = false;
  bool _isTypeContextDisposed = false;

  /// Whether [initializeTypeContext] has been called and completed.
  bool get isTypeContextInitialized => _isTypeContextInitialized;

  /// Whether [disposeTypeContext] has been called and completed.
  bool get isTypeContextDisposed => _isTypeContextDisposed;

  bool isValid() => serviceTypeId.isNotEmpty;

  /// Lifecycle hook called when the first subsystem of this type is registered.
  /// Managed by the registry; should not be called directly.
  @protected
  Future<void> initializeTypeContext() async {}

  /// Lifecycle hook called when the last subsystem of this type is disposed.
  /// Managed by the registry; should not be called directly.
  @protected
  Future<void> disposeTypeContext() async {}

  /// Idempotent: only initializes once even if called multiple times.
  Future<void> _beginInitializeTypeContext() async {
    if (_isTypeContextInitialized) {
      return;
    }
    await initializeTypeContext();
    _isTypeContextInitialized = true;
    _isTypeContextDisposed = false;
  }

  /// Idempotent: only disposes once even if called multiple times.
  /// Resets [_isTypeContextInitialized] so the context can be re-initialized
  /// if subsystems of this type are registered again later.
  Future<void> _beginDisposeTypeContext() async {
    if (_isTypeContextDisposed) {
      return;
    }
    _isTypeContextDisposed = true;
    _isTypeContextInitialized = false;
    await disposeTypeContext();
  }

  /// Retrieves the registry associated with this type.
  ///
  /// Throws [SubsystemNotFoundException] if no registry has been created yet.
  SubsystemInstanceRegistryByTypeDesc getRegistry() {
    final registry = SubsystemInstanceRegistry.findRegistryForTypeId(serviceTypeId);
    if (registry == null) {
      throw SubsystemNotFoundException(
        'No registry found for type ID: $serviceTypeId',
        typeId: serviceTypeId,
      );
    }
    return registry;
  }

  /// Retrieves all instantiated subsystems of this type.
  List<Subsystem> get allInstances {
    final reg = getRegistry();
    return reg.allInstances;
  }

  /// Retrieves all instantiated subsystems of this type matching [TSubsystem].
  List<TSubsystem> allInstancesOfType<TSubsystem extends Subsystem>() {
    final reg = getRegistry();
    return reg.allInstancesOfType<TSubsystem>();
  }

  /// Retrieves an instance of this type by its [classId].
  ///
  /// Throws [SubsystemNotFoundException] if no instance with [classId] exists.
  TSubsystem getInstanceByClassId<TSubsystem extends Subsystem>(String classId) {
    final reg = getRegistry();
    final instance = reg.findByClassId(classId);
    if (instance == null) {
      throw SubsystemNotFoundException(
        'No instance found for class ID: $classId in type ID: $serviceTypeId',
        typeId: serviceTypeId,
        classId: classId,
      );
    }
    return instance as TSubsystem;
  }

  @override
  String toString() => 'SubsystemTypeDesc($serviceTypeId)';
}
