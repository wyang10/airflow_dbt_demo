import importlib
import pathlib
import sys


def _airflow_available() -> bool:
    try:
        import airflow  # noqa: F401
        return True
    except Exception:
        return False


def _dag_files():
    dags_dir = pathlib.Path(__file__).resolve().parents[1] / "airflow" / "dags"
    return [
        p
        for p in dags_dir.rglob("*.py")
        if "__pycache__" not in p.parts and "/lib/" not in str(p)
    ]


def test_import_dags_module_level():
    if not _airflow_available():
        return  # skip silently on CI without Airflow
    sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1]))
    for path in _dag_files():
        module_name = (
            "airflow.dags." + path.relative_to(path.parents[2] / "airflow" / "dags").with_suffix("")
        ).replace("/", ".")
        importlib.import_module(module_name)

