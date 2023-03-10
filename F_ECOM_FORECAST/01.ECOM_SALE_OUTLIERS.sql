SET AUTOCOMMIT  OFF;

MERGE INTO REL_ECOM_OUTLIER AS DST
USING (
    WITH SALES AS (
        SELECT
            LC.DATE_ID,
            LH.HOUR_ID,
            LES.ECOM_SHOP_ID,
            round(sum(zeroifnull(F.NET_SALES_VALUE))) AS GROSS_AMNT
        FROM LU_CALENDAR LC
        JOIN LU_HOUR LH ON 1=1
        JOIN LU_ECOM_SHOP LES ON 1=1 AND LES.ECOM_SHOP_ID IN (1, 2)
        LEFT JOIN F_ECOM_SALE F ON F.DATE_ID = LC.DATE_ID AND F.HOUR_ID = LH.HOUR_ID AND F.ECOM_SHOP_ID = LES.ECOM_SHOP_ID
        WHERE LC.DATE_ID BETWEEN CAST(CONVERT_TZ(CURRENT_DATE,'CET','Europe/Moscow') AS DATE) - 60 AND
            CAST(CONVERT_TZ(CURRENT_DATE,'CET','Europe/Moscow') AS DATE) AND
            convert_tz(to_timestamp((to_char(LC.DATE_ID,'YYYY-MM-DD')|| ' '|| CASE WHEN LENGTH(to_char(HOUR_NO)) = 1 THEN '0' END || to_char(LH.HOUR_NO) || ':00:00'),'YYYY-MM-DD HH24:MI:SS'),'UTC','Europe/Moscow') <= DATE_TRUNC('hour', add_hours(CONVERT_TZ(CAST(CURRENT_TIMESTAMP AS TIMESTAMP),'CET','Europe/Moscow'),1))
        GROUP BY
            LC.DATE_ID,
            LH.HOUR_ID,
            LES.ECOM_SHOP_ID
    ),
    SRC_1 AS (
        -- find outliers in series
        SELECT S.DATE_ID,
               S.HOUR_ID,
               S.ECOM_SHOP_ID,
               CASE
                   WHEN O.ECOM_GROSS_DEMAND_CORRECTED IS NOT NULL
                       THEN O.ECOM_GROSS_DEMAND_CORRECTED
                   ELSE S.GROSS_AMNT END AS GROSS_AMNT_CORR,
               GROSS_AMNT,
               round(STDDEV(LOCAL.GROSS_AMNT_CORR) OVER(PARTITION BY S.ECOM_SHOP_ID, S.HOUR_ID ORDER BY S.DATE_ID)) AS STDDEV,
               round(AVG(GROSS_AMNT) OVER(PARTITION BY S.ECOM_SHOP_ID, S.HOUR_ID ORDER BY S.DATE_ID)) AS AVG_ORIGINAL,
               round(AVG(LOCAL.GROSS_AMNT_CORR) OVER(PARTITION BY S.ECOM_SHOP_ID, S.HOUR_ID ORDER BY S.DATE_ID)) AS AVG
    FROM SALES S
    LEFT JOIN REL_ECOM_OUTLIER O ON
        S.HOUR_ID = O.HOUR_ID AND
        S.DATE_ID = O.DATE_ID AND
        S.ECOM_SHOP_ID = O.ECOM_SHOP_ID
),
    SRC_2 AS (
        SELECT
            DATE_ID,
            HOUR_ID,
            ECOM_SHOP_ID,
            GROSS_AMNT AS GROSS_AMNT_ORIGINAL,
            GROSS_AMNT_CORR,
            CASE WHEN AVG IS NULL OR AVG = 0 THEN 0 ELSE abs((AVG-LOCAL.GROSS_AMNT_ORIGINAL)/AVG) END AS DIFF_PERCENT,
            LAG(STDDEV, 1) OVER (PARTITION BY ECOM_SHOP_ID, HOUR_ID ORDER BY DATE_ID) STDDEV,
            LAG(AVG_original, 1) OVER (PARTITION BY ECOM_SHOP_ID, HOUR_ID ORDER BY DATE_ID) AS AVG,
            CASE WHEN (GROSS_AMNT_CORR > LOCAL.AVG+3*LOCAL.STDDEV AND LOCAL.STDDEV>0) THEN 1 ELSE 0 END AS IS_ANOMALY,
            CASE WHEN (GROSS_AMNT_CORR > LOCAL.AVG+3*LOCAL.STDDEV AND LOCAL.STDDEV>0) THEN LOCAL.AVG ELSE GROSS_AMNT_CORR END AS GROSS_AMNT
        FROM SRC_1
    )
    SELECT
        DATE_ID,
        HOUR_ID,
        ECOM_SHOP_ID,
        GROSS_AMNT
    FROM SRC_2
    WHERE IS_ANOMALY = 1 AND DATE_ID = CAST(CONVERT_TZ(CURRENT_DATE,'CET','Europe/Moscow') AS DATE)
) SRC ON
    SRC.DATE_ID = DST.DATE_ID AND
    SRC.ECOM_SHOP_ID = DST.ECOM_SHOP_ID AND
    SRC.HOUR_ID = DST.HOUR_ID
WHEN MATCHED THEN UPDATE SET
     DST.ECOM_GROSS_DEMAND_CORRECTED = SRC.GROSS_AMNT,
     DST.SOURCE_CURRENCY_ID = 1,
     DST.MODIFIED_AT = CONVERT_TZ(CAST(CURRENT_TIMESTAMP AS TIMESTAMP),'CET','Europe/Moscow')
WHEN NOT MATCHED THEN INSERT (
    DATE_ID,
    HOUR_ID,
    ECOM_SHOP_ID,
    SOURCE_CURRENCY_ID,
    ECOM_GROSS_DEMAND_CORRECTED,
    CREATED_AT
) VALUES (
    SRC.DATE_ID,
    SRC.HOUR_ID,
    SRC.ECOM_SHOP_ID,
    1,
    SRC.GROSS_AMNT,
    CONVERT_TZ(CAST(CURRENT_TIMESTAMP AS TIMESTAMP),'CET','Europe/Moscow')
);


COMMIT;
SET AUTOCOMMIT OFF;
