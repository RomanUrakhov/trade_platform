import time
from datetime import datetime
from datetime import timedelta

from flask import json, url_for, abort
from flask import jsonify, request, g
from sqlalchemy import func, text
from sqlalchemy.exc import IntegrityError
from werkzeug.exceptions import HTTPException

from . import app, auth
from .models import db, User, ObjectType, Account, Item, OfferSell, OfferBuy


@auth.verify_password
def verify_password(login, password):
    user = User.query.filter(User.login == login).first()
    if not user or not user.verify_password(password):
        abort(401)
    g.user = user
    return True


@app.route("/api/users/<int:usr_id>", methods=['GET'])
def get_user(usr_id):
    user = User.query.get(usr_id)
    if user:
        balance = db.session.query(func.get_balance(usr_id)).first()[0]
        rs = db.session.execute(text('SELECT * FROM get_inventory(:x)'), {'x': usr_id})
        inventory = [{
            "item_id": item.id_item,
            "item_name": item.name_item,
            "type_id": item.id_item_type,
            "type_name": item.item_type
        } for item in rs]
        return jsonify({
            "login": user.login,
            "balance": str(balance),
            "inventory": inventory
        })
    else:
        return jsonify(({
            'message': 'there is no user with specified id'
        }))


@app.route("/api/users", methods=['POST'])
def signup_user():
    if request.headers.get('Content-Type') != 'application/json':
        abort(400, {"message": "The request doesn't contain 'Application/json' header or its Body is empty"})

    login = request.json.get('login')
    password = request.json.get('password')
    type = request.json.get('type')

    if login and password and type:
        new_user = User()
        new_user.login = login
        new_user.hash_password(password)
        new_user.type = type

        db.session.add(new_user)
        try:
            db.session.commit()
        except IntegrityError:
            db.session.rollback()
            return jsonify({
                'message': 'the user with the specified login already exists'
            })
        db.session.refresh(new_user)

        return jsonify({
            "login": new_user.login
        }), 201, {"Location": url_for('get_user', usr_id=new_user.id, _external=True)}
    return jsonify({
        'message': 'none of the specified arguments can be empty'
    })


@app.route("/api/offers/buy", methods=['GET'])
def get_offers_buy():
    user_id = request.args.get("user_id")
    item_id = request.args.get("item_id")
    item_name = request.args.get("item_name")

    if item_name and item_id:
        return jsonify({
            "message": "you are not allowed to pass both 'item_id' and "
                       "'item_name' parameters. Choose one of these filters"
        })

    if not (user_id.isdigit() and item_id.isdigit()):
        abort(400, {"message": "invalid parameters type passed"})

    query = db.session.query(OfferBuy).filter(OfferBuy.status_id == 1, OfferBuy.user_id.notin_([1, 2]))
    if user_id:
        query = query.filter(OfferBuy.user_id == user_id)
    if item_id:
        query = query.filter(OfferBuy.item_id == item_id)
    if item_name:
        appropriate_ids = [item.id for item in Item.query.filter(Item.name == item_name).all()]
        if not appropriate_ids:
            return jsonify({
                "message": "there are no items with such name"
            })
        query = query.filter(OfferBuy.item_id.in_(appropriate_ids))

    result = query.all()

    if not result:
        return jsonify({
            "message": "there are no purchasing offers with such filter(s)"
        })
    response = [{
        'id': row.id,
        'user_id': row.user_id,
        'item_id': row.item_id,
        'price': row.price,
        'status_id': row.status_id,
        'date': row.date
    } for row in result]
    return jsonify(response)


