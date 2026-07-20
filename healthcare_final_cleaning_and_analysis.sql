-- ================================================================
-- HEALTHCARE FINAL SIMULATION, SQL CLEANING, VALIDATION & ANALYSIS
-- ================================================================
-- Author:  Eric        Partner: Wil (Power BI build)
-- Tool:    DB Browser for SQLite
-- Dataset: modified_healthcare_dataset.csv (Eduardo Licea), 55,500 rows, 16 columns
--
-- Pipeline stages owned in this file (per The Analysis Playbook):
--   PROFILE  ->  CLEAN  ->  EXPLORE / CALCULATE
-- Model + visualize is Power BI (Wil). There is no live database connection in
-- this environment, so the bridge to Power BI is a manual clean-CSV export
-- (see Section 5). Same stage order, one manual export between clean and visualize.
--
-- ETL framing: EXTRACT = import the CSV. TRANSFORM = Sections 2-5 below.
-- LOAD = export the analysis-ready table and pull it into Power BI.
--
-- HOW TO RUN (DB Browser for SQLite):
--   1. File > Import > Table from CSV file. Name the table exactly:  healthcare_raw
--      - CHECK "Column names in first line"  (or your headers become field1, field2...)
--      - Field separator: comma   Quote: "   Encoding: UTF-8
--      - Trim fields: OFF. Preserve imported text for the audit baseline instead of silently
--        changing it during import. Sections 2.2 and 2.2b check blanks and padded whitespace.
--      - Leave "detect types" off when a text-preserving import is required. The current
--        database was imported with numeric types inferred; Sections 2.1 and 2.1b document
--        the actual storage classes, and the clean transformation CASTs explicitly.
--   2. File > Write Changes (Ctrl+S) to save the import to the .db file before you query it.
--   3. Execute SQL tab: run ONE query at a time. Highlight the query, then Play.
--      With multiple queries in the box, DB Browser only reliably runs the highlighted one.
--      If a query errors with "no such table: healthcare_raw", the import above has not run
--      yet, do step 1 first, then everything downstream works.
--   4. Never UPDATE or DELETE healthcare_raw. Every fix happens on a copy, so the raw
--      table stays available for auditing.
--
-- ----------------------------------------------------------------
-- DATA NOTES: quirks reviewed during the completed Section 2 profiling.
-- Keep the validation notes with this script as the evidence record.
-- ----------------------------------------------------------------
--  * No ID column ships in the file, and Name is not unique, so Section 3 mints a
--    surrogate key (encounter_id) from SQLite's rowid.
--  * Depending on the import setting, columns arrive as text or as typed numbers. The
--    script casts explicitly either way, and range checks cast first because a text
--    MIN/MAX sorts lexically, where "10000" reads as smaller than "9".
--  * Length of Stay is a derived field. Section 2.7 checks it against Discharge Date minus
--    Date of Admission before trusting it. Document it as calculated, not source data.
--  * "Alzheimer's" uses a curly apostrophe (Unicode U+2019), not a straight one, so an
--    exact filter with a normal apostrophe returns nothing. Copy the value from the data.
--  * Verified Admission Type values: Emergency, Elective, Urgent, Routine.
-- ================================================================


-- ================================================================
-- SECTION 1, CONFIRM THE IMPORT (Extract)
-- ================================================================

-- 1.1 Peek at the raw table. First move on any table: confirm the headers are real
--     names (not field1/field2) and the import worked before building on it.
SELECT *
FROM healthcare_raw
LIMIT 10;

-- 1.2 Baseline row count. Official result: 55,500. This is the "before" number the
--     post-cleaning count must reconcile against.
SELECT COUNT(*) AS raw_row_count
FROM healthcare_raw;

-- 1.3 Confirm the imported schema.
PRAGMA table_info(healthcare_raw);


-- ================================================================
-- SECTION 2, PROFILE BEFORE CLEANING (Look)
-- Understand what you are holding before changing anything.
-- ================================================================

-- 2.1 Confirm how the import stored one representative row. Official result: Age integer,
--     Billing real, Room integer, LOS integer, Admission Date text. The clean copy still
--     casts explicitly for repeatability and semantic handling.
SELECT
    typeof("Age")               AS age_stored_type,
    typeof("Billing Amount")    AS billing_stored_type,
    typeof("Room Number")       AS room_stored_type,
    typeof("Length of Stay")    AS los_stored_type,
    typeof("Date of Admission") AS admission_date_stored_type
FROM healthcare_raw
LIMIT 1;

-- 2.1b Full-column storage-class distribution. Official result: one storage class per
--      inspected column across all 55,500 rows; no mixed-type rows.
SELECT
    'Age' AS column_name,
    typeof("Age") AS storage_type,
    COUNT(*) AS rows
FROM healthcare_raw
GROUP BY typeof("Age")

UNION ALL

