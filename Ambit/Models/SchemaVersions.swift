import SwiftData

/// The current on-disk shape of the model graph. This is the first versioned
/// schema in the app — nothing shipped before it, so it has no migration
/// stage of its own, but it's the baseline every future version migrates from.
///
/// When a model's stored properties change:
/// 1. Bump to a new `AmbitSchemaVN`, listing every model (reuse the type
///    directly for anything unchanged, only the changed model(s) need new
///    shape).
/// 2. Add it to `AmbitMigrationPlan.schemas`.
/// 3. Add a `.lightweight(fromVersion:toVersion:)` stage to
///    `AmbitMigrationPlan.stages` for additive/removable changes (e.g. a new
///    property with an inline default). Use `.custom` instead when a
///    property is renamed, retyped, or needs a data transformation —
///    lightweight inference can't handle those.
enum AmbitSchemaV1: VersionedSchema {
    static var versionIdentifier: Schema.Version {
        Schema.Version(1, 0, 0)
    }

    static var models: [any PersistentModel.Type] {
        [Trip.self, Day.self, Stop.self]
    }
}

enum AmbitMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [AmbitSchemaV1.self]
    }

    static var stages: [MigrationStage] {
        []
    }
}
