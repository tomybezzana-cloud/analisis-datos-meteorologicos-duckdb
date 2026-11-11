-- Consulta 2 (conteos): qué porcentaje de los días tiene temperatura máxima
-- válida, por estación y década.
-- Define qué períodos se pueden analizar: una década con la mitad de los días
-- vacíos no se puede comparar con una completa.
-- El denominador son los días del calendario de cada década (la última,
-- hasta la fecha más reciente del dataset).
WITH ultima AS (
    SELECT max(fecha) + 1 AS fin FROM clima
),
por_decada AS (
    SELECT
        estacion,
        year(fecha) // 10 * 10 AS decada,
        count(tmax)            AS dias_con_tmax
    FROM clima
    WHERE fecha >= DATE '1960-01-01'
    GROUP BY estacion, decada
)
PIVOT (
    SELECT
        estacion,
        decada || 's' AS decada,
        round(100.0 * dias_con_tmax / date_diff(
            'day',
            make_date(decada, 1, 1),
            least(make_date(decada + 10, 1, 1), (SELECT fin FROM ultima))
        )) AS pct
    FROM por_decada
)
ON decada IN ('1960s', '1970s', '1980s', '1990s', '2000s', '2010s', '2020s')
USING first(pct)
ORDER BY estacion;
