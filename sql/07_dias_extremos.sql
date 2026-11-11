-- Consulta 6 (filtrado complejo): perfil de extremos de cada estación.
-- Cuenta, por año, los días que cumplen cada condición y después promedia
-- entre años (1961-2000, solo años con al menos 330 días con máxima Y con
-- mínima medidas, para no subestimar los conteos):
--   - días de calor:      tmax >= 35 °C
--   - días de helada:     tmin <  0 °C
--   - noches tropicales:  tmin >= 20 °C (la temperatura no baja de 20 en toda la noche)
--   - amplitud térmica:   diferencia promedio entre la máxima y la mínima del día
WITH anual AS (
    SELECT
        estacion,
        year(fecha)                           AS anio,
        count(*) FILTER (WHERE tmax >= 35)    AS dias_calor,
        count(*) FILTER (WHERE tmin < 0)      AS dias_helada,
        count(*) FILTER (WHERE tmin >= 20)    AS noches_tropicales,
        avg(tmax - tmin)                      AS amplitud
    FROM clima
    WHERE fecha BETWEEN DATE '1961-01-01' AND DATE '2000-12-31'
    GROUP BY estacion, anio
    HAVING count(tmax) >= 330
       AND count(tmin) >= 330
)
SELECT
    estacion,
    count(*)                          AS anios,
    round(avg(dias_calor), 1)         AS dias_calor_por_anio,
    round(avg(dias_helada), 1)        AS dias_helada_por_anio,
    round(avg(noches_tropicales), 1)  AS noches_tropicales_por_anio,
    round(avg(amplitud), 1)           AS amplitud_diaria
FROM anual
GROUP BY estacion
ORDER BY amplitud_diaria DESC;
