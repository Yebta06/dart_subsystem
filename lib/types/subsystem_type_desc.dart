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

  bool isValid() => serviceTypeId.isNotEmpty;

  @protected
  /// Lifecycle hook called when the first subsystem of this type is registered.
  /// Managed by the registry; should not be called directly.
  Future<void> initializeTypeContext() async {}

  @protected
  /// Lifecycle hook called when the last subsystem of this type is disposed.
  /// Managed by the registry; should not be called directly.
  Future<void> disposeTypeContext() async {}

  Future<void> _beginInitializeTypeContext() async => initializeTypeContext();
  Future<void> _beginDisposeTypeContext() async => disposeTypeContext();

  /// Synchronously retrieves the registry associated with this type.
  SubsystemInstanceRegistryByTypeDesc getRegistrySync() {
    final registry = SubsystemInstanceRegistry.findRegistryForTypeIdSync(serviceTypeId);
    if (registry == null) {
      throw SubsystemNotFoundException(
        'No registry found for type ID: $serviceTypeId',
        typeId: serviceTypeId,
      );
    }
    return registry;
  }

  /// Asynchronously retrieves the registry associated with this type.
  Future<SubsystemInstanceRegistryByTypeDesc> get registry async {
    final registry = await SubsystemInstanceRegistry.findRegistryForTypeId(serviceTypeId);
    if (registry == null) {
      throw SubsystemNotFoundException(
        'No registry found for type ID: $serviceTypeId',
        typeId: serviceTypeId,
      );
    }
    return registry;
  }

  /// Retrieves all instantiated subsystems of this type.
  Future<List<Subsystem>> get allInstances async {
    final reg = await registry;
    return reg.allInstances;
  }

  /// Synchronously retrieves all instantiated subsystems of this type matching [TSubsystem].
  List<TSubsystem> allInstancesSync<TSubsystem extends Subsystem>() {
    final reg = getRegistrySync();
    return reg.allInstancesOfType<TSubsystem>();
  }

  /// Asynchronously retrieves an instance of this type by its [classId].
  Future<TSubsystem> getInstanceByClassId<TSubsystem extends Subsystem>(String classId) async {
    final reg = await registry;
    final instance = await reg.findByClassId(classId);
    if (instance == null) {
      throw SubsystemNotFoundException(
        'No instance found for class ID: $classId in type ID: $serviceTypeId',
        typeId: serviceTypeId,
        classId: classId,
      );
    }
    return instance as TSubsystem;
  }

  /// Synchronously retrieves an instance of this type by its [classId].
  TSubsystem getInstanceByClassIdSync<TSubsystem extends Subsystem>(String classId) {
    final reg = getRegistrySync();
    final instance = reg.findByClassIdSync(classId);
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