@app.route("/api/offers/sell", methods=['GET'])
def get_offers_sell():
    user_id = request.args.get("user_id")
    item_id = request.args.get("item_id")
    item_name = request.args.get("item_name")

    if item_name and item_id:
        return jsonify({
            "message": "you are not allowed to pass both 'item_id' and "
                       "'item_name' parameters. Choose one of these filters"
        })

    if not (user_id.isdigit() and item_id.isdigit()):
        abort(400, {"message": "invalid parameters type passed"})

    query = db.session.query(OfferSell).filter(OfferSell.status_id == 1, OfferSell.user_id.notin_([1, 2]))
    if user_id:
        query = query.filter(OfferSell.user_id == user_id)
    if item_id:
        query = query.filter(OfferSell.item_id == item_id)
    if item_name:
        appropriate_ids = [item.id for item in Item.query.filter(Item.name == item_name).all()]
        if not appropriate_ids:
            return jsonify({
                "message": "there are no items with such name"
            })
        query = query.filter(OfferSell.item_id.in_(appropriate_ids))

    result = query.all()

    if not result:
        return jsonify({
            "message": "there are no selling offers with such filter(s)"
        })
    response = [{
        'id': row.id,
        'user_id': row.user_id,
        'item_id': row.item_id,
        'price': row.price,
        'status_id': row.status_id,
        'date': row.date
    } for row in result]
    return jsonify(response)


@app.route("/api/offers/sell", methods=['POST'])
@auth.login_required
def add_offer_sell():
    if request.headers.get('Content-Type') != 'application/json':
        abort(400, {"message": "The request doesn't contain 'Application/json' header or its Body is empty"})

    user_id = g.user.id
    item_id = request.json.get('item_id')
    price = request.json.get('price')
    status_id = request.json.get('status_id')

    if user_id and item_id and price and status_id:

        try:
            int(user_id)
            int(item_id)
            float(price)
            int(status_id)
        except ValueError:
            return jsonify({
                "message": "an argument of incorrect type was specified"
            })

        existing_item = Item.query.get(item_id)
        if not existing_item:
            return jsonify({
                "message": "there is no item with such id"
            })

        inventory_items = [row.id_item for row in db.session.execute(
            'SELECT * FROM get_inventory(:x)', {"x": user_id})]
        if item_id not in inventory_items:
            return jsonify({
                "message": "there is no item with such id in your inventory"
            })

        existing_offer = OfferSell.query.filter(
            OfferSell.item_id == item_id,
            OfferSell.status_id == 1,
            OfferSell.user_id == user_id
        ).first()
        if existing_offer:
            return jsonify({
                "message": "you have already put up an offer to sell the specified item"
            })

        # нужно будет проверить last_sell, потому что может вернуться пустое значение (самая первая продажа)
        last_sell = OfferSell.query.filter(
            OfferSell.item_id == item_id,
            OfferSell.status_id == 2,
            # исключаем админа и поставщика, т.к. ограничение на перепродажу раз в сутки распр. только на пользователей
            OfferSell.user_id.notin_([1, 2])
        ).order_by(OfferSell.date.desc()).first()

        if last_sell:
            curr_date = db.session.query(func.now()).first()[0].replace(tzinfo=None)
            time_passed = curr_date - last_sell.date
            if time_passed < timedelta(hours=24):
                return jsonify({
                    'message': "you can't resell the item more that 1 time a day",
                    'time_remained': time.strftime(
                        '%Hh:%Mm',
                        time.gmtime((timedelta(hours=24) - time_passed).total_seconds())
                    )
                })

        offer_sell = OfferSell()
        offer_sell.user_id = user_id
        offer_sell.item_id = item_id
        offer_sell.status_id = status_id
        offer_sell.price = price

        db.session.add(offer_sell)
        db.session.commit()
        db.session.refresh(offer_sell)

        return jsonify({
            "id": offer_sell.id,
            "user_id": offer_sell.user_id,
            "item_id": offer_sell.item_id,
            "price": offer_sell.price,
            "status_id": offer_sell.status_id,
            "date": offer_sell.date
        })
    else:
        return jsonify({
            "message": "none of the specified arguments can be empty"
        })


