part of '../subsystem_base.dart';

typedef SubsystemBuilder<TSubsystem extends Subsystem> = Future<TSubsystem?> Function(BuildServiceParameters params);

class BuildServiceParameters {
  BuildServiceParameters({
    required this.classDescription,
    this.context,
    this.shouldAbortBuild,
    this.isSynchronous = false,
    this.customBuilder,
  });

  factory BuildServiceParameters.fromClass(
    SubsystemClassDesc classDesc, {
    Map<String, Object?>? context,
  }) {
    return BuildServiceParameters(
      classDescription: classDesc,
      context: context,
    );
  }

  bool get isValid => classDescription.isValid();

  /// Whether this service initializes synchronously and should be registered first.
  /// Synchronous services are initialized before async ones to ensure dependencies are available.
  bool isSynchronous;

  /// Metadata descriptor for the subsystem class.
  SubsystemClassDesc classDescription;

  /// Optional custom builder to instantiate the subsystem.
  SubsystemBuilder? customBuilder;

  /// Arbitrary context for builders (env, config, DI container, etc.).
  Map<String, Object?>? context;

  /// Optional predicate: if true, construction and activation are skipped.
  FutureOr<bool> Function(BuildServiceParameters params)? shouldAbortBuild;

  Future<bool> get shouldBuild async {
    if (shouldAbortBuild == null) {
      return true;
    }
    return await shouldAbortBuild!(this) == false;
  }

  @override
  String toString() {
    return 'BuildServiceParameters{class: ${classDescription.serviceType.serviceTypeId}::${classDescription.serviceClassId}}';
  }

  BuildServiceParameters abortBuild() {
    shouldAbortBuild = (params) => true;
    return this;
  }

  BuildServiceParameters setSynchronous(bool value) {
    isSynchronous = value;
    return this;
  }

  BuildServiceParameters setCustomBuilder(SubsystemBuilder builder) {
    customBuilder = builder;
    return this;
  }

  BuildServiceParameters setContext(Map<String, Object?> context) {
    this.context = context;
    return this;
  }

  BuildServiceParameters setContextValue(String key, Object? value) {
    context ??= {};
    context![key] = value;
    return this;
  }

  BuildServiceParameters setShouldAbortBuild(FutureOr<bool> Function(BuildServiceParameters params) predicate) {
    shouldAbortBuild = predicate;
    return this;
  }

  BuildServiceParameters copy() {
    return BuildServiceParameters(
      classDescription: classDescription,
      context: context != null ? Map<String, Object?>.from(context!) : null,
      shouldAbortBuild: shouldAbortBuild,
      isSynchronous: isSynchronous,
      customBuilder: customBuilder,
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
      classDescription: classDescription ?? this.classDescription,
      context: context ?? (this.context != null ? Map<String, Object?>.from(this.context!) : null),
      shouldAbortBuild: shouldAbortBuild ?? this.shouldAbortBuild,
      isSynchronous: isSynchronous ?? this.isSynchronous,
      customBuilder: customBuilder ?? this.customBuilder,
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

  TClassDesc get classDesc => classDescription as TClassDesc;
}
