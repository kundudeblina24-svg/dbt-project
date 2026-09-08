-- ============================================================================
-- BOOTSTRAP — run this ONCE before your first dbt run
-- ============================================================================
-- Creates everything the dbt project reads from:
--   * the schemas
--   * a Unity Catalog VOLUME for raw files
--   * the three source tables, with sample data
--
-- HOW TO RUN: paste into a Databricks SQL editor and hit Run All.
--             Takes about 30 seconds.
--
-- Change `workspace` below if you build into a different catalog.
-- ============================================================================


-- ---------------------------------------------------------------- schemas --
-- dbt creates staging / gold / snapshots itself. These two are for the RAW
-- side, which dbt does not own.

CREATE SCHEMA IF NOT EXISTS workspace.learn_raw
  COMMENT 'Source tables the dbt project reads. dbt does NOT build these.';

CREATE SCHEMA IF NOT EXISTS workspace.bronze
  COMMENT 'Holds the landing volume for file-based ingestion.';


-- ----------------------------------------------------------------- volume --
-- A VOLUME is Unity Catalog storage for FILES rather than tables - CSV, JSON,
-- parquet, images. It is the Free Edition stand-in for an S3 prefix.
--
-- In production this would instead be an EXTERNAL VOLUME:
--   CREATE EXTERNAL VOLUME workspace.bronze.landing
--     LOCATION 's3://acme-lakehouse-prod/landing';
-- which requires a Storage Credential + External Location first.
-- See ENTERPRISE_SETUP.md.

CREATE VOLUME IF NOT EXISTS workspace.bronze.landing
  COMMENT 'Raw file landing zone. Stands in for an S3 prefix.';


-- --------------------------------------------------------------- sources ---
-- Deliberately small and readable. Note the planted defects - they are what
-- make the tests interesting:
--   * customer 9 has NO EMAIL        -> not_null test WARNS
--   * order 115 -> customer 99       -> relationships test WARNS (99 does not exist)
--   * payment 9006 is NEGATIVE       -> a refund; amounts stay signed on purpose

CREATE OR REPLACE TABLE workspace.learn_raw.customers AS
SELECT * FROM VALUES
  (1,'Amara','Okafor','amara.okafor@example.com',DATE'2025-01-14','NG'),
  (2,'Petra','Novak','petra.novak@example.com',DATE'2025-01-22','CZ'),
  (3,'Luis','Ferreira','luis.ferreira@example.com',DATE'2025-02-03','BR'),
  (4,'Mei','Tanaka','mei.tanaka@example.com',DATE'2025-02-11','JP'),
  (5,'Ravi','Iyer','ravi.iyer@example.com',DATE'2025-02-27','IN'),
  (6,'Sofia','Rossi','sofia.rossi@example.com',DATE'2025-03-05','IT'),
  (7,'Jonas','Berg','jonas.berg@example.com',DATE'2025-03-19','SE'),
  (8,'Nadia','Haddad','nadia.haddad@example.com',DATE'2025-04-02','MA'),
  (9,'Tom','Whitfield',NULL,DATE'2025-04-15','GB'),          -- no email, on purpose
  (10,'Elena','Petrova','elena.petrova@example.com',DATE'2025-05-08','BG')
AS t(customer_id, first_name, last_name, email, signup_date, country_code);


CREATE OR REPLACE TABLE workspace.learn_raw.orders AS
SELECT *, current_timestamp() AS _loaded_at FROM VALUES
  (101,1,DATE'2025-03-01','delivered'), (102,1,DATE'2025-04-12','delivered'),
  (103,2,DATE'2025-03-14','shipped'),   (104,3,DATE'2025-03-22','delivered'),
  (105,3,DATE'2025-05-02','returned'),  (106,4,DATE'2025-04-01','delivered'),
  (107,5,DATE'2025-04-09','placed'),    (108,5,DATE'2025-05-19','delivered'),
  (109,6,DATE'2025-04-25','cancelled'), (110,7,DATE'2025-05-03','delivered'),
  (111,1,DATE'2025-05-27','shipped'),   (112,8,DATE'2025-05-30','placed'),
  (113,10,DATE'2025-06-04','delivered'),(114,3,DATE'2025-06-11','delivered'),
  (115,99,DATE'2025-06-15','delivered')          -- customer 99 does not exist
AS t(order_id, customer_id, order_date, order_status);


CREATE OR REPLACE TABLE workspace.learn_raw.payments AS
SELECT *, current_timestamp() AS _loaded_at FROM VALUES
  (9001,101,'card',4250,DATE'2025-03-01'),
  (9002,102,'card',11800,DATE'2025-04-12'),
  (9003,103,'paypal',2999,DATE'2025-03-14'),
  (9004,104,'card',7600,DATE'2025-03-22'),
  (9005,105,'card',5400,DATE'2025-05-02'),
  (9006,105,'card',-5400,DATE'2025-05-09'),      -- refund: NEGATIVE on purpose
  (9007,106,'bank_transfer',23000,DATE'2025-04-01'),
  (9008,108,'card',3125,DATE'2025-05-19'),
  (9009,110,'paypal',8899,DATE'2025-05-03'),
  (9010,111,'card',6400,DATE'2025-05-27'),
  (9011,113,'card',15250,DATE'2025-06-04'),
  (9012,114,'wallet',4799,DATE'2025-06-11'),
  (9013,115,'card',9999,DATE'2025-06-15')
AS t(payment_id, order_id, payment_method, amount_cents, paid_at);
-- amounts are in CENTS (integers). Storing money as a float is how you end up
-- with 0.30000000000000004. The cents_to_dollars macro converts.


-- ----------------------------------------------------------------- check ---
SELECT 'customers' AS tbl, COUNT(*) AS rows FROM workspace.learn_raw.customers
UNION ALL SELECT 'orders',   COUNT(*) FROM workspace.learn_raw.orders
UNION ALL SELECT 'payments', COUNT(*) FROM workspace.learn_raw.payments;
-- expect 10 / 15 / 13


-- ============================================================================
-- NEXT
--   1. python setup/02_seed_volume.py     (only needed for the streaming model)
--   2. cp .env.example .env  &&  source env.sh
--   3. dbt debug
--   4. dbt build
-- ============================================================================