@app.route("/api/offers/buy", methods=['POST'])
@auth.login_required
def add_offer_buy():
    if request.headers.get('Content-Type') != 'application/json':
        abort(400, {"message": "The request doesn't contain 'Application/json' header or its Body is empty"})

    user_id = g.user.id
    item_id = request.json.get('item_id')
    price = request.json.get('price')
    status_id = request.json.get('status_id')

    if user_id and item_id and price and status_id:

        try:
            int(user_id)
            int(item_id)
            float(price)
            int(status_id)
        except ValueError:
            return jsonify({
                "message": "an argument of incorrect type was specified"
            })

        existing_item = Item.query.get(item_id)
        if not existing_item:
            return jsonify({
                "message": "there is no item with such id"
            })

        inventory_items = [row.id_item for row in db.session.execute(
            'SELECT * FROM get_inventory(:x)', {"x": user_id})]
        if item_id in inventory_items:
            return jsonify({
                "message": "the specified item is already in your inventory"
            })

        existing_offer = OfferBuy.query.filter(
            OfferBuy.item_id == item_id,
            OfferBuy.status_id == 1,
            OfferBuy.user_id == user_id).first()
        if existing_offer:
            return jsonify({
                "message": "you have already put up an offer to buy the specified item"
            })

        offer_buy = OfferBuy()
        offer_buy.user_id = user_id
        offer_buy.item_id = item_id
        offer_buy.status_id = status_id
        offer_buy.price = price

        db.session.add(offer_buy)
        db.session.commit()
        db.session.refresh(offer_buy)

        return jsonify({
            "id": offer_buy.id,
            "user_id": offer_buy.user_id,
            "item_id": offer_buy.item_id,
            "price": offer_buy.price,
            "status_id": offer_buy.status_id,
            "date": offer_buy.date
        })
    else:
        return jsonify({
            "message": "none of the specified arguments can be empty"
        })


@app.route("/api/offers/sell/<int:ofr_id>", methods=['PUT'])
@auth.login_required
def edit_offer_sell(ofr_id):
    if request.headers.get('Content-Type') != 'application/json':
        abort(400, {"message": "The request doesn't contain 'Application/json' header or its Body is empty"})

    status_id = request.json.get('status_id')
    item_id = request.json.get('item_id')
    price = request.json.get('price')

    offer_exists = OfferSell.query.get(ofr_id)
    if not offer_exists:
        return jsonify({
            "message": "there is no offer with the specified id"
        })

    if status_id:

        try:
            int(status_id)
        except ValueError:
            return jsonify({
                "message": "an argument of incorrect type was specified"
            })

        OfferSell.query.filter(OfferSell.id == ofr_id).update({"status_id": status_id})
        db.session.commit()
        return jsonify({
            "id": ofr_id,
            "user_id": offer_exists.user_id,
            "item_id": offer_exists.item_id,
            "price": offer_exists.price,
            "status_id": offer_exists.status_id,
            "date": offer_exists.date
        })

    if price or item_id:

        try:
            if item_id:
                int(item_id)
            if price:
                float(price)
        except ValueError:
            return jsonify({
                "message": "an argument of incorrect type was specified"
            })

        update_info = {key: value for key, value in zip(['item_id', 'price'], [item_id, price]) if value is not None}
        OfferSell.query.filter(OfferSell.id == ofr_id).update(update_info)
        db.session.commit()
        return jsonify({
            "id": ofr_id,
            "user_id": offer_exists.user_id,
            "item_id": offer_exists.item_id,
            "price": offer_exists.price,
            "status_id": offer_exists.status_id,
            "date": offer_exists.date
        })
    else:
        return jsonify({
            "message": "there can be no empty arguments in the request"
        })