SELECT
    'Billing Amount',
    typeof("Billing Amount"),
    COUNT(*)
FROM healthcare_raw
GROUP BY typeof("Billing Amount")

UNION ALL

SELECT
    'Room Number',
    typeof("Room Number"),
    COUNT(*)
FROM healthcare_raw
GROUP BY typeof("Room Number")

UNION ALL

SELECT
    'Length of Stay',
    typeof("Length of Stay"),
    COUNT(*)
FROM healthcare_raw
GROUP BY typeof("Length of Stay")

UNION ALL

SELECT
    'Date of Admission',
    typeof("Date of Admission"),
    COUNT(*)
FROM healthcare_raw
GROUP BY typeof("Date of Admission")

ORDER BY column_name, rows DESC;

-- 2.2 Missing or blank values across all 16 columns. TRIM first, then test NULL or empty,
--     so a cell holding only spaces is caught (IS NULL alone misses it).
--     Official result: all 16 counters are 0; no imputation required.
SELECT
    COUNT(*) AS total_rows,
    SUM(CASE WHEN "Name"               IS NULL OR TRIM("Name")               = '' THEN 1 ELSE 0 END) AS missing_name,
    SUM(CASE WHEN TRIM(CAST("Age" AS TEXT))            = '' OR "Age"            IS NULL THEN 1 ELSE 0 END) AS missing_age,
    SUM(CASE WHEN "Gender"             IS NULL OR TRIM("Gender")             = '' THEN 1 ELSE 0 END) AS missing_gender,
    SUM(CASE WHEN "Blood Type"         IS NULL OR TRIM("Blood Type")         = '' THEN 1 ELSE 0 END) AS missing_blood_type,
    SUM(CASE WHEN "Medical Condition"  IS NULL OR TRIM("Medical Condition")  = '' THEN 1 ELSE 0 END) AS missing_medical_condition,
    SUM(CASE WHEN "Date of Admission"  IS NULL OR TRIM("Date of Admission")  = '' THEN 1 ELSE 0 END) AS missing_admission_date,
    SUM(CASE WHEN "Doctor"             IS NULL OR TRIM("Doctor")             = '' THEN 1 ELSE 0 END) AS missing_doctor,
    SUM(CASE WHEN "Hospital"           IS NULL OR TRIM("Hospital")           = '' THEN 1 ELSE 0 END) AS missing_hospital,
    SUM(CASE WHEN "Insurance Provider" IS NULL OR TRIM("Insurance Provider") = '' THEN 1 ELSE 0 END) AS missing_insurance_provider,
    SUM(CASE WHEN TRIM(CAST("Billing Amount" AS TEXT)) = '' OR "Billing Amount" IS NULL THEN 1 ELSE 0 END) AS missing_billing_amount,
    SUM(CASE WHEN TRIM(CAST("Room Number" AS TEXT))    = '' OR "Room Number"    IS NULL THEN 1 ELSE 0 END) AS missing_room_number,
    SUM(CASE WHEN "Admission Type"     IS NULL OR TRIM("Admission Type")     = '' THEN 1 ELSE 0 END) AS missing_admission_type,
    SUM(CASE WHEN "Discharge Date"     IS NULL OR TRIM("Discharge Date")     = '' THEN 1 ELSE 0 END) AS missing_discharge_date,
    SUM(CASE WHEN "Medication"         IS NULL OR TRIM("Medication")         = '' THEN 1 ELSE 0 END) AS missing_medication,
    SUM(CASE WHEN "Test Results"       IS NULL OR TRIM("Test Results")       = '' THEN 1 ELSE 0 END) AS missing_test_results,
    SUM(CASE WHEN TRIM(CAST("Length of Stay" AS TEXT)) = '' OR "Length of Stay" IS NULL THEN 1 ELSE 0 END) AS missing_length_of_stay
FROM healthcare_raw;
-- Result: every column returns 0. Missing rate is 0.00% on all fields, so no imputation.

