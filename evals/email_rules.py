"""独立的 Sift 邮件分类 Prompt 构造与本地偏好合成状态机（Superhuman 7 类 + 安全护栏）。

只使用 Python 标准库，不依赖 Swift/Go 应用运行时，也不对任何邮箱执行写入操作。
"""

import json
import math
from pathlib import Path
import re


DEFAULT_POLICY = Path(__file__).with_name("email_classification_policy.json")
ACTIONS = ("keep", "archive", "trash", "review")
CATEGORIES = ("respond", "fyi", "security", "news", "pitch", "social", "marketing", "review")
REVIEW_REASONS = (
    "insufficient_context",
    "uncertain_attention",
    "uncertain_disposal",
    "protection_conflict",
)
SIGNALS = (
    "needs_attention",
    "security_event",
    "retain_record",
    "pitch_outreach",
    "social_digest",
    "discardable",
    "context_sufficient",
)
THRESHOLDS = (
    "topic",
    "protection",
    "context_min",
    "attention_high",
    "attention_low",
    "record_max_for_trash",
    "archive_max_discardable",
    "digest_min",
    "trash_min",
)
ALLOWED_PREFERENCES = {
    "fyi": ("keep", "archive"),
    "security": ("keep", "archive"),
    "news": ("keep", "archive", "trash"),
    "pitch": ("keep", "archive", "trash"),
    "social": ("keep", "archive", "trash"),
    "marketing": ("keep", "archive", "trash"),
}
INVISIBLE_FILLER_RE = re.compile(r"[\u00ad\u034f\u2007\u200b-\u200f\u202a-\u202e\u2060-\u206f\ufeff]+")
BOILERPLATE_RE = re.compile(
    r"\[image alt:[^\]]*\]|https?://\S+|"
    r"(?:如不想收到此类邮件[,，\s]*点击退订|点击退订|退订|unsubscribe|privacy policy|view in browser|online version)",
    re.IGNORECASE,
)


def probability(value, name):
    if isinstance(value, bool) or not isinstance(value, (int, float)) or not math.isfinite(value) or not 0 <= value <= 1:
        raise ValueError(f"无效的概率或门槛：{name}")
    return value


def clean_body_text(text):
    cleaned = INVISIBLE_FILLER_RE.sub("", text).replace("\r\n", "\n")
    return re.sub(r"\n[ \t\xa0]*\n(?:[ \t\xa0]*\n)+", "\n\n", cleaned)


def is_boilerplate_stub(body):
    stripped = BOILERPLATE_RE.sub(" ", clean_body_text(body))
    substantive = re.sub(r"[\s|.,;:!?()<>—\-_/\\]+", "", stripped)
    return len(substantive) == 0


def sender_matches(sender, patterns):
    lowered = sender.lower()
    return any(pattern.strip().lower() in lowered for pattern in patterns if isinstance(pattern, str) and pattern.strip())


def load_policy(path=DEFAULT_POLICY):
    policy = json.loads(Path(path).read_text(encoding="utf-8"))
    if not isinstance(policy, dict) or not isinstance(policy.get("version"), str) or not policy["version"].strip():
        raise ValueError("策略缺少版本号。")
    for field in ("instructions", "signal_instructions"):
        if not isinstance(policy.get(field), str) or not policy[field].strip():
            raise ValueError(f"策略缺少 {field}。")
    for name in THRESHOLDS:
        probability(policy["thresholds"][name], name)
    prefs = policy.get("preferences")
    if not isinstance(prefs, dict):
        raise ValueError("策略缺少 preferences。")
    for key, allowed in ALLOWED_PREFERENCES.items():
        if prefs.get(key) not in allowed:
            raise ValueError(f"preferences.{key} 必须是 {'/'.join(allowed)} 之一。")
    if not isinstance(prefs.get("vip_senders", []), list) or not isinstance(prefs.get("blocked_senders", []), list):
        raise ValueError("vip_senders 与 blocked_senders 必须是列表。")
    questions = policy["questions"]
    expected_questions = {*SIGNALS, *("topic_" + key for key in policy["topics"])}
    if set(questions) != expected_questions:
        raise ValueError("策略问题集合必须与正交信号及话题集合严格一致。")
    for name in expected_questions:
        if questions[name]["type"] != "noul" or not isinstance(questions[name].get("instructions"), str) or not questions[name]["instructions"].strip():
            raise ValueError(f"{name} 必须是包含 instructions 的 noul 问题。")
    for topic in policy["topics"].values():
        if not isinstance(topic["protect_from_trash"], bool):
            raise ValueError("protect_from_trash 必须是布尔值。")
    return policy


