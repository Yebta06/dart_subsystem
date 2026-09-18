part of '../subsystem_base.dart';

/// Description of a subsystem class implementation.
///
/// Enables instantiation, lookup, and configuration overrides
/// for subsystems managed by [SubsystemInstanceRegistry].
class SubsystemClassDesc {
  SubsystemClassDesc({
    required this.serviceType,
    this.defaultBuilder,
    required this.displayName,
    required this.description,
    required this.serviceClassId,
  });

  /// The service type category this class belongs to.
  final SubsystemTypeDesc serviceType;

  final String displayName;
  final String description;

  /// Default builder function to instantiate the subsystem.
  final SubsystemBuilder<Subsystem>? defaultBuilder;

  /// Unique identifier of this implementation within its [serviceType].
  final String serviceClassId;

  bool isValid() => serviceType.isValid() && serviceClassId.isNotEmpty;

  /// Retrieves the registered instance of this subsystem.
  ///
  /// Returns `null` if no instance is currently registered.
  TSubsystem? getInstance<TSubsystem extends Subsystem>() {
    return SubsystemInstanceRegistry.findSubsystemByIds<TSubsystem>(
      serviceType.serviceTypeId,
      serviceClassId,
    );
  }

  @override
  String toString() => 'SubsystemClassDesc(${serviceType.serviceTypeId}::$serviceClassId)';
}
