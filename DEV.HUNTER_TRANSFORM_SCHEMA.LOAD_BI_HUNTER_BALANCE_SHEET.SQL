create or replace task DEV.HUNTER_TRANSFORM_SCHEMA.LOAD_BI_HUNTER_BALANCE_SHEET
	warehouse=DEV_BI_WH
	schedule='USING CRON 50 7 * * * America/Denver'
	as CREATE OR REPLACE TABLE DEV.HUNTER_TRANSFORM_SCHEMA.BI_HUNTER_BALANCE_SHEET AS


  WITH INCOME AS (      
        SELECT 
             ACCOUNTING_PERIOD
            , SUM(CASE WHEN HEADER1 = 'Revenue' THEN AMOUNT ELSE 0 END) REV_AMOUNT
            , SUM(CASE WHEN HEADER1 = 'Cost of Service' THEN AMOUNT ELSE 0 END) GOGS_AMOUNT
            , (REV_AMOUNT - GOGS_AMOUNT) AS GROSS_MARGIN
            , SUM(CASE WHEN HEADER1 = 'Selling, General and Admin' THEN AMOUNT ELSE 0 END) SGA_AMOUNT
            -- , SUM(CASE WHEN HEADER1 = 'Depreciation' THEN AMOUNT ELSE 0 END) DEPRECIATION_AMOUNT
            , (GROSS_MARGIN - SGA_AMOUNT) AS NET_ORDINARY_INCOME
            , SUM(CASE WHEN HEADER1 = 'Other Income and Expenses' THEN AMOUNT ELSE 0 END) OTHER_EXPENSE_AMOUNT
            --, SUM(CASE WHEN HEADER1 = 'Operating Expenses' THEN AMOUNT ELSE 0 END) OP_EXPENSE_AMOUNT
            --, SUM(CASE WHEN HEADER1 = 'Income Taxes' THEN AMOUNT ELSE 0 END) INCOME_TAXES_AMOUNT
            , (NET_ORDINARY_INCOME - OTHER_EXPENSE_AMOUNT)  AS NET_INCOME
         FROM DEV.HUNTER_TRANSFORM_SCHEMA.BI_HUNTER_INCOME_STATEMENT 
            WHERE 1=1 
             --AND ACCOUNTING_PERIOD = '2024-04-01'
            GROUP BY ACCOUNTING_PERIOD
    ),



    
YTD_INCOME AS (
    SELECT 
          ACCOUNTING_PERIOD
        , YEAR (ACCOUNTING_PERIOD) ACCOUNTING_YEAR
        , DATE_TRUNC(MONTH, LAST_DAY(ACCOUNTING_PERIOD, 'year')) AS LAST_MONTH_OF_YEAR
        , SUM(NET_INCOME) OVER ( ORDER BY ACCOUNTING_PERIOD) AS YTD_NET_INCOME
    FROM INCOME
),





INCOME_DETAILS AS (
        SELECT 
             INC.ACCOUNTING_PERIOD
            , '\'' || RIGHT(DATE_PART(YEAR, INC.ACCOUNTING_PERIOD),2) || '-' ||
                   'Q' || DATE_PART(QUARTER, INC.ACCOUNTING_PERIOD)                     AS ACCOUNTING_QUARTER
            , '\'' || TO_CHAR(INC.ACCOUNTING_PERIOD, 'YY-Mon')                          AS ACCOUNTING_MONTH
            , NULL                                                                  AS SUBSIDIARY
            , NULL AS COMPANY
            , NULL AS LOCATION
            , NULL AS DEPARTMENT
            , NULL AS VERTICAL
            , NULL AS PROJECT
            , NULL AS GL_ACCOUNT_NUMBER
            , 'Net Income Lifetime'                                                 AS GL_ACCOUNT_NAME
            , 'Net Income Lifetime'                                                 AS ACCOUNT_GROUP
            , 'Equity'                                                              AS HIERARCHY_LEVEL_1
            , NULL                                                                  AS HIERARCHY_LEVEL_2
            , NULL                                                                  AS HIERARCHY_LEVEL_3
            , NULL                                                                  AS HIERARCHY_LEVEL_4
            , NULL                                                                  AS HIERARCHY_LEVEL_5
            , NULL                                                                  AS SORT_ORDER
            , YTD_NET_INCOME                                                        AS YTD_AMOUNT
            , NET_INCOME                                                            AS MONTHLY_AMOUNT
            , CASE 
                  WHEN MONTH(INC.ACCOUNTING_PERIOD) IN (3,6,9,12) THEN 1
              ELSE 0 END                                                            AS EOQ_IND -- flag for last month of quarter
            , CASE
                WHEN INC.ACCOUNTING_PERIOD < DATE_TRUNC('QUARTER', LAST_DAY(CURRENT_DATE)) 
                    THEN 1 ELSE 0 END                                               AS ACCOUNTING_QUARTER_FILTER -- Flag to filter out partial quarters in reporting
        FROM INCOME INC
            JOIN YTD_INCOME YTD
                ON INC.ACCOUNTING_PERIOD = YTD.ACCOUNTING_PERIOD
        WHERE 1=1
),

