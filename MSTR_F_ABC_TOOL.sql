CREATE OR REPLACE VIEW MSTR_F_ABC_TOOL AS
WITH MAN AS (

        WITH MISSING_VALUE AS (
            SELECT DISTINCT
                S.SHOP_ID,
                A.ARTICLE_ID,
                MIN(A.ARTICLE_NO) OVER (PARTITION BY S.SAP_RETAIL_NO ORDER BY A.ARTICLE_NO) AS FIRST_ARTICLE
            FROM MAN_F_ABC_TOOL ABC
            JOIN LU_SHOP S ON S.SHOP_ID = ABC.SHOP_ID
            JOIN LU_ARTICLE A ON A.ARTICLE_ID = ABC.ARTICLE_ID
        )
        SELECT
            S.SAP_RETAIL_NO,
            A.ARTICLE_NO,
            LEAD(A.ARTICLE_NO,1,MISSING_VALUE.FIRST_ARTICLE) OVER (PARTITION BY S.SAP_RETAIL_NO ORDER BY A.ARTICLE_NO) AS LEAD_ARTICLE
        FROM (
            SELECT DISTINCT
                SHOP_ID,
                ARTICLE_ID
            FROM MAN_F_ABC_TOOL
        ) AS ABC
        JOIN LU_SHOP S ON S.SHOP_ID = ABC.SHOP_ID
        JOIN LU_ARTICLE A ON A.ARTICLE_ID = ABC.ARTICLE_ID
        JOIN MISSING_VALUE ON ABC.SHOP_ID = MISSING_VALUE.SHOP_ID AND ABC.ARTICLE_ID = MISSING_VALUE.ARTICLE_ID
)
, S1 AS (

        SELECT DISTINCT
            SHOP_ID,
            MARKETING,
            ARTICLE_ID,
            SUM(ORDER_NUMBER) AS ORDER_NUMBER
        FROM MAN_F_ABC_TOOL
        GROUP BY
            SHOP_ID,
            MARKETING,
            ARTICLE_ID
        ORDER BY
            SHOP_ID,
            MARKETING,
            ARTICLE_ID
)
, CUMSUM1 AS (

        SELECT
            S1.SHOP_ID,
            S1.ARTICLE_ID,
            SUM(S1.ORDER_NUMBER) OVER (
                PARTITION BY S1.SHOP_ID
                ORDER BY S1.MARKETING, A.ARTICLE_NO ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
            ) AS CUMSUM,
            ORDER_NUMBER
        FROM S1
        JOIN LU_ARTICLE A ON A.ARTICLE_ID = S1.ARTICLE_ID
        JOIN MAN ON MAN.LEAD_ARTICLE = A.ARTICLE_NO
)
,TAKE1 AS (

        SELECT DISTINCT
            CUMSUM1.SHOP_ID,
            CUMSUM1.ARTICLE_ID,
            CUMSUM1.CUMSUM,
            CUMSUM1.ORDER_NUMBER,
--                         s1.MARKETING,
            ABC.SHIPMENT_FCST_FOR_STORE,
            ABC.deficit,
            ABC.UNPACKING,
            ABC.PRODUCT_TYPES,
            CASE WHEN ABC.MARKETING = 1 AND CUMSUM1.CUMSUM <= ABC.SHIPMENT_FCST_FOR_STORE
                THEN 1 ELSE 0 END AS TAKE_MARKETING,
            MAX(CASE WHEN LOCAL.TAKE_MARKETING = 1 THEN CUMSUM1.CUMSUM ELSE 0 END) OVER (PARTITION BY ABC.SHOP_ID) AS SUM_MARKETING,
            MAX(SHIPMENT_FCST_FOR_STORE) OVER (PARTITION BY ABC.SHOP_ID) AS FCST,
            LOCAL.FCST - LOCAL.SUM_MARKETING AS NEW_FCST
        FROM MAN_F_ABC_TOOL ABC
        JOIN CUMSUM1 ON CUMSUM1.SHOP_ID = ABC.SHOP_ID AND CUMSUM1.ARTICLE_ID = ABC.ARTICLE_ID
        ORDER BY
            CUMSUM1.SHOP_ID,
            CUMSUM1.CUMSUM
)
, TAKE2_1 AS (

       WITH NS AS (
            SELECT
                S1.SHOP_ID,
                S1.ARTICLE_ID,
                SUM(ABC.NET_SALES) AS NET_SALES
            FROM S1
            JOIN MAN_F_ABC_TOOL ABC ON S1.SHOP_ID=ABC.SHOP_ID AND S1.ARTICLE_ID=ABC.ARTICLE_ID
            GROUP BY
                S1.SHOP_ID,
                S1.ARTICLE_ID
        )

        SELECT DISTINCT
            S1.SHOP_ID,
            S1.ARTICLE_ID,
            A.ARTICLE_NO,
            CONCAT(
                    BR.ARTICLE_BRAND_NAME_INT,
                    DIV.ARTICLE_RMH_PRODUCT_DIVISION_NAME_SHORT_INT,
                    GEN.ARTICLE_RMH_GENDER_NAME_INT,
                    CASE WHEN DIV.ARTICLE_RMH_PRODUCT_DIVISION_NO = '3'
                        THEN FO.ARTICLE_PRODUCT_TYPE_FO_SHORT_NAME_INT
                        ELSE CAT.ARTICLE_CATEGORY_FO_SHORT_NAME_LOCAL END
            ) AS ABC_KEY,
--             (SELECT ARTICLE_COLLECTION_NAME_SHORT_INT
--             FROM LU_ARTICLE_COLLECTION
--             WHERE SEASON_START_DATE_ID <= CURRENT_DATE AND SEASON_END_DATE_ID >= CURRENT_DATE
--             ) AS CURRENT_COLLECTION,
            'SS22' AS CURRENT_COLLECTION,
            CASE WHEN LEFT (AILA.REPLENISHMENT_COMMENT_02, 7) = 'SPECIAL'
                AND RIGHT (AILA.REPLENISHMENT_COMMENT_02, 4) = LOCAL.CURRENT_COLLECTION
                    THEN 1
                    ELSE 2
            END AS COLLECTIONS,
            CASE WHEN AILA.SEASONALITY IN ('WINTER','MID-SEASON') THEN 1 ELSE 2 END AS SEASONALITY,
            ZEROIFNULL(TSFO.DEFICIT_QTY) AS DEFICIT,
            TAKE1.PRODUCT_TYPES,
            GEN.ARTICLE_RMH_GENDER_NAME_INT,
            DIV.ARTICLE_RMH_PRODUCT_DIVISION_NAME_INT,
            TAKE1.UNPACKING,
            NS.NET_SALES,
            TAKE1.DEFICIT as def,
            TAKE1.CUMSUM AS TAKE1_CUMSUM,
            SUM(S1.ORDER_NUMBER) OVER (
                PARTITION BY LOCAL.ABC_KEY
                ORDER BY
                    TAKE1.TAKE_MARKETING,
                    local.def DESC,
                    LOCAL.ABC_KEY,
                    LOCAL.COLLECTIONS,
                    LOCAL.SEASONALITY,
                    TAKE1.PRODUCT_TYPES,
                    GEN.ARTICLE_RMH_GENDER_NAME_INT,
                    DIV.ARTICLE_RMH_PRODUCT_DIVISION_NAME_INT,
                    TAKE1.UNPACKING,
                    NS.NET_SALES DESC,
                    A.ARTICLE_NO
                ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
            ) AS CUMSUM,
            S1.ORDER_NUMBER,
            CASE WHEN TAKE1.TAKE_MARKETING = 0 AND LOCAL.CUMSUM <= ZEROIFNULL(local.def) THEN 1 ELSE 0
            END AS TAKE_DEFICIT
        FROM S1
        JOIN TAKE1 ON S1.SHOP_ID = TAKE1.SHOP_ID AND S1.ARTICLE_ID = TAKE1.ARTICLE_ID
        JOIN LU_ARTICLE A ON S1.ARTICLE_ID = A.ARTICLE_ID
        JOIN LU_ARTICLE_BRAND BR ON A.ARTICLE_BRAND_ID = BR.ARTICLE_BRAND_ID
        JOIN LU_ARTICLE_RMH_PRODUCT_DIVISION DIV ON A.ARTICLE_RMH_PRODUCT_DIVISION_ID = DIV.ARTICLE_RMH_PRODUCT_DIVISION_ID
        JOIN LU_ARTICLE_RMH_GENDER GEN ON A.ARTICLE_RMH_GENDER_ID = GEN.ARTICLE_RMH_GENDER_ID
        JOIN LU_ARTICLE_RMH_PRODUCT_TYPE TYP ON A.ARTICLE_RMH_PRODUCT_TYPE_ID = TYP.ARTICLE_RMH_PRODUCT_TYPE_ID
        JOIN LU_ARTICLE_PRODUCT_TYPE_FO_SHORT FO ON TYP.ARTICLE_PRODUCT_TYPE_FO_SHORT_ID = FO.ARTICLE_PRODUCT_TYPE_FO_SHORT_ID
        JOIN LU_ARTICLE_RMH_CATEGORY RMHCAT ON A.ARTICLE_RMH_CATEGORY_ID = RMHCAT.ARTICLE_RMH_CATEGORY_ID
        JOIN LU_ARTICLE_CATEGORY_FO_SHORT CAT ON RMHCAT.ARTICLE_CATEGORY_FO_SHORT_ID = CAT.ARTICLE_CATEGORY_FO_SHORT_ID
        JOIN REL_ARTICLE_INTERIM_LOCAL_ATTRIBUTES AILA ON A.ARTICLE_ID = AILA.ARTICLE_ID
        JOIN NS ON S1.SHOP_ID = NS.SHOP_ID AND S1.ARTICLE_ID = NS.ARTICLE_ID
        LEFT JOIN MAN_F_TARGET_STOCK_FO TSFO ON
            TSFO.SHOP_ID = S1.SHOP_ID AND
            TSFO.ARTICLE_BRAND_ID = A.ARTICLE_BRAND_ID AND
            TSFO.ARTICLE_SUBBRAND_ID = A.ARTICLE_SUBBRAND_ID AND
            TSFO.ARTICLE_RMH_PRODUCT_DIVISION_ID = DIV.ARTICLE_RMH_PRODUCT_DIVISION_ID AND
            TSFO.ARTICLE_CATEGORY_FO_SHORT_ID  = CAT.ARTICLE_CATEGORY_FO_SHORT_ID AND
            TSFO.ARTICLE_RMH_GENDER_ID = GEN.ARTICLE_RMH_GENDER_ID
)
, TAKE2_2 AS (

    SELECT
        SHOP_ID,
        ARTICLE_ID,
        CUMSUM,
        take_marketing,
        aTAKE_DEFICIT,
        SUM_TAKE,
        SUM(CASE WHEN SUM_TAKE = 1 THEN ORDER_NUMBER ELSE 0 END) OVER (PARTITION BY SHOP_ID) AS SUM_ORDER,
        MAX(SHIPMENT_FCST_FOR_STORE) OVER (PARTITION BY SHOP_ID) AS FCST,
        LOCAL.FCST - LOCAL.SUM_ORDER AS NEW_FCST
    FROM (
        SELECT
            S1.SHOP_ID,
            S1.ARTICLE_ID,
            TAKE1.take_marketing,
            TAKE1.SHIPMENT_FCST_FOR_STORE,
               TAKE2_1.TAKE_DEFICIT,
                    TAKE2_1.DEF,
                    TAKE2_1.COLLECTIONS,
                    TAKE2_1.SEASONALITY,
                    TAKE2_1.PRODUCT_TYPES,
                    TAKE2_1.ARTICLE_RMH_GENDER_NAME_INT,
                    TAKE2_1.ARTICLE_RMH_PRODUCT_DIVISION_NAME_INT,
                    TAKE2_1.UNPACKING,
                    TAKE2_1.NET_SALES,
                    TAKE2_1.ARTICLE_NO,
            SUM(S1.ORDER_NUMBER) OVER (
                PARTITION BY S1.SHOP_ID
                ORDER BY
                    TAKE2_1.TAKE_DEFICIT DESC,
                    S1.SHOP_ID,
                    TAKE2_1.DEF DESC,
                    TAKE2_1.COLLECTIONS,
                    TAKE2_1.SEASONALITY,
                    TAKE2_1.PRODUCT_TYPES,
                    TAKE2_1.ARTICLE_RMH_GENDER_NAME_INT,
                    TAKE2_1.ARTICLE_RMH_PRODUCT_DIVISION_NAME_INT,
                    TAKE2_1.UNPACKING,
                    TAKE2_1.NET_SALES DESC,
                    TAKE2_1.ARTICLE_NO
                ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
            ) AS CUMSUM,
            S1.ORDER_NUMBER,
            CASE WHEN TAKE2_1.TAKE_DEFICIT = 1 AND LOCAL.CUMSUM <= TAKE1.NEW_FCST THEN 1 ELSE 0
            END AS aTAKE_DEFICIT,
            TAKE1.TAKE_MARKETING + LOCAL.aTAKE_DEFICIT AS SUM_TAKE
        FROM S1
        JOIN TAKE1 ON S1.SHOP_ID = TAKE1.SHOP_ID AND S1.ARTICLE_ID = TAKE1.ARTICLE_ID
        JOIN TAKE2_1 ON S1.SHOP_ID = TAKE2_1.SHOP_ID AND S1.ARTICLE_ID = TAKE2_1.ARTICLE_ID
    )
)
, TAKE3 AS (

        SELECT
            S1.SHOP_ID,
            S1.ARTICLE_ID,
            SH.SAP_RETAIL_NO,
            SUM(S1.ORDER_NUMBER) OVER (
                        PARTITION BY S1.SHOP_ID
                        ORDER BY
                            TAKE2_2.SUM_TAKE,
                            SH.SAP_RETAIL_NO,
                            TAKE2_1.DEFICIT DESC,
                            TAKE2_1.COLLECTIONS,
                            TAKE2_1.SEASONALITY,
                            TAKE2_1.PRODUCT_TYPES,
                            TAKE2_1.ARTICLE_RMH_GENDER_NAME_INT,
                            TAKE2_1.ARTICLE_RMH_PRODUCT_DIVISION_NAME_INT,
                            TAKE2_1.UNPACKING,
                            TAKE2_1.NET_SALES DESC,
                            TAKE2_1.ARTICLE_NO
                        ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
            ) AS CUMSUM,
            S1.ORDER_NUMBER,
            CASE WHEN SUM_TAKE = 0 AND LOCAL.CUMSUM <= TAKE2_2.NEW_FCST THEN 1 ELSE 0 END AS TAKE,
            SUM_TAKE + LOCAL.TAKE AS FINAL_TAKE
        FROM S1
        JOIN TAKE2_1 ON S1.SHOP_ID = TAKE2_1.SHOP_ID AND S1.ARTICLE_ID = TAKE2_1.ARTICLE_ID
        JOIN TAKE2_2 ON S1.SHOP_ID = TAKE2_2.SHOP_ID AND S1.ARTICLE_ID = TAKE2_2.ARTICLE_ID
        JOIN LU_SHOP SH ON S1.SHOP_ID = SH.SHOP_ID
)

