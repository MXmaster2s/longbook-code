// The device-build reset: device:install alone passes the setting that compiles it in, the
// app answers longbook://dev/first-use with it, and the release scripts refuse an archive
// whose binary carries its marker. See apps/longbook/Sources/FirstUseReset.swift.
import { existsSync, readFileSync } from 'node:fs'
import { join } from 'node:path'

/** Passed to xcodebuild by device-install.mts only. project.yml leaves it empty. */
export const DEVICE_BUILD_SETTING = 'LONGBOOK_DEVICE_BUILD=DEVICE_BUILD'
export const FIRST_USE_URL = 'longbook://dev/first-use'
/** FirstUseReset.marker: long enough that Swift keeps it as text in the binary. */
export const RESET_MARKER = 'longbook device build: first-use reset'

/** The main executable of a built longbook.app, Mac or iPhone. */
export const appExecutable = (app: string): string =>
  existsSync(join(app, 'Contents/MacOS')) ? join(app, 'Contents/MacOS/longbook') : join(app, 'longbook')

/** Whether a built app answers the reset link. A missing file carries nothing. */
export function carriesFirstUseReset(app: string): boolean {
  const file = appExecutable(app)
  return existsSync(file) && readFileSync(file).includes(RESET_MARKER)
}
