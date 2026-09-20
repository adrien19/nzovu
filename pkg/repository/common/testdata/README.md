These binary fixtures were encoded with protoc 32.0 from the ChronoQueue
`chronoqueue.api.*` descriptors at commit `5c77248`, before the Nzovu namespace
migration. They cover persisted message, queue and schedule payloads. Keep these
original bytes when regenerating Nzovu APIs; the serializer test verifies that
existing data remains readable without a database rewrite.
