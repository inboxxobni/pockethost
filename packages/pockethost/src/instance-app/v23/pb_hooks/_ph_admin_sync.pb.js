onBootstrap((e) => {
  e.next()
  const { mkLog } = /** @type {Lib} */ (require(`${__hooks}/_ph_lib.js`))

  const log = mkLog(`admin-sync`)

  /**
   * ADMIN_SYNC carries one admin (an object) or several (an array): the instance owner, plus the platform superadmin,
   * who must be able to administer any instance. Both shapes are accepted so an older control plane keeps working.
   *
   * @type {{ id: string; email: string; tokenKey: string; passwordHash: string }[]}
   */
  const admins = (() => {
    try {
      const parsed = JSON.parse(process.env.ADMIN_SYNC)
      const list = Array.isArray(parsed) ? parsed : [parsed]
      return list.filter((a) => a && a.email)
    } catch (err) {
      return []
    }
  })()

  if (!admins.length) {
    log(`Not active - skipped`)
    return
  }

  const query = `
    insert or replace into _superusers (id, email, tokenKey, password) values ({:id}, {:email}, {:tokenKey}, {:passwordHash})
      `

  for (const { id, email, tokenKey, passwordHash } of admins) {
    if (!id) {
      log(`Skipping ${email} - no id`)
      continue
    }
    try {
      e.app.db().newQuery(query).bind({ id, email, tokenKey, passwordHash }).execute()
      log(`Success updating admin credentials ${email}`)
    } catch (err) {
      log(`Failed to update admin credentials ${email}: ${err}`)
    }
  }
})
