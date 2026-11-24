"""
Unit tests for the visitor counter.

These tests use a fake DynamoDB table, so they run in seconds,
cost nothing and need no AWS account. GitHub Actions runs them
automatically on every push.
"""

import json
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "lambda"))

import visitor_counter  # noqa: E402


class FakeTable:
    """Pretends to be a DynamoDB table that keeps the count in memory."""

    def __init__(self, start=0, fail=False):
        self.visits = start
        self.fail = fail
        self.calls = []

    def update_item(self, **kwargs):
        if self.fail:
            raise RuntimeError("DynamoDB is unavailable")
        self.calls.append(kwargs)
        self.visits += kwargs["ExpressionAttributeValues"][":inc"]
        return {"Attributes": {"visits": self.visits}}


def use_table(monkeypatch, table):
    monkeypatch.setattr(visitor_counter, "get_table", lambda: table)


def test_first_visit_returns_one(monkeypatch):
    use_table(monkeypatch, FakeTable(start=0))
    response = visitor_counter.lambda_handler({}, None)
    assert response["statusCode"] == 200
    assert json.loads(response["body"]) == {"visits": 1}


def test_counter_keeps_increasing(monkeypatch):
    table = FakeTable(start=41)
    use_table(monkeypatch, table)
    visitor_counter.lambda_handler({}, None)
    response = visitor_counter.lambda_handler({}, None)
    assert json.loads(response["body"]) == {"visits": 43}


def test_uses_atomic_add_on_the_counter_item():
    table = FakeTable()
    visitor_counter.increment_visits(table)
    call = table.calls[0]
    assert call["Key"] == {"id": "visitors"}
    assert call["UpdateExpression"] == "ADD visits :inc"


def test_returns_json_content_type(monkeypatch):
    use_table(monkeypatch, FakeTable())
    response = visitor_counter.lambda_handler({}, None)
    assert response["headers"]["Content-Type"] == "application/json"


def test_database_error_returns_500_instead_of_crashing(monkeypatch):
    use_table(monkeypatch, FakeTable(fail=True))
    response = visitor_counter.lambda_handler({}, None)
    assert response["statusCode"] == 500
    assert "error" in json.loads(response["body"])
