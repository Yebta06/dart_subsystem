import 'package:dart_subsystem/dart_subsystem.dart';
import 'package:test/test.dart';

// Test Subsystem definitions
final testTypeDesc = SubsystemTypeDesc(
  displayName: 'Test Subsystem Type',
  description: 'Type descriptor for testing',
  serviceTypeId: 'test.type',
  supportsMultipleClasses: true,
);

final singleClassTypeDesc = SubsystemTypeDesc(
  displayName: 'Single Class Type',
  description: 'Type descriptor supporting only single class',
  serviceTypeId: 'test.single_type',
  supportsMultipleClasses: false,
);

class MockSubsystem extends Subsystem {
  final List<String> lifecycleLog = [];

  MockSubsystem({required super.classDesc});

  @override
  void beginConstruct(BuildServiceParameters params) {
    lifecycleLog.add('beginConstruct');
  }

  @override
  void postConstruct(BuildServiceParameters params) {
    lifecycleLog.add('postConstruct');
  }

  @override
  Future<void> initialize(BuildServiceParameters params) async {
    lifecycleLog.add('initialize');
  }

  @override
  Future<void> postInitialize(BuildServiceParameters params) async {
    lifecycleLog.add('postInitialize');
  }

  @override
  Future<void> dispose() async {
    lifecycleLog.add('dispose');
  }

  @override
  Future<void> finalDispose() async {
    lifecycleLog.add('finalDispose');
  }
}

class FailingDisposeSubsystem extends Subsystem {
  bool finalDisposeCalled = false;

  FailingDisposeSubsystem({required super.classDesc});

  @override
  Future<void> dispose() async {
    throw StateError('Intentional error in dispose');
  }

  @override
  Future<void> finalDispose() async {
    finalDisposeCalled = true;
  }
}

class FailingInitSubsystem extends Subsystem {
  bool disposeCalledOnFail = false;

  FailingInitSubsystem({required super.classDesc});

  @override
  Future<void> initialize(BuildServiceParameters params) async {
    throw StateError('Failed in initialize');
  }

  @override
  Future<void> dispose() async {
    disposeCalledOnFail = true;
  }
}

class TrackingTypeDesc extends SubsystemTypeDesc {
  int initContextCount = 0;
  int disposeContextCount = 0;

  TrackingTypeDesc({
    required super.displayName,
    required super.description,
    required super.serviceTypeId,
    super.supportsMultipleClasses = true,
  });

  @override
  Future<void> initializeTypeContext() async {
    initContextCount++;
  }

  @override
  Future<void> disposeTypeContext() async {
    disposeContextCount++;
  }
}

