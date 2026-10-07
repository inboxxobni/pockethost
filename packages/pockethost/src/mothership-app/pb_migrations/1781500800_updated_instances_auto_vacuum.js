/// <reference path="../pb_data/types.d.ts" />
// Ported to the PocketBase >= 0.23 JSVM API. The original used the legacy
// `Dao` / `SchemaField` / `collection.schema` shape, which the current
// PocketBase binary cannot execute.
migrate(
  (app) => {
    const collection = app.findCollectionByNameOrId('etae8tuiaxl6xfv')

    collection.fields.add(
      new BoolField({
        id: 'k8m2vacu',
        name: 'autoVacuum',
        required: false,
        presentable: false,
        system: false,
        hidden: false,
      })
    )

    app.save(collection)

    app.db().newQuery('UPDATE instances SET autoVacuum = {:v}').bind({ v: true }).execute()
  },
  (app) => {
    const collection = app.findCollectionByNameOrId('etae8tuiaxl6xfv')

    collection.fields.removeById('k8m2vacu')

    app.save(collection)
  }
)
