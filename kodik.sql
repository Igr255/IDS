
-- DROP ALL TABLES
drop table visits;
drop table offers;
drop table contracts;
drop table estates;
drop table questions;
drop table brokers;
drop table users;
commit;


--TABLE BROKERS
create table brokers
(
    user_id  number generated as identity
        constraint BROKERS_PK
            primary key,
    name     nvarchar2(80)    not null,
    surname  nvarchar2(80)    not null,
    phone    char(15 char) CONSTRAINT brokersPhoneCheck CHECK (REGEXP_LIKE (RTRIM(phone), '^\+\d{12}|^\d{9}$')),
    login    varchar(32 char) not null,
    password nvarchar2(80)    not null,
    photo    blob,
    language nvarchar2(20)
);

create unique index BROKERS_LOGIN_UINDEX
    on brokers (login);




--TABLE USERS
create table users
(
    user_id  number generated as identity
        constraint USERS_PK
            primary key,
    name        nvarchar2(80)    not null,
    surname     nvarchar2(80)    not null,
    phone       char(15 char) CONSTRAINT usersPhoneCheck CHECK (REGEXP_LIKE (RTRIM(phone), '^\+\d{12}|^\d{9}$')),
    login       varchar(32 char) not null,
    password    nvarchar2(80)    not null,
    address     nvarchar2(80),
    email       nvarchar2(80) CONSTRAINT emailCheck CHECK (REGEXP_LIKE (email, '^(\S+)\@(\S+)\.(\S+)$')) not null,
    permissions int              not null
);

create unique index USERS_LOGIN_UINDEX
    on users (login);


-- TABLE QUESTIONS
create table questions
(
    question_id number generated as identity
        constraint QUESTIONS_PK
            primary key,
    content     nvarchar2(1024) not null,
    broker_id   number
        constraint QUESTIONS_BROKERS_USER_ID_FK
            references BROKERS,
    user_id     number
        constraint QUESTIONS_USERS_USER_ID_FK
            references USERS
                on delete set null
);

--TABLE ESTATES
create table estates
(
    estate_id          number generated as identity
        constraint ESTATES_PK
            primary key,
    address            nvarchar2(80)  not null,
    state              nvarchar2(80),
    price              decimal(15, 2) not null,
    building_type      nvarchar2(40),
    managing_broker_id number
        constraint ESTATES_BROKERS_USER_ID_FK
            references BROKERS
);

-- TABLE CONTRACTS
create table contracts
(
    contract_id   number generated as identity
        constraint CONTRACTS_PK
            primary key,
    creation_date date default sysdate not null,
    agreed_price  decimal(15, 2)       not null,
    eval_state    nvarchar2(20)        not null,
    estate_id     number               not null
        constraint CONTRACTS_ESTATES_ESTATE_ID_FK
            references ESTATES
                on delete cascade,
    buyer_id      number
        constraint CONTRACTS_USERS_USER_ID_FK_2
            references USERS
                on delete set null,
    seller_id     number
        constraint CONTRACTS_USERS_USER_ID_FK
            references USERS
                on delete set null
);


--TABLE OFFERS
create table offers
(
    offer_id         number generated as identity
        constraint OFFERS_PK
            primary key,
    amount           decimal(15, 2) not null,
    offering_user_id number
        constraint OFFERS_USERS_USER_ID_FK
            references USERS
                on delete set null,
    estate_id        number
        constraint OFFERS_ESTATES_ESTATE_ID_FK
            references ESTATES
                on delete cascade
);


--TABLE VISITS
create table visits
(
    visit_id         number generated as identity
        constraint VISITS_PK
            primary key,
    visit_date       timestamp default current_timestamp not null,
    visiting_user_id number
        constraint VISITS_USERS_USER_ID_FK
            references USERS,
    estate_id        number
        constraint VISITS_ESTATES_ESTATE_ID_FK
            references ESTATES
);

---TRIGGERS
-------------------
--Pokud neni receno jinak, nastavi datum contractu na aktualni
CREATE OR REPLACE TRIGGER "auto_contract_date"
    BEFORE INSERT on contracts
    FOR EACH ROW
    begin
        IF :NEW.creation_date IS NULL THEN
            :NEW.creation_date := SYSDATE;
        end if;
    end;