@app.route("/api/offers/buy/<int:ofr_id>", methods=['PUT'])
@auth.login_required
def edit_offer_buy(ofr_id):
    if request.headers.get('Content-Type') != 'application/json':
        abort(400, {"message": "The request doesn't contain 'Application/json' header or its Body is empty"})

    status_id = request.json.get('status_id')
    item_id = request.json.get('item_id')
    price = request.json.get('price')

    offer_exists = OfferBuy.query.get(ofr_id)
    if not offer_exists:
        return jsonify({
            "message": "there is no offer with the specified id"
        })

    if status_id:

        try:
            int(status_id)
        except ValueError:
            return jsonify({
                "message": "an argument of incorrect type was specified"
            })

        OfferBuy.query.filter(OfferBuy.id == ofr_id).update({"status_id": status_id})
        db.session.commit()
        return jsonify({
            "id": ofr_id,
            "user_id": offer_exists.user_id,
            "item_id": offer_exists.item_id,
            "price": offer_exists.price,
            "status_id": offer_exists.status_id,
            "date": offer_exists.date
        })

    if price or item_id:

        try:
            if item_id:
                int(item_id)
            if price:
                float(price)
        except ValueError:
            return jsonify({
                "message": "an argument of incorrect type was specified"
            })

        update_info = {key: value for key, value in zip(['item_id', 'price'], [item_id, price]) if value}
        OfferBuy.query.filter(OfferBuy.id == ofr_id).update(update_info)
        db.session.commit()
        return jsonify({
            "id": ofr_id,
            "user_id": offer_exists.user_id,
            "item_id": offer_exists.item_id,
            "price": offer_exists.price,
            "status_id": offer_exists.status_id,
            "date": offer_exists.date
        })
    else:
        return jsonify({
            "message": "there can be no empty arguments in the request"
        })


@app.route("/api/users/<int:usr_id>/activity", methods=['GET'])
@auth.login_required
def get_activity_history(usr_id):
    if not g.user.type == 'admin':
        abort(401, {"message": "you do not have administrator rights"})

    a = request.args.get('filter')
    search_filter = int(a) if a in ['1', '2'] else None

    rs = []
    if not search_filter:
        rs = db.session.execute(text('SELECT * FROM get_user_activity(:x)'), {'x': usr_id})
    # История начилений
    if search_filter == 1:
        rs = db.session.execute(text('SELECT * FROM get_user_activity(:x) WHERE user_receiver=:x'), {'x': usr_id})
    # Истирия отчислений
    elif search_filter == 2:
        rs = db.session.execute(text('SELECT * FROM get_user_activity(:x) WHERE user_sender=:x'), {'x': usr_id})

    if not rs:
        return jsonify({
            "message": "the activity history of the specified user is currently empty"
        })
    res = []
    for row in rs:
        record = {
            'user_sender': row.user_sender,
            'user_receiver': row.user_receiver,
            'object_type_id': row.object_type_id,
            'object_type_title': row.object_type_title,
            'count': str(row.count),
            'date': row.date
        }
        if row.object_type_id != 1:
            record['item_id'] = row.item_id
            record['item_name'] = row.item_name
        res.append(record)
    return jsonify(res)


@app.route("/api/deposit/<int:usr_id>", methods=['POST'])
@auth.login_required
def make_deposit(usr_id):
    if not g.user.type == 'admin':
        abort(401, {"message": "you do not have administrator rights"})

    if request.headers.get('Content-Type') != 'application/json':
        abort(400, {"message": "The request doesn't contain 'Application/json' header or its Body is empty"})
    amount = request.json.get('amount')
    if not amount:
        return jsonify({
            "message": "the field 'amount' cannot be empty"
        })
    try:
        float(amount)
    except ValueError:
        abort(400, {"message": "invalid parameter type passed"})

    existing_user = User.query.get(usr_id)
    if not existing_user:
        return jsonify({
            "message": "there is no user with such id"
        })

    sender_acc = Account.query.filter(Account.owner_id == g.user.id, Account.obj_type_id == 1).first()
    receiver_acc = Account.query.filter(Account.owner_id == usr_id, Account.obj_type_id == 1).first()

    db.session.execute("INSERT INTO transaction(sender_acc_id, receiver_acc_id, count)"
                       " VALUES (:sa, :ra, :c)", {"sa": sender_acc.id, "ra": receiver_acc.id, "c": amount})
    db.session.commit()

    return jsonify({
        "receiver": existing_user.login,
        "amount": amount
    })