-- 2.2b Leading/trailing whitespace in non-empty text values. Official result: all 12
--      counters are 0. TRIM remains in Section 3 as defensive, idempotent standardization.
SELECT
    SUM(CASE WHEN "Name" IS NOT NULL
                  AND "Name" <> TRIM("Name")
             THEN 1 ELSE 0 END) AS padded_name,
    SUM(CASE WHEN "Gender" IS NOT NULL
                  AND "Gender" <> TRIM("Gender")
             THEN 1 ELSE 0 END) AS padded_gender,
    SUM(CASE WHEN "Blood Type" IS NOT NULL
                  AND "Blood Type" <> TRIM("Blood Type")
             THEN 1 ELSE 0 END) AS padded_blood_type,
    SUM(CASE WHEN "Medical Condition" IS NOT NULL
                  AND "Medical Condition" <> TRIM("Medical Condition")
             THEN 1 ELSE 0 END) AS padded_medical_condition,
    SUM(CASE WHEN "Date of Admission" IS NOT NULL
                  AND "Date of Admission" <> TRIM("Date of Admission")
             THEN 1 ELSE 0 END) AS padded_admission_date,
    SUM(CASE WHEN "Doctor" IS NOT NULL
                  AND "Doctor" <> TRIM("Doctor")
             THEN 1 ELSE 0 END) AS padded_doctor,
    SUM(CASE WHEN "Hospital" IS NOT NULL
                  AND "Hospital" <> TRIM("Hospital")
             THEN 1 ELSE 0 END) AS padded_hospital,
    SUM(CASE WHEN "Insurance Provider" IS NOT NULL
                  AND "Insurance Provider" <> TRIM("Insurance Provider")
             THEN 1 ELSE 0 END) AS padded_insurance_provider,
    SUM(CASE WHEN "Admission Type" IS NOT NULL
                  AND "Admission Type" <> TRIM("Admission Type")
             THEN 1 ELSE 0 END) AS padded_admission_type,
    SUM(CASE WHEN "Discharge Date" IS NOT NULL
                  AND "Discharge Date" <> TRIM("Discharge Date")
             THEN 1 ELSE 0 END) AS padded_discharge_date,
    SUM(CASE WHEN "Medication" IS NOT NULL
                  AND "Medication" <> TRIM("Medication")
             THEN 1 ELSE 0 END) AS padded_medication,
    SUM(CASE WHEN "Test Results" IS NOT NULL
                  AND "Test Results" <> TRIM("Test Results")
             THEN 1 ELSE 0 END) AS padded_test_results
FROM healthcare_raw;

-- 2.3 Review each categorical field and its frequency. This identifies apparent spelling,
--     capitalization, blank, and duplicate-label variants and reconciles category totals.
SELECT "Gender"            AS value, COUNT(*) AS rows FROM healthcare_raw GROUP BY "Gender"            ORDER BY rows DESC;
SELECT "Blood Type"        AS value, COUNT(*) AS rows FROM healthcare_raw GROUP BY "Blood Type"        ORDER BY rows DESC;
SELECT "Medical Condition" AS value, COUNT(*) AS rows FROM healthcare_raw GROUP BY "Medical Condition" ORDER BY rows DESC;
SELECT "Admission Type"    AS value, COUNT(*) AS rows FROM healthcare_raw GROUP BY "Admission Type"    ORDER BY rows DESC;
SELECT "Test Results"      AS value, COUNT(*) AS rows FROM healthcare_raw GROUP BY "Test Results"      ORDER BY rows DESC;
SELECT "Medication"        AS value, COUNT(*) AS rows FROM healthcare_raw GROUP BY "Medication"        ORDER BY rows DESC;
SELECT "Hospital"          AS value, COUNT(*) AS rows FROM healthcare_raw GROUP BY "Hospital"          ORDER BY rows DESC;
SELECT "Insurance Provider" AS value, COUNT(*) AS rows FROM healthcare_raw GROUP BY "Insurance Provider" ORDER BY rows DESC;

-- 2.4 Numeric range checks. CAST first so MIN/MAX compare as numbers, not text. These
--     aggregates establish boundaries; they do not prove every source value is valid.
SELECT
    MIN(CAST("Age" AS INTEGER))            AS minimum_age,
    MAX(CAST("Age" AS INTEGER))            AS maximum_age,
    MIN(CAST("Billing Amount" AS REAL))    AS minimum_billing,
    MAX(CAST("Billing Amount" AS REAL))    AS maximum_billing,
    MIN(CAST("Room Number" AS INTEGER))    AS minimum_room,
    MAX(CAST("Room Number" AS INTEGER))    AS maximum_room,
    MIN(CAST("Length of Stay" AS INTEGER)) AS minimum_source_los,
    MAX(CAST("Length of Stay" AS INTEGER)) AS maximum_source_los
FROM healthcare_raw;

-- 2.5 Flag impossible or suspicious numeric values. Flag, do not auto-delete.
--     Official result: 0 rows returned.
SELECT *
FROM healthcare_raw
WHERE CAST("Age" AS INTEGER) < 0
   OR CAST("Age" AS INTEGER) > 120
   OR CAST("Billing Amount" AS REAL) < 0
   OR CAST("Room Number" AS INTEGER) <= 0
   OR CAST("Length of Stay" AS INTEGER) < 0;

-- 2.6 Date validity and range. A valid ISO date parses and returns the same YYYY-MM-DD
--     value. Official row-level format result: 0 exceptions.
SELECT
    MIN(date("Date of Admission")) AS earliest_admission,
    MAX(date("Date of Admission")) AS latest_admission,
    MIN(date("Discharge Date"))    AS earliest_discharge,
    MAX(date("Discharge Date"))    AS latest_discharge
