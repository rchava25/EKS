import os

OPENSEARCH_HOST  = os.environ["OPENSEARCH_HOST"]
OPENSEARCH_INDEX = os.environ.get("OPENSEARCH_INDEX", "products")
AWS_REGION       = os.environ["AWS_REGION"]