@app.route("/api/items/types", methods=['GET'])
def get_items_types():
    itm_types = ObjectType.query.filter(ObjectType.id != 1).all()
    if not itm_types:
        return jsonify({
            "message": "there are no items at the moment"
        })
    response = [{'type_title': itm_type.title} for itm_type in itm_types]
    return jsonify(response)


@app.route("/api/items/types/", methods=['POST'])
@auth.login_required
def create_item_type():
    if not g.user.type == 'admin':
        abort(401, {"message": "you do not have administrator rights"})

    if request.headers.get('Content-Type') != 'application/json':
        abort(400, {"message": "The request doesn't contain 'Application/json' header or its Body is empty"})

    title = request.json.get('title')

    if not title:
        return jsonify({
            "message": "the arguments of the request cannot be empty"
        })

    existing_title = ObjectType.query.filter(ObjectType.title == title).first()
    if existing_title:
        return jsonify({
            "message": "the item type with such title already exists"
        })

    item_type = ObjectType()
    item_type.title = title

    db.session.add(item_type)
    db.session.commit()

    return jsonify({
        "title": title
    })


@app.route("/api/items/<int:itm_id>", methods=['GET'])
def get_item_info(itm_id):
    item = Item.query.get(itm_id)
    if not item:
        return jsonify({
            'message': 'there is no item with such id'
        })

    rs = db.session.query(func.get_item_owner(itm_id).label("owner_id")).all()
    resales_count = len(OfferSell.query.filter(
        OfferSell.item_id == itm_id,
        OfferSell.status_id == 2,
        OfferSell.user_id.notin_([1, 2])
    ).all())
    res = {
        "id": item.id,
        "name": item.name,
        "type_id": item.type_id,
        "owner_id": rs[0].owner_id if rs else '',
        "resales_count": resales_count
    }
    return jsonify(res)


@app.route("/api/items/top", methods=['GET'])
def get_top_items():
    from_date = request.args.get('from_date')
    to_date = request.args.get('to_date')

    try:
        if from_date is not None:
            datetime.strptime(from_date, '%Y-%m-%d')
        if to_date is not None:
            datetime.strptime(to_date, '%Y-%m-%d')
    except ValueError:
        return jsonify({
            "message": "the specified arguments should be 'datetime' compatible (YYYY-MM-DD)"
        })

    result = db.session.execute("SELECT count(i.name) as c, i.name FROM offer_sell as os "
                                "JOIN item as i ON i.id = os.item_id "
                                "JOIN trade as t ON os.id = t.offer_sell_id "
                                "WHERE os.status_id = 2 and os.user_id NOT IN(1,2) and "
                                "t.date BETWEEN coalesce(:x, '-infinity'::date) and coalesce(:y, 'infinity'::date) "
                                "GROUP BY i.name ORDER BY c DESC LIMIT 3", {"x": from_date, "y": to_date})
    response = [{
        "item_name": row.name
    } for row in result]

    if not response:
        return jsonify({
            "message": "no items were sold during the specified period"
        })
    return jsonify(response)


