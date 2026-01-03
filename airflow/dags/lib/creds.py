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

    # Accept password auth OR key pair auth OR oauth token auth.
    base = ("SNOWFLAKE_ACCOUNT", "SNOWFLAKE_USER")
    password_ok = ok("SNOWFLAKE_PASSWORD")
    keypair_ok = ok("SNOWFLAKE_PRIVATE_KEY_PATH") or ok("SNOWFLAKE_PRIVATE_KEY")
    oauth_ok = ok("SNOWFLAKE_OAUTH_TOKEN")
    return all(ok(k) for k in base) and (password_ok or keypair_ok or oauth_ok)
