"""A small S3 client for Cloudflare R2 (AWS Signature Version 4), using only the standard library.

Just what clip syncing needs: list, head, get, put and delete objects, with progress for big files. Uploads are
single PUTs with a signed SHA-256 of the body, so R2 refuses anything that arrives damaged, and their ETag is the
body's MD5.
"""
import errno
import hashlib
import hmac
import http.client
import io
import os
import time
import urllib.parse
import xml.etree.ElementTree as ET
from datetime import datetime, timezone

EMPTY_SHA256 = hashlib.sha256(b"").hexdigest()
CHUNK = 256 * 1024
TIMEOUT = 60  # Seconds a connection may sit silent
RETRIES = 3
NETWORK_ERRORS = (OSError, http.client.HTTPException)
LOCAL_ERRNOS = {errno.ENOENT, errno.EACCES, errno.EPERM, errno.EISDIR, errno.ENOSPC, errno.EDQUOT, errno.EROFS}


class S3Error(Exception):
    """status is the HTTP status, or 0 when the server couldn't be reached."""

    def __init__(self, message, status=0, code=""):
        super().__init__(message)
        self.status = status
        self.code = code


def quote(text, safe="-_.~"):
    return urllib.parse.quote(text, safe=safe)


def canonical_query(query):
    return "&".join(f"{quote(k)}={quote(v)}" for k, v in sorted(query.items()))


def hmac_sha256(key, message):
    return hmac.new(key, message.encode(), hashlib.sha256).digest()


def authorization(method, path, query, headers, payload_hash, access_key, secret_key, region, service="s3"):
    """The Authorization header for a request, signing every header in `headers` (which must include host and
    x-amz-date). `path` is the raw, unencoded path."""
    amz_date = headers["x-amz-date"]
    scope = f"{amz_date[:8]}/{region}/{service}/aws4_request"
    values = {name.lower(): " ".join(str(value).split()) for name, value in headers.items()}
    names = sorted(values)
    canonical_request = "\n".join([
        method,
        quote(path, safe="/-_.~"),
        canonical_query(query),
        "".join(f"{name}:{values[name]}\n" for name in names),
        ";".join(names),
        payload_hash,
    ])
    string_to_sign = "\n".join(["AWS4-HMAC-SHA256", amz_date, scope, hashlib.sha256(canonical_request.encode()).hexdigest()])
    key = ("AWS4" + secret_key).encode()
    for part in (amz_date[:8], region, service, "aws4_request"):
        key = hmac_sha256(key, part)
    signature = hmac.new(key, string_to_sign.encode(), hashlib.sha256).hexdigest()
    return f"AWS4-HMAC-SHA256 Credential={access_key}/{scope}, SignedHeaders={';'.join(names)}, Signature={signature}"


def clean_etag(value):
    return (value or "").strip('"').lower()


def file_hashes(path):
    """MD5 and SHA-256 of a file, in one read."""
    md5, sha256 = hashlib.md5(), hashlib.sha256()
    with open(path, "rb") as f:
        while chunk := f.read(1 << 20):
            md5.update(chunk)
            sha256.update(chunk)
    return md5.hexdigest(), sha256.hexdigest()


