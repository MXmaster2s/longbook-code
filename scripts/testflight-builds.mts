// Which TestFlight builds go to the public Early access group. The iPhone build does; the
// Mac is downloaded from longbook.app, so its builds stay in the internal group.
export const PUBLIC_BETA_PLATFORMS = ['IOS']

/** Whether a build on App Store Connect, by its pre-release version's platform, joins the public beta. */
export const joinsPublicBeta = (platform: string | undefined): boolean =>
  platform !== undefined && PUBLIC_BETA_PLATFORMS.includes(platform)
