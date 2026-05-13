import os, secrets

SHEET_ID = "1FnRLNy8LMj1kwkH7N3v0vEC-Cp0dI4n9JT1b0mdByj4"
USERNAME = "Carlos"
# werkzeug hash of "invictus2017"
PASSWORD_HASH = "scrypt:32768:8:1$eVm5XImrKFc71Yys$3b70c16b3e99c6a56a5b12048f10236c4b028d80c4e57999601a2be6ee2ea85f6740fe01671ee8356b3fce995e727534a9eb92a57e4483027fab253ab301ff4b"
SECRET_KEY = os.environ.get("SECRET_KEY", "cXmpo-dashboard-secret-2025-xK9pLmN3qR7tWvZ1")
CACHE_TTL = 600  # segundos
