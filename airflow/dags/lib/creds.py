import os


def has_snowflake_creds() -> bool:
    def ok(k: str) -> bool:
        v = os.environ.get(k, "")
        if not v:
            return False
        low = v.strip().lower()
        return low not in {
            "changeme",
            "placeholder",
            "dummy",
            "example",
            "sample",
        }

    required = ("SNOWFLAKE_ACCOUNT", "SNOWFLAKE_USER", "SNOWFLAKE_PASSWORD")
    return all(ok(k) for k in required)
