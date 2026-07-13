# Agent Rules

- **Git Commit and Push**: Every time code files are modified, added, or deleted, stage the changes (`git add`), commit them with a descriptive message, and push them to the remote git repository (`git push`) before completing the turn. Do not wait for the user to request a push.

- **Secure and Robust Coding**: When writing or refactoring code, always prioritize security and robustness:
  - **No Hardcoded Secrets**: Never hardcode credentials, client IDs, client secrets, database passwords, or private URLs in the source code. Always read them from `.env` or system environment variables.
  - **Input Sanitization and Validation**: Sanitize all incoming user data (GET/POST/COOKIE parameters). Prevent SQL Injection by using prepared statements (PDO/MySQLi with parameter binding) and XSS by escaping output with `htmlspecialchars` or equivalent.
  - **Secure Error Handling**: Disable display of raw errors to end users in production. Logs errors securely to the server error log instead of displaying system paths, database schemas, or raw stack traces.
  - **Secure Session Management**: Ensure session IDs are handled securely (e.g., cookie HTTP-only, secure flags where appropriate, and regenerating session IDs upon login to prevent session fixation).