--SELECT * FROM INCOME_DETAILS


BALANCE_SHEET AS (
        SELECT 
              ACCOUNTING_PERIOD
            , '\'' || RIGHT(DATE_PART(YEAR, ACCOUNTING_PERIOD),2) || '-' ||
                   'Q' || DATE_PART(QUARTER, ACCOUNTING_PERIOD)                     AS ACCOUNTING_QUARTER
            , '\'' || TO_CHAR(ACCOUNTING_PERIOD, 'YY-Mon')                          AS ACCOUNTING_MONTH
            , SUBSIDIARY
            , COMPANY
            , LOCATION
            , DEPARTMENT
            , VERTICAL
            , PROJECT
            , GL_ACCOUNT_NUMBER
            , NAME                                                                  AS GL_ACCOUNT_NAME
            , CONCAT(GL_ACCOUNT_NUMBER, ' - '
                , NVL(TRIM(REGEXP_SUBSTR(NAME,':([^:]+)',1,1,'e')), NAME))          AS ACCOUNT_GROUP
            , HEADER1                                                               AS HIERARCHY_LEVEL_1
            , HEADER2                                                               AS HIERARCHY_LEVEL_2
            , HEADER3                                                               AS HIERARCHY_LEVEL_3
            , HEADER4                                                               AS HIERARCHY_LEVEL_4
            , NULL                                                                  AS HIERARCHY_LEVEL_5
            , SORT_ORDER
            , SUM(AMOUNT)                                                                AS AMOUNT
            --, NVL(AMOUNT - LAG(AMOUNT) OVER (PARTITION BY GL_ACCOUNT_NUMBER, NAME ORDER BY ACCOUNTING_PERIOD ), AMOUNT)  AS MONTHLY_AMOUNT
            , CASE 
                  WHEN MONTH(ACCOUNTING_PERIOD) IN (3,6,9,12) THEN 1
              ELSE 0 END                                                            AS EOQ_IND -- flag for last month of quarter
            , CASE
                WHEN ACCOUNTING_PERIOD < dateadd('quarter', -1, DATE_TRUNC(MONTH, CURRENT_DATE))
                    THEN 1
                WHEN DATEADD(MONTH, 3, DATE_TRUNC('quarter', ACCOUNTING_PERIOD)) = DATE_TRUNC(QUARTER, DATE_TRUNC(MONTH, CURRENT_DATE - 15))
                    THEN 1 
                        ELSE 0 END                                                        AS ACCOUNTING_QUARTER_FILTER -- Flag to filter out partial quarters in reporting
            , CURRENT_TIMESTAMP AS LOAD_DATE
        FROM DEV.HUNTER_STAGE_SCHEMA.RPT_BALANCE_SHEET_STG
        WHERE 1=1
        AND TYPE = 'general_ledger_account'
        --AND GL_ACCOUNT_NUMBER NOT IN ('5', '6') -- Not used in current reporting
        AND ACCOUNTING_PERIOD >= DATEADD(YEAR, -4, CURRENT_DATE) 
        AND ACCOUNTING_PERIOD < DATE_TRUNC(MONTH, CURRENT_DATE)  -- Don't include partial month
        GROUP BY ALL
        UNION ----ADD NET INCOME FROM INCOME STATEMENT
        SELECT 
             ACCOUNTING_PERIOD
            ,ACCOUNTING_QUARTER
            ,ACCOUNTING_MONTH
            ,SUBSIDIARY
            ,COMPANY
            ,LOCATION
            ,DEPARTMENT
            ,VERTICAL
            ,PROJECT
            ,GL_ACCOUNT_NUMBER
            ,GL_ACCOUNT_NAME
            ,ACCOUNT_GROUP
            ,HIERARCHY_LEVEL_1
            ,HIERARCHY_LEVEL_2
            ,HIERARCHY_LEVEL_3
            ,HIERARCHY_LEVEL_4
            ,HIERARCHY_LEVEL_5
            ,SORT_ORDER
            ,YTD_AMOUNT  AS AMOUNT
            --,MONTHLY_AMOUNT
            ,EOQ_IND
            ,ACCOUNTING_QUARTER_FILTER
            ,CURRENT_TIMESTAMP AS LOAD_DATE
        FROM INCOME_DETAILS
)


SELECT  * FROM BALANCE_SHEET WHERE 1=1
  AND DATEADD(DAY, 14, DATEADD(MONTH, 1, ACCOUNTING_PERIOD)) < CURRENT_DATE;