FROM healthcare_raw;

SELECT *
FROM healthcare_raw
WHERE date(TRIM("Date of Admission")) IS NULL
   OR date(TRIM("Date of Admission")) <> TRIM("Date of Admission")
   OR date(TRIM("Discharge Date"))    IS NULL
   OR date(TRIM("Discharge Date"))    <> TRIM("Discharge Date");

-- Column-against-column check: discharge cannot precede admission. Official result: 0.
SELECT COUNT(*) AS discharge_before_admission_rows
FROM healthcare_raw
WHERE julianday("Discharge Date") < julianday("Date of Admission");

-- 2.7 Validate the DERIVED Length of Stay against its formula. julianday() turns each date
--     into a number so the subtraction returns a day count; compare that to the stored value.
--     Official result: matching = 55,500 and mismatched = 0. The writeup records LOS as
--     a supplied derived field validated against the two dates.
SELECT
    COUNT(*) AS total_rows,
    SUM(CASE WHEN CAST("Length of Stay" AS INTEGER)
                  = CAST(julianday("Discharge Date") - julianday("Date of Admission") AS INTEGER)
             THEN 1 ELSE 0 END) AS matching_los_rows,
    SUM(CASE WHEN CAST("Length of Stay" AS INTEGER)
                  <> CAST(julianday("Discharge Date") - julianday("Date of Admission") AS INTEGER)
             THEN 1 ELSE 0 END) AS mismatched_los_rows
FROM healthcare_raw;

-- Inspect any mismatches. Official result: 0 rows. If a future import returns records,
-- rebuild LOS from the two dates rather than trusting the supplied value.
SELECT
    rowid AS encounter_id,
    "Date of Admission",
    "Discharge Date",
    "Length of Stay" AS source_los,
    CAST(julianday("Discharge Date") - julianday("Date of Admission") AS INTEGER) AS calculated_los
FROM healthcare_raw
WHERE CAST("Length of Stay" AS INTEGER)
      <> CAST(julianday("Discharge Date") - julianday("Date of Admission") AS INTEGER)
LIMIT 100;

-- 2.8 Exact-duplicate check against the grain. The grain is one row per admission, so two
--     rows sharing a name can still be two real encounters, a single field is never the
--     test. Group by every column and keep only groups that repeat. Official result: 0 rows.
SELECT
    "Name", "Age", "Gender", "Blood Type", "Medical Condition", "Date of Admission",
    "Doctor", "Hospital", "Insurance Provider", "Billing Amount", "Room Number",
    "Admission Type", "Discharge Date", "Medication", "Test Results", "Length of Stay",
    COUNT(*) AS copies
FROM healthcare_raw
GROUP BY 1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16
HAVING COUNT(*) > 1
ORDER BY copies DESC;

-- 2.9 Outlier read. An outlier is not automatically an error, so investigate before removing.
--     Base SQLite has no standard-deviation or percentile function, so a Z-score or an IQR
--     bound cannot be computed here, sort the column high/low and read the extreme rows to
--     catch anything implausible. The formal IQR/Z-score and the box plot run in Power BI,
--     where the functions and the chart exist.
SELECT rowid AS encounter_id, "Medical Condition", "Admission Type", "Billing Amount", "Length of Stay"
FROM healthcare_raw
ORDER BY CAST("Billing Amount" AS REAL) DESC
LIMIT 20;

SELECT rowid AS encounter_id, "Medical Condition", "Admission Type", "Billing Amount", "Length of Stay"
FROM healthcare_raw
ORDER BY CAST("Length of Stay" AS INTEGER) DESC
LIMIT 20;


-- ================================================================
-- SECTION 3, CREATE THE FULL CLEAN COPY (Transform)
-- Run only after reviewing the profiling above. Raw table stays untouched.
-- Every source row is kept. Headers are aliased to lowercase_underscore once, here, so
-- later queries never quote a column again and the names carry into Power BI cleanly.
-- ================================================================

DROP TABLE IF EXISTS healthcare_clean;

