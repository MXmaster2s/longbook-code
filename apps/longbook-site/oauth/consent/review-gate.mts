// Password sign-in for the App Review account only: its password is the code review:account
// keeps in the keychain. Any other address is refused before a request leaves the browser.
// Must match REVIEW_EMAIL in AuthClient.swift and EMAIL in scripts/review-account.mts.
export const APP_REVIEW_ADDRESS = 'appreview@longbook.app'

/** Whether the password form may sign this address in: the App Review address, any case, nothing else. */
export const mayUsePassword = (email: string): boolean => email.trim().toLowerCase() === APP_REVIEW_ADDRESS
