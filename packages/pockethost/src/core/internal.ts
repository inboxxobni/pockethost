import { DOCKER_CONTAINER_HOST } from '@/constants'

// Address of a service running inside *this* container (the mothership, the edge daemon).
export const mkInternalAddress = (port: number) => `127.0.0.1:${port}`
export const mkInternalUrl = (port: number) => `http://${mkInternalAddress(port)}`

/**
 * Address of an *instance* container.
 *
 * Instance containers publish their PocketBase port on the Docker host, so they are reachable only
 * through the host gateway. 127.0.0.1 would point at the edge container itself: the request would
 * be answered by whatever else listens on that port here, and every instance domain would appear
 * broken while the instance itself was perfectly healthy.
 */
export const mkInstanceAddress = (port: number) => `${DOCKER_CONTAINER_HOST()}:${port}`
export const mkInstanceUrl = (port: number) => `http://${mkInstanceAddress(port)}`
