#ifndef X_DIAGNOSTICS_H
#define X_DIAGNOSTICS_H
/* Temporary removable diagnostic module; no network/content capture. Call Start on main. */
#ifndef XAD_DIAGNOSTICS
#define XAD_DIAGNOSTICS 1
#endif
#if XAD_DIAGNOSTICS
void XADStart(void);
void XADBootstrap(const char *stage);
void XADLog(const char *category, const char *format, ...) __attribute__((format(printf, 2, 3)));
void XADCoreStatus(const char *status);
void XADSetSnapshotHandler(void (*handler)(void));
#else
#define XADStart() ((void)0)
#define XADBootstrap(...) ((void)0)
#define XADLog(...) ((void)0)
#define XADCoreStatus(...) ((void)0)
#define XADSetSnapshotHandler(...) ((void)0)
#endif
#endif
