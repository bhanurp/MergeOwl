# Team PRs

Available from v0.2.4. This view is not included in v0.2.3 or earlier downloads.

Select **Team PRs** in either layout, or open **Settings → Team**, then choose a visible team. MergeOwl searches for open PRs **authored by team members**, including child-team members. This is different from reviews requested from a team. Each row includes the author, repository, review/readiness labels and CI inspector. The selected team belongs to the active account and survives relaunch.

The app paginates organization/team discovery and membership, then searches one member at a time. **Load more** advances through additional PR pages and members. Ordering and counts cover loaded PRs only. Membership is held stable within a pagination sequence and fetched again on refresh. Empty teams produce an empty list; membership/access errors offer a reload and do not disconnect the account.

Only repositories visible to the active account are included. Classic tokens need organization membership read access (`read:org`) to discover teams; fine-grained tokens need the corresponding organization/member and repository permissions. Authorize SSO if your organization requires it. GitHub search caps results at 1,000 PRs per author; coverage warnings identify affected authors. GitHub may require a narrower search for accounts with access to over 10,000 repositories.

Reopening the picker reuses the successfully loaded directory within the current account session. Choose **Reload teams** to discover new teams or name changes. PR refreshes still fetch current membership and PR data.

Team requests use the account's selected GitHub.com or Enterprise Server endpoint and the existing shared request budget. CI failure notifications continue to monitor your own authored PRs, independently of this view.
