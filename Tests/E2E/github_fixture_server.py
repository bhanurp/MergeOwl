"""Local-only GitHub API fixtures for the actual macOS application UI tests."""
import argparse
import json
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer


def pr(identifier, title, author="octocat"):
    return dict(id=identifier, number=int(identifier.split("_")[1]), title=title,
                url=f"https://github.com/example/repo/pull/{identifier.split('_')[1]}",
                createdAt="2026-01-01T00:00:00Z", updatedAt="2026-01-02T00:00:00Z",
                isDraft=False, author=dict(login=author), repository=dict(nameWithOwner="example/repo"))


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass  # Never log credentials or authorization headers.

    def respond(self, payload, status=200):
        body = json.dumps(payload).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def authorized(self):
        token = self.headers.get("Authorization", "").removeprefix("Bearer ")
        if token not in {"e2e-valid", "e2e-partial", "e2e-empty", "e2e-hubot", "e2e-cap"}:
            self.respond(dict(message="Bad credentials"), 401)
            return None
        return token

    def do_GET(self):
        if self.path == "/health":
            self.respond(dict(ready=True))
        elif self.path == "/user":
            token = self.authorized()
            if token:
                self.respond(dict(id=2, login="hubot") if token == "e2e-hubot" else dict(id=1, login="octocat"))
        else:
            self.respond(dict(message="Not found"), 404)

    def do_POST(self):
        token = self.authorized()
        if not token:
            return
        request = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
        query, variables = request["query"], request.get("variables", {})
        if "query Viewer" in query:
            self.respond(dict(data=dict(viewer=dict(login="hubot" if token == "e2e-hubot" else "octocat"))))
        elif "query SearchPRs" in query:
            search = variables["query"]
            if token == "e2e-hubot":
                nodes = [pr("PR_20", "Hubot private work", "hubot")]
            elif token == "e2e-empty":
                nodes = []
            elif "review-requested" in search:
                nodes = [pr("PR_3", "Review API change", "contributor"), pr("PR_4", "Already reviewed", "contributor")]
            elif "repo:" in search:
                nodes = [pr("PR_5", "Watched repository update")] if "repo:example/repo" in search.split() else []
            elif variables.get("after"):
                nodes = [pr("PR_6", "Next page PR")]
            else:
                nodes = [pr("PR_1", "Improve documentation"), pr("PR_2", "Fix token handling")]
            has_next = "author:@me" in search and not variables.get("after") and bool(nodes)
            payload = dict(data=dict(search=dict(nodes=nodes, pageInfo=dict(hasNextPage=has_next, endCursor="page2" if has_next else None))))
            if token == "e2e-cap":
                payload["data"]["search"]["issueCount"] = 1001
            if token == "e2e-partial":
                payload["errors"] = [dict(message="Resource protected by organization SAML enforcement. Authorize your token for SSO.")]
                payload["data"]["search"]["nodes"].append(None)
            self.respond(payload)
        elif "query PRDetails" in query:
            nodes = []
            for identifier in variables["ids"]:
                reviews = []
                if identifier == "PR_4":
                    reviews = [dict(author=dict(login="octocat"), state="APPROVED", submittedAt="2026-01-03T00:00:00Z")]
                nodes.append(dict(id=identifier, mergeable="MERGEABLE", mergeStateStatus="CLEAN", reviewDecision="REVIEW_REQUIRED" if identifier == "PR_4" else "APPROVED",
                                  commits=dict(nodes=[dict(commit=dict(committedDate="2026-01-02T00:00:00Z"))]),
                                  reviews=dict(nodes=reviews), closingIssuesReferences=dict(nodes=[]), timelineItems=dict(nodes=[])))
            self.respond(dict(data=dict(nodes=nodes)))
        elif "query PRCI" in query:
            identifier = variables["id"]
            head = f"head-{identifier}"
            node = dict(state="OPEN", headRefOid=head, potentialMergeCommit=None)
            if "query PRCIRevision" not in query:
                checks = [dict(__typename="CheckRun", id=f"check-{identifier}", name="Unit tests",
                               status="IN_PROGRESS" if identifier == "PR_2" else "COMPLETED",
                               conclusion="FAILURE" if identifier == "PR_1" else "SUCCESS",
                               detailsUrl="https://github.com/example/repo/actions/runs/1",
                               startedAt="2026-10-27T00:00:00Z", completedAt=None)]
                node["commits"] = dict(nodes=[dict(commit=dict(id=f"commit-{identifier}", oid=head,
                    statusCheckRollup=dict(contexts=dict(nodes=checks, pageInfo=dict(hasNextPage=False, endCursor=None)))))])
            self.respond(dict(data=dict(node=node)))
        else:
            self.respond(dict(errors=[dict(message="Unexpected fixture query")]), 400)


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--port", type=int, default=8765)
    args = parser.parse_args()
    ThreadingHTTPServer(("127.0.0.1", args.port), Handler).serve_forever()
