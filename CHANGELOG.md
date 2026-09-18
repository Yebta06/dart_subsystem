# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.0] - Initial Release

### Added
- **Subsystem Base**: Core lifecycle management (`beginConstruct`, `initialize`, `dispose`, `finalDispose`).
- **State Tracking**: Subsystems track their own state safely (`isConstructed`, `isInitialized`, `isDisposed`).
- **Registry System**: `SubsystemInstanceRegistry` and `SubsystemInstanceRegistryByTypeDesc` for safe singleton storage and type-based lookup.
- **Factory System**: Fluent `TSubsystemFactory` API to build, override, and disable subsystems conditionally before startup.
- **Fail-Safe Initialization**: Graceful rollback and error tracking (`lastFailedRegistrations`) if a subsystem throws during initialization.
- **Idempotent Teardown**: Guaranteed execution of `finalDispose` and protection against duplicate disposal calls.
- **Custom Exceptions**: Typed error handling with `SubsystemInitializationException` and `SubsystemNotFoundException`.