--Pokud neni receno jinak, dostane novou estate broker s nejmensim poctem estates
CREATE OR REPLACE TRIGGER "auto_managing_broker"
    BEFORE INSERT  on estates
    FOR EACH ROW
DECLARE
user_id number;
begin
    IF :NEW.managing_broker_id IS NULL THEN
    BEGIN
        SELECT user_id INTO user_id FROM (SELECT user_id, COUNT(*) AS estate_count
            FROM brokers INNER JOIN estates ON brokers.user_id = estates.managing_broker_id
            GROUP BY brokers.user_id, name, surname
            ORDER BY estate_count ASC) WHERE ROWNUM = 1;

    EXCEPTION WHEN NO_DATA_FOUND THEN
        SELECT user_id INTO user_id FROM brokers WHERE user_id not in (SELECT managing_broker_id FROM estates) AND ROWNUM = 1;
    end;


        :NEW.managing_broker_id := user_id;
    end if;
    end;


--- PROCEDURESS
-----------------------------

-- overall statistics on estates and broker availability
CREATE OR REPLACE PROCEDURE estate_prices
AS
    max_price NUMBER;
    low_price NUMBER;
    broker_count NUMBER ;
    estate_count NUMBER;
    broker_estate_ratio NUMBER;
BEGIN

    SELECT COUNT(*) INTO estate_count FROM estates;
    SELECT MAX(price) INTO max_price FROM estates;
    SELECT MIN(price) INTO low_price FROM estates;
    SELECT COUNT(*) INTO broker_count FROM brokers;

    broker_estate_ratio := broker_count / estate_count;

    DBMS_OUTPUT.PUT_LINE( 'Total estates: ' || estate_count );
    DBMS_OUTPUT.PUT_LINE( 'Highest price: ' || max_price );
    DBMS_OUTPUT.PUT_LINE( 'Lowest price: ' || low_price );
    DBMS_OUTPUT.PUT_LINE( 'Broker availability for estate: ' || broker_estate_ratio );

    EXCEPTION WHEN ZERO_DIVIDE THEN
    BEGIN
        IF estate_count = 0 THEN
            DBMS_OUTPUT.put_line('Zero devision error');
        END IF;
    END;
end;

BEGIN estate_prices; END;


-- question asked by registered users
CREATE OR REPLACE PROCEDURE registered_users_questions
AS
    user_name users.name%TYPE;
    user_surname users.surname%TYPE;
    user_permission users.permissions%TYPE;
    user_id_value users.user_id%TYPE;

    question_text questions.content%TYPE;

    CURSOR cursor_users IS SELECT user_id, name, surname, permissions FROM users;
BEGIN
    DBMS_OUTPUT.PUT_LINE('Questions created by registered users:');

    OPEN cursor_users;
    LOOP
        FETCH cursor_users INTO user_id_value, user_name, user_surname, user_permission;

        EXIT WHEN cursor_users%NOTFOUND;

        IF user_permission = 1  THEN
            SELECT content INTO question_text FROM questions
            WHERE questions.user_id = user_id_value;

            DBMS_OUTPUT.PUT_LINE('Question from ' || user_name || ' ' || user_surname || ':');
            DBMS_OUTPUT.PUT_LINE(question_text);

        end if;

    end loop;

    EXCEPTION WHEN TOO_MANY_ROWS THEN
    BEGIN
        DBMS_OUTPUT.PUT_LINE('User ' || user_name || ' ' || user_surname ||' has multiple questions, quite annoying :(');
    END;
end;

BEGIN registered_users_questions; END;

---DATABASE SEEDS
-----------------------------

--BROKERS
INSERT INTO BROKERS (NAME, SURNAME, PHONE, LOGIN, PASSWORD, PHOTO, LANGUAGE)
VALUES ('Jsem', 'Jednorožec', '777777777', 'weirdChamp', 'better', null, 'zemiak');

INSERT INTO BROKERS (NAME, SURNAME, PHONE, LOGIN, PASSWORD, PHOTO, LANGUAGE)
VALUES ('Miško', 'Pažitka', '+420999123123', 'kek', 'tipFedora', null, 'magyarom');

INSERT INTO BROKERS (NAME, SURNAME, PHONE, LOGIN, PASSWORD, PHOTO, LANGUAGE)
VALUES ('Michal', 'Nevydalo', '123456789', 'pepeLa', 'null', null, 'self');

