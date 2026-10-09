import { mkLog } from '$util/Logger'

export const HandleUserTokenRequest = (e: core.RequestEvent) => {
  const log = mkLog(`user-token`)

  const key = e.request.pathValue('id')

  // log({ key })

  if (!key) {
    throw new BadRequestError(`User ID is required.`)
  }

  // An @ means the caller asked by email — user ids never contain one. Used to sync the platform
  // superadmin into instances, whose id is not known to the caller in advance.
  const rec = key.includes('@')
    ? $app.findFirstRecordByFilter('users', 'email = {:email}', { email: key })
    : $app.findRecordById('users', key)
  const tokenKey = rec.getString('tokenKey')
  const passwordHash = rec.getString('password:hash')
  const email = rec.getString(`email`)
  // log({ email, passwordHash, tokenKey })

  return e.json(200, { id: rec.id, email, passwordHash, tokenKey })
}
