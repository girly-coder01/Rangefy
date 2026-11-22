from src.config import ROOT, Settings


def test_defaults_and_parsing(monkeypatch):
    monkeypatch.setenv("API_CORS_ORIGINS", "http://a, http://b")
    monkeypatch.setenv("DB_PATH", "data/x.db")
    s = Settings(_env_file=None)
    assert s.chain_id == 1301
    assert s.api_cors_origins == ["http://a", "http://b"]
    assert s.db_path == ROOT / "data" / "x.db"