def input_data(email, conversation=()):
    """只选择原文和必要元数据，清理隐形填充字符，不把参考标签、旧结果或内部 ID 发给模型。"""
    def fields(message, limit):
        result = {key: message.get(key, "") for key in ("from", "subject", "date", "body")}
        if any(not isinstance(value, str) for value in result.values()):
            raise ValueError("邮件头和正文必须是字符串。")
        cleaned = clean_body_text(result["body"])
        clipped = len(cleaned) > limit
        result["body"] = cleaned[:limit]
        return result, clipped

    original, clipped = fields(email, 30000)
    history = []
    clipped = clipped or len(conversation) > 12
    for message in conversation[-12:]:
        text, shortened = fields(message, 8000)
        history.append(text)
        clipped = clipped or shortened
    flags = {}
    for source, target in (
        ("has_attachments", "has_unread_attachments"),
        ("truncated", "truncated"),
        ("body_is_image_only", "body_is_image_only"),
    ):
        value = email.get(source, False)
        if not isinstance(value, bool):
            raise ValueError(f"{source} 必须是布尔值。")
        flags[target] = value
    flags["truncated"] = flags["truncated"] or clipped
    flags["body_is_image_only"] = flags["body_is_image_only"] or (
        bool(original["body"].strip()) and is_boilerplate_stub(original["body"])
    )
    return {"untrusted_email": original, "untrusted_conversation": history, "preprocessing": flags}


def build_request(email, policy, model="gemini-decision-1", conversation=()):
    questions = {}
    for name, question in policy["questions"].items():
        parts = [policy["instructions"]]
        if name in SIGNALS:
            parts.append(policy["signal_instructions"])
        parts.append(question["instructions"])
        questions[name] = {**question, "instructions": "\n\n".join(parts)}
    return {
        "model": model,
        "input": json.dumps(input_data(email, conversation), ensure_ascii=False),
        "questions": questions,
    }


def directional_suggestion(signals, prefs):
    """未加保守灰区和本地保护前的 0.5 中点方向性读数（action, category），仅供诊断对比。"""
    if signals["context_sufficient"] < 0.5:
        return "review", "review"
    if signals["needs_attention"] >= 0.5:
        return "keep", "respond"
    if signals["security_event"] >= 0.5:
        return prefs["security"], "security"
    if signals["pitch_outreach"] >= 0.5 and signals["retain_record"] < 0.5:
        return prefs["pitch"], "pitch"
    if signals["social_digest"] >= 0.5 and signals["retain_record"] < 0.5:
        return prefs["social"], "social"
    if signals["discardable"] >= 0.5 and signals["retain_record"] < 0.5:
        return prefs["marketing"], "marketing"
    if signals["retain_record"] >= 0.5:
        return prefs["fyi"], "fyi"
    return prefs["news"], "news"


def apply_preference_action(target_action, category, label, signal_score, protected, signals, threshold):
    if target_action == "keep":
        return "keep", category, None, f"命中{label}偏好（留在收件箱）。", signal_score
    if target_action == "archive":
        return "archive", category, None, f"命中{label}偏好（归档保留）。", min(signals["context_sufficient"], signal_score)
    if not protected and signals["retain_record"] <= threshold["record_max_for_trash"]:
        return (
            "trash",
            category,
            None,
            f"命中{label}偏好且无受保护信号，移入垃圾箱。",
            min(signals["context_sufficient"], 1.0 - signals["needs_attention"], 1.0 - signals["retain_record"], signal_score),
        )
    return (
        "review",
        "review",
        "protection_conflict",
        f"{label}删除偏好与受保护记录信号冲突，等待人工复核。",
        signal_score,
    )


