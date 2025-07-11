create or replace task DEV.HUNTER_TRANSFORM_SCHEMA.LOAD_BI_HUNTER_INCOME_STATEMENT
	warehouse=DEV_BI_WH
	schedule='USING CRON 45 7 * * * America/Denver'
	as CREATE OR REPLACE TABLE DEV.HUNTER_TRANSFORM_SCHEMA.BI_HUNTER_INCOME_STATEMENT AS


SELECT 
    ACCOUNTING_PERIOD                                                              AS ACCOUNTING_PERIOD
    , '\'' || RIGHT(DATE_PART(YEAR, ACCOUNTING_PERIOD),2) || '-' || 
          'Q' || DATE_PART(QUARTER, ACCOUNTING_PERIOD)                             AS ACCOUNTING_QUARTER
    , '\'' || TO_CHAR(ACCOUNTING_PERIOD, 'YY-Mon')                                 AS ACCOUNTING_MONTH
    , YEAR(ACCOUNTING_PERIOD)                                                      AS ACCOUNTING_YEAR
    , LOCATION_ID
    , LOCATION
    , COMPANY
    , SUBSIDIARY_ID
    , SUBSIDIARY
    , DEPARTMENT_ID
    , DEPARTMENT
    , VERTICAL_ID
    , VERTICAL
    , PROJECT_ID
    , PROJECT
    , GL_CLASSIFICATION_ID
    , GL_CLASSIFICATION
    , GL_ACCOUNT_NUMBER
    , CONCAT(GL_ACCOUNT_NUMBER, ' - '
        , NVL(TRIM(REGEXP_SUBSTR(NAME,':([^:]+)',1,1,'e')), NAME))                   AS GL_ACCOUNT
    , NAME
    , HEADER1
    , HEADER2
    , HEADER3
    , HEADER4
    , HEADER1                                                                        AS HIERARCHY_LEVEL_1                              
    , HEADER2                                                                        AS HIERARCHY_LEVEL_2
    , TRIM(left(NAME, len(NAME) - charindex(':', reverse(NAME))))                    AS HIERARCHY_LEVEL_3
    , TRIM(REGEXP_SUBSTR(NAME,':([^:]+)',1,1,'e'))                                   AS HIERARCHY_LEVEL_4
    , SORT_ORDER
    , AMOUNT
    , NVL(AMOUNT - LAG(AMOUNT) OVER (PARTITION BY GL_ACCOUNT, NAME, YEAR(ACCOUNTING_PERIOD) ORDER BY ACCOUNTING_PERIOD ), AMOUNT)  AS MONTHLY_AMOUNT
    , CASE
        WHEN ACCOUNTING_PERIOD < dateadd('quarter', -1, DATE_TRUNC(MONTH, CURRENT_DATE))
            THEN 1
        WHEN DATEADD(MONTH, 3, DATE_TRUNC('quarter', ACCOUNTING_PERIOD)) = DATE_TRUNC(QUARTER, DATE_TRUNC(MONTH, CURRENT_DATE - 15))
            THEN 1 
                ELSE 0 END                                                        AS ACCOUNTING_QUARTER_FILTER
    , CURRENT_TIMESTAMP AS LOAD_DATE
FROM DEV.HUNTER_STAGE_SCHEMA.RPT_INCOME_STATEMENT_STG 
WHERE 1=1
AND TYPE = 'general_ledger_account'
--AND ACCOUNTING_PERIOD >= DATEADD(YEAR, -4, CURRENT_DATE) ---filter in view
--AND ACCOUNTING_PERIOD < DATE_TRUNC(MONTH, CURRENT_DATE)  
AND DATEADD(DAY, 14, DATEADD(MONTH, 1, ACCOUNTING_PERIOD)) < CURRENT_DATE ---Ensure the Statement has been closed for 15 days before showing the period
ORDER BY 1 DESC;