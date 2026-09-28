/// <reference path="../src/types/types.d.ts" />
// Ported to the PocketBase >= 0.23 JSVM API. The original used the legacy
// `Dao` / `new Collection({ schema: [...] })` / `options` shape, which the
// current PocketBase binary cannot execute, so a fresh mothership database
// could never be built from the migration chain.
migrate(
  (app) => {
    const collection = new Collection({
      id: 'n4sshkeys9v1k2m',
      name: 'ssh_keys',
      type: 'base',
      system: false,
      fields: [
        {
          autogeneratePattern: '[a-z0-9]{15}',
          hidden: false,
          id: 'text3208210256',
          max: 15,
          min: 15,
          name: 'id',
          pattern: '^[a-z0-9]+$',
          presentable: false,
          primaryKey: true,
          required: true,
          system: true,
          type: 'text',
        },
        {
          hidden: false,
          id: 'skuser01',
          name: 'user',
          type: 'relation',
          required: true,
          presentable: false,
          system: false,
          collectionId: 'systemprofiles0',
          cascadeDelete: true,
          minSelect: null,
          maxSelect: 1,
          displayFields: ['email'],
        },
        {
          autogeneratePattern: '',
          hidden: false,
          id: 'sklabel1',
          max: 100,
          min: 1,
          name: 'label',
          pattern: '',
          presentable: true,
          required: true,
          system: false,
          type: 'text',
        },
        {
          autogeneratePattern: '',
          hidden: false,
          id: 'skpubkey',
          max: 500,
          min: 40,
          name: 'public_key',
          pattern: '^ssh-ed25519 ',
          presentable: false,
          required: true,
          system: false,
          type: 'text',
        },
        {
          autogeneratePattern: '',
          hidden: false,
          id: 'skfprint',
          max: 100,
          min: 10,
          name: 'fingerprint',
          pattern: '^SHA256:',
          presentable: false,
          required: true,
          system: false,
          type: 'text',
        },
        {
          hidden: false,
          id: 'skallins',
          name: 'all_instances',
          presentable: false,
          required: false,
          system: false,
          type: 'bool',
        },
        {
          hidden: false,
          id: 'skinstds',
          name: 'instances',
          type: 'relation',
          required: false,
          presentable: false,
          system: false,
          collectionId: 'etae8tuiaxl6xfv',
          cascadeDelete: false,
          minSelect: null,
          maxSelect: null,
          displayFields: ['subdomain'],
        },
        {
          hidden: false,
          id: 'autodate20001',
          name: 'created',
          onCreate: true,
          onUpdate: false,
          presentable: false,
          system: false,
          type: 'autodate',
        },
        {
          hidden: false,
          id: 'autodate20002',
          name: 'updated',
          onCreate: true,
          onUpdate: true,
          presentable: false,
          system: false,
          type: 'autodate',
        },
      ],
      indexes: [
        'CREATE INDEX `idx_ssh_keys_user` ON `ssh_keys` (`user`)',
        'CREATE INDEX `idx_ssh_keys_fingerprint` ON `ssh_keys` (`fingerprint`)',
        'CREATE UNIQUE INDEX `idx_ssh_keys_user_fingerprint` ON `ssh_keys` (`user`, `fingerprint`)',
      ],
      listRule: 'user = @request.auth.id',
      viewRule: 'user = @request.auth.id',
      createRule: '@request.auth.id != "" && user = @request.auth.id',
      updateRule: 'user = @request.auth.id',
      deleteRule: 'user = @request.auth.id',
    })

    app.save(collection)
  },
  (app) => {
    try {
      app.delete(app.findCollectionByNameOrId('ssh_keys'))
    } catch (e) {
      // collection already gone
    }
  }
)
