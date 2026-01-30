import base64
import json
import os
import pg8000.dbapi
from google.cloud import secretmanager


# Initialize Secret Manager client
secret_client = secretmanager.SecretManagerServiceClient()


def get_db_password():
    """
    Fetch database password securely from Secret Manager
    """
    project_id = os.environ.get("GCP_PROJECT")
    secret_name = os.environ.get("DB_PASSWORD_SECRET")

    secret_path = f"projects/{project_id}/secrets/{secret_name}/versions/latest"
    response = secret_client.access_secret_version(request={"name": secret_path})
    return response.payload.data.decode("UTF-8")


def process_event(event, context):
    """
    Triggered from a Pub/Sub message.
    Extracts GCS file metadata and writes to Cloud SQL.
    """

    # Decode Pub/Sub message
    pubsub_message = base64.b64decode(event["data"]).decode("utf-8")
    message_json = json.loads(pubsub_message)

    bucket_name = message_json["bucket"]
    file_name = message_json["name"]

    print(f"Processing file '{file_name}' from bucket '{bucket_name}'")

    # Environment variables
    db_user = os.environ.get("DB_USER")
    db_name = os.environ.get("DB_NAME")
    db_host = os.environ.get("DB_HOST")

    # Fetch password securely
    db_password = get_db_password()

    try:
        # Connect to Cloud SQL (private IP)
        conn = pg8000.dbapi.connect(
            user=db_user,
            password=db_password,
            host=db_host,
            database=db_name,
        )

        cursor = conn.cursor()
        cursor.execute(
            """
            INSERT INTO events (bucket_name, file_name)
            VALUES (%s, %s)
            """,
            (bucket_name, file_name),
        )

        conn.commit()
        cursor.close()
        conn.close()

        print(f"Successfully recorded event for file: {file_name}")

    except Exception as e:
        print(f"Error connecting to database: {e}")
        raise
