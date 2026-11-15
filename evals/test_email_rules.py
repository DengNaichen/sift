"""Sift 邮件分类状态机（Superhuman 7 类 + 安全护栏）、偏好切换、限速重试与独立性离线测试。"""

import ast
import contextlib
import io
import json
from pathlib import Path
import sys
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch
from urllib.error import HTTPError, URLError

sys.path.insert(0, str(Path(__file__).resolve().parent))
import email_rules as rules  # noqa: E402
import eval_gemini_emails as evaluator  # noqa: E402


def response(**overrides):
    policy = rules.load_policy()
    answers = {}
    for name in policy["questions"]:
        default = 0.98 if name in ("context_sufficient", "discardable", "topic_marketing") else 0.01
        answers[name] = {"type": "noul", "noul": overrides.get(name, default)}
    return {"answers": answers, "usage": {"total_input_tokens": 100, "total_output_tokens": 0}}


class SiftEmailRulesTests(unittest.TestCase):
    def setUp(self):
        self.policy = rules.load_policy()
        self.email = {"from": "sender@example.com", "subject": "Sample", "body": "Complete sample message."}

    def decide(self, email=None, conversation=(), policy=None, **signals):
        return rules.resolve_decision(response(**signals), email or self.email, policy or self.policy, conversation)

    def test_superhuman_seven_categories_and_review_guardrails(self):
        cases = [
            ("marketing flyer", {}, "trash", "marketing", None),
            ("fyi paid receipt", {"topic_finance": 0.99, "retain_record": 0.99, "discardable": 0.01}, "archive", "fyi", None),
            ("subscribed newsletter", {"topic_newsletter": 0.99, "retain_record": 0.02, "discardable": 0.02}, "archive", "news", None),
            ("product changelog", {"topic_newsletter": 0.55, "topic_product": 0.85, "discardable": 0.05}, "archive", "news", None),
            ("respond pending task", {"needs_attention": 0.92, "discardable": 0.01}, "keep", "respond", None),
            ("security OTP notice", {"security_event": 0.95, "topic_account_security": 0.99, "retain_record": 0.95, "discardable": 0.01}, "keep", "security", None),
            ("cold B2B pitch or job digest", {"pitch_outreach": 0.95, "topic_marketing": 0.90, "discardable": 0.02}, "trash", "pitch", None),
            ("cold pitch even if discardable also high", {"pitch_outreach": 0.93, "discardable": 0.92}, "trash", "pitch", None),
            ("social roundup default trash", {"social_digest": 0.95, "topic_newsletter": 0.90, "discardable": 0.01}, "trash", "social", None),
            ("protected work blocks pitch trash", {"pitch_outreach": 0.95, "topic_work": 0.80, "retain_record": 0.90, "discardable": 0.01}, "review", "review", "protection_conflict"),
            ("gray-zone attention", {"needs_attention": 0.30, "discardable": 0.02}, "review", "review", "uncertain_attention"),
            ("gray-zone security", {"security_event": 0.30, "discardable": 0.02}, "review", "review", "uncertain_attention"),
            ("record blocks marketing deletion", {"retain_record": 0.60, "discardable": 0.95}, "review", "review", "protection_conflict"),
            ("possible work blocks deletion", {"topic_work": 0.20, "discardable": 0.95}, "review", "review", "protection_conflict"),
            ("insufficient context", {"context_sufficient": 0.50, "discardable": 0.02}, "review", "review", "insufficient_context"),
            ("gray-zone disposal", {"discardable": 0.60}, "review", "review", "uncertain_disposal"),
        ]
        for name, signals, expected_action, expected_category, expected_review in cases:
            with self.subTest(name=name):
                result = self.decide(**signals)
                self.assertEqual(result["action"], expected_action)
                self.assertEqual(result["category"], expected_category)
                self.assertEqual(result["review_reason"], expected_review)

    def test_preference_mode_switching_without_prompt_changes(self):
        job_hunting = json.loads(json.dumps(self.policy))
        job_hunting["preferences"]["pitch"] = "archive"
        res_archive = self.decide(policy=job_hunting, pitch_outreach=0.95, discardable=0.01)
        self.assertEqual((res_archive["action"], res_archive["category"]), ("archive", "pitch"))

        job_hunting["preferences"]["pitch"] = "keep"
        res_keep = self.decide(policy=job_hunting, pitch_outreach=0.95, discardable=0.01)
        self.assertEqual((res_keep["action"], res_keep["category"]), ("keep", "pitch"))

        quiet_security = json.loads(json.dumps(self.policy))
        quiet_security["preferences"]["security"] = "archive"
        res_sec = self.decide(
            policy=quiet_security, security_event=0.95, topic_account_security=0.99, retain_record=0.95, discardable=0.01
        )
        self.assertEqual((res_sec["action"], res_sec["category"]), ("archive", "security"))

        conservative_marketing = json.loads(json.dumps(self.policy))
        conservative_marketing["preferences"]["marketing"] = "archive"
        res_mkt = self.decide(policy=conservative_marketing, discardable=0.96)
        self.assertEqual((res_mkt["action"], res_mkt["category"]), ("archive", "marketing"))

        illegal = json.loads(json.dumps(self.policy))
        illegal["preferences"]["fyi"] = "trash"
        with tempfile.NamedTemporaryFile("w", suffix=".json", delete=False) as handle:
            json.dump(illegal, handle)
            bad_path = Path(handle.name)
        try:
            with self.assertRaises(ValueError):
                rules.load_policy(bad_path)
        finally:
            bad_path.unlink(missing_ok=True)

    def test_local_protection_boilerplate_stub_and_sender_overrides(self):
        for flag in ("has_attachments", "truncated", "body_is_image_only"):
            with self.subTest(flag=flag):
                res = self.decide(email={**self.email, flag: True}, discardable=0.01)
                self.assertEqual((res["action"], res["category"], res["review_reason"]), ("review", "review", "insufficient_context"))
        self.assertEqual(self.decide(email={**self.email, "body": " "})["action"], "review")
        self.assertEqual(self.decide(email={**self.email, "body": "如不想收到此类邮件,点击退订"})["action"], "review")
        self.assertEqual(self.decide(email={**self.email, "starred": True})["category"], "respond")
        self.assertEqual(self.decide(conversation=[{"sent_by_owner": True}], discardable=0.98)["action"], "review")
        self.assertEqual(self.decide(conversation=[{"sent_by_owner": True}], discardable=0.02)["category"], "fyi")

        custom_policy = json.loads(json.dumps(self.policy))
        custom_policy["preferences"]["vip_senders"] = ["boss@company.com"]
        custom_policy["preferences"]["blocked_senders"] = ["spam@promo.example"]
        self.assertEqual(
            self.decide(email={**self.email, "from": "Boss <boss@company.com>"}, policy=custom_policy, discardable=0.02)["action"],
            "keep",
        )
        self.assertEqual(
            self.decide(email={**self.email, "from": "spam@promo.example"}, policy=custom_policy, discardable=0.40)["action"],
            "trash",
        )
        self.assertEqual(
            self.decide(email={**self.email, "from": "spam@promo.example"}, policy=custom_policy, discardable=0.40, topic_finance=0.50)["action"],
            "review",
        )

    def test_invalid_responses_are_rejected(self):
        for value in (True, -0.1, 1.1, float("nan"), "0.99"):
            with self.subTest(value=value), self.assertRaises(ValueError):
                self.decide(needs_attention=value)
        invalid = response()
        del invalid["answers"]["context_sufficient"]
        with self.assertRaises(KeyError):
            rules.resolve_decision(invalid, self.email, self.policy)
        wrong_type = response()
        wrong_type["answers"]["needs_attention"] = {"type": "choice", "choice": "keep", "confidence": 0.99}
        with self.assertRaises(ValueError):
            rules.resolve_decision(wrong_type, self.email, self.policy)

    def test_only_email_data_enters_input_and_role_preambles_attach(self):
        email = {
            **self.email,
            "body": "Hello\u034f\u2007\u00ad world",
            "gold": "do-not-send",
            "decision": "old-answer",
            "gmail_id": "private-id",
            "starred": True,
        }
        payload = rules.build_request(email, self.policy)
        serialized = json.dumps(payload)
        for secret in ("do-not-send", "old-answer", "private-id", "starred", "\u034f"):
            self.assertNotIn(secret, serialized)
        for name, question in payload["questions"].items():
            self.assertTrue(question["instructions"].startswith(self.policy["instructions"]))
            if name in rules.SIGNALS:
                self.assertIn(self.policy["signal_instructions"], question["instructions"])
            else:
                self.assertNotIn(self.policy["signal_instructions"], question["instructions"])

    def test_truncation_changes_review_state(self):
        email = {**self.email, "body": "x" * 30001}
        payload = json.loads(rules.build_request(email, self.policy)["input"])
        self.assertEqual(len(payload["untrusted_email"]["body"]), 30000)
        self.assertTrue(payload["preprocessing"]["truncated"])
        self.assertEqual(self.decide(email=email, discardable=0.02)["action"], "review")

    def test_one_http_request_rate_limit_retry_category_eval_and_no_key_leak(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            dataset, gold, output = root / "emails.json", root / "gold.json", root / "result"
            dataset.write_text(json.dumps({"samples": [{"id": "email-01", "email": self.email}]}))
            gold.write_text(json.dumps({
                "_metadata": {"annotator": "Gemini 4 Hydrogen"},
                "annotations": {"email-01": {"action": "trash", "category": "marketing"}},
            }))
            args = SimpleNamespace(
                dataset=dataset, gold=gold, output=output, policy=rules.DEFAULT_POLICY, env_file=None, interval=0, max_tpm=0
            )
            body = io.BytesIO(json.dumps(response()).encode())
            with patch.object(evaluator, "read_api_key", return_value="fixture-secret"), patch.object(
                evaluator, "urlopen", return_value=body
            ) as opener, contextlib.redirect_stdout(io.StringIO()):
                self.assertEqual(evaluator.run(args), 0)
            self.assertEqual(opener.call_count, 1)
            summary = json.loads((output / "summary.json").read_text())
            self.assertEqual(summary["final_action_agreement"]["correct"], 1)
            self.assertEqual(summary["category_evaluation"]["final_category_agreement"]["correct"], 1)
            for path in output.iterdir():
                self.assertNotIn("fixture-secret", path.read_text())

            output_retry = root / "result-retry"
            args_retry = SimpleNamespace(
                dataset=dataset, gold=gold, output=output_retry, policy=rules.DEFAULT_POLICY, env_file=None, interval=0, max_tpm=0
            )
            err_body = io.BytesIO(b'{"error":{"message":"Please retry in 1s fixture-secret"}}')
            rate_err = HTTPError(evaluator.ENDPOINT, 429, "Too Many Requests", {}, err_body)
            ok_body = io.BytesIO(json.dumps(response()).encode())
            with patch.object(evaluator, "read_api_key", return_value="fixture-secret"), patch.object(
                evaluator.time, "sleep"
            ) as sleeper, patch.object(evaluator, "urlopen", side_effect=[rate_err, ok_body]) as opener2, contextlib.redirect_stdout(
                io.StringIO()
            ):
                self.assertEqual(evaluator.run(args_retry), 0)
            self.assertEqual(opener2.call_count, 2)
            sleeper.assert_called_once()

            output_tunnel = root / "result-tunnel-retry"
            args_tunnel = SimpleNamespace(
                dataset=dataset, gold=gold, output=output_tunnel, policy=rules.DEFAULT_POLICY, env_file=None, interval=0, max_tpm=0
            )
            tunnel_err = URLError("Tunnel connection failed: 503 Service Unavailable fixture-secret")
            ok_body2 = io.BytesIO(json.dumps(response()).encode())
            with patch.object(evaluator, "read_api_key", return_value="fixture-secret"), patch.object(
                evaluator.time, "sleep"
            ) as sleeper2, patch.object(evaluator, "urlopen", side_effect=[tunnel_err, ok_body2]) as opener3, contextlib.redirect_stdout(
                io.StringIO()
            ):
                self.assertEqual(evaluator.run(args_tunnel), 0)
            self.assertEqual(opener3.call_count, 2)
            sleeper2.assert_called_once()

    def test_scripts_stay_independent(self):
        for name in ("email_rules.py", "eval_gemini_emails.py"):
            text = Path(__file__).with_name(name).read_text()
            imports = {node.names[0].name for node in ast.walk(ast.parse(text)) if isinstance(node, ast.Import)}
            self.assertNotIn("subprocess", imports)


if __name__ == "__main__":
    unittest.main()