@app.route("/api/profile/activity", methods=['GET'])
@auth.login_required
def get_personal_activity():
    a = request.args.get('filter')
    search_filter = int(a) if a in ['1', '2'] else None

    rs = []
    if not search_filter:
        rs = db.session.execute(text('SELECT * FROM get_user_activity(:x)'), {'x': g.user.id})
    # История начилений
    if search_filter == 1:
        rs = db.session.execute(text('SELECT * FROM get_user_activity(:x) WHERE user_receiver=:x'), {'x': g.user.id})
    # Истирия отчислений
    elif search_filter == 2:
        rs = db.session.execute(text('SELECT * FROM get_user_activity(:x) WHERE user_sender=:x'), {'x': g.user.id})

    if not rs:
        return jsonify({
            "message": "your activity history is currently empty"
        })
    res = []
    for row in rs:
        record = {
            'user_sender': row.user_sender,
            'user_receiver': row.user_receiver,
            'object_type_id': row.object_type_id,
            'object_type_title': row.object_type_title,
            'count': str(row.count),
            'date': row.date
        }
        if row.object_type_id != 1:
            record['item_id'] = row.item_id
            record['item_name'] = row.item_name
        res.append(record)
    return jsonify(res)


@app.route("/api/profile/balance", methods=['GET'])
@auth.login_required
def get_revenue():
    from_date = request.args.get('from_date')
    to_date = request.args.get('to_date')

    try:
        if from_date is not None:
            datetime.strptime(from_date, '%Y-%m-%d')
        if to_date is not None:
            datetime.strptime(to_date, '%Y-%m-%d')
    except ValueError:
        return jsonify({
            "message": "the specified arguments should be 'datetime' compatible (YYYY-MM-DD)"
        })

    result = db.session.execute('SELECT * FROM get_balance(:x, :y, :z)',
                                {'x': g.user.id, 'y': from_date, 'z': to_date}).first()[0]
    return jsonify({
        "balance": str(result)
    })


@app.route("/api/market", methods=['GET'])
def get_market_info():
    commission = db.session.execute('SELECT * FROM get_fee()').first().get_fee
    users = User.query.filter(User.id != 2).all()
    items_count = 0
    for user in users:
        items_count += db.session.execute('SELECT COUNT(*) FROM get_inventory(:x)', {"x": user.id}).first()[0]
    offers_buy_count = db.session.execute(
        'SELECT COUNT(*) FROM offer_buy WHERE status_id = 1 AND user_id NOT IN (1,2)').first()[0]
    offers_sell_count = db.session.execute(
        'SELECT COUNT(*) FROM offer_sell WHERE status_id = 1 AND user_id NOT IN (1,2)').first()[0]
    return jsonify({
        "commission": str(commission),
        "items": items_count,
        "offers_buy": offers_buy_count,
        "offers_sell": offers_sell_count
    })


@app.route("/api/market", methods=['POST'])
@auth.login_required
def set_market_commission():
    if not g.user.type == 'admin':
        abort(401, {"message": "you do not have administrator rights"})

    if request.headers.get('Content-Type') != 'application/json':
        abort(400, {"message": "The request doesn't contain 'Application/json' header or its Body is empty"})

    commission = request.json.get('commission')
    if not commission:
        return jsonify({
            "message": "required argument 'commission' cannot be empty"
        })

    try:
        float(commission)
    except ValueError:
        return jsonify({
            "message": "incorrect type of specified argument 'commission'. Should be float or int"
        })

    current_fee_id = db.session.execute('SELECT id FROM trade_fee WHERE "end"=:x', {'x': 'infinity'}).first()[0]
    db.session.execute('INSERT INTO trade_fee(start, fee) VALUES (NOW(), :y)', {'y': commission})
    db.session.execute('UPDATE trade_fee SET "end" = NOW() WHERE id = :x', {'x': current_fee_id})
    db.session.commit()

    return jsonify({
        "commission": commission
    })


@app.errorhandler(HTTPException)
def handle_exception(e):
    response = e.get_response()
    response.data = json.dumps({
        "code": e.code,
        "name": e.name,
        "description": e.description
    })
    response.content_type = "application/json"
    return response


@app.errorhandler(401)
def handle_auth_exception(e):
    response = e.get_response()
    response.data = json.dumps({
        "code": e.code,
        "name": e.name,
        "description": e.description
    })
    response.content_type = "application/json"
    response.headers['WWW-Authentication'] = 'Basic realm="Login required"'
    return response