commit;

--USERS
INSERT INTO USERS (NAME, SURNAME, PHONE, LOGIN, PASSWORD, ADDRESS, EMAIL, PERMISSIONS)
VALUES ('Peter', 'Papuca', '+421777666555', 'null', 'null', 'Zemiakova 32, Brno 61200', 'PEterr@seznam.cz', 0);

INSERT INTO USERS (NAME, SURNAME, PHONE, LOGIN, PASSWORD, ADDRESS, EMAIL, PERMISSIONS)
VALUES ('Jana', 'Jablkova', '555666777', 'jjabko', 'jablko23', 'Zemiakova 32, Brno 61200',
        'jankajabko@centrum.sk', 1);

INSERT INTO USERS (NAME, SURNAME, PHONE, LOGIN, PASSWORD, ADDRESS, EMAIL, PERMISSIONS)
VALUES ('Johana', 'Anahoj', '111222333', 'Ajajaj', '132', 'Okurkova 21, Brno 61300', 'Jojka@gmail.com', 1);

INSERT INTO USERS (NAME, SURNAME, PHONE, LOGIN, PASSWORD, ADDRESS, EMAIL, PERMISSIONS)
VALUES ('Peter', 'Anahoj', '111222343', 'Jojojoj', '132', 'Okurkova 21, Brno 61300', 'Petko@gmail.com', 0);


commit;

--ESTATES
INSERT INTO ESTATES (ADDRESS, STATE, PRICE, BUILDING_TYPE, MANAGING_BROKER_ID)
VALUES ('Okurkova 22, Brno 61300', 'Old', 123.10, 'House', 3);

INSERT INTO ESTATES (ADDRESS, STATE, PRICE, BUILDING_TYPE, MANAGING_BROKER_ID)
VALUES ('Okurkova 54, Brno 61300', 'Very old', 12.10, 'House', 3);

INSERT INTO ESTATES (ADDRESS, STATE, PRICE, BUILDING_TYPE, MANAGING_BROKER_ID)
VALUES ('NiekdevZahranici 321, Zahranicie 1802983', 'New', 4000000, 'Flat', 2);

INSERT INTO ESTATES (ADDRESS, STATE, PRICE, BUILDING_TYPE, MANAGING_BROKER_ID)
VALUES ('Pristav 3, Praha 1', 'Reconstructed', 430000000, 'Houseboat', 1);

INSERT INTO ESTATES (ADDRESS, STATE, PRICE, BUILDING_TYPE, MANAGING_BROKER_ID)
VALUES ('Pristav 34, Praha 1', 'Reconstructed', 430000000, 'Houseboat', 1);

INSERT INTO ESTATES (ADDRESS, STATE, PRICE, BUILDING_TYPE, MANAGING_BROKER_ID)
VALUES ('Pristav 35, Praha 1', 'Reconstructed', 430000000, 'Houseboat', 1);

commit;


--CONTRACTS
INSERT INTO CONTRACTS (CREATION_DATE, AGREED_PRICE, EVAL_STATE, ESTATE_ID, BUYER_ID, SELLER_ID)
VALUES (TO_DATE('1231-03-29 17:24:32', 'YYYY-MM-DD HH24:MI:SS'), 123121.10, 'New', 1, 1, 3);

INSERT INTO CONTRACTS (CREATION_DATE, AGREED_PRICE, EVAL_STATE, ESTATE_ID, BUYER_ID, SELLER_ID)
VALUES (TO_DATE('2022-06-29 17:25:18', 'YYYY-MM-DD HH24:MI:SS'), 321312.12, 'Signed', 1, 2, 1);

INSERT INTO CONTRACTS (CREATION_DATE, AGREED_PRICE, EVAL_STATE, ESTATE_ID, BUYER_ID, SELLER_ID)
VALUES (TO_DATE('2007-03-29 17:25:42', 'YYYY-MM-DD HH24:MI:SS'), 0.01, 'Closed', 3, 3, 2);
commit;

--OFFERS
INSERT INTO OFFERS (AMOUNT, OFFERING_USER_ID, ESTATE_ID)
VALUES (9.00, 2, 1);

INSERT INTO OFFERS (AMOUNT, OFFERING_USER_ID, ESTATE_ID)
VALUES (10000000, 3, 2);

