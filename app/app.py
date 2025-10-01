import os
import signal
import logging
from datetime import date, datetime
from decimal import Decimal
from typing import Any, Dict, List

from flask import Flask, jsonify, request
import psycopg2
from psycopg2.extras import RealDictCursor
import yaml

ACL_CONFIG_PATH = os.getenv("ACL_CONFIG_PATH", "/config/config.yaml")
DB_CONFIG = {
    "user":     os.getenv("DB_USER", "appuser"),
    "host":     os.getenv("DB_HOST", "postgres"),
    "database": os.getenv("DB_NAME", "appdb"),
    "password": os.getenv("DB_PASSWORD", "apppassword"),
    "port":     int(os.getenv("DB_PORT", "5432")),
}

app = Flask(__name__)
logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
log = logging.getLogger("acl")

state: Dict[str, Any] = {"routes": {}}

def _coerce(v: Any) -> Any:
    if isinstance(v, (datetime, date)): return v.isoformat()
    if isinstance(v, Decimal): return float(v)
    return v

def _map_row(row: Dict[str, Any], mapping: Dict[str, str]) -> Dict[str, Any]:
    return {api: _coerce(row.get(db)) for api, db in mapping.items()}

def _connect():
    return psycopg2.connect(**DB_CONFIG)

def _invert(db_to_api: Dict[str, str]) -> Dict[str, str]:
    return {api: db for db, api in db_to_api.items()}

def load_config():
    with open(ACL_CONFIG_PATH, "r", encoding="utf-8") as f:
        cfg = yaml.safe_load(f) or {}

    eps: List[Dict[str, Any]] = []
    if "endpoints" in cfg:
        for ep in cfg["endpoints"]:
            eps.append({"path": ep["path"], "query": ep["query"], "mapping": dict(ep.get("mapping", {}))})
    elif "mappings" in cfg:
        for m in cfg["mappings"]:
            eps.append({"path": m["api_endpoint"], "query": m["query"], "mapping": _invert(dict(m.get("columns", {}))) })
    else:
        raise ValueError("Config must contain 'endpoints' or 'mappings'.")
    return eps

def rebuild_routes():
    state["routes"].clear()
    for spec in load_config():
        path, query, mapping = spec["path"], spec["query"], spec["mapping"]
        epname = f"ep_{path.replace('/','_') or 'root'}"

        def make_view(_q=query, _m=mapping):
            def view():
                try:
                    with _connect() as conn, conn.cursor(cursor_factory=RealDictCursor) as cur:
                        cur.execute(_q)
                        rows = cur.fetchall()
                        return jsonify([_map_row(r, _m) for r in rows]), 200
                except Exception as e:
                    log.exception("Query failed for %s", request.path)
                    return jsonify({"error": str(e)}), 500
            return view

        # Remove duplicate rule if reloading
        for rule in list(app.url_map.iter_rules()):
            if str(rule.rule) == path:
                app.url_map._rules.remove(rule)  # type: ignore
                app.view_functions.pop(rule.endpoint, None)

        app.add_url_rule(path, endpoint=epname, view_func=make_view(), methods=["GET"])
        state["routes"][path] = {"query": query, "mapping": mapping}

@app.route("/healthz")
def healthz(): return jsonify({"status": "ok"}), 200

@app.route("/__meta/routes")
def meta(): return jsonify(state["routes"]), 200

def _hup(_sig, _frm):
    try:
        rebuild_routes()
        log.info("config reloaded")
    except Exception:
        log.exception("reload failed")

signal.signal(signal.SIGHUP, _hup)
rebuild_routes()

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=int(os.getenv("PORT", "3000")), debug=False)
