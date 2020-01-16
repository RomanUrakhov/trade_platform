from flask import Flask
from flask_httpauth import HTTPBasicAuth
from .database import db
import os

# Экземпляр приложения
app = Flask(__name__)
app.config.from_object(os.environ['APP_SETTINGS'])

db.init_app(app)
auth = HTTPBasicAuth()
with app.app_context():
    db.create_all()
    from . import routes