def resolve_decision(response, email, policy, conversation=()):
    answers = response["answers"]
    values = {}
    for name, question in policy["questions"].items():
        answer = answers[name]
        if answer["type"] != question["type"]:
            raise ValueError(f"模型返回了无效的问题类型：{name}")
        values[name] = probability(answer["noul"], name)

    threshold = policy["thresholds"]
    prefs = policy["preferences"]
    scores = {key: values["topic_" + key] for key in policy["topics"]}
    signals = {key: values[key] for key in SIGNALS}
    signals["topic_scores"] = scores

    for message in (email, *conversation):
        for flag in ("starred", "sent_by_owner"):
            if not isinstance(message.get(flag, False), bool):
                raise ValueError(f"{flag} 必须是布尔值。")

    sender = email.get("from", "")
    vip = sender_matches(sender, prefs.get("vip_senders", []))
    blocked = sender_matches(sender, prefs.get("blocked_senders", []))

    protected = any(
        topic["protect_from_trash"] and scores[key] >= threshold["protection"]
        for key, topic in policy["topics"].items()
    )
    protected = protected or signals["retain_record"] > threshold["record_max_for_trash"]
    protected = (
        protected
        or vip
        or email.get("starred", False)
        or any(message.get("sent_by_owner", False) for message in (email, *conversation))
    )

    data = input_data(email, conversation)
    incomplete = is_boilerplate_stub(data["untrusted_email"]["body"]) or any(data["preprocessing"].values())
    suggested_action, suggested_category = directional_suggestion(signals, prefs)

    if email.get("starred", False) or vip:
        action, category, review_reason, reason, support = (
            "keep",
            "respond",
            None,
            "邮件已加星或命中重要发件人偏好，留在收件箱优先处理。",
            1.0,
        )
    elif signals["needs_attention"] >= threshold["attention_high"]:
        action, category, review_reason, reason, support = (
            "keep",
            "respond",
            None,
            "邮件存在未解决待办、回复请求、故障或面试安排，留在收件箱。",
            signals["needs_attention"],
        )
    elif signals["security_event"] >= threshold["attention_high"] and prefs["security"] == "keep":
        action, category, review_reason, reason, support = (
            "keep",
            "security",
            None,
            "安全登录、验证码或权限变动提醒，留在收件箱供核验。",
            signals["security_event"],
        )
    elif incomplete or signals["context_sufficient"] < threshold["context_min"]:
        action, category, review_reason, reason, support = (
            "review",
            "review",
            "insufficient_context",
            "正文、图片、附件或可读上下文不足，等待人工复核。",
            1.0 - signals["context_sufficient"],
        )
    elif signals["needs_attention"] > threshold["attention_low"] or (
        prefs["security"] == "keep" and signals["security_event"] > threshold["attention_low"]
    ):
        action, category, review_reason, reason, support = (
            "review",
            "review",
            "uncertain_attention",
            "待办或安全核验信号处于不确定灰区，暂停归档或删除，等待人工复核。",
            max(signals["needs_attention"], signals["security_event"]),
        )
    elif signals["security_event"] >= threshold["attention_high"]:
        action, category, review_reason, reason, support = apply_preference_action(
            prefs["security"], "security", "安全验证通知", signals["security_event"], True, signals, threshold
        )
    elif blocked:
        if not protected:
            action, category, review_reason, reason, support = (
                "trash",
                "marketing",
                None,
                "命中用户屏蔽发件人偏好且无受保护信号，移入垃圾箱。",
                1.0,
            )
        else:
            action, category, review_reason, reason, support = (
                "review",
                "review",
                "protection_conflict",
                "屏蔽发件人邮件含受保护信号，等待人工复核。",
                1.0,
            )
    elif signals["pitch_outreach"] >= threshold["digest_min"]:
        action, category, review_reason, reason, support = apply_preference_action(
            prefs["pitch"], "pitch", "陌生推销与群发荐岗", signals["pitch_outreach"], protected, signals, threshold
        )
    elif signals["social_digest"] >= threshold["digest_min"]:
        action, category, review_reason, reason, support = apply_preference_action(
            prefs["social"], "social", "社交与公共社区动态", signals["social_digest"], protected, signals, threshold
        )
    elif signals["discardable"] >= threshold["trash_min"]:
        action, category, review_reason, reason, support = apply_preference_action(
            prefs["marketing"], "marketing", "商业打折促销", signals["discardable"], protected, signals, threshold
        )
    elif (
        (prefs["marketing"] == "trash" and signals["discardable"] > threshold["archive_max_discardable"])
        or (prefs["pitch"] == "trash" and signals["pitch_outreach"] > threshold["archive_max_discardable"])
        or (prefs["social"] == "trash" and signals["social_digest"] > threshold["archive_max_discardable"])
    ):
        action, category, review_reason, reason, support = (
            "review",
            "review",
            "uncertain_disposal",
            "可删除类别信号处于不确定灰区，等待人工复核。",
            max(signals["discardable"], signals["pitch_outreach"], signals["social_digest"]),
        )
    elif protected or signals["retain_record"] > threshold["record_max_for_trash"]:
        fyi_score = min(
            signals["context_sufficient"],
            1.0 - signals["needs_attention"],
            1.0 - signals["discardable"],
        )
        action, category, review_reason, reason, support = apply_preference_action(
            prefs["fyi"], "fyi", "知悉留档记录", fyi_score, True, signals, threshold
        )
    else:
        news_score = 1.0 - max(signals["discardable"], signals["pitch_outreach"], signals["social_digest"])
        action, category, review_reason, reason, support = apply_preference_action(
            prefs["news"], "news", "资讯简报与产品动态", news_score, protected, signals, threshold
        )

    return {
        "topics": sorted(key for key, score in scores.items() if score >= threshold["topic"]),
        "category": category,
        "review_reason": review_reason,
        "suggested_action": suggested_action,
        "suggested_category": suggested_category,
        "action": action,
        "confidence": round(support, 6),  # 本地合成规则下的保守支持度，不是已校准准确率。
        "protected_from_trash": protected,
        "reason": reason,
        "signals": signals,
    }
