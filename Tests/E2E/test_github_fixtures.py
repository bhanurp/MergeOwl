import json
import threading
import unittest
from http.server import ThreadingHTTPServer
from urllib.request import Request, urlopen

from github_fixture_server import Handler


class GitHubFixtureTests(unittest.TestCase):
    def test_second_account_has_distinct_identity_and_pull_requests(self):
        server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        worker = threading.Thread(target=server.serve_forever, daemon=True)
        worker.start()
        try:
            request = Request(f"http://127.0.0.1:{server.server_port}/user", headers={"Authorization": "Bearer e2e-hubot"})
            with urlopen(request) as response:
                self.assertEqual(json.load(response), {"id": 2, "login": "hubot"})
            body = json.dumps({"query": "query SearchPRs", "variables": {"query": "review-requested:@me"}}).encode()
            request = Request(f"http://127.0.0.1:{server.server_port}/graphql", data=body, headers={"Authorization": "Bearer e2e-hubot"})
            with urlopen(request) as response:
                self.assertEqual(json.load(response)["data"]["search"]["nodes"][0]["title"], "Hubot private work")
        finally:
            server.shutdown(); server.server_close(); worker.join()

    def test_watched_search_requires_the_expected_repository(self):
        server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        worker = threading.Thread(target=server.serve_forever, daemon=True)
        worker.start()
        try:
            for repository, expected_count in [("example/repo", 1), ("other/repo", 0), ("example/repo-extra", 0)]:
                with self.subTest(repository=repository):
                    body = json.dumps({"query": "query SearchPRs", "variables": {"query": f"is:pr is:open repo:{repository}"}}).encode()
                    request = Request(f"http://127.0.0.1:{server.server_port}/graphql", data=body,
                                      headers={"Authorization": "Bearer e2e-valid", "Content-Type": "application/json"})
                    with urlopen(request) as response:
                        nodes = json.load(response)["data"]["search"]["nodes"]
                    self.assertEqual(len(nodes), expected_count)
        finally:
            server.shutdown()
            server.server_close()
            worker.join()


if __name__ == "__main__":
    unittest.main()
