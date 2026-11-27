#ifndef MAGQLITE_H
#define MAGQLITE_H

#ifdef __cplusplus
extern "C" {
#endif

typedef struct MagqliteHandle MagqliteHandle;
typedef struct MagqliteStmt MagqliteStmt;

/* Open a MagQLite database file (or ":memory:") with default config. */
MagqliteHandle* magqlite_open(const char* path);

/* Open with explicit JSON DbConfig (durability, encryption_key, auth_secret, etc.). */
MagqliteHandle* magqlite_open_with_config(const char* path, const char* config_json);

/* Close and free a MagQLite database handle. */
void magqlite_close(MagqliteHandle* handle);

/* Execute SQL and return a heap-allocated JSON string. Free with magqlite_free_string(). */
char* magqlite_exec_json(MagqliteHandle* handle, const char* sql);

/* Execute SQL under a host-locked RLS identity (raw SQL SET IDENTITY is rejected). */
char* magqlite_exec_as_identity_json(MagqliteHandle* handle, const char* identity, const char* sql);

/* Execute SQL under a host-locked RBAC role (raw SQL SET ROLE is rejected). */
char* magqlite_exec_as_role_json(MagqliteHandle* handle, const char* role, const char* sql);

/* Execute SQL under both a host-locked RLS identity and RBAC role. */
char* magqlite_exec_as_context_json(MagqliteHandle* handle, const char* identity, const char* role, const char* sql);

/* Pre-parse a SQL statement with ? / $1 placeholders. Free with magqlite_free_stmt(). */
MagqliteStmt* magqlite_prepare(MagqliteHandle* handle, const char* sql);

/* Execute a prepared statement bound with one 64-bit integer parameter. */
char* magqlite_exec_prepared_i64(MagqliteHandle* handle, MagqliteStmt* stmt, long long param1);

/* Execute a prepared statement bound with a JSON array of typed parameters. */
char* magqlite_exec_params_json(MagqliteHandle* handle, MagqliteStmt* stmt, const char* params_json);

/* Free a prepared statement. */
void magqlite_free_stmt(MagqliteStmt* stmt);

/* Return JSON array of modules compiled into this library. Free with magqlite_free_string(). */
char* magqlite_modules_json(void);

/* Free a string returned by MagQLite. */
void magqlite_free_string(char* ptr);

#ifdef __cplusplus
}
#endif

#endif /* MAGQLITE_H */
