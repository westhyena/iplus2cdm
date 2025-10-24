WITH 
    last_date AS (
        SELECT
            청구코드 AS code,
            max(적용일자) AS apply_date
        FROM
            [$(SrcSchema)].[PICMECHM]
        WHERE
            수가분류 = 3
        GROUP BY
            청구코드
    )
SELECT
    p.*
FROM
    [$(SrcSchema)].[PICMECHM] p
    JOIN last_date d ON p.적용일자 = d.apply_date
    AND p.청구코드 = d.code
