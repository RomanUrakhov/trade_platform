from app.database import db
import datetime
from passlib.apps import custom_app_context as pwd_context


class User(db.Model):
    __tablename__ = "trade_user"

    id = db.Column(db.Integer, primary_key=True)
    login = db.Column(db.String(1000), nullable=False)
    password = db.Column(db.String(1000), nullable=False)
    type = db.Column(db.String(20), nullable=False)

    accounts = db.relationship('Account', backref='trade_user', lazy='dynamic')

    def __str__(self):
        return self.login

    def hash_password(self, password):
        self.password = pwd_context.encrypt(password)

    def verify_password(self, password):
        return pwd_context.verify(password, self.password)


class ObjectType(db.Model):
    __tablename__ = "object_type"

    id = db.Column(db.Integer, primary_key=True)
    title = db.Column(db.String(20))

    # связь с item
    items = db.relationship('Item', backref='object_type', lazy='dynamic')
    accounts = db.relationship('Account', backref='object_type', lazy='dynamic')

    def __str__(self):
        return self.title


class Item(db.Model):
    __tablename__ = "item"

    id = db.Column(db.Integer, primary_key=True)
    name = db.Column(db.String(1000), nullable=False)
    type_id = db.Column(db.Integer, db.ForeignKey('object_type.id'))

    def __str__(self):
        return self.name


class Account(db.Model):
    __tablename__ = "account"

    id = db.Column(db.Integer, primary_key=True)
    obj_type_id = db.Column(db.Integer, db.ForeignKey('object_type.id'))
    owner_id = db.Column(db.Integer, db.ForeignKey('trade_user.id'))


class OfferSell(db.Model):
    __tablename__ = "offer_sell"

    id = db.Column(db.Integer, primary_key=True)
    user_id = db.Column(db.Integer, nullable=False)
    item_id = db.Column(db.Integer, nullable=False)
    price = db.Column(db.Float)
    status_id = db.Column(db.Integer)
    date = db.Column(db.DateTime, nullable=False, default=datetime.datetime.now())


class OfferBuy(db.Model):
    __tablename__ = "offer_buy"

    id = db.Column(db.Integer, primary_key=True)
    user_id = db.Column(db.Integer, nullable=False)
    item_id = db.Column(db.Integer, nullable=False)
    price = db.Column(db.Float)
    status_id = db.Column(db.Integer)
    date = db.Column(db.DateTime, nullable=False, default=datetime.datetime.now())


class Status(db.Model):
    __tablename__ = "status"

    id = db.Column(db.Integer, primary_key=True)
    title = db.Column(db.String(10))


class Trade(db.Model):
    __tablename__ = "trade"

    id = db.Column(db.Integer, primary_key=True)
    offer_sell_id = db.Column(db.Integer, nullable=False)
    offer_buy_id = db.Column(db.Integer, nullable=False)
    date = db.Column(db.DateTime, default=datetime.datetime.now())


class Transaction(db.Model):
    __tablename__ = "transaction"

    id = db.Column(db.Integer, primary_key=True)
    trade_id = db.Column(db.Integer)
    sender_acc_id = db.Column(db.Integer)
    receiver_acc_id = db.Column(db.Integer)
    count = db.Column(db.Float)
    date = db.Column(db.DateTime, default=datetime.datetime.now())
