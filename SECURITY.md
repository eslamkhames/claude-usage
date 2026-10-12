# Security

ClaudeBar stores claude.ai session cookies for the accounts you add. They live in per-account WebKit data stores on your Mac and are only ever sent to claude.ai. The only other network request is the daily update check against the GitHub releases API.

## Reporting a vulnerability

Please **don't open a public issue** for security problems, such as a way for session cookies to leak or for an update to be tampered with. Instead, use GitHub's private reporting: **Security → Report a vulnerability** on this repository.

Include what you found, how to reproduce it, and the ClaudeBar and macOS versions. You'll get a reply as soon as possible, and a fix will be released before the details are made public.

Never paste your own `sessionKey` into an issue, log or screenshot.
