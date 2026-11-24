"""
Visitor counter Lambda function.

Every time someone opens the website, the browser calls this function
(through API Gateway). It adds 1 to a counter stored in DynamoDB and
returns the new total as JSON, for example: {"visits": 42}
"""

import json
import os

# Name of the DynamoDB table. Terraform passes this in as an environment variable.
TABLE_NAME = os.environ.get("TABLE_NAME", "")

# The single item in the table that holds our counter.
COUNTER_KEY = {"id": "visitors"}

_table = None


def get_table():
    """Connect to the DynamoDB table once and reuse the connection.

    boto3 (the AWS SDK for Python) is imported here, not at the top,
    so the unit tests can run without AWS installed.
    """
    global _table
    if _table is None:
        import boto3

        _table = boto3.resource("dynamodb").Table(TABLE_NAME)
    return _table


def increment_visits(table):
    """Add 1 to the counter in one atomic step and return the new value.

    'ADD' is atomic, so two visitors arriving at the same moment
    can never overwrite each other's count. If the item does not
    exist yet, DynamoDB creates it starting from 0.
    """
    response = table.update_item(
        Key=COUNTER_KEY,
        UpdateExpression="ADD visits :inc",
        ExpressionAttributeValues={":inc": 1},
        ReturnValues="UPDATED_NEW",
    )
    return int(response["Attributes"]["visits"])


def build_response(status_code, body):
    """Format a reply the way API Gateway expects it."""
    return {
        "statusCode": status_code,
        "headers": {"Content-Type": "application/json"},
        "body": json.dumps(body),
    }


def lambda_handler(event, context):
    """Entry point. AWS Lambda calls this function on every request."""
    try:
        visits = increment_visits(get_table())
        return build_response(200, {"visits": visits})
    except Exception as error:  # log the problem, never crash the website
        print(f"Error updating visitor count: {error}")
        return build_response(500, {"error": "Could not update visitor count"})