SELECT
    S1.SHOP_ID,
    S1.ARTICLE_ID,
    S1.ORDER_NUMBER,
    TAKE1.SHIPMENT_FCST_FOR_STORE,
    TAKE1.NEW_FCST AS NEW_FCST_1,
    TAKE2_2.NEW_FCST AS NEW_FCST_2,
    TAKE2_1.ABC_KEY,
    TAKE2_1.DEFICIT,
    TAKE1.CUMSUM AS CUMSUM_1,
    TAKE1.TAKE_MARKETING AS MARKETING_1,
    TAKE2_1.CUMSUM AS CUMSUM_2_1,
    TAKE2_1.TAKE_DEFICIT AS DEFICIT_2_1,
    TAKE2_2.CUMSUM AS CUMSUM_2_2,
    TAKE2_2.aTAKE_DEFICIT AS DEFICIT_2_2,
    TAKE2_2.SUM_TAKE AS SUM_TAKE,
    TAKE3.CUMSUM AS CUMSUM_3,
    TAKE3.TAKE AS TAKE_3,
    TAKE3.FINAL_TAKE,
    SUM(S1.ORDER_NUMBER) OVER (
--     SUM(CASE WHEN TAKE3.FINAL_TAKE = 1 THEN S1.ORDER_NUMBER ELSE 0 END) OVER (
                PARTITION BY TAKE3.FINAL_TAKE, S1.SHOP_ID
                ORDER BY
                    TAKE3.FINAL_TAKE DESC,
                    TAKE3.SAP_RETAIL_NO,
                    S1.MARKETING,
                    TAKE2_1.DEFICIT DESC,
                    TAKE2_1.COLLECTIONS,
                    TAKE2_1.SEASONALITY,
                    TAKE2_1.PRODUCT_TYPES,
                    TAKE2_1.ARTICLE_RMH_GENDER_NAME_INT,
                    TAKE2_1.ARTICLE_RMH_PRODUCT_DIVISION_NAME_INT,
                    TAKE2_1.UNPACKING,
                    TAKE2_1.NET_SALES DESC,
                    TAKE2_1.ARTICLE_NO
                ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
    ) AS FINAL_CUMSUM,
    ROUND(LOCAL.FINAL_CUMSUM / TAKE1.SHIPMENT_FCST_FOR_STORE * 100) AS PERCENT,
    CASE WHEN TAKE3.FINAL_TAKE = 1
        THEN CASE WHEN LOCAL.PERCENT <= 40
            THEN 'A'
            ELSE 'B'
        END
        ELSE 'C'
    END AS ABC
FROM S1
JOIN TAKE1 ON S1.SHOP_ID = TAKE1.SHOP_ID AND S1.ARTICLE_ID = TAKE1.ARTICLE_ID
JOIN TAKE2_1 ON S1.SHOP_ID = TAKE2_1.SHOP_ID AND S1.ARTICLE_ID = TAKE2_1.ARTICLE_ID
JOIN TAKE2_2 ON S1.SHOP_ID = TAKE2_2.SHOP_ID AND S1.ARTICLE_ID = TAKE2_2.ARTICLE_ID
JOIN TAKE3 ON S1.SHOP_ID = TAKE3.SHOP_ID AND S1.ARTICLE_ID = TAKE3.ARTICLE_ID
ORDER BY
    TAKE3.SAP_RETAIL_NO,
    LOCAL.ABC,
    LOCAL.FINAL_CUMSUM,
    TAKE3.CUMSUM,
    TAKE2_2.CUMSUM,
    TAKE2_1.CUMSUM,
    TAKE1.CUMSUM
;