void main() {
  setUp(() async {
    await SubsystemInstanceRegistry.clearAll();
  });

  tearDown(() async {
    await SubsystemInstanceRegistry.clearAll();
  });

  group('Subsystem Lifecycle Progression', () {
    test('executes all hooks in the correct order and updates flags', () async {
      final classDesc = SubsystemClassDesc(
        serviceType: testTypeDesc,
        displayName: 'Test Service',
        description: 'Test Description',
        serviceClassId: 'service_a',
        defaultBuilder: (params) async => MockSubsystem(classDesc: params.classDescription),
      );

      final factory = TSubsystemFactory<MockSubsystem>();
      factory.addService(BuildServiceParameters(classDescription: classDesc));

      final instances = await factory.registerSubsystems();
      expect(instances.length, equals(1));

      final instance = instances.first;
      expect(instance.isConstructed, isTrue);
      expect(instance.isInitialized, isTrue);
      expect(instance.isDisposed, isFalse);

      expect(instance.lifecycleLog, equals([
        'beginConstruct',
        'postConstruct',
        'initialize',
        'postInitialize',
      ]));

      // Teardown
      await SubsystemInstanceRegistry.removeSubsystemByIds('test.type', 'service_a');
      expect(instance.isDisposed, isTrue);
      expect(instance.lifecycleLog, equals([
        'beginConstruct',
        'postConstruct',
        'initialize',
        'postInitialize',
        'dispose',
        'finalDispose',
      ]));
    });

    test('disposal is idempotent and safe against repeated calls', () async {
      final classDesc = SubsystemClassDesc(
        serviceType: testTypeDesc,
        displayName: 'Test Service',
        description: 'Test Description',
        serviceClassId: 'service_idempotent',
        defaultBuilder: (params) async => MockSubsystem(classDesc: params.classDescription),
      );

      final factory = TSubsystemFactory<MockSubsystem>();
      factory.addService(BuildServiceParameters(classDescription: classDesc));

      final instances = await factory.registerSubsystems();
      final instance = instances.first;

      await SubsystemInstanceRegistry.removeSubsystemByIds('test.type', 'service_idempotent');
      expect(instance.isDisposed, isTrue);
      final logLengthAfterFirstDispose = instance.lifecycleLog.length;

      // Second unregister attempt on same instance
      await SubsystemInstanceRegistry.removeSubsystemByIds('test.type', 'service_idempotent');
      expect(instance.lifecycleLog.length, equals(logLengthAfterFirstDispose));
    });

    test('finalDispose is guaranteed even when dispose throws', () async {
      final classDesc = SubsystemClassDesc(
        serviceType: testTypeDesc,
        displayName: 'Failing Dispose Service',
        description: 'Test Description',
        serviceClassId: 'failing_dispose',
        defaultBuilder: (params) async => FailingDisposeSubsystem(classDesc: params.classDescription),
      );

      final factory = TSubsystemFactory<FailingDisposeSubsystem>();
      factory.addService(BuildServiceParameters(classDescription: classDesc));

      final instances = await factory.registerSubsystems();
      final instance = instances.first;

      expect(instance.isDisposed, isFalse);
      expect(instance.finalDisposeCalled, isFalse);

      // Disposal should catch/throw but still execute finalDispose
      await expectLater(
        () => SubsystemInstanceRegistry.removeSubsystemByIds('test.type', 'failing_dispose'),
        throwsStateError,
      );

      expect(instance.isDisposed, isTrue);
      expect(instance.finalDisposeCalled, isTrue);
    });
  });

  group('Synchronous vs Asynchronous initialization order', () {
    test('synchronous subsystems initialize before async subsystems', () async {
      final executionSteps = <String>[];

      final syncClassDesc = SubsystemClassDesc(
        serviceType: testTypeDesc,
        displayName: 'Sync Service',
        description: 'Sync',
        serviceClassId: 'sync_service',
        defaultBuilder: (params) async => _StepLoggingSubsystem(
          classDesc: params.classDescription,
          stepName: 'sync',
          steps: executionSteps,
        ),
      );

      final asyncClassDesc = SubsystemClassDesc(
        serviceType: testTypeDesc,
        displayName: 'Async Service',
        description: 'Async',
        serviceClassId: 'async_service',
        defaultBuilder: (params) async => _StepLoggingSubsystem(
          classDesc: params.classDescription,
          stepName: 'async',
          steps: executionSteps,
        ),
      );

      final factory = TSubsystemFactory();
      factory.addService(BuildServiceParameters(classDescription: asyncClassDesc, isSynchronous: false));
      factory.addService(BuildServiceParameters(classDescription: syncClassDesc, isSynchronous: true));

      await factory.registerSubsystems();

      // Sync initialize must complete before async initialize
      final syncInitIndex = executionSteps.indexOf('sync:initialize');
      final asyncInitIndex = executionSteps.indexOf('async:initialize');
      expect(syncInitIndex, lessThan(asyncInitIndex));
    });
  });

  group('Type Context Lifecycle', () {
    test('initializes and disposes type context exactly once without double disposal', () async {
      final trackingType = TrackingTypeDesc(
        displayName: 'Tracking Type',
        description: 'Tracks context lifecycle',
        serviceTypeId: 'test.tracking',
      );

      final classDescA = SubsystemClassDesc(
        serviceType: trackingType,
        displayName: 'Service A',
        description: 'A',
        serviceClassId: 'class_a',
        defaultBuilder: (params) async => MockSubsystem(classDesc: params.classDescription),
      );

      final classDescB = SubsystemClassDesc(
        serviceType: trackingType,
        displayName: 'Service B',
        description: 'B',
        serviceClassId: 'class_b',
        defaultBuilder: (params) async => MockSubsystem(classDesc: params.classDescription),
      );

      final factory = TSubsystemFactory<MockSubsystem>();
      factory.addServices([
        BuildServiceParameters(classDescription: classDescA),
        BuildServiceParameters(classDescription: classDescB),
      ]);

      await factory.registerSubsystems();

      expect(trackingType.initContextCount, equals(1));
      expect(trackingType.disposeContextCount, equals(0));

      // Clear all subsystems: must dispose type context exactly ONCE
      await SubsystemInstanceRegistry.clearAll();
      expect(trackingType.disposeContextCount, equals(1));
    });
  });

  group('Failure and Error Resilience', () {
    test('cleans up registry, tracks failed params, and throws on init failure', () async {
      final classDesc = SubsystemClassDesc(
        serviceType: testTypeDesc,
        displayName: 'Failing Init Service',
        description: 'Fails',
        serviceClassId: 'failing_init',
        defaultBuilder: (params) async => FailingInitSubsystem(classDesc: params.classDescription),
      );

      final params = BuildServiceParameters(classDescription: classDesc);
      final factory = TSubsystemFactory<FailingInitSubsystem>();
      factory.addService(params);

      await expectLater(
        () => factory.registerSubsystems(),
        throwsA(isA<SubsystemInitializationException>()),
      );

      // Verify failure tracking
      expect(SubsystemInstanceRegistry.lastFailedRegistrations.contains(params), isTrue);

      // Verify the zombie instance was NOT left in the registry
      final lookup = SubsystemInstanceRegistry.findSubsystemByIdsSync('test.type', 'failing_init');
      expect(lookup, isNull);
    });
  });

  group('Lookup and Factory API', () {
    test('findSubsystemByIdsChecked throws SubsystemNotFoundException when absent', () async {
      expect(
        () async => await SubsystemInstanceRegistry.findSubsystemByIdsChecked('non_existent', 'none'),
        throwsA(isA<SubsystemNotFoundException>()),
      );
    });

    test('supportsMultipleClasses = false overrides previous class registration', () async {
      final classDesc1 = SubsystemClassDesc(
        serviceType: singleClassTypeDesc,
        displayName: 'Impl 1',
        description: '1',
        serviceClassId: 'impl_1',
        defaultBuilder: (params) async => MockSubsystem(classDesc: params.classDescription),
      );

      final classDesc2 = SubsystemClassDesc(
        serviceType: singleClassTypeDesc,
        displayName: 'Impl 2',
        description: '2',
        serviceClassId: 'impl_2',
        defaultBuilder: (params) async => MockSubsystem(classDesc: params.classDescription),
      );

      final factory = TSubsystemFactory<MockSubsystem>();
      factory.addService(BuildServiceParameters(classDescription: classDesc1));
      factory.addService(BuildServiceParameters(classDescription: classDesc2));

      expect(factory.getRegistrations().length, equals(1));
      expect(factory.getRegistrations().first.classDescription.serviceClassId, equals('impl_2'));
    });

    test('disableByClassId skips construction at build time', () async {
      final classDesc = SubsystemClassDesc(
        serviceType: testTypeDesc,
        displayName: 'Disabled Service',
        description: 'Disabled',
        serviceClassId: 'disabled_class',
        defaultBuilder: (params) async => MockSubsystem(classDesc: params.classDescription),
      );

      final factory = TSubsystemFactory<MockSubsystem>();
      factory.addService(BuildServiceParameters(classDescription: classDesc));
      factory.disableByClassId('disabled_class');

      final instances = await factory.registerSubsystems();
      expect(instances, isEmpty);
      expect(SubsystemInstanceRegistry.findSubsystemByIdsSync('test.type', 'disabled_class'), isNull);
    });
  });
}

class _StepLoggingSubsystem extends Subsystem {
  final String stepName;
  final List<String> steps;

  _StepLoggingSubsystem({
    required super.classDesc,
    required this.stepName,
    required this.steps,
  });

  @override
  Future<void> initialize(BuildServiceParameters params) async {
    steps.add('$stepName:initialize');
  }

  @override
  Future<void> postInitialize(BuildServiceParameters params) async {
    steps.add('$stepName:postInitialize');
  }
}