CREATE TABLE healthcare_clean AS
WITH standardized AS (
    SELECT
        -- Snapshot surrogate key. No ID ships in the file and Name is not unique, so rowid
        -- identifies each row in this imported snapshot. It is not a durable real-world ID:
        -- rebuilding or reordering the raw table can change it. Once copied here it is
        -- suitable for this project's Power BI handoff and integer relationships.
        rowid                                              AS encounter_id,
        NULLIF(TRIM("Name"), '')                           AS name,
        CAST(NULLIF(TRIM(CAST("Age" AS TEXT)), '') AS INTEGER) AS age,
        NULLIF(TRIM("Gender"), '')                         AS gender,
        NULLIF(TRIM("Blood Type"), '')                     AS blood_type,
        NULLIF(TRIM("Medical Condition"), '')              AS medical_condition,
        date(NULLIF(TRIM("Date of Admission"), ''))        AS admission_date,
        NULLIF(TRIM("Doctor"), '')                         AS doctor,
        NULLIF(TRIM("Hospital"), '')                       AS hospital,
        NULLIF(TRIM("Insurance Provider"), '')             AS insurance_provider,
        -- Keep the source's numeric precision as REAL so reconciliation in 4.2 is zero;
        -- round only for display. A production financial database would use an exact decimal
        -- type (or integer minor units), but SQLite uses dynamic typing.
        CAST(NULLIF(TRIM(CAST("Billing Amount" AS TEXT)), '') AS REAL) AS billing_amount,
        -- Room number is an identifier, not a quantity you do math on, so keep it as text.
        NULLIF(TRIM(CAST("Room Number" AS TEXT)), '')      AS room_number,
        NULLIF(TRIM("Admission Type"), '')                 AS admission_type,
        date(NULLIF(TRIM("Discharge Date"), ''))           AS discharge_date,
        -- Preserve the source label for brand/generic comparison in Power BI.
        NULLIF(TRIM("Medication"), '')                     AS medication_source,
        -- Also provide a normalized active-ingredient label so Tamiflu and Oseltamivir
        -- can be grouped together when the analysis calls for it. Raw remains unchanged.
        CASE
            WHEN TRIM("Medication") = 'Tamiflu' THEN 'Oseltamivir'
            ELSE NULLIF(TRIM("Medication"), '')
        END                                                AS medication,
        NULLIF(TRIM("Test Results"), '')                   AS test_results,
        CAST(NULLIF(TRIM(CAST("Length of Stay" AS TEXT)), '') AS INTEGER) AS source_length_of_stay
    FROM healthcare_raw
),
calculated AS (
    SELECT
        *,
        -- Rebuild length of stay from the two dates so the number is defensible.
        CASE
            WHEN admission_date IS NOT NULL
             AND discharge_date IS NOT NULL
             AND julianday(discharge_date) >= julianday(admission_date)
            THEN CAST(julianday(discharge_date) - julianday(admission_date) AS INTEGER)
            ELSE NULL
        END AS calculated_length_of_stay
    FROM standardized
)
SELECT
    *,
    -- Use the rebuilt value; fall back to the supplied one only if a date is missing.
    -- Section 2.7 officially verified agreement across all 55,500 source rows.
    COALESCE(calculated_length_of_stay, source_length_of_stay) AS length_of_stay,
    -- Derived analysis fields:
    CASE
        WHEN COALESCE(calculated_length_of_stay, source_length_of_stay) > 0
        THEN ROUND(billing_amount / COALESCE(calculated_length_of_stay, source_length_of_stay), 2)
        ELSE NULL
    END AS billing_per_day,
    CASE WHEN test_results = 'Abnormal' THEN 1 ELSE 0 END AS abnormal_test_flag,
    -- Audit flag: does the supplied LOS match the dates? Section 4 must confirm 1 per row.
    CASE WHEN source_length_of_stay = calculated_length_of_stay THEN 1 ELSE 0 END AS los_matches_dates_flag,
    -- Date parts for time-series slicing in Power BI.
    CAST(strftime('%Y', admission_date) AS INTEGER) AS admission_year,
    strftime('%Y-%m', admission_date)               AS admission_month
FROM calculated;


-- ================================================================
-- SECTION 4, VALIDATE THE CLEAN TABLE
-- Cleaning can drop rows or distort values silently. Prove neither happened.
-- ================================================================

-- 4.1 Row reconciliation. Validation target: row difference = 0.
SELECT
    (SELECT COUNT(*) FROM healthcare_raw)   AS raw_rows,
    (SELECT COUNT(*) FROM healthcare_clean) AS clean_rows,
    (SELECT COUNT(*) FROM healthcare_raw) - (SELECT COUNT(*) FROM healthcare_clean) AS row_difference;

-- 4.2 Key-total reconciliation. A row count proves rows survived; it does not prove the
--     values inside survived. Sum billing before and after; validation target = 0.00,
--     because billing is stored at full precision (no rounding applied to the stored value).
SELECT
    ROUND((SELECT SUM(CAST("Billing Amount" AS REAL))
           FROM healthcare_raw), 2) AS raw_total_billing,
    ROUND((SELECT SUM(billing_amount)
           FROM healthcare_clean), 2) AS clean_total_billing,
    ROUND(
        (SELECT SUM(CAST("Billing Amount" AS REAL))
         FROM healthcare_raw)
        -
        (SELECT SUM(billing_amount)
         FROM healthcare_clean),
        2
    ) AS billing_difference;

