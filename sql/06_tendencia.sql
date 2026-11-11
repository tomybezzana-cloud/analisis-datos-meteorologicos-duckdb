-- Consulta 5 (filtrado complejo): ¿cambió la temperatura media anual?
-- Compara 1961-1975 con 1986-2000: los dos tramos de 15 años más separados
-- dentro del período con datos completos (antes de la caída de cobertura de
-- 2001, ver consulta 2).
-- Filtros en dos niveles para que la comparación sea justa:
--   - un año cuenta solo si tiene al menos 330 días con tmedia (HAVING);
--   - una estación entra solo si tiene al menos 10 años válidos en CADA tramo
--     (segundo HAVING). Si no, la diferencia podría salir de comparar años
--     distintos y no de un cambio real.
WITH anual AS (
    SELECT
        estacion,
        year(fecha)  AS anio,
        avg(tmedia)  AS tmedia_anual
    FROM clima
    WHERE year(fecha) BETWEEN 1961 AND 1975
       OR year(fecha) BETWEEN 1986 AND 2000
    GROUP BY estacion, anio
    HAVING count(tmedia) >= 330
)
SELECT
    estacion,
    count(*) FILTER (WHERE anio <= 1975)                     AS anios_1961_75,
    count(*) FILTER (WHERE anio >= 1986)                     AS anios_1986_00,
    round(avg(tmedia_anual) FILTER (WHERE anio <= 1975), 2)  AS tmedia_1961_75,
    round(avg(tmedia_anual) FILTER (WHERE anio >= 1986), 2)  AS tmedia_1986_00,
    round(avg(tmedia_anual) FILTER (WHERE anio >= 1986)
        - avg(tmedia_anual) FILTER (WHERE anio <= 1975), 2)  AS diferencia
FROM anual
GROUP BY estacion
HAVING count(*) FILTER (WHERE anio <= 1975) >= 10
   AND count(*) FILTER (WHERE anio >= 1986) >= 10
ORDER BY diferencia DESC;
