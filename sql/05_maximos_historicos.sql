-- Consulta 4 (máximos y mínimos): récords históricos por estación.
-- arg_max(fecha, tmax) devuelve la fecha en que se dio el máximo, sin
-- necesidad de un JOIN contra la misma tabla. Usa todo el período disponible
-- (los valores con flag de calidad ya se descartaron en la limpieza).
SELECT
    estacion,
    max(tmax)              AS record_maxima,
    arg_max(fecha, tmax)   AS fecha_maxima,
    min(tmin)              AS record_minima,
    arg_min(fecha, tmin)   AS fecha_minima,
    round(max(tmax) - min(tmin), 1) AS amplitud
FROM clima
GROUP BY estacion
ORDER BY record_maxima DESC;