-- 4.3 Confirm ranges and the calculated fields after cleaning.
SELECT
    COUNT(*)                    AS clean_rows,
    COUNT(DISTINCT encounter_id) AS unique_encounter_ids,
    MIN(age)                    AS minimum_age,
    MAX(age)                    AS maximum_age,
    MIN(admission_date)         AS earliest_admission,
    MAX(admission_date)         AS latest_admission,
    MIN(billing_amount)         AS minimum_billing,
    MAX(billing_amount)         AS maximum_billing,
    MIN(length_of_stay)         AS minimum_los,
    MAX(length_of_stay)         AS maximum_los,
    SUM(CASE WHEN los_matches_dates_flag = 0 THEN 1 ELSE 0 END) AS los_mismatch_rows
FROM healthcare_clean;

-- 4.4 Final quality exceptions. Validation target: 0 rows.
SELECT *
FROM healthcare_clean
WHERE encounter_id IS NULL
   OR medical_condition IS NULL
   OR admission_type IS NULL
   OR admission_date IS NULL
   OR discharge_date IS NULL
   OR billing_amount IS NULL
   OR billing_amount < 0
   OR length_of_stay IS NULL
   OR length_of_stay < 0;

-- 4.5 Validate both medication grains. Validation targets: source Tamiflu = 2,326;
--     source Oseltamivir = 2,329; normalized Tamiflu = 0; normalized Oseltamivir = 4,655;
--     Zanamivir remains unchanged at 2,391.
SELECT
    SUM(CASE WHEN medication_source = 'Tamiflu'     THEN 1 ELSE 0 END) AS source_tamiflu_rows,
    SUM(CASE WHEN medication_source = 'Oseltamivir' THEN 1 ELSE 0 END) AS source_oseltamivir_rows,
    SUM(CASE WHEN medication = 'Tamiflu'            THEN 1 ELSE 0 END) AS normalized_tamiflu_rows,
    SUM(CASE WHEN medication = 'Oseltamivir'        THEN 1 ELSE 0 END) AS normalized_oseltamivir_rows,
    SUM(CASE WHEN medication_source = 'Zanamivir'
              AND medication = 'Zanamivir'          THEN 1 ELSE 0 END) AS unchanged_zanamivir_rows
FROM healthcare_clean;


-- ================================================================
-- SECTION 5, BUILD THE LEAN ANALYSIS-READY HANDOFF (Load-ready)
-- Keep healthcare_clean as the full audited copy. This lean table is what Wil imports into
-- Power BI: only the fields the analysis needs, plus the derived fields, with direct
-- identifiers (name, doctor, room_number) dropped.
--
-- EXPORT after this runs:  right-click healthcare_analysis_ready in the Database Structure
-- tab > Export > Table to CSV. Name it healthcare_analysis_ready.csv. That CSV is the bridge
-- into Power BI (Get Data > Text/CSV > Transform).
-- ================================================================

DROP TABLE IF EXISTS healthcare_analysis_ready;

CREATE TABLE healthcare_analysis_ready AS
SELECT
    encounter_id,
    age,
    gender,
    blood_type,          -- optional demographic slicer
    medical_condition,
    admission_date,
    admission_year,
    admission_month,
    hospital,            -- available as a filter; analytical importance is not assumed
    insurance_provider,  -- available as a filter; analytical importance is not assumed
    billing_amount,
    admission_type,
    discharge_date,
    medication_source,    -- original label for brand/generic comparison
    medication,           -- normalized active-ingredient label
    test_results,
    length_of_stay,
    billing_per_day,
    abnormal_test_flag
FROM healthcare_clean
WHERE encounter_id IS NOT NULL
  AND medical_condition IS NOT NULL
  AND admission_type IS NOT NULL
  AND admission_date IS NOT NULL
  AND discharge_date IS NOT NULL
  AND billing_amount IS NOT NULL
  AND billing_amount >= 0
  AND length_of_stay IS NOT NULL
  AND length_of_stay >= 0;

-- Handoff reconciliation. Validation target: excluded_quality_rows = 0.
SELECT
    (SELECT COUNT(*) FROM healthcare_clean)          AS full_clean_rows,
    (SELECT COUNT(*) FROM healthcare_analysis_ready) AS analysis_ready_rows,
    (SELECT COUNT(*) FROM healthcare_clean)
      - (SELECT COUNT(*) FROM healthcare_analysis_ready) AS excluded_quality_rows;

-- 5.1 Confirm the final handoff schema and both medication grains. Validation targets:
--     19 columns; 55,500 rows; source Tamiflu = 2,326; source Oseltamivir = 2,329;
--     normalized Tamiflu = 0; normalized Oseltamivir = 4,655; Zanamivir = 2,391.
SELECT
    (SELECT COUNT(*)
     FROM pragma_table_info('healthcare_analysis_ready')) AS column_count,
    COUNT(*) AS analysis_ready_rows,
    SUM(CASE WHEN medication_source = 'Tamiflu'
             THEN 1 ELSE 0 END) AS source_tamiflu_rows,
    SUM(CASE WHEN medication_source = 'Oseltamivir'
             THEN 1 ELSE 0 END) AS source_oseltamivir_rows,
    SUM(CASE WHEN medication = 'Tamiflu'
             THEN 1 ELSE 0 END) AS normalized_tamiflu_rows,
    SUM(CASE WHEN medication = 'Oseltamivir'
             THEN 1 ELSE 0 END) AS normalized_oseltamivir_rows,
    SUM(CASE WHEN medication_source = 'Zanamivir'
              AND medication = 'Zanamivir'
             THEN 1 ELSE 0 END) AS unchanged_zanamivir_rows
