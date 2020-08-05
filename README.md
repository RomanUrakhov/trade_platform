# Trade Platform REST API
API, предоставляющий взаимодействие с биржей игровых предметов
## Модель базы данных:
<p align="center">
    <img src="resources/physical.png" width="600">
</p>

## Логика в БД:
### Триггеры:
* Триггер на организацию сделки:
    * сведение двух предложений (buy и sell) в таблицу trade
    * формирование __трех__ записей в таблице transaction (оплата продавцу, оплата комиссии бирже, передача вещи)    
    [+ можно разелить в соответствующие функции запись в trade и запись в transaction]
* Триггер на добавление всех аккаунтов пользователя (срабатывает при создании нового пользователя, либо при добавлении нового типа предмета)

### Функции:
* Функция для возврата комиссии за нужную дату(```get_fee```)
* Функция для возврата инвентаря конкретного пользователя (```get_inventory```)
* Функция для возврата текущего баланса конкретного пользователя(```get_balance```)
* Функция для возврата владельца конкретной вещи(```get_item_owner```)
* Функция для получения истории деятельности пользователя(```get_user_activity```)

## Логика API:
### Методы администратора:    
* установка комиссии биржи (```route: /api/market method: POST```)
* пополнение баланса пользователя (```route: /api/deposit/<int:usr_id> method: POST```)
* создание типа предмета (```route: /api/items/types/ method: POST```)
* получение истории активности любого пользователя (```route: /api/users/<int:usr_id>/activity method: GET```)

### Методы пользователя:
* регистрация (```route: /api/users method: POST```)
* создание предложения на покупку предмета(```route: /api/offers/buy method: POST```)
* создание предложения на продажу предмета(```route: /api/offers/sell method: POST```)
* обновление предложения на продажу (```route: /api/offers/sell/<int:ofr_id> method: PUT```)
* обновление предложения на покупку (```route: /api/offers/buy/<int:ofr_id> method: PUT```)
* получение своей истории активности (```route: /api/profile/activity method: GET```)

### Общие методы:
* получение списка типов предметов (```route: /api/items/types method: GET```) (for what purpose???)
* получение текущего состояния биржи (```route: /api/market method: GET```)
* получение информации общей инф. о пользователе (```route: /api/users/<int:usr_id> method: GET```)
* получение выручки за период (```route: /api/profile/balance method: GET```) ~ получение баланса
* получение списка предложений о покупке (```route: /api/offers/buy method: GET```)
* получение списка предложение о продаже (```route: /api/offers/sell method: GET```)
* получение информации о предмете (```route: /api/items/<int:itm_id> method: GET```)
* получение топ-3 самых продаваемых предметов (```route: /api/items/top method: GET```)

## Запуск:
1. Импорт дампа бд:
```bash
cat db.sql | psql -h hostname -U username dbname
```
2. Установка переменной окружения ```DATABSE_URI```:    
```bash
export DATABASE_URI="postgresql://user:mypassword@localhost:5432/database"
```
3. Установка переменной окружения ```APP_SETTINGS```:    
```bash
export APP_SETTINGS="config.DevelopmentConfig"
```
4. Запуск сервера:
```bash
python runner.py
```
