-- Consulta 1 (conteos): calidad de los datos por estación.
-- Antes de sacar conclusiones hay que saber con qué se cuenta: desde cuándo
-- mide cada estación, qué porcentaje de días no tiene temperatura y cuántos
-- valores se descartaron en la limpieza.
SELECT
    replace(NAME, ', AR', '')                                   AS estacion,
    min("DATE")                                                 AS desde,
    max("DATE")                                                 AS hasta,
    count(*)                                                    AS dias,
    round(100.0 * count(*) FILTER (WHERE TMAX IS NULL) / count(*), 1) AS pct_sin_tmax,
    round(100.0 * count(*) FILTER (WHERE TMIN IS NULL) / count(*), 1) AS pct_sin_tmin,
    count(*) FILTER (WHERE split_part(TMAX_ATTRIBUTES, ',', 2) <> ''
                        OR split_part(TMIN_ATTRIBUTES, ',', 2) <> '')  AS con_flag_calidad,
    count(*) FILTER (WHERE TMAX < TMIN)                         AS max_menor_que_min
FROM clima_crudo
GROUP BY estacion
ORDER BY desde;