FROM healthcare_analysis_ready;


-- ================================================================
-- SECTION 6, PARTNER-READY ANALYSIS QUERIES (Explore / Calculate)
-- Selected set for the length-of-stay + billing dashboard direction: context KPIs first,
-- then condition/admission comparisons, with test results and medication as supporting
-- factors. Each query is standalone and can be reproduced as a Power BI measure or visual.
-- Use these SQL results as the validation baseline for the report and dashboard.
-- ================================================================

-- Dashboard KPI summary. One row for partner validation before visuals are built.
SELECT
    COUNT(*)                         AS total_admissions,
    MIN(admission_date)              AS earliest_admission,
    MAX(discharge_date)              AS latest_discharge,
    ROUND(AVG(length_of_stay), 2)    AS average_length_of_stay_days,
    ROUND(SUM(billing_amount), 2)    AS total_billing,
    ROUND(AVG(billing_amount), 2)    AS average_billing
FROM healthcare_analysis_ready;

-- Context: admissions over time by admission type (feeds a trend line). Preserve all rows,
-- but flag the two partial boundary months so Power BI can label or filter them explicitly.
SELECT
    admission_month,
    CASE
        WHEN admission_month IN ('2019-05', '2024-05') THEN 'Partial month'
        ELSE 'Complete month'
    END AS period_status,
    admission_type,
    COUNT(*) AS admissions
FROM healthcare_analysis_ready
GROUP BY admission_month, period_status, admission_type
ORDER BY admission_month, admission_type;

-- Q1. What is the admission-type mix? ("count per admission type, as a share of the whole")
SELECT
    admission_type,
    COUNT(*) AS admissions,
    ROUND(100.0 * COUNT(*) / (SELECT COUNT(*) FROM healthcare_analysis_ready), 2) AS percent_of_admissions
FROM healthcare_analysis_ready
GROUP BY admission_type
ORDER BY admissions DESC;

-- Q2. What is the average length of stay overall?
SELECT
    ROUND(AVG(length_of_stay), 2) AS average_length_of_stay_days
FROM healthcare_analysis_ready;

-- Q3. What are total and average billing overall?
SELECT
    ROUND(SUM(billing_amount), 2) AS total_billing,
    ROUND(AVG(billing_amount), 2) AS average_billing,
    COUNT(*)                      AS admissions
FROM healthcare_analysis_ready;

-- Q4. Which conditions have the longest average length of stay? ("avg LOS per condition")
SELECT
    medical_condition,
    COUNT(*)                      AS admissions,
    ROUND(AVG(length_of_stay), 2) AS average_length_of_stay_days
FROM healthcare_analysis_ready
GROUP BY medical_condition
ORDER BY average_length_of_stay_days DESC;

-- Q5. Which condition + admission-type combinations carry the highest average billing?
SELECT
    medical_condition,
    admission_type,
    COUNT(*)                    AS admissions,
    ROUND(AVG(billing_amount), 2) AS average_billing
FROM healthcare_analysis_ready
GROUP BY medical_condition, admission_type
ORDER BY average_billing DESC;

-- Q6. For the same condition, what is the observed average-billing difference between
--     Emergency and Elective admissions? This controls for condition mix, but it is an
--     association and does not prove admission urgency caused the difference.
WITH condition_comparison AS (
    SELECT
        medical_condition,
        SUM(CASE WHEN admission_type = 'Emergency' THEN 1 ELSE 0 END) AS emergency_admissions,
        SUM(CASE WHEN admission_type = 'Elective'  THEN 1 ELSE 0 END) AS elective_admissions,
        AVG(CASE WHEN admission_type = 'Emergency' THEN billing_amount END) AS emergency_avg_billing,
        AVG(CASE WHEN admission_type = 'Elective'  THEN billing_amount END) AS elective_avg_billing
    FROM healthcare_analysis_ready
    GROUP BY medical_condition
)
SELECT
    medical_condition,
    emergency_admissions,
    elective_admissions,
    ROUND(emergency_avg_billing, 2) AS emergency_avg_billing,
    ROUND(elective_avg_billing, 2)  AS elective_avg_billing,
    ROUND(emergency_avg_billing - elective_avg_billing, 2) AS emergency_billing_difference,
    ROUND(100.0 * (emergency_avg_billing - elective_avg_billing) / NULLIF(elective_avg_billing, 0), 2) AS emergency_billing_difference_percent
