part of '../subsystem_base.dart';

typedef SubsystemBuilder<TSubsystem extends Subsystem> = Future<TSubsystem?> Function(BuildServiceParameters params);

/// Configuration parameters for building and registering a subsystem instance.
///
/// Use the fluent setter methods ([setSynchronous], [setCustomBuilder], etc.)
/// to configure parameters after construction.
class BuildServiceParameters {
  BuildServiceParameters({
    required SubsystemClassDesc classDescription,
    Map<String, Object?>? context,
    FutureOr<bool> Function(BuildServiceParameters params)? shouldAbortBuild,
    bool isSynchronous = false,
    SubsystemBuilder? customBuilder,
  })  : _classDescription = classDescription,
        _context = context,
        _shouldAbortBuild = shouldAbortBuild,
        _isSynchronous = isSynchronous,
        _customBuilder = customBuilder;

  factory BuildServiceParameters.fromClass(
    SubsystemClassDesc classDesc, {
    Map<String, Object?>? context,
  }) {
    return BuildServiceParameters(
      classDescription: classDesc,
      context: context,
    );
  }

  bool get isValid => _classDescription.isValid();

  SubsystemClassDesc _classDescription;
  bool _isSynchronous;
  SubsystemBuilder? _customBuilder;
  Map<String, Object?>? _context;
  FutureOr<bool> Function(BuildServiceParameters params)? _shouldAbortBuild;

  /// Metadata descriptor for the subsystem class.
  SubsystemClassDesc get classDescription => _classDescription;

  /// Whether this service initializes synchronously and should be registered first.
  /// Synchronous services are initialized before async ones to ensure dependencies are available.
  bool get isSynchronous => _isSynchronous;

  /// Optional custom builder to instantiate the subsystem.
  SubsystemBuilder? get customBuilder => _customBuilder;

  /// Arbitrary context for builders (env, config, DI container, etc.).
  Map<String, Object?>? get context => _context;

  /// Optional predicate: if returns true, construction and activation are skipped.
  FutureOr<bool> Function(BuildServiceParameters params)? get shouldAbortBuild => _shouldAbortBuild;

  Future<bool> get shouldBuild async {
    if (_shouldAbortBuild == null) {
      return true;
    }
    return await _shouldAbortBuild!(this) == false;
  }

  @override
  String toString() {
    return 'BuildServiceParameters{class: ${_classDescription.serviceType.serviceTypeId}::${_classDescription.serviceClassId}}';
  }

  BuildServiceParameters abortBuild() {
    _shouldAbortBuild = (params) => true;
    return this;
  }

  BuildServiceParameters setSynchronous(bool value) {
    _isSynchronous = value;
    return this;
  }

  BuildServiceParameters setCustomBuilder(SubsystemBuilder builder) {
    _customBuilder = builder;
    return this;
  }

  BuildServiceParameters setContext(Map<String, Object?> context) {
    _context = context;
    return this;
  }

  BuildServiceParameters setContextValue(String key, Object? value) {
    _context ??= {};
    _context![key] = value;
    return this;
  }

  BuildServiceParameters setShouldAbortBuild(FutureOr<bool> Function(BuildServiceParameters params) predicate) {
    _shouldAbortBuild = predicate;
    return this;
  }

  BuildServiceParameters copy() {
    return BuildServiceParameters(
      classDescription: _classDescription,
      context: _context != null ? Map<String, Object?>.from(_context!) : null,
      shouldAbortBuild: _shouldAbortBuild,
      isSynchronous: _isSynchronous,
      customBuilder: _customBuilder,
    );
  }

  BuildServiceParameters copyWith({
    SubsystemClassDesc? classDescription,
    Map<String, Object?>? context,
    FutureOr<bool> Function(BuildServiceParameters params)? shouldAbortBuild,
    bool? isSynchronous,
    SubsystemBuilder? customBuilder,
  }) {
    return BuildServiceParameters(
      classDescription: classDescription ?? _classDescription,
      context: context ?? (_context != null ? Map<String, Object?>.from(_context!) : null),
      shouldAbortBuild: shouldAbortBuild ?? _shouldAbortBuild,
      isSynchronous: isSynchronous ?? _isSynchronous,
      customBuilder: customBuilder ?? _customBuilder,
    );
  }
}

class TBuildServiceParameters<TClassDesc extends SubsystemClassDesc> extends BuildServiceParameters {
  TBuildServiceParameters({
    required TClassDesc classDesc,
    super.context,
    super.shouldAbortBuild,
    super.isSynchronous = false,
    super.customBuilder,
  }) : super(classDescription: classDesc);

  TClassDesc get classDesc => _classDescription as TClassDesc;
}
