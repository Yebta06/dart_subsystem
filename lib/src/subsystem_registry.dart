part of '../subsystem_base.dart';

/// Central registry managing subsystem singleton instances across all [SubsystemTypeDesc] categories.
///
/// Orchestrates the initialization, dependency ordering, and teardown of subsystems.
class SubsystemInstanceRegistry {
  static final Map<SubsystemTypeDesc, SubsystemInstanceRegistryByTypeDesc> _registriesByTypeDesc = {};
  static final List<BuildServiceParameters> _failedRegistrations = [];

  /// Returns an unmodifiable list of parameters that failed to build or initialize
  /// during the last [buildInstances] executions.
  static List<BuildServiceParameters> get lastFailedRegistrations =>
      List.unmodifiable(_failedRegistrations);

  /// Clears the history of failed registrations.
  static void clearFailedRegistrations() {
    _failedRegistrations.clear();
  }

  static Future<TSubsystem?> _buildInstance<TSubsystem extends Subsystem>(
    BuildServiceParameters params,
  ) async {
    final registry = await _findOrAddRegistryForTypeDesc(params.classDescription.serviceType);
    return registry._buildInstance<TSubsystem>(params);
  }

  /// Builds and initializes a batch of subsystems defined by [paramsList].
  ///
  /// Synchronous subsystems ([BuildServiceParameters.isSynchronous] = true) are
  /// initialized first sequentially to make foundational services available to
  /// asynchronous ones.
  ///
  /// If an error occurs during initialization, the failed instance is disposed,
  /// removed from the registry, recorded in [lastFailedRegistrations], and a
  /// [SubsystemInitializationException] is thrown.
  static Future<List<TSubsystem>> buildInstances<TSubsystem extends Subsystem>(
    List<BuildServiceParameters> paramsList,
  ) async {
    final instances = <TSubsystem, BuildServiceParameters>{};
    final asyncInitInstances = <TSubsystem>[];

    // Phase 1: Construction
    for (final params in paramsList) {
      if (await params.shouldBuild == false) {
        continue;
      }

      TSubsystem? instance;
      try {
        instance = await _buildInstance<TSubsystem>(params);
      } catch (error, stackTrace) {
        _failedRegistrations.add(params);
        throw SubsystemInitializationException(
          message: 'Failed to construct subsystem',
          parameters: params,
          cause: error,
          stackTrace: stackTrace,
        );
      }

      if (instance != null) {
        instances[instance] = params;

        if (params.isSynchronous) {
          try {
            await instance._initSubsystem(params);
          } catch (error, stackTrace) {
            _failedRegistrations.add(params);
            await _cleanupFailedInstance(instance, params);
            throw SubsystemInitializationException(
              message: 'Failed during synchronous initialization',
              parameters: params,
              cause: error,
              stackTrace: stackTrace,
            );
          }
        } else {
          asyncInitInstances.add(instance);
        }
      }
    }

    // Phase 2: Asynchronous initialization
    if (asyncInitInstances.isNotEmpty) {
      final results = await Future.wait(
        asyncInitInstances.map((instance) async {
          final params = instances[instance]!;
          try {
            await instance._initSubsystem(params);
            return null;
          } catch (error, stackTrace) {
            return _InitError(instance: instance, params: params, error: error, stackTrace: stackTrace);
          }
        }),
      );

      final firstError = results.whereType<_InitError>().firstOrNull;
      if (firstError != null) {
        _failedRegistrations.add(firstError.params);
        await _cleanupFailedInstance(firstError.instance, firstError.params);
        throw SubsystemInitializationException(
          message: 'Failed during asynchronous initialization',
          parameters: firstError.params,
          cause: firstError.error,
          stackTrace: firstError.stackTrace,
        );
      }
    }

    // Phase 3: Post-initialization
    for (final entry in instances.entries) {
      final instance = entry.key;
      final params = entry.value;

      try {
        await instance._postInitSubsystem(params);
      } catch (error, stackTrace) {
        _failedRegistrations.add(params);
        await _cleanupFailedInstance(instance, params);
        throw SubsystemInitializationException(
          message: 'Failed during post-initialization',
          parameters: params,
          cause: error,
          stackTrace: stackTrace,
        );
      }
    }

    return instances.keys.toList();
  }

  static Future<void> _cleanupFailedInstance(
    Subsystem instance,
    BuildServiceParameters params,
  ) async {
    final registry = findRegistryForTypeIdSync(params.classDescription.serviceType.serviceTypeId);
    if (registry != null) {
      registry._removeInstanceSilently(instance);
      try {
        await instance._disposeSubsystem();
      } catch (_) {
        // Ignore secondary teardown errors to prioritize reporting the primary initialization failure
      }
    }
  }