FROM condition_comparison
WHERE emergency_admissions > 0
  AND elective_admissions > 0
ORDER BY emergency_billing_difference DESC;

-- Q7. Is a condition's billed amount associated with long stays or high billing per inpatient
--     day? Weighted billing per day = total billing / total inpatient days, which avoids
--     averaging group averages. Billing is not hospital cost, payment, or collected revenue.
WITH condition_metrics AS (
    SELECT
        medical_condition,
        COUNT(*)             AS admissions,
        AVG(length_of_stay)  AS avg_los,
        SUM(billing_amount) / NULLIF(SUM(length_of_stay), 0) AS weighted_billing_per_day,
        AVG(billing_amount)  AS avg_billing
    FROM healthcare_analysis_ready
    GROUP BY medical_condition
),
overall AS (
    SELECT
        AVG(length_of_stay) AS overall_avg_los,
        SUM(billing_amount) / NULLIF(SUM(length_of_stay), 0) AS overall_weighted_billing_per_day
    FROM healthcare_analysis_ready
)
SELECT
    c.medical_condition,
    c.admissions,
    ROUND(c.avg_los, 2)          AS average_los,
    ROUND(c.weighted_billing_per_day, 2) AS weighted_billing_per_day,
    ROUND(c.avg_billing, 2)      AS average_billing,
    CASE
        WHEN c.avg_los > o.overall_avg_los AND c.weighted_billing_per_day <= o.overall_weighted_billing_per_day THEN 'Higher-stay pattern'
        WHEN c.avg_los <= o.overall_avg_los AND c.weighted_billing_per_day > o.overall_weighted_billing_per_day THEN 'Higher billing-per-day pattern'
        WHEN c.avg_los > o.overall_avg_los AND c.weighted_billing_per_day > o.overall_weighted_billing_per_day  THEN 'Higher on both measures'
        ELSE 'Below average on both'
    END AS billing_pattern_category
FROM condition_metrics AS c
CROSS JOIN overall AS o
ORDER BY c.avg_billing DESC;

-- Q8. Billing, stay, and abnormal-test profile by condition. Metrics stay separate, no blended
--     score without agreed weights.
SELECT
    medical_condition,
    COUNT(*)                          AS admissions,
    ROUND(AVG(billing_amount), 2)     AS average_billing,
    ROUND(AVG(length_of_stay), 2)     AS average_length_of_stay,
    ROUND(100.0 * AVG(abnormal_test_flag), 2) AS abnormal_test_rate_percent
FROM healthcare_analysis_ready
GROUP BY medical_condition
ORDER BY average_billing DESC;

-- Q9. Within the same condition, does length of stay differ by normalized medication
--     active ingredient? Shows association, not proof that a medication caused the
--     difference. HAVING keeps only groups big enough to be worth reading (30+ admissions).
SELECT
    medical_condition,
    medication,
    COUNT(*)                      AS admissions,
    ROUND(AVG(length_of_stay), 2) AS average_length_of_stay,
    ROUND(AVG(billing_amount), 2) AS average_billing
FROM healthcare_analysis_ready
GROUP BY medical_condition, medication
HAVING COUNT(*) >= 30
ORDER BY medical_condition, average_length_of_stay DESC;

-- Q10. Top five conditions by volume, then compare their stay and billing to the overall
--      averages. These are descriptive billing/stay profiles, not measures of actual cost.
WITH top_five_conditions AS (
    SELECT medical_condition, COUNT(*) AS admissions
    FROM healthcare_analysis_ready
    GROUP BY medical_condition
    ORDER BY admissions DESC
    LIMIT 5
),
overall AS (
    SELECT AVG(length_of_stay) AS overall_avg_los, AVG(billing_amount) AS overall_avg_billing
    FROM healthcare_analysis_ready
)
SELECT
    h.medical_condition,
    COUNT(*)                      AS admissions,
    ROUND(AVG(h.length_of_stay), 2) AS average_los,
    ROUND(AVG(h.billing_amount), 2) AS average_billing,
    CASE
        WHEN AVG(h.length_of_stay) > o.overall_avg_los AND AVG(h.billing_amount) > o.overall_avg_billing THEN 'Higher stay / higher billing'
        WHEN AVG(h.length_of_stay) <= o.overall_avg_los AND AVG(h.billing_amount) <= o.overall_avg_billing THEN 'Lower stay / lower billing'
        ELSE 'Mixed'
    END AS stay_billing_profile
FROM healthcare_analysis_ready AS h
INNER JOIN top_five_conditions AS t ON h.medical_condition = t.medical_condition
CROSS JOIN overall AS o
GROUP BY h.medical_condition
ORDER BY admissions DESC;

-- End of script.
