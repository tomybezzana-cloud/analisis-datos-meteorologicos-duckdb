-- Consulta 3 (promedios): temperatura media mensual, normal 1961-1990.
-- 1961-1990 es un período de referencia ("normal climatológica") de la
-- Organización Meteorológica Mundial y es el que tiene datos casi completos
-- en este dataset (la normal 1991-2020 no se puede calcular: desde 2001 falta
-- más de la mitad de los días, ver consulta 2).
-- Filtros:
--   - un mes de un año cuenta solo si tiene al menos 20 días con tmedia;
--   - el promedio de un mes se informa solo si hay al menos 10 años válidos.
-- Bariloche y Ushuaia no llegan en ningún mes y quedan fuera.
WITH mes_por_anio AS (
    SELECT
        estacion,
        year(fecha)  AS anio,
        month(fecha) AS mes,
        avg(tmedia)  AS tmedia
    FROM clima
    WHERE fecha BETWEEN DATE '1961-01-01' AND DATE '1990-12-31'
    GROUP BY estacion, anio, mes
    HAVING count(tmedia) >= 20
),
normal AS (
    SELECT
        estacion,
        ['Ene', 'Feb', 'Mar', 'Abr', 'May', 'Jun',
         'Jul', 'Ago', 'Sep', 'Oct', 'Nov', 'Dic'][mes] AS mes,
        round(avg(tmedia), 1) AS tmedia
    FROM mes_por_anio
    GROUP BY estacion, mes
    HAVING count(*) >= 10
)
PIVOT normal
ON mes IN ('Ene', 'Feb', 'Mar', 'Abr', 'May', 'Jun',
           'Jul', 'Ago', 'Sep', 'Oct', 'Nov', 'Dic')
USING first(tmedia)
ORDER BY Ene DESC;
