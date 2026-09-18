part of '../subsystem_base.dart';

/// Fluent builder to configure and register batches of subsystems.
///
/// Configuration API (chainable):
/// - [addService] / [addServices]: register or override subsystem parameters
/// - [removeClass] / [removeType]: remove specific configurations
/// - [disableByClassId] / [disableByTypeId]: mark configurations to abort at build time
///
/// Then [registerSubsystems] executes validation, construction, and initialization
/// via [SubsystemInstanceRegistry].
///
/// [TSubsystem]: common base type of subsystems configured by this factory.
class TSubsystemFactory<TSubsystem extends Subsystem> {
  final List<BuildServiceParameters> _registrations = [];

  /// Builds and initializes all registered subsystems.
  ///
  /// Clears the factory by default ([flushAfter] = true).
  ///
  /// If [atomicBatch] is `true`, a failure in any subsystem rolls back all
  /// previously built instances from this batch. When `false` (the default),
  /// only the failing instance is rolled back and successfully initialized
  /// subsystems remain active.
  Future<List<TSubsystem>> registerSubsystems({
    bool flushAfter = true,
    bool atomicBatch = false,
  }) async {
    final out = await SubsystemInstanceRegistry.buildInstances<TSubsystem>(
      _registrations.toList(growable: false),
      atomicBatch: atomicBatch,
    );

    if (flushAfter) {
      _registrations.clear();
    }

    return out;
  }

  /// Adds a subsystem registration parameter.
  ///
  /// Overrides existing registrations for the same type/class according to
  /// [SubsystemTypeDesc.supportsMultipleClasses].
  TSubsystemFactory<TSubsystem> addService(BuildServiceParameters parameter) {
    if (!parameter.isValid) {
      throw ArgumentError.value(
        parameter,
        'parameter',
        'Invalid service registration parameters',
      );
    }

    if (!parameter.classDescription.serviceType.supportsMultipleClasses) {
      removeType(parameter.classDescription.serviceType.serviceTypeId);
    } else {
      removeClass(parameter.classDescription.serviceClassId);
    }

    _registrations.add(parameter);
    return this;
  }

  /// Adds multiple subsystem registration parameters.
  TSubsystemFactory<TSubsystem> addServices(List<BuildServiceParameters> parameters) {
    for (final param in parameters) {
      addService(param);
    }
    return this;
  }

  /// Removes all registrations matching [serviceClassId].
  void removeClass(String serviceClassId) {
    _registrations.removeWhere(
      (params) => params.classDescription.serviceClassId == serviceClassId,
    );
  }

  /// Removes all registrations matching [serviceTypeId].
  void removeType(String serviceTypeId) {
    _registrations.removeWhere(
      (params) => params.classDescription.serviceType.serviceTypeId == serviceTypeId,
    );
  }

  /// Finds pending registration parameters for [serviceClassId].
  BuildServiceParameters? findServiceParametersByClassId(String serviceClassId) {
    for (final reg in _registrations) {
      if (reg.classDescription.serviceClassId == serviceClassId) {
        return reg;
      }
    }
    return null;
  }

  /// Finds all pending registration parameters for [serviceTypeId].
  List<BuildServiceParameters> findAllServiceParametersByTypeId(String serviceTypeId) {
    final results = <BuildServiceParameters>[];
    for (final reg in _registrations) {
      if (reg.classDescription.serviceType.serviceTypeId == serviceTypeId) {
        results.add(reg);
      }
    }
    return results;
  }

  /// Marks a subsystem configuration as disabled so it will not be constructed.
  TSubsystemFactory<TSubsystem> disableByClassId(String classId) {
    final serviceParams = findServiceParametersByClassId(classId);
    if (serviceParams != null) {
      serviceParams.abortBuild();
      return this;
    } else {
      throw SubsystemNotFoundException(
        'Cannot disable subsystem: classId "$classId" not found in factory registrations',
        classId: classId,
      );
    }
  }

  /// Marks all subsystems of a given type as disabled.
  TSubsystemFactory<TSubsystem> disableByTypeId(String typeId) {
    final services = findAllServiceParametersByTypeId(typeId);
    for (final param in services) {
      param.abortBuild();
    }
    return this;
  }

  /// Returns an unmodifiable snapshot of currently pending configurations.
  List<BuildServiceParameters> getRegistrations() => List.unmodifiable(_registrations);
}
