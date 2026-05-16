/// Root namespace placeholder for the `OfflineCache` module.
///
/// The module's public surface is the ``OfflineCacheStore`` actor and
/// the ``OfflineCacheSnapshot`` struct. This empty type exists only so
/// `import OfflineCache` is meaningful in test crash logs and so the
/// module has a stable symbol for breakpoints.
public enum OfflineCache: Sendable {}
