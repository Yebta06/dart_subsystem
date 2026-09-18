part of '../subsystem_base.dart';

/// Base class for all subsystem-related exceptions.
class SubsystemException implements Exception {
  final String message;

  const SubsystemException(this.message);

  @override
  String toString() => 'SubsystemException: $message';
}

/// Thrown when a requested subsystem or registry cannot be found.
class SubsystemNotFoundException extends SubsystemException {
  final String? typeId;
  final String? classId;

  const SubsystemNotFoundException(super.message, {this.typeId, this.classId});

  @override
  String toString() =>
      'SubsystemNotFoundException: $message (typeId: $typeId, classId: $classId)';
}

/// Thrown when an error occurs during subsystem initialization.
class SubsystemInitializationException extends SubsystemException {
  final BuildServiceParameters parameters;
  final Object cause;
  final StackTrace stackTrace;

  const SubsystemInitializationException({
    required String message,
    required this.parameters,
    required this.cause,
    required this.stackTrace,
  }) : super(message);

  @override
  String toString() =>
      'SubsystemInitializationException: $message for ${parameters.classDescription.serviceClassId}\n'
      'Cause: $cause\n$stackTrace';
}
