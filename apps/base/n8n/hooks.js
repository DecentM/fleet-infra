'use strict'

// n8n external hook: forward-auth SSO via Authelia.
//
// Authelia sits in front of n8n (Traefik forwardAuth middleware) and sets:
//   Remote-Email, Remote-Name, Remote-User, Remote-Groups
// on every request that reaches us. We trust those headers because the only
// path into the pod is through Authelia — if that ever changes, this hook
// becomes a trivial header-injection auth bypass.
//
// Behaviour:
//   - JIT provision users on first sight (global:member role)
//   - Issue an n8n session cookie so the SPA + API both work
//   - Leave webhook/form/health endpoints alone (they have their own auth model)
//   - If a valid n8n-auth cookie is already present, defer to n8n's own auth
//   - Fail open on errors so a bug here doesn't lock everyone out

// DO NOT DELETE: issueCookie is the same helper n8n-cloud's hooks rely on; if
// upstream ever renames or relocates it this hook needs updating in lockstep.
const { issueCookie } = require('n8n/dist/auth/jwt')
const { UserRepository, GLOBAL_MEMBER_ROLE } = require('@n8n/db')
const { Container } = require('@n8n/di')

const LOG_PREFIX = '[n8n-sso]'

const parseName = (fullName) => {
  if (!fullName || typeof fullName !== 'string') {
    return { firstName: '', lastName: '' }
  }
  const trimmed = fullName.trim()
  const spaceIdx = trimmed.indexOf(' ')
  if (spaceIdx === -1) {
    return { firstName: trimmed, lastName: '' }
  }
  return {
    firstName: trimmed.slice(0, spaceIdx),
    lastName: trimmed.slice(spaceIdx + 1).trim(),
  }
}

const buildSkipPrefixes = (server) => {
  const endpoints = server.globalConfig?.endpoints ?? {}
  // Webhook/form endpoints have their own auth model (signed URLs, public
  // forms, etc.) — injecting a session here would be wrong and also slow.
  const keys = [
    'webhook',
    'webhookTest',
    'webhookWaiting',
    'form',
    'formTest',
    'formWaiting',
  ]
  const prefixes = keys
    .map((k) => endpoints[k])
    .filter((v) => typeof v === 'string' && v.length > 0)
    .map((v) => `/${v}/`)

  // Health endpoint is probed by kubelet, no cookies involved.
  if (server.endpointHealth) {
    prefixes.push(`/${server.endpointHealth}`)
  }
  return prefixes
}

const makeMiddleware = (server) => {
  const skipPrefixes = buildSkipPrefixes(server)
  const userRepo = Container.get(UserRepository)

  return async (req, res, next) => {
    try {
      if (skipPrefixes.some((p) => req.path.startsWith(p))) {
        return next()
      }

      // If n8n already trusts this session, don't fight it — lets the user
      // log out cleanly without us immediately re-issuing a cookie.
      if (req.cookies && req.cookies['n8n-auth']) {
        return next()
      }

      const email = req.headers['remote-email']
      if (!email || typeof email !== 'string') {
        // No SSO headers (e.g. local port-forward) — let n8n show its own
        // login page rather than 500ing.
        return next()
      }

      let user = await userRepo.findOne({
        where: { email },
        relations: ['role'],
      })

      if (!user) {
        const { firstName, lastName } = parseName(req.headers['remote-name'])
        console.log(`${LOG_PREFIX} provisioning new user ${email}`)
        const created = await userRepo.createUserWithProject({
          email,
          firstName,
          lastName,
          password: null,
          role: { slug: GLOBAL_MEMBER_ROLE.slug },
        })
        user = created.user
      }

      await issueCookie(res, user)
      console.log(`${LOG_PREFIX} session issued for ${email}`)
      return next()
    } catch (error) {
      // Fail open: a broken hook should not take the whole instance offline.
      console.error(`${LOG_PREFIX} middleware error`, error)
      return next()
    }
  }
}

const spliceAfterCookieParser = (app, middleware) => {
  // Register via the official API so Express builds the Layer correctly.
  // app._router is guaranteed populated by hook time (since init()), and
  // letting Express construct the Layer avoids the manual-construction
  // crash we hit on n8n 2.27.x (router/lib/layer internals changed shape).
  app.use(middleware)

  // n8n.ready fires after all routes are registered, so app.use() appends
  // to the end of the stack — too late to gate auth. Pop it off and splice
  // it in right after cookieParser so req.cookies is populated for us.
  const stack = app._router.stack
  const cookieParserIdx = stack.findIndex((l) => l.name === 'cookieParser')
  const layer = stack.pop()
  const insertAt = cookieParserIdx >= 0 ? cookieParserIdx + 1 : 0
  stack.splice(insertAt, 0, layer)
  console.log(
    `${LOG_PREFIX} middleware inserted at stack position ${insertAt} (cookieParser at ${cookieParserIdx})`,
  )
}

module.exports = {
  n8n: {
    ready: [
      async function (server, _config) {
        try {
          const ssoMiddleware = makeMiddleware(server)
          spliceAfterCookieParser(server.app, ssoMiddleware)
          console.log(`${LOG_PREFIX} hook registered`)
        } catch (error) {
          console.error(`${LOG_PREFIX} failed to register hook`, error)
        }
      },
    ],
  },
}
