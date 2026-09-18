part of '../subsystem_base.dart';

/// Registry holding active singleton instances for a specific [SubsystemTypeDesc].
class SubsystemInstanceRegistryByTypeDesc {
  SubsystemInstanceRegistryByTypeDesc({required this.typeDesc});

  final SubsystemTypeDesc typeDesc;
  final Map<SubsystemClassDesc, Subsystem> _singletonsByDesc = {};

  /// Unmodifiable view of registered singletons keyed by class descriptor.
  Map<SubsystemClassDesc, Subsystem> get singletonsByDesc =>
      Map.unmodifiable(_singletonsByDesc);

  /// All active subsystem instances in this registry.
  List<Subsystem> get allInstances => _singletonsByDesc.values.toList();

  /// All active subsystem instances matching type [TSubsystem].
  List<TSubsystem> allInstancesOfType<TSubsystem extends Subsystem>() {
    final instances = <TSubsystem>[];
    for (final singleton in _singletonsByDesc.values) {
      if (singleton is TSubsystem) {
        instances.add(singleton);
      }
    }
    return instances;
  }

  /// Finds a registered subsystem by its [classId].
  ///
  /// Returns `null` if no subsystem with [classId] is registered.
  Subsystem? findByClassId(String classId) {
    for (final entry in _singletonsByDesc.entries) {
      if (entry.key.serviceClassId == classId) {
        return entry.value;
      }
    }
    return null;
  }

  Future<TSubsystem> _buildInstance<TSubsystem extends Subsystem>(
    BuildServiceParameters params,
  ) async {
    final existing = findByClassId(params.classDescription.serviceClassId);
    if (existing != null) {
      throw StateError(
        'Singleton already registered for classId ${params.classDescription.serviceClassId}',
      );
    }

    Subsystem? singleton;
    if (params.customBuilder != null) {
      singleton = await params.customBuilder!(params);
    } else if (params.classDescription.defaultBuilder != null) {
      singleton = await params.classDescription.defaultBuilder!(params);
    } else {
      throw StateError(
        'No builder provided for classId ${params.classDescription.serviceClassId}',
      );
    }

    if (singleton == null) {
      throw StateError(
        'Builder returned null for classId ${params.classDescription.serviceClassId}',
      );
    }

    if (singleton is! TSubsystem) {
      throw TypeError();
    }

    _singletonsByDesc[params.classDescription] = singleton;
    try {
      singleton._constructSubsystem(params);
    } catch (_) {
      _singletonsByDesc.remove(params.classDescription);
      // L3: Dispose the partially-constructed instance to release any
      // resources allocated by beginConstruct before postConstruct threw.
      try {
        await singleton._disposeSubsystem();
      } catch (_) {
        // Ignore secondary teardown errors
      }
      rethrow;
    }

    return singleton;
  }

  /// Unregisters and disposes a singleton by its [classId].
  Future<void> unregisterSingletonByClassId(
    String classId, {
    bool preserveTypeContext = false,
  }) async {
    final singleton = findByClassId(classId);
    if (singleton != null) {
      await unregisterSingleton(singleton, preserveTypeContext: preserveTypeContext);
    }
  }

  /// Unregisters and disposes a singleton instance.
  /// Safe and idempotent: does nothing if the instance is not registered.
  Future<void> unregisterSingleton(
    Subsystem instance, {
    bool preserveTypeContext = false,
  }) async {
    final removed = _singletonsByDesc.remove(instance.classDesc);
    if (removed == null) {
      return;
    }

    await instance._disposeSubsystem();

    if (_singletonsByDesc.isEmpty && !preserveTypeContext) {
      await typeDesc._beginDisposeTypeContext();
      SubsystemInstanceRegistry._registriesByTypeDesc.remove(typeDesc);
    }
  }

  /// Removes an instance from the registry without running disposal hooks.
  /// Used for rollback during initialization failures.
  void _removeInstanceSilently(Subsystem instance) {
    _singletonsByDesc.remove(instance.classDesc);
  }

  /// Deletes this type registry and all contained subsystems.
  Future<void> deleteRegistry() async {
    await SubsystemInstanceRegistry.clearType(typeDesc.serviceTypeId);
  }

  /// B2: Disposes all singletons, continuing even if individual dispose()
  /// calls throw. Errors are reported via [SubsystemInstanceRegistry.onLifecycleError].
  Future<void> _clearInternal() async {
    final singletons = _singletonsByDesc.values.toList();
    for (final singleton in singletons) {
      try {
        await unregisterSingleton(singleton, preserveTypeContext: true);
      } catch (error, stackTrace) {
        // Remove it from the map even if disposal failed
        _singletonsByDesc.remove(singleton.classDesc);
        SubsystemInstanceRegistry._reportLifecycleError(error, stackTrace);
      }
    }
    _singletonsByDesc.clear();
    await typeDesc._beginDisposeTypeContext();
  }
}