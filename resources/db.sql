--
-- PostgreSQL database dump
--

-- Dumped from database version 10.9 (Ubuntu 10.9-1.pgdg18.10+1)
-- Dumped by pg_dump version 11.4 (Ubuntu 11.4-1.pgdg18.10+1)

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: user_priority; Type: TYPE; Schema: public; Owner: postgres
--

CREATE TYPE public.user_priority AS ENUM (
    'admin',
    'provider',
    'common'
);


ALTER TYPE public.user_priority OWNER TO postgres;

--
-- Name: arrange_trade(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.arrange_trade() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
declare
    item_price decimal(12,2);
    id_item integer;
    item_type_id integer;
    offer_status integer;
    offer_rec record;
    sender_acc record;
    receiver_acc record;
    admin_acc record;
    id_trade integer;
    admin_id integer;
    test_val record;
begin
    item_price = NEW.price;
    id_item = NEW.item_id;
    offer_status = NEW.status_id;

    --ID администратора биржи
    select id into admin_id from trade_user
    where "type" = 'admin';
    --ID типа игрового предмета
    select type_id into item_type_id from item
    where id = id_item;
    
    -- Если предложение имеет статус "АКТИВНО"
    if offer_status = 1 then
        if TG_TABLE_NAME = 'offer_sell' then
            select id, user_id, price into offer_rec from offer_buy 
            where item_id = id_item and status_id = 1 and price >= item_price
            order by price desc, "date" asc limit 1;

            -- Если запись найдена, то сводим предложения в таблицу trade, а также обновляем их статусы
            -- также проводим запись в таблицу transaction
            if found then
                --
                --trade
                --
                insert into trade(offer_sell_id, offer_buy_id)
                    values (NEW.id, offer_rec.id)
                    returning id into id_trade;
                update offer_sell set status_id = 2 where item_id = id_item;
                update offer_buy set status_id = 2 where item_id = id_item;
               
                --
                --transaction
                --

                select id, obj_type_id, owner_id into sender_acc from account
                where 
                    owner_id = offer_rec.user_id and
                    obj_type_id = 1; --денежный аккаунт

                select id, obj_type_id, owner_id into receiver_acc from account
                where 
                    owner_id = NEW.user_id and 
                    obj_type_id = 1; --денежный аккаунт

                select id, obj_type_id, owner_id into admin_acc from account
                where
                    owner_id = admin_id and
                    obj_type_id = 1; 

                --Перечисление продавцу
                insert into "transaction" (trade_id, sender_acc_id, receiver_acc_id, "count")
                    values (id_trade, sender_acc.id, receiver_acc.id, offer_rec.price*(1-get_fee()));

                --Перечисление бирже
                insert into "transaction" (trade_id, sender_acc_id, receiver_acc_id, "count")
                    values (id_trade, sender_acc.id, admin_acc.id, offer_rec.price*get_fee());

                select id, obj_type_id, owner_id into sender_acc from account
                where
                    owner_id = NEW.user_id and
                    obj_type_id = item_type_id; --аккаунт с соответствующим предмету типом

                select id, obj_type_id, owner_id into receiver_acc from account
                where
                    owner_id = offer_rec.user_id and
                    obj_type_id = item_type_id; --аккаунт с соответствующим предмету типом

                --Перечисление покупателю
                insert into "transaction" (trade_id, sender_acc_id, receiver_acc_id, "count")
                    values (id_trade, sender_acc.id, receiver_acc.id, 1);
            end if;
        else 
            select id, user_id, price into offer_rec from offer_sell
            where item_id = id_item and status_id = 1 and price <= item_price
            order by price asc, "date" asc limit 1;

            if found then
                --trade
                insert into trade(offer_sell_id, offer_buy_id)
                    values (offer_rec.id, NEW.id)
                    returning id into id_trade;
                
                update offer_sell set status_id = 2 where item_id = id_item;
                update offer_buy set status_id = 2 where item_id = id_item;

                --
                --transaction
                -- 

                select id, obj_type_id, owner_id into sender_acc from account
                where 
                    owner_id = NEW.user_id and
                    obj_type_id = 1; --денежный аккаунт

                select id, obj_type_id, owner_id into receiver_acc from account
                where 
                    owner_id = offer_rec.user_id and 
                    obj_type_id = 1;

                select id, obj_type_id, owner_id into admin_acc from account
                where
                    owner_id = admin_id and
                    obj_type_id = 1;                 

                --Перечисление продавцу
                insert into "transaction" (trade_id, sender_acc_id, receiver_acc_id, "count")
                    values (id_trade, sender_acc.id, receiver_acc.id, offer_rec.price*(1-get_fee()));

                --Перечисление бирже
                insert into "transaction" (trade_id, sender_acc_id, receiver_acc_id, "count")
                    values (id_trade, sender_acc.id, admin_acc.id, offer_rec.price*get_fee());

                select id, obj_type_id, owner_id into sender_acc from account
                where
                    owner_id = offer_rec.user_id and
                    obj_type_id = item_type_id; --аккаунт с соответствующим предмету типом

                select id, obj_type_id, owner_id into receiver_acc from account
                where
                    owner_id = NEW.user_id and
                    obj_type_id = item_type_id; --аккаунт с соответствующим предмету типом

                --Перечисление покупателю
                insert into "transaction" (trade_id, sender_acc_id, receiver_acc_id, "count")
                    values (id_trade, sender_acc.id, receiver_acc.id, 1);
            end if; 
        end if;
    end if;
    return null;
end;
$$;


ALTER FUNCTION public.arrange_trade() OWNER TO postgres;

--
-- Name: create_accounts(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.create_accounts() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
declare
    user_id integer;
    new_object_type_id integer;
begin

    -- если сработало на таблице с пользователями
    if TG_TABLE_NAME = 'trade_user' then
        user_id = NEW.id;

        insert into account(obj_type_id, owner_id)
        select
            unnest(array(select id from object_type)), user_id;

        return null;
    else --если сработало на таблице с типами объектов
        new_object_type_id = NEW.id;

        insert into account(obj_type_id, owner_id)
        select
            new_object_type_id, unnest(array(select id from trade_user));

        return null;
    end if;
end;
$$;


ALTER FUNCTION public.create_accounts() OWNER TO postgres;

--
-- Name: get_balance(integer, date, date); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.get_balance(owner_id integer, from_date date DEFAULT NULL::date, to_date date DEFAULT NULL::date) RETURNS numeric
    LANGUAGE plpgsql
    AS $_$
declare
    income decimal(12,2); 
    outcome decimal(12,2);
begin
    select sum("count") into income from (
        select tr.trade_id, ac_s.owner_id as sender_user, ac_r.owner_id as receiver_user, tr.count, tr."date" from "transaction" as tr
            inner join
            account as ac_r on tr.receiver_acc_id = ac_r.id
            inner join
            account as ac_s on tr.sender_acc_id = ac_s.id
            where 
            ac_r.obj_type_id = 1 and 
            tr."date" between coalesce(from_date, '-infinity'::date) and coalesce(to_date, 'infinity'::date)
    ) r where r.receiver_user = $1;

    if income is null then
        return 0.0;
    end if;  

    if $1 = 1 then
        return income;
    end if;

    select sum("count") into outcome from (
        select tr.trade_id, ac_s.owner_id as sender_user, ac_r.owner_id as receiver_user, tr.count, tr."date" from "transaction" as tr
            inner join
            account as ac_r on tr.receiver_acc_id = ac_r.id
            inner join
            account as ac_s on tr.sender_acc_id = ac_s.id
            where ac_r.obj_type_id = 1 and 
            tr."date" between coalesce(from_date, '-infinity'::date) and coalesce(to_date, 'infinity'::date)
    ) r where r.sender_user = $1;

    if outcome is null then
        outcome = 0.0;
    end if;

    return income - outcome;
end;
$_$;


ALTER FUNCTION public.get_balance(owner_id integer, from_date date, to_date date) OWNER TO postgres;

--
-- Name: get_fee(timestamp without time zone); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.get_fee(date timestamp without time zone DEFAULT now()) RETURNS numeric
    LANGUAGE plpgsql
    AS $_$
declare
    res decimal(12,2);
begin
    select fee into res from trade_fee where $1 between "start" and "end";
    return res;
end;
$_$;


ALTER FUNCTION public.get_fee(date timestamp without time zone) OWNER TO postgres;

--
-- Name: get_inventory(integer); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.get_inventory(owner_id integer) RETURNS TABLE(id_item integer, name_item character varying, id_item_type integer, item_type character varying)
    LANGUAGE plpgsql
    AS $_$
begin
    return query
    select item_id, "name", type_id, title from
    (
        select *, row_number() over (partition by item_id order by "date" desc) as rn
        from
        (
            select tr.trade_id, ac_r.owner_id as receiver_user, ac_s.owner_id as sender_user, ob.item_id, tr."date" from "transaction" as tr
            inner join
            trade as td on td.id = tr.trade_id
            inner join
            offer_buy as ob on ob.id = td.offer_buy_id
            inner join
            account as ac_r on tr.receiver_acc_id = ac_r.id
            inner join
            account as ac_s on tr.sender_acc_id = ac_s.id
            where ac_r.obj_type_id != 1
        ) r1
    ) r
    join item i on i.id = r.item_id 
    join object_type ot on ot.id = i.type_id 
    where r.rn = 1 and r.receiver_user = $1;
end;
$_$;


ALTER FUNCTION public.get_inventory(owner_id integer) OWNER TO postgres;

--
-- Name: get_item_owner(integer); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.get_item_owner(id_item integer) RETURNS integer
    LANGUAGE plpgsql
    AS $_$
begin
    return (
        select r.receiver_user as "owner_id" from
        (
            select *, row_number() over (partition by item_id order by "date" desc) as rn
            from
            (
                select tr.trade_id, ac_r.owner_id as receiver_user, ac_s.owner_id as sender_user, ob.item_id, tr."date" from "transaction" as tr
                inner join
                trade as td on td.id = tr.trade_id
                inner join
                offer_buy as ob on ob.id = td.offer_buy_id
                inner join
                account as ac_r on tr.receiver_acc_id = ac_r.id
                inner join
                account as ac_s on tr.sender_acc_id = ac_s.id
                where ac_r.obj_type_id != 1
            ) r1
        ) r
        where r.rn = 1 and item_id = $1
    );
end;
$_$;


ALTER FUNCTION public.get_item_owner(id_item integer) OWNER TO postgres;

--
-- Name: get_user_activity(integer); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.get_user_activity(owner_id integer) RETURNS TABLE(user_sender integer, user_receiver integer, object_type_id integer, object_type_title character varying, item_id integer, item_name character varying, count numeric, date timestamp without time zone)
    LANGUAGE plpgsql
    AS $_$
begin
    return query
    select 
    acc_s.owner_id as user_sender, 
    acc_r.owner_id as user_receiver, 
    ot.id as object_type_id, 
    ot.title as object_type_title, 
    ob.item_id,
    it.name as item_name,
    tr.count, 
    tr.date 
    from transaction as tr
    inner join 
    account as acc_r on tr.receiver_acc_id = acc_r.id
    inner join 
    account as acc_s on tr.sender_acc_id = acc_s.id
    inner join
    object_type as ot on ot.id = acc_r.obj_type_id 
    inner join 
    trade as td on tr.trade_id = td.id
    inner join 
    offer_buy as ob on ob.id = td.offer_buy_id
    inner join
    item as it on it.id = ob.item_id
    where
    (acc_r.owner_id = $1 or acc_s.owner_id = $1) and 
    acc_r.owner_id != 1
    order by tr.date desc;
end;
$_$;


ALTER FUNCTION public.get_user_activity(owner_id integer) OWNER TO postgres;

--
-- Name: process_transaction(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.process_transaction() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
declare
    seller_id integer;
    buyer_id integer;
    admin_id integer;
    id_item integer;
    item_type_id integer;
    sender_acc record;
    receiver_acc record;
begin
    --ID пользователя-продавца
    select user_id into seller_id from offer_sell
    where id = NEW.offer_sell_id;

    --ID пользователя-покупателя
    select user_id into buyer_id from offer_buy
    where id = NEW.offer_buy_id;

    --ID администратора биржи
    select id into admin_id from trade_user
    where "type" = 'admin';

    --ID игрового предмета обмена --НЕ МОЖЕТ НАЙТИ ШМОТКУ (в NOW есть id офера на покупку, но в офере на покупку нет записи вообще)
    select item_id into id_item from offer_sell
    where id = NEW.offer_buy_id;

    --ID типа игрового предмета
    select type_id into item_type_id from item
    where id = id_item;

    -- raise exception 'Запись: %', NEW;
    --
    --Создание транзакций на оплату вещи
    --
    select id, obj_type_id, owner_id into sender_acc from account
    where 
        owner_id = buyer_id and
        obj_type_id = 1; --денежный аккаунт

    select id, obj_type_id, owner_id into receiver_acc from account
    where 
        owner_id = seller_id and 
        obj_type_id = 1; --денежный аккаунт

    --Перечисление продавцу
    insert into "transaction" (trade_id, sender_acc_id, receiver_acc_id, "count")
        values (NEW.id, sender_acc.id, receiver_acc.id, NEW.total_price*0.95); --где хранить процент комиссии

    --Перечисление бирже
    insert into "transaction" (trade_id, sender_acc_id, receiver_acc_id, "count")
        values (NEW.id, receiver_acc.id, admin_id, NEW.total_price*0.5);

    --
    --Создание транзакции на отправку вещи
    --
    select id, obj_type_id, owner_id into sender_acc from account
    where
        owner_id = seller_id and
        obj_type_id = item_type_id; --аккаунт с соответствующим предмету типом

    select id, obj_type_id, owner_id into receiver_acc from account
    where
        owner_id = buyer_id and
        obj_type_id = item_type_id; --аккаунт с соответствующим предмету типом

    --Перечисление покупателю
    insert into "transaction" (trade_id, sender_acc_id, receiver_acc_id, "count")
        values (NEW.id, sender_acc.id, receiver_acc.id, 1);

    return null;
end;
$$;


ALTER FUNCTION public.process_transaction() OWNER TO postgres;

SET default_tablespace = '';

SET default_with_oids = false;

--
-- Name: account; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.account (
    id integer NOT NULL,
    obj_type_id integer NOT NULL,
    owner_id integer NOT NULL
);


ALTER TABLE public.account OWNER TO postgres;

--
-- Name: account_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.account_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.account_id_seq OWNER TO postgres;

--
-- Name: account_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.account_id_seq OWNED BY public.account.id;


--
-- Name: income; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.income (
    sum numeric
);


ALTER TABLE public.income OWNER TO postgres;

--
-- Name: item; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.item (
    id integer NOT NULL,
    name character varying NOT NULL,
    type_id integer NOT NULL,
    CONSTRAINT not_money_check CHECK ((type_id <> 1))
);


ALTER TABLE public.item OWNER TO postgres;

--
-- Name: item_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.item_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.item_id_seq OWNER TO postgres;

--
-- Name: item_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.item_id_seq OWNED BY public.item.id;


--
-- Name: object_type; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.object_type (
    id integer NOT NULL,
    title character varying NOT NULL
);


ALTER TABLE public.object_type OWNER TO postgres;

--
-- Name: object_type_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.object_type_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.object_type_id_seq OWNER TO postgres;

--
-- Name: object_type_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.object_type_id_seq OWNED BY public.object_type.id;


--
-- Name: offer_buy; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.offer_buy (
    id integer NOT NULL,
    user_id integer NOT NULL,
    item_id integer NOT NULL,
    price numeric(12,2) DEFAULT 0,
    status_id integer NOT NULL,
    date timestamp without time zone DEFAULT now(),
    CONSTRAINT price_check CHECK ((price >= (0)::numeric))
);


ALTER TABLE public.offer_buy OWNER TO postgres;

--
-- Name: offer_buy_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.offer_buy_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.offer_buy_id_seq OWNER TO postgres;

--
-- Name: offer_buy_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.offer_buy_id_seq OWNED BY public.offer_buy.id;


--
-- Name: offer_sell; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.offer_sell (
    id integer NOT NULL,
    user_id integer NOT NULL,
    item_id integer NOT NULL,
    price numeric(12,2) DEFAULT 0,
    status_id integer NOT NULL,
    date timestamp without time zone DEFAULT now(),
    CONSTRAINT price_check CHECK ((price >= (0)::numeric))
);


ALTER TABLE public.offer_sell OWNER TO postgres;

--
-- Name: offer_sell_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.offer_sell_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.offer_sell_id_seq OWNER TO postgres;

--
-- Name: offer_sell_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.offer_sell_id_seq OWNED BY public.offer_sell.id;


--
-- Name: status; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.status (
    id integer NOT NULL,
    title character varying NOT NULL
);


ALTER TABLE public.status OWNER TO postgres;

--
-- Name: status_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.status_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.status_id_seq OWNER TO postgres;

--
-- Name: status_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.status_id_seq OWNED BY public.status.id;


--
-- Name: trade; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.trade (
    id integer NOT NULL,
    offer_sell_id integer NOT NULL,
    offer_buy_id integer NOT NULL,
    date timestamp without time zone DEFAULT now()
);


ALTER TABLE public.trade OWNER TO postgres;

--
-- Name: trade_fee; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.trade_fee (
    id integer NOT NULL,
    start timestamp without time zone NOT NULL,
    "end" timestamp without time zone DEFAULT 'infinity'::timestamp without time zone,
    fee numeric(12,2) NOT NULL,
    CONSTRAINT check_coefficient CHECK (((fee <= 0.2) AND (fee > (0)::numeric)))
);


ALTER TABLE public.trade_fee OWNER TO postgres;

--
-- Name: trade_fee_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.trade_fee_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.trade_fee_id_seq OWNER TO postgres;

--
-- Name: trade_fee_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.trade_fee_id_seq OWNED BY public.trade_fee.id;


--
-- Name: trade_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.trade_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.trade_id_seq OWNER TO postgres;

--
-- Name: trade_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.trade_id_seq OWNED BY public.trade.id;


--
-- Name: trade_user; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.trade_user (
    id integer NOT NULL,
    type public.user_priority NOT NULL,
    login character varying NOT NULL,
    password character varying NOT NULL
);


ALTER TABLE public.trade_user OWNER TO postgres;

--
-- Name: trade_user_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.trade_user_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.trade_user_id_seq OWNER TO postgres;

--
-- Name: trade_user_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.trade_user_id_seq OWNED BY public.trade_user.id;


--
-- Name: transaction; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.transaction (
    trade_id integer,
    sender_acc_id integer NOT NULL,
    receiver_acc_id integer NOT NULL,
    count numeric(12,2) NOT NULL,
    date timestamp without time zone DEFAULT now()
);


ALTER TABLE public.transaction OWNER TO postgres;

--
-- Name: account id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.account ALTER COLUMN id SET DEFAULT nextval('public.account_id_seq'::regclass);


--
-- Name: item id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.item ALTER COLUMN id SET DEFAULT nextval('public.item_id_seq'::regclass);


--
-- Name: object_type id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.object_type ALTER COLUMN id SET DEFAULT nextval('public.object_type_id_seq'::regclass);


--
-- Name: offer_buy id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.offer_buy ALTER COLUMN id SET DEFAULT nextval('public.offer_buy_id_seq'::regclass);


--
-- Name: offer_sell id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.offer_sell ALTER COLUMN id SET DEFAULT nextval('public.offer_sell_id_seq'::regclass);


--
-- Name: status id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.status ALTER COLUMN id SET DEFAULT nextval('public.status_id_seq'::regclass);


--
-- Name: trade id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.trade ALTER COLUMN id SET DEFAULT nextval('public.trade_id_seq'::regclass);


--
-- Name: trade_fee id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.trade_fee ALTER COLUMN id SET DEFAULT nextval('public.trade_fee_id_seq'::regclass);


--
-- Name: trade_user id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.trade_user ALTER COLUMN id SET DEFAULT nextval('public.trade_user_id_seq'::regclass);
