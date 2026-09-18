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

  void doSomething() {
    assertNotDisposed();
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

class FailingConstructSubsystem extends Subsystem {
  bool disposeCalledOnFail = false;

  FailingConstructSubsystem({required super.classDesc});

  @override
  void postConstruct(BuildServiceParameters params) {
    throw StateError('Failed in postConstruct');
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
    SubsystemInstanceRegistry.onLifecycleError = null;
    await SubsystemInstanceRegistry.clearAll();
  });

  tearDown(() async {
    SubsystemInstanceRegistry.onLifecycleError = null;
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

      // Should be usable before disposal
      expect(() => instance.doSomething(), returnsNormally);

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

      // L1: assertNotDisposed throws after disposal
      expect(() => instance.doSomething(), throwsStateError);
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

    test('B1: dispose errors do not propagate and are reported to onLifecycleError; finalDispose still runs', () async {
      final errors = <Object>[];
      SubsystemInstanceRegistry.onLifecycleError = (error, stack) {
        errors.add(error);
      };

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

      // Disposal should NOT throw, but report to onLifecycleError
      await SubsystemInstanceRegistry.removeSubsystemByIds('test.type', 'failing_dispose');

      expect(instance.isDisposed, isTrue);
      expect(instance.finalDisposeCalled, isTrue);
      expect(errors.length, equals(1));
      expect(errors.first, isA<StateError>());
    });

    test('B2: clearAll continues teardown even when individual dispose throws', () async {
      final failingDesc = SubsystemClassDesc(
        serviceType: testTypeDesc,
        displayName: 'Failing',
        description: 'Fails in dispose',
        serviceClassId: 'fail_disp_1',
        defaultBuilder: (params) async => FailingDisposeSubsystem(classDesc: params.classDescription),
      );

      final okDesc = SubsystemClassDesc(
        serviceType: testTypeDesc,
        displayName: 'OK Service',
        description: 'Disposes normally',
        serviceClassId: 'ok_disp_2',
        defaultBuilder: (params) async => MockSubsystem(classDesc: params.classDescription),
      );

      final factory = TSubsystemFactory<Subsystem>();
      factory.addServices([
        BuildServiceParameters(classDescription: failingDesc),
        BuildServiceParameters(classDescription: okDesc),
      ]);

      final instances = await factory.registerSubsystems();
      final okInstance = instances.firstWhere((i) => i.classDesc.serviceClassId == 'ok_disp_2') as MockSubsystem;

      await SubsystemInstanceRegistry.clearAll();

      expect(okInstance.isDisposed, isTrue);
      expect(okInstance.lifecycleLog.contains('finalDispose'), isTrue);
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
    test('B4: initializes and disposes type context idempotently', () async {
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
      expect(trackingType.isTypeContextInitialized, isTrue);
      expect(trackingType.isTypeContextDisposed, isFalse);

      // Clear all subsystems: must dispose type context exactly ONCE
      await SubsystemInstanceRegistry.clearAll();
      expect(trackingType.disposeContextCount, equals(1));
      expect(trackingType.isTypeContextDisposed, isTrue);
      expect(trackingType.isTypeContextInitialized, isFalse);

      // Calling clear again should not double-dispose
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
      final lookup = SubsystemInstanceRegistry.findSubsystemByIds('test.type', 'failing_init');
      expect(lookup, isNull);
    });

    test('L3: disposes instance when postConstruct throws during build', () async {
      FailingConstructSubsystem? createdInstance;
      final classDesc = SubsystemClassDesc(
        serviceType: testTypeDesc,
        displayName: 'Failing Construct',
        description: 'Fails construct',
        serviceClassId: 'failing_construct',
        defaultBuilder: (params) async {
          final s = FailingConstructSubsystem(classDesc: params.classDescription);
          createdInstance = s;
          return s;
        },
      );

      final factory = TSubsystemFactory<FailingConstructSubsystem>();
      factory.addService(BuildServiceParameters(classDescription: classDesc));

      await expectLater(
        () => factory.registerSubsystems(),
        throwsA(isA<SubsystemInitializationException>()),
      );

      expect(createdInstance, isNotNull);
      expect(createdInstance!.disposeCalledOnFail, isTrue);
      expect(SubsystemInstanceRegistry.findSubsystemByIds('test.type', 'failing_construct'), isNull);
    });

    test('B3: atomicBatch: true rolls back all previous instances on failure', () async {
      final okDesc = SubsystemClassDesc(
        serviceType: testTypeDesc,
        displayName: 'OK Service',
        description: 'OK',
        serviceClassId: 'ok_service_atomic',
        defaultBuilder: (params) async => MockSubsystem(classDesc: params.classDescription),
      );

      final failDesc = SubsystemClassDesc(
        serviceType: testTypeDesc,
        displayName: 'Fail Service',
        description: 'Fails in init',
        serviceClassId: 'fail_service_atomic',
        defaultBuilder: (params) async => FailingInitSubsystem(classDesc: params.classDescription),
      );

      final factory = TSubsystemFactory();
      factory.addService(BuildServiceParameters(classDescription: okDesc, isSynchronous: true));
      factory.addService(BuildServiceParameters(classDescription: failDesc, isSynchronous: true));

      await expectLater(
        () => factory.registerSubsystems(atomicBatch: true),
        throwsA(isA<SubsystemInitializationException>()),
      );

      // With atomicBatch: true, the previously successful ok_service_atomic must be rolled back
      expect(SubsystemInstanceRegistry.findSubsystemByIds('test.type', 'ok_service_atomic'), isNull);
    });

    test('B3: atomicBatch: false leaves earlier successful instances active', () async {
      final okDesc = SubsystemClassDesc(
        serviceType: testTypeDesc,
        displayName: 'OK Service Non-Atomic',
        description: 'OK',
        serviceClassId: 'ok_service_non_atomic',
        defaultBuilder: (params) async => MockSubsystem(classDesc: params.classDescription),
      );

      final failDesc = SubsystemClassDesc(
        serviceType: testTypeDesc,
        displayName: 'Fail Service',
        description: 'Fails in init',
        serviceClassId: 'fail_service_non_atomic',
        defaultBuilder: (params) async => FailingInitSubsystem(classDesc: params.classDescription),
      );

      final factory = TSubsystemFactory();
      factory.addService(BuildServiceParameters(classDescription: okDesc, isSynchronous: true));
      factory.addService(BuildServiceParameters(classDescription: failDesc, isSynchronous: true));

      await expectLater(
        () => factory.registerSubsystems(atomicBatch: false),
        throwsA(isA<SubsystemInitializationException>()),
      );

      // With atomicBatch: false, the ok service remains in registry
      expect(SubsystemInstanceRegistry.findSubsystemByIds('test.type', 'ok_service_non_atomic'), isNotNull);
    });
  });

  group('Lookup and Factory API', () {
    test('findSubsystemByIdsChecked throws SubsystemNotFoundException when absent', () {
      expect(
        () => SubsystemInstanceRegistry.findSubsystemByIdsChecked('non_existent', 'none'),
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
      expect(SubsystemInstanceRegistry.findSubsystemByIds('test.type', 'disabled_class'), isNull);
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
