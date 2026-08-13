# Agent Rules

- **Git Commit and Push**: Every time code files are modified, added, or deleted, stage the changes (`git add`), commit them with a descriptive message, and push them to the remote git repository (`git push`) before completing the turn. Do not wait for the user to request a push.

- **Secure and Robust Coding**: When writing or refactoring code, always prioritize security and robustness:
  - **No Hardcoded Secrets**: Never hardcode credentials, client IDs, client secrets, database passwords, or private URLs in the source code. Always read them from `.env` or system environment variables.
  - **Input Sanitization and Validation**: Sanitize all incoming user data (GET/POST/COOKIE parameters). Prevent SQL Injection by using prepared statements (PDO/MySQLi with parameter binding) and XSS by escaping output with `htmlspecialchars` or equivalent.
  - **Secure Error Handling**: Disable display of raw errors to end users in production. Logs errors securely to the server error log instead of displaying system paths, database schemas, or raw stack traces.
  - **Secure Session Management**: Ensure session IDs are handled securely (e.g., cookie HTTP-only, secure flags where appropriate, and regenerating session IDs upon login to prevent session fixation).

- **Code Commenting in Thai**: ทุกครั้งที่มีการเขียนหรือแก้ไขโค้ด จะต้องเขียน Comment เพื่ออธิบายการทำงานของ Source code ตัวแปร และ Logic ทุกครั้งเป็นภาษาไทย (Always write code comments in Thai to explain the source code, variables, and logic).

- **Database Changes**: Every time there is a database table modification or addition, implement an automatic migration system or auto-create logic (like 'CREATE TABLE IF NOT EXISTS' or ALTER scripts) inside the application code instead of just relying on manual SQL scripts.

- **CLI Parameters**: Every time a new command line parameter or flag is added to the application, you MUST immediately update the '--help' (or equivalent) documentation output to accurately reflect the change and usage.

- **Package Deployment**: Whenever the user explicitly instructs to "push package" or similar, ONLY push the pre-compiled deployment packages (binaries, .env.example, templates, service files) and NOT the source code (`.pas` files) to the repository `https://github.com/thaidelphi/internet-authen`.
  - **Process**: Copy the necessary package files into `/var/www/api/package_send`, then `git add`, `git commit`, and `git push` from inside that directory.
