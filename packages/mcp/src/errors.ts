// The refusal every write path throws, kept free of any filesystem import so the
// hosted engine's validators can raise it too.

/** A refusal in the product's voice — the tool reports its message verbatim. */
export class VaultWriteError extends Error {}