class Client:
    def __init__(self, endpoint, bucket, access_key, secret_key, region="auto"):
        url = urllib.parse.urlsplit(endpoint)
        self.secure = url.scheme != "http"
        self.host = url.netloc
        self.bucket = bucket
        self.access_key = access_key
        self.secret_key = secret_key
        self.region = region

    # ---- Plumbing ----

    def call(self, method, key="", query=None, headers=None, body=None, payload_hash=EMPTY_SHA256, read=None,
             on_sent=None, missing_ok=False):
        """Sends a request, retrying when the network or the server trips up, and returns read(response) (or the
        response itself, already read). body is bytes or a file path. With missing_ok, a 404 returns None."""
        for attempt in range(RETRIES):
            try:
                return self.attempt(method, key, query or {}, headers or {}, body, payload_hash, read, on_sent, missing_ok)
            except S3Error as e:
                if (e.status < 500 and e.status != 429) or attempt == RETRIES - 1:
                    raise
            except NETWORK_ERRORS as e:
                if isinstance(e, OSError) and e.errno in LOCAL_ERRNOS:  # This computer's files, not the network
                    raise
                if attempt == RETRIES - 1:
                    raise S3Error(f"can't reach R2 ({e or type(e).__name__})") from e
            time.sleep(2 ** attempt)

    def attempt(self, method, key, query, headers, body, payload_hash, read, on_sent, missing_ok):
        path = f"/{self.bucket}/{key}" if key else f"/{self.bucket}"
        headers = {**{k.lower(): v for k, v in headers.items()}, "host": self.host,
                   "x-amz-date": datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ"),
                   "x-amz-content-sha256": payload_hash}
        headers["authorization"] = authorization(method, path, query, headers, payload_hash,
                                                 self.access_key, self.secret_key, self.region)
        target = quote(path, safe="/-_.~") + (f"?{canonical_query(query)}" if query else "")
        connection = (http.client.HTTPSConnection if self.secure else http.client.HTTPConnection)(self.host, timeout=TIMEOUT)
        try:
            connection.putrequest(method, target, skip_host=True, skip_accept_encoding=True)
            for name, value in headers.items():
                connection.putheader(name, value)
            if body is None:
                connection.endheaders()
            else:
                stream = io.BytesIO(body) if isinstance(body, bytes) else open(body, "rb")
                with stream:
                    length = stream.seek(0, os.SEEK_END)
                    stream.seek(0)
                    connection.putheader("content-length", str(length))
                    connection.endheaders()
                    sent = 0
                    while chunk := stream.read(CHUNK):
                        connection.send(chunk)
                        sent += len(chunk)
                        if on_sent:
                            on_sent(sent, length)
            response = connection.getresponse()
            if response.status == 404 and missing_ok:
                response.read()
                return None
            if response.status >= 300:
                raise self.error(response)
            if read:
                return read(response)
            response.read()
            return response
        finally:
            connection.close()

    def error(self, response):
        code, message = "", ""
        try:
            root = ET.fromstring(response.read() or b"<x/>")
            code, message = root.findtext("Code") or "", root.findtext("Message") or ""
        except ET.ParseError:
            pass
        if not code:
            code = {401: "Unauthorized", 403: "AccessDenied", 404: "NotFound"}.get(response.status, f"HTTP {response.status}")
        return S3Error(f"{code}: {message}" if message else code, response.status, code)

    # ---- Objects ----

    def list(self, prefix="", limit=None):
        """Objects under a prefix: [{"key", "etag", "size", "modified"}]. With a limit, just the first page."""
        objects, token = [], None
        while True:
            query = {"list-type": "2", "prefix": prefix}
            if limit:
                query["max-keys"] = str(limit)
            if token:
                query["continuation-token"] = token
            root = self.call("GET", query=query, read=lambda r: ET.fromstring(r.read()))
            ns = root.tag[:root.tag.index("}") + 1] if root.tag.startswith("{") else ""
            for item in root.iter(f"{ns}Contents"):
                modified = item.findtext(f"{ns}LastModified") or ""
                try:
                    modified = datetime.fromisoformat(modified.replace("Z", "+00:00")).timestamp()
                except ValueError:
                    modified = time.time()
                objects.append({"key": item.findtext(f"{ns}Key"), "etag": clean_etag(item.findtext(f"{ns}ETag")),
                                "size": int(item.findtext(f"{ns}Size") or 0), "modified": modified})
            token = root.findtext(f"{ns}NextContinuationToken")
            if limit or root.findtext(f"{ns}IsTruncated") != "true" or not token:
                return objects

    def head(self, key):
        """{"etag", "size", "metadata"} for an object, or None if there's no such object."""
        def read(response):
            response.read()
            return {"etag": clean_etag(response.getheader("etag")), "size": int(response.getheader("content-length") or 0),
                    "metadata": {name[11:].lower(): value for name, value in response.getheaders()
                                 if name.lower().startswith("x-amz-meta-")}}
        return self.call("HEAD", key, read=read, missing_ok=True)

    def get_bytes(self, key):
        """(content, etag), or None if there's no such object."""
        return self.call("GET", key, read=lambda r: (r.read(), clean_etag(r.getheader("etag"))), missing_ok=True)

    def get_file(self, key, dest, on_progress=None):
        """Downloads an object into dest and returns its ETag."""
        def read(response):
            total = int(response.getheader("content-length") or 0)
            got = 0
            with open(dest, "wb") as f:
                while chunk := response.read(CHUNK):
                    f.write(chunk)
                    got += len(chunk)
                    if on_progress and total:
                        on_progress(got / total)
            if total and got != total:
                raise ConnectionError("the download was cut short")
            return clean_etag(response.getheader("etag"))
        return self.call("GET", key, read=read)

    def put(self, key, body, content_type, metadata=None, on_progress=None):
        """Uploads bytes or a file and returns the new ETag, after checking it matches what was sent."""
        if isinstance(body, bytes):
            md5, sha256 = hashlib.md5(body).hexdigest(), hashlib.sha256(body).hexdigest()
        else:
            md5, sha256 = file_hashes(body)
        headers = {"content-type": content_type, **{f"x-amz-meta-{k}": v for k, v in (metadata or {}).items()}}
        on_sent = (lambda sent, total: on_progress(sent / total if total else 1)) if on_progress else None
        response = self.call("PUT", key, headers=headers, body=body, payload_hash=sha256, on_sent=on_sent)
        etag = clean_etag(response.getheader("etag"))
        if len(etag) == 32 and etag != md5:
            raise S3Error(f"{key} didn't arrive intact")
        return etag or md5

    def delete(self, key):
        self.call("DELETE", key, missing_ok=True)
