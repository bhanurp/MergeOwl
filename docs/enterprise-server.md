# GitHub Enterprise Server accounts

Available in source builds after v0.2.3. The v0.2.3 download supports GitHub.com only.

1. Open **More → Settings → Account → Add account**.
2. Choose **GitHub Enterprise Server** under **GitHub service**.
3. Enter the HTTPS web address, such as `https://github.example.com`. Use the site origin, without `/api/v3`, a repository path, login credentials, query or fragment. An explicit HTTPS port is supported.
4. Create a personal access token on that server, following your organization's repository, review, checks and organization-access policies. The **Create a GitHub token** link uses the selected server. Never paste a GitHub.com token into an Enterprise account or vice versa.
5. Enter the token and click **Connect GitHub**. **Test connection** verifies a token without saving it; use Connect or Update token to save it.
6. Select the account in the menu-bar popover. Enterprise entries include their server name so identical logins on different hosts remain distinguishable. Only one account is active.

There is no version selector or fixed version allowlist. Identity validation uses REST `/api/v3/user` and the minimal GraphQL viewer query at `/api/graphql`. PR lists and CI requests use the selected server. Features depend on APIs and token permissions available on the server: optional detail/CI failures report unavailable or partial data rather than passing checks. An unreachable server or unavailable core identity API prevents verification with an error. This does not claim every historical GHES schema supports every MergeOwl feature.

The Mac must reach the server, including any required corporate VPN, and trust its HTTPS certificate. Certificate verification is not disabled. Ask your administrator to configure the appropriate trust chain if needed. Tokens are not forwarded by authenticated redirects to another host, port or scheme; use the server's canonical address if it redirects elsewhere.

Account identity combines the canonical server origin and GitHub user ID. Profiles retain separate UUID-based credentials and local data, even if two hosts report the same user ID. Existing profiles without a server remain GitHub.com accounts. Updating an existing token cannot change its server; add another account instead. Adding Enterprise first does not discard a pending legacy GitHub.com migration or its recovery backups.

CI alert intervals, request budgets, active-account scope and manual updates remain unchanged. Administrators may configure server-specific rate limits or restrict token features. Synthetic tests cover routing and account separation; they do not establish access to a customer's private server, organization SSO, VPN or macOS notification delivery.

Endpoint reference: [GitHub Enterprise Server GraphQL calls](https://docs.github.com/en/enterprise-server@3.20/graphql/guides/forming-calls-with-graphql).