INSERT INTO OFFERS (AMOUNT, OFFERING_USER_ID, ESTATE_ID)
VALUES (312890876, 1, 3);
commit;

--QUESTIONS
INSERT INTO QUESTIONS (CONTENT, BROKER_ID, USER_ID)
VALUES ('Mozem dostat dom za nejake drobne prosim vas, mlady pan, budte laskavy.', 1, 1);

INSERT INTO QUESTIONS (CONTENT, BROKER_ID, USER_ID)
VALUES ('Umrel niekto na tom byte?', 2, 2);

INSERT INTO QUESTIONS (CONTENT, BROKER_ID, USER_ID)
VALUES ('Je mozne mat na byte aj 10 maciek?', 3, 3);
commit;

--VISIT
INSERT INTO VISITS (VISIT_DATE, VISITING_USER_ID, ESTATE_ID)
VALUES (TO_TIMESTAMP('2022-06-29 17:33:15.000000', 'YYYY-MM-DD HH24:MI:SS.FF6'), 3, 3);

INSERT INTO VISITS (VISIT_DATE, VISITING_USER_ID, ESTATE_ID)
VALUES (TO_TIMESTAMP('3022-03-29 17:33:30.000000', 'YYYY-MM-DD HH24:MI:SS.FF6'), 2, 2);

INSERT INTO VISITS (VISIT_DATE, VISITING_USER_ID, ESTATE_ID)
VALUES (TO_TIMESTAMP('2022-03-29 17:33:44.000000', 'YYYY-MM-DD HH24:MI:SS.FF6'), 1, 1);
commit;


/* Selects individual brokers and the amount of estates they are in charge of */
SELECT brokers.user_id, brokers.name AS name, brokers.surname AS surname, COUNT(*) AS estate_count
FROM brokers INNER JOIN estates ON brokers.user_id = estates.managing_broker_id
GROUP BY brokers.user_id, name, surname
ORDER BY estate_count DESC;

/* Selects brokers who do not have any estates with contracts on them */
SELECT * FROM brokers WHERE user_id NOT IN (
    SELECT brokers.user_id
    FROM brokers
             JOIN estates ON estates.managing_broker_id = brokers.user_id
             JOIN contracts ON contracts.estate_id = estates.estate_id
    GROUP BY brokers.user_id, brokers.surname
);

/* Selects brokers who sell an estate for more than 200 */
SELECT * FROM brokers WHERE EXISTS(
    SELECT * FROM estates WHERE estates.price > 200 AND estates.managing_broker_id = brokers.user_id
                                );


-- Permissions---
-----------------

GRANT ALL ON visits TO XKNAPO05;
GRANT ALL ON offers TO XKNAPO05;
GRANT ALL ON contracts TO XKNAPO05;
GRANT ALL ON estates TO XKNAPO05;
GRANT ALL ON questions TO XKNAPO05;
GRANT ALL ON brokers TO XKNAPO05;
GRANT ALL ON users TO XKNAPO05;

GRANT EXECUTE ON estate_prices TO XKNAPO05;

-- view---
--------------

CREATE MATERIALIZED VIEW reconstructed_estates AS
    SELECT address, price, building_type
    FROM estates
    WHERE state = 'Reconstructed';

SELECT * FROM reconstructed_estates;


EXPLAIN PLAN FOR SELECT * FROM brokers WHERE user_id NOT IN (
    SELECT brokers.user_id
    FROM brokers
             JOIN estates ON estates.managing_broker_id = brokers.user_id
             JOIN contracts ON contracts.estate_id = estates.estate_id
    GROUP BY brokers.user_id, brokers.surname
);
SELECT * FROM TABLE ( DBMS_XPLAN.display );

CREATE INDEX "managing_broker_id" on estates (managing_broker_id);
CREATE INDEX "estate_id" on contracts (estate_id);

EXPLAIN PLAN FOR SELECT * FROM brokers WHERE user_id NOT IN (
    SELECT brokers.user_id
    FROM brokers
             JOIN estates ON estates.managing_broker_id = brokers.user_id
             JOIN contracts ON contracts.estate_id = estates.estate_id
    GROUP BY brokers.user_id, brokers.surname
);
SELECT * FROM TABLE ( DBMS_XPLAN.display );