  /// Synchronously finds the registry associated with [typeId].
  static SubsystemInstanceRegistryByTypeDesc? findRegistryForTypeIdSync(String typeId) {
    for (final registry in _registriesByTypeDesc.values) {
      if (registry.typeDesc.serviceTypeId == typeId) {
        return registry;
      }
    }
    return null;
  }

  /// Asynchronously finds the registry associated with [typeId].
  static Future<SubsystemInstanceRegistryByTypeDesc?> findRegistryForTypeId(String typeId) async {
    return findRegistryForTypeIdSync(typeId);
  }

  static Future<SubsystemInstanceRegistryByTypeDesc> _findOrAddRegistryForTypeDesc(
    SubsystemTypeDesc typeDesc,
  ) async {
    if (!typeDesc.isValid()) {
      throw ArgumentError.value(typeDesc, 'typeDesc', 'Invalid SubsystemTypeDesc provided');
    }

    final existing = findRegistryForTypeIdSync(typeDesc.serviceTypeId);
    if (existing != null) {
      return existing;
    }

    final newRegistry = SubsystemInstanceRegistryByTypeDesc(typeDesc: typeDesc);
    await newRegistry.typeDesc._beginInitializeTypeContext();

    // Re-check after async gap in case another task registered it
    final existingAfterGap = findRegistryForTypeIdSync(typeDesc.serviceTypeId);
    if (existingAfterGap != null) {
      await newRegistry.typeDesc._beginDisposeTypeContext();
      return existingAfterGap;
    }

    _registriesByTypeDesc[typeDesc] = newRegistry;
    return newRegistry;
  }

  /// Finds a subsystem singleton by its type and class IDs.
  static Future<TSubsystem?> findSubsystemByIds<TSubsystem extends Subsystem>(
    String typeId,
    String classId,
  ) async {
    return findSubsystemByIdsSync<TSubsystem>(typeId, classId);
  }

  /// Synchronously finds a subsystem singleton by its type and class IDs.
  static TSubsystem? findSubsystemByIdsSync<TSubsystem extends Subsystem>(
    String typeId,
    String classId,
  ) {
    final registry = findRegistryForTypeIdSync(typeId);
    if (registry != null) {
      final singleton = registry.findByClassIdSync(classId);
      if (singleton != null && singleton is! TSubsystem) {
        throw TypeError();
      }
      return singleton as TSubsystem?;
    }
    return null;
  }

  /// Finds a subsystem singleton or throws [SubsystemNotFoundException] if absent.
  static Future<TSubsystem> findSubsystemByIdsChecked<TSubsystem extends Subsystem>(
    String typeId,
    String classId,
  ) async {
    final registry = findRegistryForTypeIdSync(typeId);
    if (registry == null) {
      throw SubsystemNotFoundException(
        'No registry found for typeId $typeId',
        typeId: typeId,
        classId: classId,
      );
    }

    final singleton = registry.findByClassIdSync(classId);
    if (singleton == null) {
      throw SubsystemNotFoundException(
        'No singleton found for classId $classId in typeId $typeId',
        typeId: typeId,
        classId: classId,
      );
    }

    if (singleton is! TSubsystem) {
      throw TypeError();
    }
    return singleton;
  }

  /// Unregisters and disposes a subsystem by its type and class IDs.
  static Future<void> removeSubsystemByIds(String typeId, String classId) async {
    final registry = findRegistryForTypeIdSync(typeId);
    if (registry != null) {
      await registry.unregisterSingletonByClassId(classId);
    }
  }

  /// Clears all subsystems of a given type and disposes its type context.
  static Future<void> clearType(String typeId) async {
    final registry = findRegistryForTypeIdSync(typeId);
    if (registry != null) {
      await registry._clearInternal();
      _registriesByTypeDesc.remove(registry.typeDesc);
    }
  }

  /// Clears all registered subsystems across all types and resets registries.
  static Future<void> clearAll() async {
    final registries = _registriesByTypeDesc.values.toList();
    for (final registry in registries) {
      await registry._clearInternal();
    }
    _registriesByTypeDesc.clear();
    clearFailedRegistrations();
  }
}

class _InitError {
  final Subsystem instance;
  final BuildServiceParameters params;
  final Object error;
  final StackTrace stackTrace;

  _InitError({
    required this.instance,
    required this.params,
    required this.error,
    required this.stackTrace,
  });
}