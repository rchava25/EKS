import logging
from typing import Optional

import boto3
from opensearchpy import OpenSearch, RequestsHttpConnection
from requests_aws4auth import AWS4Auth

from app.config import AWS_REGION, OPENSEARCH_HOST, OPENSEARCH_INDEX
from app.models.search import SearchResponse, SearchResult

logger = logging.getLogger(__name__)

_credentials = boto3.Session().get_credentials()
_awsauth = AWS4Auth(
    refreshable_credentials=_credentials,
    region=AWS_REGION,
    service="es",
)

_client = OpenSearch(
    hosts=[OPENSEARCH_HOST],
    http_auth=_awsauth,
    use_ssl=True,
    verify_certs=True,
    connection_class=RequestsHttpConnection,
)


def search_products(
    query: str,
    category: Optional[str] = None,
    min_price: Optional[float] = None,
    max_price: Optional[float] = None,
    page: int = 1,
    page_size: int = 20,
) -> SearchResponse:
    must = [{"multi_match": {"query": query, "fields": ["name^2", "description"]}}]
    filters = []

    if category:
        filters.append({"term": {"category.keyword": category}})
    if min_price is not None or max_price is not None:
        price_range: dict = {}
        if min_price is not None:
            price_range["gte"] = min_price
        if max_price is not None:
            price_range["lte"] = max_price
        filters.append({"range": {"price": price_range}})

    body = {
        "query": {"bool": {"must": must, "filter": filters}},
        "from": (page - 1) * page_size,
        "size": page_size,
    }

    resp = _client.search(index=OPENSEARCH_INDEX, body=body)
    hits = resp["hits"]
    results = [
        SearchResult(
            id=h["_id"],
            score=h["_score"],
            **h["_source"],
        )
        for h in hits["hits"]
    ]
    return SearchResponse(
        total=hits["total"]["value"],
        page=page,
        page_size=page_size,
        results=results,
    )
